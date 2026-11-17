-- CF-247 S1-Build (Platform Admin 17 Nov 2026 13:11): temporarily pause low-yield background jobs, so database connections and worker
-- leases stay free for the bulk REQ and Roadmap ingestion.
-- Evidence (read 17 Nov 2026 13:2x AEDT, security.job_outcomes_v1(72) and cron.job_run_details, last 72 hours):
--   scholarship-discover-refill  hourly; 86 s a run, 102 busy minutes, 8 of 71 runs failed; it lines up providers for the lane below
--   scholarship-discover         1 of 399 runs moved anything (95 zero-work errors)
--   scholarship-read             0 of 767 runs moved anything
--   calendar-reread              0 of 70 runs moved anything
-- Kept on: every legacy job shadowed by PR 1 (pipeline.rollup_targets, 26), PR 2 (pipeline.admission_rules, 20) and PR 3
-- (coverage-lane-dispatch, 13 lanes, including coverage-reextract and policy-add-tests, which are also idle), and the dispatchers
-- themselves; openrouter-balance (feeds the OpenRouter credit floor); coverage-discover, coverage-read and scholarship-listing (still
-- moving work).
-- A pause is what Automations › Pause does (security.admin_automation_control_v1 'pause': cron.alter_job active false and an
-- admin_control_events row), so the jobs show as paused there with this reason, and Resume on Automations switches them back on.
-- Nothing is dropped, unscheduled or changed: each command, schedule and register row stays as it is. G1: no new job. G2: no setting.
-- G3: no consumer API object.
-- Replaces: nothing
-- Retires: nothing (a temporary pause; the jobs stay active in pipeline.component_register)

set local lock_timeout = '5s';

do $pause$
declare
  v_jobs constant text[] := array['scholarship-discover-refill', 'scholarship-discover', 'scholarship-read', 'calendar-reread'];
  v_reason constant text := 'Temporarily paused for bulk REQ and Roadmap ingestion (Platform Admin 17 Nov 2026 13:11): no or almost no work moved in 72 hours. Resume on Automations.';
  r record; v_n int := 0;
begin
  -- never one of the three schedulers' shadowed or live jobs
  if exists (select 1 from unnest(v_jobs) x where x in (select legacy_job from pipeline.rollup_targets)
                                              or x in (select legacy_job from pipeline.admission_rules)
                                              or x in (select lane_code from pipeline.coverage_lane_runs where tick_at > now() - interval '1 day')
                                              or x in ('rollup-scheduler', 'coverage-lane-dispatch')
                                              or x like 'admission-rule-runner%') then
    raise exception 'a job in this pause belongs to PR 1, PR 2 or PR 3';
  end if;
  for r in select j.jobid, j.jobname from cron.job j where j.jobname = any (v_jobs) and j.active loop
    perform cron.alter_job(r.jobid, active => false);
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('automations', 'pause', r.jobname, jsonb_build_object('reason', v_reason, 'by', 'migration 20261117051700', 'temporary', true), null);
    v_n := v_n + 1;
  end loop;
  raise notice 'paused % job(s)', v_n;
end $pause$;

-- Post-checks
do $c$
begin
  if exists (select 1 from cron.job where jobname in ('scholarship-discover-refill', 'scholarship-discover', 'scholarship-read', 'calendar-reread') and active) then
    raise exception 'post-check: a job in this pause is still active';
  end if;
  if (select count(*) from cron.job where jobname in ('scholarship-discover-refill', 'scholarship-discover', 'scholarship-read', 'calendar-reread')) <> 4 then
    raise exception 'post-check: expected 4 jobs';
  end if;
  if not exists (select 1 from cron.job where jobname = 'rollup-scheduler' and active) or not exists (select 1 from cron.job where jobname = 'coverage-lane-dispatch' and active) then
    raise exception 'post-check: a scheduler is not running';
  end if;
end $c$;
