CREATE OR REPLACE FUNCTION security.job_run_now_v1(p_job text, p_reason text, p_args jsonb, p_requester uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cap int := security.pipeline_num_v1('run_now.pilot_cap', 20)::int;
        v_id uuid := gen_random_uuid(); v_key text := nullif(btrim(coalesce(p_args->>'idempotency_key', '')), '');
        v_cohort pipeline.run_now_cohorts%rowtype; v_ids uuid[]; v_rank int; v_cat pipeline.automation_catalogue%rowtype;
        v_prev pipeline.admin_jobs%rowtype; v_why text; v_res jsonb; v_start timestamptz := clock_timestamp(); v_calls int; v_by jsonb; v_holder jsonb;
        v_err text; v_title text;
begin
  if p_requester is null then raise exception 'a requester is required'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'a reason is required'; end if;
  if v_key is not null then
    select * into v_prev from pipeline.admin_jobs where kind = 'job_run_now' and args->>'idempotency_key' = v_key;
    if found then return jsonb_build_object('run_id', v_prev.id, 'state', v_prev.state, 'repeat', true, 'result', v_prev.result); end if;
  end if;
  select * into v_cat from pipeline.automation_catalogue where jobname = p_job;
  select coalesce(max(r.rank), 0) into v_rank from security.user_roles ur join security.roles r on r.code = ur.role_code
   where ur.user_id = p_requester and (ur.expires_at is null or ur.expires_at > now()) and r.status = 'active';
  select * into v_cohort from pipeline.run_now_cohorts where id = nullif(p_args->>'cohort_id', '')::uuid;
  v_ids := array(select m.course_id from pipeline.run_now_cohort_members m where m.cohort_id = v_cohort.id order by m.pick);
  v_why := case
    when not (p_job = any (array(select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'run_now.jobs'), '[]'::jsonb))))) then 'job is not on the Run now list'
    when v_cat.jobname is null then 'job is not catalogued'
    when v_rank < greatest(coalesce(v_cat.control_rank, 6), 1) then 'requester rank ' || v_rank || ' is below the job''s rank ' || coalesce(v_cat.control_rank, 6)
    when not exists (select 1 from cron.job j where j.jobname = p_job) then 'job is not scheduled'
    when exists (select 1 from cron.job j where j.jobname = p_job and not j.active) then 'job is paused'
    when p_job = 'intake-dates-apply' and not coalesce((security.toolset_setting('pipeline', 'intake_dates.apply_enabled') #>> '{}')::boolean, false) then 'job switch is off (Intake dates: on)'
    when p_job <> 'intake-dates-apply' then 'no bounded runner for this job'
    when v_cohort.id is null then 'a cohort_id is required'
    when v_cohort.job <> p_job then 'cohort belongs to job ' || v_cohort.job
    when coalesce(cardinality(v_ids), 0) = 0 then 'cohort has no courses'
    when cardinality(v_ids) > v_cap then 'cohort has ' || cardinality(v_ids) || ' courses, over the cap of ' || v_cap
    when not pg_try_advisory_xact_lock(hashtext('cf247 intake dates apply')) then 'a run of this job is in progress'  -- the job's own lock, tried, never waited for
  end;
  v_title := 'Run now: ' || coalesce(v_cat.label, p_job) || coalesce(' (' || v_cohort.label || ')', '');
  if v_why is not null then
    if v_why = 'a run of this job is in progress' then
      select jsonb_build_object('pid', a.pid, 'since', a.query_start, 'query', left(a.query, 160)) into v_holder
        from pg_catalog.pg_locks l join pg_catalog.pg_stat_activity a on a.pid = l.pid
       where l.locktype = 'advisory' and l.granted and l.objid = (hashtext('cf247 intake dates apply')::bigint & 4294967295)::oid and a.pid <> pg_backend_pid() limit 1;
    end if;
    insert into pipeline.admin_jobs(id, kind, lane, state, title, args, result, requested_by, reason, created_at, started_at, updated_at, finished_at, scope, outcome)
    values (v_id, 'job_run_now', 'run_now', 'cancelled', v_title || ' (refused)',
            jsonb_strip_nulls(jsonb_build_object('job', p_job, 'cohort_id', v_cohort.id, 'idempotency_key', v_key)),
            jsonb_strip_nulls(jsonb_build_object('refused', v_why, 'in_flight', v_holder)), p_requester, btrim(p_reason), v_start, v_start, clock_timestamp(), clock_timestamp(),
            'cohort:' || coalesce(v_cohort.id::text, '-'), 'refused');
    return jsonb_strip_nulls(jsonb_build_object('run_id', v_id, 'state', 'refused', 'refused', v_why, 'in_flight', v_holder));
  end if;
  begin
    v_res := security.intake_dates_apply_v1(security.pipeline_num_v1('batch.intake_dates_apply', 200)::int, v_ids);
  exception when others then
    get stacked diagnostics v_err = message_text;
  end;
  -- vendor calls made while it ran (the job reads stored readings only; any call here is unexpected spend)
  select count(*) into v_calls from pipeline.edge_request_log l where l.created_at >= v_start;
  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) into v_by from (
    select d.outcome || coalesce(': ' || d.reason, '') k, count(*) n from pipeline.course_intake_dates d
     where d.course_id = any (v_ids) and d.applied_at = now() group by 1) x;
  v_res := coalesce(v_res, '{}'::jsonb) || jsonb_build_object(
    'processed', coalesce((v_res->>'looked_at')::int, 0), 'admitted', coalesce((v_res->>'filled')::int, 0),
    'skipped', coalesce((v_res->>'looked_at')::int, 0) - coalesce((v_res->>'filled')::int, 0), 'failed', case when v_err is null then 0 else 1 end,
    'by_outcome', v_by, 'vendor_calls', v_calls, 'cohort_id', v_cohort.id, 'courses', cardinality(v_ids), 'error', v_err);
  insert into pipeline.admin_jobs(id, kind, lane, state, title, args, result, error, requested_by, reason, created_at, started_at, updated_at, finished_at, scope, outcome)
  values (v_id, 'job_run_now', 'run_now', case when v_err is null then 'done' else 'failed' end, v_title,
          jsonb_strip_nulls(jsonb_build_object('job', p_job, 'cohort_id', v_cohort.id, 'idempotency_key', v_key, 'courses', cardinality(v_ids))),
          v_res, v_err, p_requester, btrim(p_reason), v_start, v_start, clock_timestamp(), clock_timestamp(), 'cohort:' || v_cohort.id, case when v_err is null then 'ran' else 'failed' end);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('run_now', case when v_err is null then 'ran' else 'failed' end, p_job, jsonb_build_object('task', v_id, 'cohort_id', v_cohort.id, 'result', v_res), p_requester);
  return jsonb_build_object('run_id', v_id, 'state', case when v_err is null then 'done' else 'failed' end, 'started_at', v_start, 'finished_at', clock_timestamp()) || v_res;
end $function$

