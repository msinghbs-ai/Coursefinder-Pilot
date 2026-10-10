CREATE OR REPLACE FUNCTION security.layer1_plan_finish_v1(p_run_id uuid, p_force boolean DEFAULT false, p_actor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'security', 'search'
AS $function$
declare p pipeline.layer1_run_plans; v_ids uuid[]; v_n int; v_expected int; v_reactivated int:=0; v_providers int:=0;
        v_limit int; v_before jsonb; v_after jsonb; v_snapshot text; v_result jsonb; v_country uuid;
begin
  select * into p from pipeline.layer1_run_plans where run_id=p_run_id for update;
  if not found then raise exception 'run plan not found'; end if;
  if p.departures_status='applied' then return p.departures_result; end if;
  if p.course_hash='seen-tracking' then return security.layer1_seen_departures_v1(p_run_id,p_force,p_actor); end if;
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
  update catalogue.courses c set last_verified_at=now()
    from catalogue.course_registrations cr, pipeline.layer1_register_row_state s
   where cr.course_id=c.id and lower(cr.scheme)='cricos' and cr.status='active' and s.source_id=p.source_id and s.record_key=upper(cr.registration_code)
     and s.seen_at>=p.created_at-interval '1 hour' and c.lifecycle_status='active' and (c.last_verified_at is null or c.last_verified_at<now()-interval '30 days');
  update catalogue.providers pv set last_verified_at=now()
   where pv.country_id=v_country and pv.lifecycle_status='active' and (pv.last_verified_at is null or pv.last_verified_at<now()-interval '30 days')
     and exists (select 1 from catalogue.courses c where c.provider_id=pv.id and c.lifecycle_status='active' and c.last_verified_at>=now()-interval '1 hour');
  if v_expected>0 or v_reactivated>0 then
    insert into search.refresh_requests(requested_by) values (format('register departures: %s retired, %s reactivated (run %s)', v_expected, v_reactivated, left(p_run_id::text,8)));
  end if;
  v_result:=jsonb_build_object('status','applied','departed',p.departed_count,'retired',v_expected,'reactivated',v_reactivated,'providers_to_review',v_providers,'approved_by',p_actor);
  update pipeline.layer1_run_plans set departures_status='applied', departures_result=v_result where run_id=p_run_id;
  return v_result;
end $function$
