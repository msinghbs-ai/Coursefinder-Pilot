-- CF-247 consolidation PR 1 cutover: rollup-scheduler takes over the 25 legacy report and cache jobs registered in pipeline.rollup_targets
-- (group A, enabled; layer2-onboarding-snapshot stays on its own job). Platform Admin 17 Nov 2026 23:07 ("promote PR 1 live as soon as the
-- shadow checks pass") and the decision recorded at the review (17 Nov 2026 ~23:20 AEDT, option "Accept and cut over now").
-- Replaces: the 25 legacy cron jobs of pipeline.rollup_targets group A (switched off, active = false; marked retiring).
-- Retires: those 25 jobs (component register: retiring, replaced_by rollup-scheduler, retire_after = today + hygiene.retire_after_days).
--          They are unscheduled by coursefinder-admin docs/paste/PASTE-20261118-rollup-legacy-unschedule.sql after the retention window;
--          a migration drops nothing.
--
-- Shadow review (read only, 17 Nov 2026 23:07 AEDT, 24 hours from 12:07Z 16 Nov; fix live 23:14 AEDT 16 Nov, Pilot #1187):
--   - 25 targets dispatched, 0 failed or refused runs; 26 legacy jobs unchanged and active (25 registered by md5 and schedule, plus
--     layer2-onboarding-snapshot on its own job); no tick ran over 60 s after its minute (largest 57.5 s, 9 of 1,441 ticks over 30 s).
--   - 22 of 25 targets match the legacy starts by dispatch count. The 3 every-minute targets (admin-read-snapshots, data-delivery, lane-funnel)
--     had 1,437 dispatches against 1,444 legacy starts, but covered exactly the same 1,444 due minutes: pg_cron started 3 ticks late at busy
--     minutes (:17, :27; cron.max_running_jobs 32 with all legacy jobs still scheduled), and the next tick took both minutes in one dispatch,
--     as designed. The Platform Admin accepted minute coverage as the gate for this cutover; switching the 25 legacy jobs off removes most
--     of that start contention.
--
-- Gate (in this migration, so it applies only while it holds): over the last 24 hours, for every one of the 25 targets the due minutes the
-- scheduler covered equal the legacy job's starts within 1 per day, and no run failed or was refused; every legacy job still carries
-- exactly the registered command and schedule (md5) and is active; no target is live yet. Otherwise nothing changes and the deploy reports why.
-- In one transaction: the 25 targets go live (the scheduler runs them from its next tick) and the 25 legacy jobs are switched off, so no
-- report runs twice. Every change is logged in pipeline.admin_control_events.
-- G1: rollup-scheduler is catalogued (consolidation PR 1). G2: no new setting, no number in a job command. G3: no consumer API object read
-- or changed. Nothing dropped.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the cron and target updates below

do $cut$
declare
  v_from timestamptz := now() - interval '24 hours'; -- fixed: the 24-hour shadow cycle the dispatcher rule requires
  v_n int; v_bad jsonb; v_t record;
begin
  -- the gate
  if exists (select 1 from pipeline.rollup_targets where rollup_group = 'A' and mode = 'live') then
    raise exception 'gate: a rollup target is already live; this cutover runs once';
  end if;
  if (select min(started_at) from pipeline.rollup_runs where status = 'shadow_due') > v_from then
    raise exception 'gate: the shadow history does not cover 24 hours';
  end if;
  if (select count(*) from pipeline.rollup_targets where rollup_group = 'A' and enabled) <> 25 then
    raise exception 'gate: expected 25 enabled group A targets';
  end if;
  if exists (select 1 from pipeline.rollup_runs where due_at >= v_from and status in ('failed', 'refused')) then
    raise exception 'gate: a scheduler run failed or was refused in the last 24 hours';
  end if;
  with s as (select r.target_code, sum(r.due_minutes) due_minutes from pipeline.rollup_runs r
              where r.due_at >= v_from and r.status in ('shadow_due', 'succeeded') group by 1),
       l as (select j.jobname, count(*) starts from cron.job j join cron.job_run_details d on d.jobid = j.jobid
              where d.start_time >= v_from and j.jobname in (select legacy_job from pipeline.rollup_targets where rollup_group = 'A' and enabled)
              group by 1)
  select jsonb_agg(jsonb_build_object('target', t.target_code, 'due_minutes', coalesce(s.due_minutes, 0), 'legacy_starts', coalesce(l.starts, 0)))
    into v_bad
    from pipeline.rollup_targets t
    left join s on s.target_code = t.target_code
    left join l on l.jobname = t.legacy_job
   where t.rollup_group = 'A' and t.enabled
     and abs(coalesce(s.due_minutes, 0) - coalesce(l.starts, 0)) > 1;
  if v_bad is not null then raise exception 'gate: minute coverage differs from the legacy starts: %', v_bad; end if;
  select count(*) into v_n from pipeline.rollup_targets t join cron.job j on j.jobname = t.legacy_job
   where t.rollup_group = 'A' and t.enabled and t.mode = 'shadow' and j.active and md5(j.command) = t.call_md5 and j.schedule = t.schedule;
  if v_n <> 25 then raise exception 'gate: % of 25 legacy jobs still carry the registered command and schedule and are active', v_n; end if;

  -- the cutover
  for v_t in select t.target_code, t.legacy_job, j.jobid from pipeline.rollup_targets t join cron.job j on j.jobname = t.legacy_job
            where t.rollup_group = 'A' and t.enabled order by t.target_code loop
    perform cron.alter_job(v_t.jobid, active => false);
    update pipeline.rollup_targets set mode = 'live', updated_at = now(),
           note = coalesce(note || '; ', '') || 'live from cutover 20261118010000 (Platform Admin 17 Nov 2026 23:07; 24-hour shadow, minute coverage matched)'
     where target_code = v_t.target_code;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('scheduler', 'dispatcher_cutover', v_t.legacy_job,
            jsonb_build_object('dispatcher', 'rollup-scheduler', 'target', v_t.target_code, 'legacy_job_active', false, 'mode', 'live',
                               'shadow_from', v_from, 'by', 'migration 20261118010000'), null);
  end loop;

  update pipeline.component_register c
     set status = 'retiring', replaced_by = 'rollup-scheduler (pipeline.rollup_targets, mode live)',
         retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,
         note = 'switched off at the consolidation PR 1 cutover (20261118010000); unscheduled by docs/paste/PASTE-20261118-rollup-legacy-unschedule.sql after retire_after'
    from pipeline.rollup_targets t
   where c.kind = 'job' and c.name = t.legacy_job and c.status = 'active' and t.rollup_group = 'A' and t.enabled;
end $cut$;

do $post$
begin
  if (select count(*) from pipeline.rollup_targets where rollup_group = 'A' and enabled and mode = 'live') <> 25 then
    raise exception 'post-check: not all 25 targets are live'; end if;
  if exists (select 1 from cron.job j join pipeline.rollup_targets t on t.legacy_job = j.jobname where t.rollup_group = 'A' and t.enabled and j.active) then
    raise exception 'post-check: a legacy report job is still switched on'; end if;
  if (select count(*) from pipeline.component_register c join pipeline.rollup_targets t on c.kind = 'job' and c.name = t.legacy_job
       where t.rollup_group = 'A' and t.enabled and c.status = 'retiring') <> 25 then
    raise exception 'post-check: not all 25 legacy jobs are retiring'; end if;
  if not exists (select 1 from cron.job where jobname = 'layer2-onboarding-snapshot' and active) then
    raise exception 'post-check: layer2-onboarding-snapshot must stay on its own job'; end if;
  if not exists (select 1 from cron.job where jobname = 'rollup-scheduler' and active) then raise exception 'post-check: rollup-scheduler must be switched on'; end if;
  if coalesce((security.pipeline_num_v1('rollup.scheduler_on', 0))::int, 0) <> 1 then raise exception 'post-check: rollup.scheduler_on must be 1'; end if;
end $post$;
