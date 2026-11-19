-- CF-247 s767: consolidated lanes read as live in the idle pause and the telemetry; the three CHRONIC_FAIL jobs brought under the statement limit
-- (Platform Admin 19 Nov 2026 11:34 AEDT, chat S1-Build).
-- Measured read only on production 19 Nov 2026 11:05–11:45 AEDT:
--   * security.flag_jobs_v1 finds coverage-sweep lanes only through their cron.job rows. It already switches a live lane in the registry
--     (job_switched_on_v1, job_switch_v1), but once PASTE-20261119-pr4-legacy-unschedule.sql (and the PR 3 file) remove those rows, the 8 PR 4
--     lanes and the PR 3 lanes would leave the idle pause. Both paste files refuse until this function reads pipeline.field_execution_registry.
--   * The telemetry exporter (Drive telemetry_snapshot_v1.sql) sums cron.job rows per worker group, so coverage-discover reads PAUSED although its
--     three lanes run every minute on coverage-lane-dispatch. security.job_effective_state_v1 gives each job a live dispatcher holds its runner,
--     state and runs, for the exporter's revision 4.
--   * CHRONIC_FAIL (48 hours): waste-guard 7 of 48 runs, no-page-propose 10 of 48, scholarship-coverage-classify 14 of 48; every failure is the
--     120-second platform statement_timeout (platform-defaults.conf), every success 38 to 119 seconds, failures in load windows (18 Nov 17:00–22:00,
--     19 Nov 07:00–11:00). The overlaps with entry-matrix-read, queue-watch and provider-description-read are artefacts of the long runs.
--       - waste-guard: security.ops_cost_guard_v1's measure (ops_cost_waste_v1) took 44 s of the 59 s median on its own; the three guards share
--         one statement with it. The cost measure moves to its own rollup-scheduler target, ops-cost-guard, inside the scheduler's tick budget.
--       - scholarship-coverage-classify: 120 providers a run, per-provider host checks; 80 keeps the 36-hour maximum age (2,565 providers) and
--         about two thirds of the run time.
--       - no-page-propose: 40 providers a run (candidate query 13.5 s, the rest per provider); 25 keeps it about 65 s.
--   * security.waste_idle_guard_v1 switches a job it paused back on with cron.alter_job, bypassing UR-07; course-link-reverse (retiring) is in
--     its watch list with paused_at set. A retiring or retired job is now never switched on here.
-- Replaces: the cost measure inside waste_guard_v1 (now rollup target ops-cost-guard); the cron.job-only lane loop of flag_jobs_v1.
-- Retires: nothing.
-- G1: no cron job added, changed or removed (the cost measure is a rollup target). G2: no new setting; two existing settings changed with reasons;
-- the target's call_sql has no number. G3: untouched (security schema only; no table, no consumer API function).

do $$
begin
  if md5(pg_get_functiondef('security.flag_jobs_v1()'::regprocedure)) <> 'd9e713cb99b993bb3d8aa70cbdcffb53' then
    raise exception 'pre-check: security.flag_jobs_v1 changed since it was read (19 Nov 2026 11:10)';
  end if;
  if md5(pg_get_functiondef('security.waste_guard_v1()'::regprocedure)) <> '49b86d8c8cac388957761e17b9f2dc28' then
    raise exception 'pre-check: security.waste_guard_v1 changed since it was read (19 Nov 2026 11:10)';
  end if;
  if md5(pg_get_functiondef('security.waste_idle_guard_v1()'::regprocedure)) <> 'fd568881335072f7ca0ff3a7b4560a65' then
    raise exception 'pre-check: security.waste_idle_guard_v1 changed since it was read (19 Nov 2026 11:40)';
  end if;
  if exists (select 1 from pipeline.rollup_targets where target_code = 'ops-cost-guard') then
    raise exception 'pre-check: rollup target ops-cost-guard already exists';
  end if;
end $$;

-- 1. The idle pause reads live lanes from the registry: while a lane's legacy cron.job row exists it is found through it (unchanged); once the row
--    is unscheduled, the live registry lane is found directly. job_switched_on_v1 and job_switch_v1 already decide a live lane from the registry.
create or replace function security.flag_jobs_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare j record; f pipeline.enrichment_flags; v_n int; v_work int; v_since timestamptz; v_until timestamptz; v jsonb := '[]'::jsonb;
        v_need int := security.pipeline_num_v1('flag.empty_calls_to_pause', 30)::int;
        -- SS-014 D14 (2 Nov 2026): only calls old enough to have answered are counted; the call still under way is never one of the last runs
        v_answered timestamptz := now() - make_interval(secs => security.pipeline_num_v1('flag.answer_wait_seconds', 120));
        v_never text[] := coalesce((select array(select jsonb_array_elements_text(s.value)) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'flag.never_pause_modes'), '{}');
begin
  -- s767 (19 Nov 2026): the legacy cron.job rows (while they exist) and the live registry lanes whose legacy row is gone (after the unschedule paste file)
  for j in select c.jobid, c.jobname, c.active, (regexp_match(c.command, $re$'mode',\s*'([a-z_0-9]+)'$re$))[1] mode
             from cron.job c where c.command like '%svc_pilot_submit_nonce(''coverage-sweep''%'
           union all
           select null::bigint, r.legacy_job, r.enabled, (regexp_match(r.call_sql, $re$'mode',\s*'([a-z_0-9]+)'$re$))[1]
             from pipeline.field_execution_registry r
            where r.kind = 'worker_lane' and r.mode = 'live' and r.legacy_job is not null and r.call_sql like '%svc_pilot_submit_nonce(''coverage-sweep''%'
              and not exists (select 1 from cron.job c2 where c2.jobname = r.legacy_job) loop
    continue when j.mode is null or j.mode = any (v_never);
    select * into f from pipeline.enrichment_flags x where x.entity = 'job' and x.entity_key = j.jobname and x.field = '' and x.reason_code = 'idle_paused';
    if security.job_switched_on_v1(j.jobid, j.jobname) and (f.id is null or f.state <> 'raised') then  -- PR 3 prerequisite (17 Nov 2026): a live lane decides
      select count(*), count(*) filter (where coalesce(security.worker_call_work_v1(r.content), 1) > 0), min(l.created_at), max(l.created_at) into v_n, v_work, v_since, v_until
        from (select l2.* from pipeline.edge_request_log l2 where l2.function_name = 'coverage-sweep' and l2.mode = j.mode and l2.created_at > coalesce(f.released_at, '-infinity') and l2.created_at <= v_answered
               order by l2.created_at desc limit v_need) l
        join net._http_response r on r.id = l.request_id where r.status_code = 200;
      if v_n >= v_need and v_work = 0
         and not (security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 and security.lane_task_waiting_v1(j.mode)) then  -- CF-247 IQ-00064: a lane a task waits for is held, not idle
        perform security.job_switch_v1(j.jobid, j.jobname, false);
        perform security.flag_raise_v1('job', j.jobname, null, '', 'idle_paused', format('Paused: its last %s runs found nothing to do (worker mode %s)', v_n, j.mode), 'hard', 'flag-recheck', 'auto',
          jsonb_build_object('mode', j.mode, 'runs', v_n, 'with_work', 0, 'from', v_since, 'to', v_until),
          null, now() + least(make_interval(hours => coalesce(security.flag_list_num_v1('flag.job_recheck_hours', coalesce(f.checks, 0)), 6)),
                                 make_interval(mins => security.pipeline_num_v1('tick.backoff_max_minutes', 15)::int)));  /* R1 Q2 (24 Oct 2026): never longer than the backoff cap */
        v := v || jsonb_build_object('paused', j.jobname);
      end if;
    elsif not security.job_switched_on_v1(j.jobid, j.jobname) and f.state = 'raised' and f.reason_code = 'idle_paused' and (f.next_check_at <= now() or security.worker_mode_waiting_v1(j.mode)
                                                                                or (security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 and security.lane_task_waiting_v1(j.mode)))  -- 19 Oct: on again when work is waiting
          and not security.job_held_off_v1(j.jobname) then  -- CF-247 IQ-00060: never a job a person or a governed restore switched off (jobs.held_off)
      perform security.flag_release_v1(f.id, 'flag-recheck', 'auto', 'Trial run: switched on again to look for new work', jsonb_build_object('mode', j.mode, 'check', f.checks + 1), true);
      v := v || jsonb_build_object('trial', j.jobname);
    end if;
  end loop;
  return v;
end $function$;

-- 2. The waste guard keeps its three guards; the cost measure runs as its own rollup-scheduler target (below)
create or replace function security.waste_guard_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  -- s767 (19 Nov 2026): the cost and yield measure (CF-247 workstream F, P0 AI operations §11) runs as rollup target ops-cost-guard, so the
  -- 44-second measure no longer shares this job's statement limit with the three guards
  return jsonb_build_object('idle', security.waste_idle_guard_v1(), 'frozen', security.waste_flipflop_guard_v1(), 'flags', security.enrichment_flags_refresh_v1(),
    'cost', 'rollup target ops-cost-guard');
end $function$;

-- 3. The idle guard never switches a retiring or retired job on again (UR-07, as security.job_switch_v1)
create or replace function security.waste_idle_guard_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare w record; v_jobid bigint; v_active boolean; v_out bigint; v_inp bigint; v jsonb := '[]'::jsonb;
        v_hours int := security.pipeline_num_v1('waste.idle_pause_hours', 24)::int;
begin
  -- Pipeline Maintenance Mode (15 Nov 2026): while paused, no job is switched off or on here
  if security.maintenance_hold_v1() then return jsonb_build_array(jsonb_build_object('maintenance', 'paused')); end if;
  for w in select * from pipeline.job_idle_watch order by jobname loop
    select j.jobid, j.active into v_jobid, v_active from cron.job j where j.jobname = w.jobname;
    continue when v_jobid is null;
    -- s767 (19 Nov 2026), UR-07: a retiring or retired job is left as it is (its dispatcher, or nothing, does its work)
    continue when exists (select 1 from pipeline.component_register r where r.kind = 'job' and r.name = w.jobname and r.status in ('retiring', 'retired'));
    execute w.output_sql into v_out using now() - make_interval(hours => v_hours);
    execute w.input_sql into v_inp;
    update pipeline.job_idle_watch set last_checked_at = now(), last_output = v_out, last_input = v_inp where jobname = w.jobname;
    if v_active and coalesce(v_out, 0) = 0 and coalesce(v_inp, 0) = 0 and coalesce(w.resumed_at, '-infinity') < now() - make_interval(hours => v_hours) then
      perform cron.alter_job(v_jobid, active := false);
      update pipeline.job_idle_watch set paused_at = now() where jobname = w.jobname;
      insert into pipeline.enrichment_flags(entity, entity_key, field, reason_code, reason, source)
      values ('job', w.jobname, '', 'idle_paused', format('Paused: no output for %s hours and nothing waiting. %s', v_hours, coalesce(w.note, '')), 'waste-guard')
      on conflict (entity, entity_key, field, reason_code) do update set reason = excluded.reason, flagged_at = now(), cleared_at = null;
      v := v || jsonb_build_object('paused', w.jobname);
    elsif not v_active and w.paused_at is not null and coalesce(v_inp, 0) > 0 then
      -- only a job this guard paused is switched on again
      perform cron.alter_job(v_jobid, active := true);
      update pipeline.job_idle_watch set paused_at = null, resumed_at = now() where jobname = w.jobname;
      update pipeline.enrichment_flags set cleared_at = now() where entity = 'job' and entity_key = w.jobname and reason_code = 'idle_paused' and cleared_at is null;
      v := v || jsonb_build_object('resumed', w.jobname);
    end if;
  end loop;
  return v;
end $function$;

-- 4. The cost and yield measure as its own rollup target: hourly at :43 (no other hourly target starts then), after the quick targets
insert into pipeline.rollup_targets(target_code, legacy_job, call_sql, call_md5, schedule, rollup_group, priority, enabled, mode, expected_ms, note)
values ('ops-cost-guard', null, 'select security.ops_cost_guard_v1()', md5('select security.ops_cost_guard_v1()'), '43 * * * *', 'A', 90, true, 'live', 45000,
        's767 (19 Nov 2026): moved out of waste-guard (44 s measured of its 59 s median), so the guard and the measure each stay under the statement limit; '
        || 'expected_ms is the measured run, so the tick budget starts it only with room to finish');

-- 5. Per-run sizes, inside the statement limit with headroom
update pipeline.platform_toolset_settings
   set value = to_jsonb(80),
       reason = 's767 (19 Nov 2026, Platform Admin 11:34 directive): 14 of 48 runs hit the 120-second statement limit at 120 providers; 80 keeps the '
             || '36-hour maximum age for the 2,565 providers in scope and about two thirds of the run',
       updated_by = 'migration 20261119120000', updated_at = now()
 where toolset_key = 'pipeline' and key = 'batch.sch_coverage_classify' and value = to_jsonb(120);
update pipeline.platform_toolset_settings
   set value = to_jsonb(25),
       reason = 's767 (19 Nov 2026, Platform Admin 11:34 directive): 10 of 48 runs hit the 120-second statement limit at 40 providers (median 97 s; '
             || 'candidate query 13.5 s, the rest per provider); 25 keeps a run near 65 s',
       updated_by = 'migration 20261119120000', updated_at = now()
 where toolset_key = 'pipeline' and key = 'bind.no_page_providers_per_run' and value = to_jsonb(40);

-- 6. Effective state of a job a live dispatcher holds (read only), for the telemetry exporter's revision 4 and the job governance audit
create or replace function security.job_effective_state_v1(p_since timestamptz, p_recent timestamptz)
 returns table(jobname text, runner text, target_code text, effective_active boolean, ok_since bigint, fail_since bigint, fail_recent bigint,
               avg_sec numeric, last_end timestamptz)
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  with t as (
    select r.legacy_job jobname, 'coverage-lane-dispatch'::text runner, r.lane_code code, r.enabled
      from pipeline.field_execution_registry r where r.kind = 'worker_lane' and r.mode = 'live' and r.legacy_job is not null
    union all
    select t.legacy_job, 'rollup-scheduler', t.target_code, t.enabled from pipeline.rollup_targets t where t.mode = 'live' and t.legacy_job is not null
    union all
    select a.legacy_job, 'admission-rule-runner', a.rule_code, a.enabled from pipeline.admission_rules a where a.mode = 'live' and a.legacy_job is not null)
  select t.jobname, t.runner, t.code,
         t.enabled and exists (select 1 from cron.job d where d.active and (d.jobname = t.runner or d.jobname ~ ('^' || t.runner || '-[a-z]$'))),
         x.ok, x.fail, x.fail_recent, round(x.avg_sec, 2), x.last_end
    from t cross join lateral (
      select count(*) filter (where s.status = 'succeeded') ok, count(*) filter (where s.status = 'failed') fail,
             count(*) filter (where s.status = 'failed' and s.due_at > p_recent) fail_recent,
             avg(s.ms) filter (where s.ms is not null) / 1000.0 avg_sec, max(s.finished_at) last_end
        from (select c.status, c.due_at, c.ms, c.finished_at from pipeline.coverage_lane_runs c where t.runner = 'coverage-lane-dispatch' and c.lane_code = t.code and c.due_at > p_since
              union all
              select u.status, u.due_at, u.ms, u.finished_at from pipeline.rollup_runs u where t.runner = 'rollup-scheduler' and u.target_code = t.code and u.due_at > p_since
              union all
              select a.status, a.due_at, a.ms, a.finished_at from pipeline.admission_rule_runs a where t.runner = 'admission-rule-runner' and a.rule_code = t.code and a.due_at > p_since) s) x
$function$;
revoke all on function security.job_effective_state_v1(timestamptz, timestamptz) from public, anon, authenticated, service_role;
comment on function security.job_effective_state_v1(timestamptz, timestamptz) is
  's767 (19 Nov 2026): for each legacy job a live dispatcher target holds (coverage-lane-dispatch, rollup-scheduler, admission-rule-runner), its runner, '
  'whether it is effectively on (target enabled and the dispatcher job active), and its runs since p_since (failed since p_recent). Read only.';

-- post-checks
do $$
declare v_n int;
begin
  if position('field_execution_registry' in (select prosrc from pg_proc where oid = 'security.flag_jobs_v1()'::regprocedure)) = 0 then
    raise exception 'post-check: flag_jobs_v1 does not read the registry';
  end if;
  if position('ops_cost_guard_v1' in (select prosrc from pg_proc where oid = 'security.waste_guard_v1()'::regprocedure)) > 0 then
    raise exception 'post-check: waste_guard_v1 still runs the cost measure';
  end if;
  if not exists (select 1 from pipeline.rollup_targets where target_code = 'ops-cost-guard' and mode = 'live' and enabled and call_md5 = md5(call_sql)) then
    raise exception 'post-check: rollup target ops-cost-guard is not live';
  end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'batch.sch_coverage_classify') <> to_jsonb(80)
     or (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'bind.no_page_providers_per_run') <> to_jsonb(25) then
    raise exception 'post-check: a per-run size was not set (changed since it was read?)';
  end if;
  select count(*) into v_n from security.job_effective_state_v1(now() - interval '1 hour', now() - interval '1 hour')  -- fixed: a post-check window
   where jobname in ('coverage-discover', 'coverage-discover-2', 'page-text') and runner = 'coverage-lane-dispatch' and effective_active;
  if v_n <> 3 then raise exception 'post-check: % of 3 PR 4 lanes read as live through job_effective_state_v1', v_n; end if;
  if exists (select 1 from cron.job where jobname = 'course-link-reverse' and active) then
    raise exception 'post-check: course-link-reverse (retiring) is switched on';
  end if;
end $$;
