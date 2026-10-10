CREATE OR REPLACE FUNCTION security.layer1_seen_departures_v1(p_run_id uuid, p_force boolean DEFAULT false, p_actor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'security', 'search'
AS $function$
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

  select coalesce(array_agg(distinct c.id),'{}') into v_ids
    from catalogue.courses c
    join catalogue.providers p on p.id=c.provider_id and p.country_id=v_country
    join catalogue.provider_registrations pr on pr.provider_id=p.id and lower(pr.registration_scheme)=v_scheme and pr.checked_at>=v_since
    join catalogue.course_registrations cr on cr.course_id=c.id and lower(cr.scheme)=v_scheme
   where c.lifecycle_status='active'
     and not exists (select 1 from pipeline.layer1_register_row_state s where s.source_id=q.source_id
                      and s.record_key=upper(pr.registration_code)||'|'||upper(cr.registration_code) and s.seen_at>=v_since-interval '1 day');
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
end $function$
