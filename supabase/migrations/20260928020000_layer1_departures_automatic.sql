-- CF-247 / Decision 155 step 6 (R20): departures, reactivations and provider departures are handled
-- at the end of every register apply run.
-- * Records that left the register are retired (inactive, never deleted) with an audit record, the
--   register file as evidence and an exact count check.
-- * A large departure (more than 50 records and more than 2% of the register) is held for a Platform
--   Admin to approve on the Layer 1 card; nothing is retired until then.
-- * A retired record that reappears is reactivated and its audit record closed.
-- * A provider whose every active course departed is recorded for a person to review as a possible
--   closure or merger (the successor is recorded by a person, not guessed).
-- Consumer API: retired courses leave the search projection through the normal refresh; the consumer
-- guard snapshot is recorded before and after every retirement.

alter table pipeline.layer1_course_retirements add column if not exists approved_by uuid;
alter table pipeline.layer1_run_plans
  add column if not exists departures_status text not null default 'pending',
  add column if not exists departures_result jsonb;

create table if not exists pipeline.layer1_provider_departures(
  id bigint generated always as identity primary key,
  provider_id uuid not null references catalogue.providers(id),
  run_id uuid,
  courses_retired integer not null,
  status text not null default 'needs_review' check (status in ('needs_review','closed','merged','reviewed')),
  successor_provider_id uuid references catalogue.providers(id),
  note text,
  created_at timestamptz not null default now(),
  reviewed_by uuid, reviewed_at timestamptz);
alter table pipeline.layer1_provider_departures enable row level security;
revoke all on pipeline.layer1_provider_departures from public, anon, authenticated;

create or replace function security.layer1_plan_finish_v1(p_run_id uuid, p_force boolean default false, p_actor uuid default null)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','catalogue','security','search' as $f$
declare p pipeline.layer1_run_plans; v_ids uuid[]; v_n int; v_expected int; v_reactivated int:=0; v_providers int:=0;
        v_limit int; v_before jsonb; v_after jsonb; v_snapshot text; v_result jsonb; v_country uuid;
begin
  select * into p from pipeline.layer1_run_plans where run_id=p_run_id for update;
  if not found then raise exception 'run plan not found'; end if;
  if p.departures_status='applied' then return p.departures_result; end if;
  select s.country_id into v_country from pipeline.sources s where s.id=p.source_id;
  v_snapshot:=coalesce((select to_char(created_at at time zone 'Australia/Sydney','DD Mon YYYY') from pipeline.layer1_run_plans where run_id=p_run_id),'');

  -- Reactivate planned 'new' records that match a retired course.
  with back as (
    select distinct r.course_id from pipeline.layer1_course_retirements r
    join catalogue.course_registrations cr on cr.course_id=r.course_id and lower(cr.scheme)='cricos'
    join jsonb_array_elements(p.items) i on upper(i->>0)=upper(cr.registration_code) and i->>2='new'
    join catalogue.courses c on c.id=r.course_id
    join catalogue.providers pv on pv.id=c.provider_id and pv.country_id=v_country
    where r.reactivated_at is null and c.lifecycle_status='inactive'),
  upd as (update catalogue.courses c set lifecycle_status='active', updated_at=now() from back where c.id=back.course_id returning c.id)
  select count(*) into v_reactivated from upd;
  update pipeline.layer1_course_retirements r set reactivated_at=now()
   where r.reactivated_at is null and exists (select 1 from catalogue.courses c where c.id=r.course_id and c.lifecycle_status='active');

  -- Departures: active courses whose register code is listed as departed.
  select array_agg(distinct c.id) into v_ids
    from catalogue.course_registrations cr
    join catalogue.courses c on c.id=cr.course_id
    join catalogue.providers pv on pv.id=c.provider_id and pv.country_id=v_country
   where lower(cr.scheme)='cricos' and upper(cr.registration_code)=any(select upper(x) from unnest(p.departed_keys) x)
     and c.lifecycle_status='active';
  v_expected:=coalesce(cardinality(v_ids),0);
  v_limit:=greatest(50, ceil(p.register_total*0.02)::int);

  if v_expected>v_limit and not p_force then
    v_result:=jsonb_build_object('status','held','departed',p.departed_count,'to_retire',v_expected,'limit',v_limit,'reactivated',v_reactivated,
      'message',format('%s courses left the register, more than the automatic limit of %s. A Platform Admin must approve the retirement.',v_expected,v_limit));
    update pipeline.layer1_run_plans set departures_status='held', departures_result=v_result where run_id=p_run_id;
    return v_result;
  end if;

  if v_expected>0 then
    v_before:=security.consumer_api_snapshot_v1();
    insert into pipeline.layer1_course_retirements(course_id,provider_id,previous_status,reason,evidence_id,run_id,approved_by)
    select c.id, c.provider_id, c.lifecycle_status, 'Not in the register as of '||v_snapshot, p.course_evidence_id, p_run_id, p_actor
      from catalogue.courses c where c.id=any(v_ids);
    update catalogue.courses set lifecycle_status='inactive', updated_at=now() where id=any(v_ids) and lifecycle_status='active';
    get diagnostics v_n = row_count;
    if v_n<>v_expected then raise exception 'retired % courses, expected %; nothing changed', v_n, v_expected; end if;
    update catalogue.course_registrations set status='inactive' where course_id=any(v_ids) and lower(scheme)='cricos' and status='active';

    -- Providers with no active courses left: record for a person (closure or merger).
    with gone as (select distinct c.provider_id from catalogue.courses c where c.id=any(v_ids)),
    empty as (select g.provider_id from gone g where not exists (select 1 from catalogue.courses c2 where c2.provider_id=g.provider_id and c2.lifecycle_status='active')),
    ins as (insert into pipeline.layer1_provider_departures(provider_id,run_id,courses_retired,note)
            select e.provider_id, p_run_id, (select count(*) from catalogue.courses c where c.id=any(v_ids) and c.provider_id=e.provider_id),
                   'All registered courses left the register; review as a closure or a merger and record any successor.'
              from empty e returning 1)
    select count(*) into v_providers from ins;

    v_after:=security.consumer_api_snapshot_v1();
    insert into pipeline.consumer_api_baselines(label, snapshot) values
      (format('before retiring %s register departures (run %s)', v_expected, left(p_run_id::text,8)), v_before),
      (format('after retiring %s register departures (run %s)', v_expected, left(p_run_id::text,8)), v_after);
  end if;

  delete from pipeline.layer1_register_row_state s where s.source_id=p.source_id and s.record_key=any(p.departed_keys);
  if v_expected>0 or v_reactivated>0 then
    insert into search.refresh_requests(requested_by) values (format('register departures: %s retired, %s reactivated (run %s)', v_expected, v_reactivated, left(p_run_id::text,8)));
  end if;
  v_result:=jsonb_build_object('status','applied','departed',p.departed_count,'retired',v_expected,'reactivated',v_reactivated,'providers_to_review',v_providers,'approved_by',p_actor);
  update pipeline.layer1_run_plans set departures_status='applied', departures_result=v_result where run_id=p_run_id;
  return v_result;
end $f$;
revoke all on function security.layer1_plan_finish_v1(uuid,boolean,uuid) from public, anon, authenticated;

create or replace function public.svc_layer1_plan_finish(p_run_id uuid)
returns jsonb language sql security definer set search_path to 'pg_catalog','security' as $f$
  select security.layer1_plan_finish_v1(p_run_id,false,null)
$f$;
revoke all on function public.svc_layer1_plan_finish(uuid) from public, anon, authenticated;
grant execute on function public.svc_layer1_plan_finish(uuid) to service_role;

-- Platform Admin approval of a held (large) departure.
create or replace function security.admin_layer1_approve_departures_v1(p_run_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','security','pipeline' as $f$
declare v_rank int; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank; if coalesce(v_rank,0)<6 then raise exception 'platform_admin role required' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'reason required' using errcode='22023'; end if;
  if not exists (select 1 from pipeline.layer1_run_plans where run_id=p_run_id and departures_status='held') then raise exception 'no held departures for this run' using errcode='55000'; end if;
  v_result:=security.layer1_plan_finish_v1(p_run_id,true,auth.uid());
  update pipeline.layer1_run_queue set result=coalesce(result,'{}'::jsonb)||jsonb_build_object('departures',v_result||jsonb_build_object('reason',left(p_reason,300))),updated_at=now() where id=p_run_id;
  return v_result;
end $f$;
revoke all on function security.admin_layer1_approve_departures_v1(uuid,text) from public, anon;
grant execute on function security.admin_layer1_approve_departures_v1(uuid,text) to authenticated; -- role checked inside (Platform Admin)

create or replace function public.layer1_approve_departures(p_run_id uuid, p_reason text)
returns jsonb language sql set search_path to 'pg_catalog','security' as $f$
  select security.admin_layer1_approve_departures_v1(p_run_id,p_reason)
$f$;
revoke all on function public.layer1_approve_departures(uuid,text) from public, anon;
grant execute on function public.layer1_approve_departures(uuid,text) to authenticated;
