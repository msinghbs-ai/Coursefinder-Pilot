-- CF-247 / Layer 1 closure: departures for registers read provider by provider (NZQA), and R14 re-verification.
--
-- 1. Seen tracking. NZQA has no register file, so a course NZQA stops listing was never retired (38 NZ
--    courses were last seen on 12 Aug 2026). Sources with seen_tracking_since set now record every course
--    they read in pipeline.layer1_register_row_state (key "provider|course", seen_at refreshed at most once
--    a day). At the end of a completed apply run, security.layer1_seen_departures_v1 retires active courses
--    of providers that were read successfully in that run but whose course was not seen, reactivates retired
--    courses that were seen again, and applies the same hold as CRICOS (more than 2% and more than 50 needs a
--    Platform Admin). Audit, evidence, count check and consumer snapshots are the same as Decision 158.
-- 2. R14. Change-based apply only touches changed rows, so "last checked" for unchanged courses would go
--    stale. At the end of each CRICOS apply run, courses and providers seen in that run are re-marked as
--    checked, at most once per 30 days (Decision 152).
-- All function patches are checksum-guarded.

alter table pipeline.layer1_source_operations add column if not exists seen_tracking_since timestamptz;
update pipeline.layer1_source_operations set seen_tracking_since=now()
 where source_id='e410b159-614e-45ef-b8f4-902c7b516257' and seen_tracking_since is null;

-- 1a. Record seen courses in the shared register apply function.
do $patch$
declare d text; n text;
begin
  d:=pg_get_functiondef('public.svc_layer1_apply_register_records(text,uuid,uuid,text,jsonb)'::regprocedure);
  if md5(d)<>'3e54f15a7c3463498f41196d978192ca' then raise exception 'svc_layer1_apply_register_records changed since review (%); not patched', md5(d); end if;
  n:=replace(d,'v_broad_code text;','v_broad_code text; v_track boolean:=false;');
  n:=replace(n,'raise exception ''registration scheme required''; end if;',
    'raise exception ''registration scheme required''; end if; select o.seen_tracking_since is not null into v_track from pipeline.layer1_source_operations o where o.source_id=p_source_id; v_track:=coalesce(v_track,false);');
  n:=replace(n,'end loop;',
    'if v_track then insert into pipeline.layer1_register_row_state(source_id,record_key,fingerprint,applied_run_id,applied_at,seen_at) values(p_source_id,v_pcode||''|''||v_ccode,''seen'',null,now(),now()) on conflict (source_id,record_key) do update set seen_at=now() where pipeline.layer1_register_row_state.seen_at < now()-interval ''1 day''; end if; end loop;');
  if (select count(*) from regexp_matches(n,'v_track','g'))<>5 then raise exception 'apply patch points not found as expected'; end if;
  execute n;
end $patch$;

-- 1b. Departures for seen-tracked sources.
create or replace function security.layer1_seen_departures_v1(p_run_id uuid, p_force boolean default false, p_actor uuid default null)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','catalogue','security','search' as $f$
declare q pipeline.layer1_run_queue; o pipeline.layer1_source_operations; v_country uuid; v_scheme text; v_since timestamptz;
        v_ids uuid[]; v_back uuid[]; v_expected int; v_n int; v_limit int; v_total int; v_providers int:=0; v_ev uuid;
        v_before jsonb; v_after jsonb; v_result jsonb; v_plan pipeline.layer1_run_plans;
begin
  select * into q from pipeline.layer1_run_queue where id=p_run_id;
  if not found then raise exception 'run not found'; end if;
  select * into o from pipeline.layer1_source_operations where source_id=q.source_id;
  if o.seen_tracking_since is null then raise exception 'source is not seen-tracked'; end if;
  select * into v_plan from pipeline.layer1_run_plans where run_id=p_run_id for update;
  if found and v_plan.departures_status='applied' then return v_plan.departures_result; end if;
  v_since:=coalesce(q.started_at,q.requested_at);
  if v_since < o.seen_tracking_since then
    return jsonb_build_object('status','skipped','reason','run started before seen tracking began');
  end if;
  select s.country_id into v_country from pipeline.sources s where s.id=q.source_id;
  select lower(pr.registration_scheme) into v_scheme from catalogue.provider_registrations pr where pr.source_id=q.source_id limit 1;
  select count(*) into v_total from pipeline.layer1_register_row_state where source_id=q.source_id and seen_at>=v_since-interval '1 day';

  -- courses of providers read in this run that were not seen
  select coalesce(array_agg(distinct c.id),'{}') into v_ids
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id and p.country_id=v_country
    join catalogue.provider_registrations pr on pr.provider_id=p.id and lower(pr.registration_scheme)=v_scheme and pr.checked_at>=v_since
    join catalogue.course_registrations cr on cr.course_id=c.id and lower(cr.scheme)=v_scheme
   where c.lifecycle_status='active'
     and not exists (select 1 from pipeline.layer1_register_row_state s where s.source_id=q.source_id
                      and s.record_key=upper(pr.registration_code)||'|'||upper(cr.registration_code) and s.seen_at>=v_since-interval '1 day');
  -- retired courses seen again
  select coalesce(array_agg(distinct c.id),'{}') into v_back
    from pipeline.layer1_course_retirements r
    join catalogue.courses c on c.id=r.course_id and c.lifecycle_status='inactive'
    join catalogue.provider_registrations pr on pr.provider_id=c.provider_id and lower(pr.registration_scheme)=v_scheme
    join catalogue.course_registrations cr on cr.course_id=c.id and lower(cr.scheme)=v_scheme
    join pipeline.layer1_register_row_state s on s.source_id=q.source_id and s.record_key=upper(pr.registration_code)||'|'||upper(cr.registration_code) and s.seen_at>=v_since-interval '1 day'
   where r.reactivated_at is null;

  v_expected:=cardinality(v_ids);
  v_limit:=greatest(50, ceil(v_total*0.02)::int);
  insert into pipeline.layer1_run_plans(run_id,source_id,register_total,new_count,changed_count,unchanged_count,departed_count,items,departed_keys,course_hash)
  values(p_run_id,q.source_id,v_total,0,0,v_total,v_expected,'[]'::jsonb,'{}','seen-tracking')
  on conflict (run_id) do update set register_total=excluded.register_total, departed_count=excluded.departed_count, course_hash='seen-tracking';

  if v_expected>v_limit and not p_force then
    v_result:=jsonb_build_object('status','held','departed',v_expected,'to_retire',v_expected,'limit',v_limit,'reactivated',0,
      'message',format('%s courses were not seen in this run, more than the automatic limit of %s. A Platform Admin must approve the retirement.',v_expected,v_limit));
    update pipeline.layer1_run_plans set departures_status='held', departures_result=v_result where run_id=p_run_id;
    return v_result;
  end if;

  if cardinality(v_back)>0 then
    update catalogue.courses set lifecycle_status='active', updated_at=now() where id=any(v_back) and lifecycle_status='inactive';
    update catalogue.course_registrations set status='active' where course_id=any(v_back) and lower(scheme)=v_scheme;
    update pipeline.layer1_course_retirements set reactivated_at=now() where course_id=any(v_back) and reactivated_at is null;
  end if;

  if v_expected>0 then
    select e.id into v_ev from pipeline.evidence_artifacts e where e.source_id=q.source_id and e.created_at>=v_since-interval '1 day' order by e.created_at desc limit 1;
    v_before:=security.consumer_api_snapshot_v1();
    insert into pipeline.layer1_course_retirements(course_id,provider_id,previous_status,reason,evidence_id,run_id,approved_by)
    select c.id, c.provider_id, c.lifecycle_status, 'Not listed by the register as of '||to_char(v_since at time zone 'Australia/Sydney','DD Mon YYYY'), v_ev, p_run_id, p_actor
      from catalogue.courses c where c.id=any(v_ids);
    update catalogue.courses set lifecycle_status='inactive', updated_at=now() where id=any(v_ids) and lifecycle_status='active';
    get diagnostics v_n = row_count;
    if v_n<>v_expected then raise exception 'retired % courses, expected %; nothing changed', v_n, v_expected; end if;
    update catalogue.course_registrations set status='inactive' where course_id=any(v_ids) and lower(scheme)=v_scheme and status='active';
    with gone as (select distinct c.provider_id from catalogue.courses c where c.id=any(v_ids)),
    empty as (select g.provider_id from gone g where not exists (select 1 from catalogue.courses c2 where c2.provider_id=g.provider_id and c2.lifecycle_status='active')
               and not exists (select 1 from pipeline.layer1_provider_departures d where d.provider_id=g.provider_id and d.status='needs_review')),
    ins as (insert into pipeline.layer1_provider_departures(provider_id,run_id,courses_retired,note)
            select e.provider_id, p_run_id, (select count(*) from catalogue.courses c where c.id=any(v_ids) and c.provider_id=e.provider_id),
                   'All registered courses left the register; review as a closure or a merger and record any successor.' from empty e returning 1)
    select count(*) into v_providers from ins;
    v_after:=security.consumer_api_snapshot_v1();
    insert into pipeline.consumer_api_baselines(label, snapshot) values
      (format('before retiring %s register departures (run %s)', v_expected, left(p_run_id::text,8)), v_before),
      (format('after retiring %s register departures (run %s)', v_expected, left(p_run_id::text,8)), v_after);
  end if;
  if v_expected>0 or cardinality(v_back)>0 then
    insert into search.refresh_requests(requested_by) values (format('register departures: %s retired, %s reactivated (run %s)', v_expected, cardinality(v_back), left(p_run_id::text,8)));
  end if;
  v_result:=jsonb_build_object('status','applied','departed',v_expected,'retired',v_expected,'reactivated',cardinality(v_back),'providers_to_review',v_providers,'approved_by',p_actor,'basis','seen tracking');
  update pipeline.layer1_run_plans set departures_status='applied', departures_result=v_result where run_id=p_run_id;
  return v_result;
end $f$;
revoke all on function security.layer1_seen_departures_v1(uuid,boolean,uuid) from public, anon, authenticated;

-- 1c. Held seen-tracked departures are approved through the existing path (plan finish dispatches).
do $patch$
declare d text; n text;
begin
  d:=pg_get_functiondef('security.layer1_plan_finish_v1(uuid,boolean,uuid)'::regprocedure);
  if md5(d)<>'cde4ccccd0eaa71552dcd3a08cbeaa68' then raise exception 'layer1_plan_finish_v1 changed since review (%); not patched', md5(d); end if;
  n:=replace(d,'if p.departures_status=''applied'' then return p.departures_result; end if;',
    'if p.departures_status=''applied'' then return p.departures_result; end if;
  if p.course_hash=''seen-tracking'' then return security.layer1_seen_departures_v1(p_run_id,p_force,p_actor); end if;');
  -- 2. R14: re-mark courses and providers seen in this run as checked, at most once per 30 days.
  n:=replace(n,'delete from pipeline.layer1_register_row_state s where s.source_id=p.source_id and s.record_key=any(p.departed_keys);',
    'delete from pipeline.layer1_register_row_state s where s.source_id=p.source_id and s.record_key=any(p.departed_keys);
  update catalogue.courses c set last_verified_at=now()
    from catalogue.course_registrations cr, pipeline.layer1_register_row_state s
   where cr.course_id=c.id and lower(cr.scheme)=''cricos'' and cr.status=''active'' and s.source_id=p.source_id and s.record_key=upper(cr.registration_code)
     and s.seen_at>=p.created_at-interval ''1 hour'' and c.lifecycle_status=''active'' and (c.last_verified_at is null or c.last_verified_at<now()-interval ''30 days'');
  update catalogue.providers pv set last_verified_at=now()
   where pv.country_id=v_country and pv.lifecycle_status=''active'' and (pv.last_verified_at is null or pv.last_verified_at<now()-interval ''30 days'')
     and exists (select 1 from catalogue.courses c where c.provider_id=pv.id and c.lifecycle_status=''active'' and c.last_verified_at>=now()-interval ''1 hour'');');
  if (select count(*) from regexp_matches(n,'seen-tracking|last_verified_at<now\(\)-interval ''30 days''','g'))<>3 then raise exception 'plan finish patch points not found as expected'; end if;
  execute n;
end $patch$;

-- 1d. Run departures when a seen-tracked apply run completes.
create or replace function pipeline.trg_layer1_seen_departures()
returns trigger language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
declare v_res jsonb;
begin
  if new.status='completed' and old.status is distinct from 'completed' and new.mode='apply'
     and exists (select 1 from pipeline.layer1_source_operations o where o.source_id=new.source_id and o.seen_tracking_since is not null) then
    begin
      v_res:=security.layer1_seen_departures_v1(new.id,false,null);
    exception when others then
      v_res:=jsonb_build_object('status','failed','error',left(sqlerrm,300));
    end;
    update pipeline.layer1_run_queue set result=coalesce(result,'{}'::jsonb)||jsonb_build_object('departures',v_res) where id=new.id;
  end if;
  return null;
end $f$;
revoke all on function pipeline.trg_layer1_seen_departures() from public, anon, authenticated;
drop trigger if exists trg_layer1_seen_departures on pipeline.layer1_run_queue;
create trigger trg_layer1_seen_departures after update of status on pipeline.layer1_run_queue
  for each row execute function pipeline.trg_layer1_seen_departures();
