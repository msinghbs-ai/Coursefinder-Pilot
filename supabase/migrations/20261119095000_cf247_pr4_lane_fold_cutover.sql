-- CF-247 consolidation PR 4 cutover: coverage-lane-dispatch takes over page-text and the 7 single-mode coverage-sweep jobs, and rollup-scheduler
-- takes over settings-backup-daily (Platform Admin 18 Nov 2026 14:24, chat S1-Build; Pilot CLAUDE.md "Cron dispatchers").
-- Shadow: 20261118170000 (Pilot #1282, live 18 Nov 2026 14:59 AEDT): 8 lanes and 1 rollup target registered byte for byte, mode shadow.
-- Replaces: the 9 legacy cron jobs coverage-discover, coverage-discover-2, coverage-ai-match, central-find, logo-find, ops-diagnose,
--           scholarship-listing, page-text and settings-backup-daily: switched off (active = false) and marked retiring.
-- Retires: those 9 jobs (component register: retiring, replaced_by the dispatcher, retire_after = today + hygiene.retire_after_days). They are
--          unscheduled by coursefinder-admin docs/paste/PASTE-20261119-pr4-legacy-unschedule.sql after the retention window; a migration drops nothing.
--
-- Early cutover (Platform Admin 19 Nov 2026 07:47 AEDT, chat S1-Build): "Do NOT wait until 15:10 AEDT — execute the PR 4 cron fold cutover
--   immediately so DB contention drops while the S2 data-admittance drains run", verified on today's completed 06:50 AEDT settings-backup-daily
--   and rollup-scheduler runs instead of the full 24-hour cycle of the Cron dispatchers rule (about 17 hours of shadow, every PR 4 legacy job
--   started at least once in it).
-- Gate, in this migration, so it applies only when it holds (otherwise nothing changes and the deploy reports the reason):
--   * no PR 4 target is live yet; the shadow is the one registered by 20261118170000 (18 Nov 2026 14:59 AEDT);
--   * today's settings-backup-daily start (06:50 AEDT) succeeded and its shadow_due rollup run holds the same minute; the latest finished
--     rollup-scheduler tick succeeded;
--   * minute coverage (the measure accepted for PR 1, Platform Admin 17 Nov 2026 23:20): for each of the 8 lanes, every minute its legacy job
--     started in the window has a dispatcher row for that minute (shadow_due, or deferred while the legacy job was off), at most 1 boundary minute
--     apart; no refused dispatch (call_sql changed). The dispatcher may hold more minutes than the legacy job: pg_cron skips a legacy start at
--     busy minutes (cron.max_running_jobs), the dispatcher does not;
--   * settings-backup-daily: every legacy start in the window has a shadow_due rollup run for that minute, and there was at least one;
--   * every legacy job still carries exactly the registered command and schedule (md5), and a legacy job that is off holds a raised idle flag.
-- In one transaction the 9 targets go live (from the next minute) and the 9 legacy jobs are switched off, so nothing runs twice. Every change is
-- logged in pipeline.admin_control_events. G1: no job is added; the dispatchers are catalogued. G2: no new setting, no number in a job command.
-- G3: no consumer API object read or changed. Nothing dropped.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the cron and registry updates below

do $cut$
declare
  v_lanes text[] := array['coverage-discover', 'coverage-discover-2', 'coverage-ai-match', 'central-find', 'logo-find', 'ops-diagnose', 'scholarship-listing', 'page-text'];
  v_from timestamptz; v_to timestamptz := date_trunc('minute', now()) - interval '1 minute'; v_bad jsonb; v_n int; r record;
begin
  -- the gate
  if exists (select 1 from pipeline.field_execution_registry where lane_code = any (v_lanes) and mode = 'live')
     or exists (select 1 from pipeline.rollup_targets where target_code = 'settings-backup-daily' and mode = 'live') then
    raise exception 'gate: a PR 4 target is already live; this cutover runs once';
  end if;
  select min(created_at) into v_from from pipeline.field_execution_registry where lane_code = any (v_lanes);
  if (select count(*) from pipeline.field_execution_registry where lane_code = any (v_lanes) and kind = 'worker_lane' and mode = 'shadow') <> 8
     or (select count(*) from pipeline.rollup_targets where target_code = 'settings-backup-daily' and mode = 'shadow' and enabled and rollup_group = 'A') <> 1 then
    raise exception 'gate: the 8 lanes and the rollup target registered by 20261118170000 must be in shadow';
  end if;
  -- early cutover authorised by the Platform Admin 19 Nov 2026 07:47 AEDT: the shadow of 20261118170000, checked on today's completed runs
  if v_from is null or v_from > timestamptz '2026-11-18 15:00:00+11' then  -- fixed: the shadow registered by 20261118170000 (live 18 Nov 14:59 AEDT)
    raise exception 'gate: the shadow has run only since %', v_from;
  end if;
  if not exists (select 1 from cron.job j join cron.job_run_details d on d.jobid = j.jobid
                   join pipeline.rollup_runs x on x.target_code = 'settings-backup-daily' and x.due_at = date_trunc('minute', d.start_time) and x.status = 'shadow_due'
                  where j.jobname = 'settings-backup-daily' and d.status = 'succeeded'
                    and (d.start_time at time zone 'Australia/Melbourne')::date = (now() at time zone 'Australia/Melbourne')::date) then
    raise exception 'gate: today''s settings-backup-daily start has not succeeded with a shadow_due rollup run for its minute';
  end if;
  if (select d.status from cron.job j join cron.job_run_details d on d.jobid = j.jobid
       where j.jobname = 'rollup-scheduler' and d.status in ('succeeded', 'failed') order by d.start_time desc limit 1) is distinct from 'succeeded' then
    raise exception 'gate: the latest finished rollup-scheduler tick did not succeed';
  end if;
  v_from := date_trunc('minute', v_from) + interval '1 minute';

  -- minute coverage per lane: legacy start minutes with no dispatcher row for that minute
  select jsonb_agg(jsonb_build_object('lane', z.lane_code, 'legacy_minutes', z.legacy_minutes, 'uncovered', z.uncovered, 'refused', z.refused)) into v_bad
    from (select fr.lane_code,
                 (select count(distinct date_trunc('minute', d.start_time)) from cron.job_run_details d where d.jobid = j.jobid and d.start_time >= v_from and d.start_time < v_to) legacy_minutes,
                 (select count(*) from (select distinct date_trunc('minute', d.start_time) m from cron.job_run_details d where d.jobid = j.jobid and d.start_time >= v_from and d.start_time < v_to) lm
                   where not exists (select 1 from pipeline.coverage_lane_runs x where x.lane_code = fr.lane_code and x.due_at = lm.m and x.status in ('shadow_due', 'deferred'))) uncovered,
                 (select count(*) from pipeline.coverage_lane_runs x where x.lane_code = fr.lane_code and x.due_at >= v_from and x.status = 'refused') refused
            from pipeline.field_execution_registry fr join cron.job j on j.jobname = fr.legacy_job
           where fr.lane_code = any (v_lanes)) z
   where z.uncovered > 1 or z.refused > 0 or z.legacy_minutes = 0;  -- fixed: 1 boundary minute
  if v_bad is not null then raise exception 'gate: minute coverage not clean for %', v_bad; end if;

  -- settings-backup-daily: every legacy start minute has a shadow_due run, and there was at least one
  select count(*) into v_n from cron.job j join cron.job_run_details d on d.jobid = j.jobid
   where j.jobname = 'settings-backup-daily' and d.start_time >= v_from and d.start_time < v_to;
  if v_n = 0 or exists (select 1 from cron.job j join cron.job_run_details d on d.jobid = j.jobid
                         where j.jobname = 'settings-backup-daily' and d.start_time >= v_from and d.start_time < v_to
                           and not exists (select 1 from pipeline.rollup_runs x where x.target_code = 'settings-backup-daily'
                                             and x.due_at = date_trunc('minute', d.start_time) and x.status = 'shadow_due')) then
    raise exception 'gate: settings-backup-daily shadow does not cover its % legacy start(s)', v_n;
  end if;

  -- the legacy jobs still carry the registered command and schedule; a job that is off is idle-paused, not paused by a person
  select count(*) into v_n from pipeline.field_execution_registry fr join cron.job j on j.jobname = fr.legacy_job
   where fr.lane_code = any (v_lanes) and md5(j.command) = fr.call_md5 and md5(fr.call_sql) = fr.call_md5 and j.schedule = fr.schedule;
  if v_n <> 8 then raise exception 'gate: % of 8 legacy jobs still carry the registered command and schedule', v_n; end if;
  if (select count(*) from pipeline.rollup_targets t join cron.job j on j.jobname = t.legacy_job
       where t.target_code = 'settings-backup-daily' and md5(j.command) = t.call_md5 and md5(t.call_sql) = t.call_md5 and j.schedule = t.schedule and j.active) <> 1 then
    raise exception 'gate: settings-backup-daily no longer carries the registered command and schedule, or is off';
  end if;
  if exists (select 1 from pipeline.field_execution_registry fr join cron.job j on j.jobname = fr.legacy_job
              where fr.lane_code = any (v_lanes) and not j.active
                and not exists (select 1 from pipeline.enrichment_flags f where f.entity = 'job' and f.entity_key = j.jobname and f.field = '' and f.reason_code = 'idle_paused' and f.state = 'raised')) then
    raise exception 'gate: a legacy job is switched off without a raised idle flag (a person paused it): resume or settle it first';
  end if;

  -- the cutover: coverage lanes
  for r in select fr.lane_code, fr.legacy_job, j.jobid, j.active from pipeline.field_execution_registry fr join cron.job j on j.jobname = fr.legacy_job
            where fr.lane_code = any (v_lanes) order by fr.lane_code loop
    perform cron.alter_job(r.jobid, active => false);
    update pipeline.field_execution_registry set mode = 'live', enabled = r.active, updated_at = now(),
           note = coalesce(note || '; ', '') || 'live from cutover 20261119095000 (consolidation PR 4; early cutover authorised 19 Nov 07:47, shadow since 18 Nov 14:59, minute coverage clean)'
             || case when r.active then '' else '; held at cutover: legacy job idle-paused, released by flag-recheck' end
     where lane_code = r.lane_code;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('scheduler', 'dispatcher_cutover', r.legacy_job,
            jsonb_build_object('dispatcher', 'coverage-lane-dispatch', 'lane', r.lane_code, 'legacy_job_active', false, 'mode', 'live', 'lane_enabled', r.active,
                               'shadow_from', v_from, 'by', 'migration 20261119095000'), null);
  end loop;
  update pipeline.component_register c
     set status = 'retiring', replaced_by = 'coverage-lane-dispatch (pipeline.field_execution_registry, mode live)',
         retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, updated_at = now(),
         note = 'switched off at the consolidation PR 4 cutover (20261119095000); unscheduled by docs/paste/PASTE-20261119-pr4-legacy-unschedule.sql after retire_after'
   where c.kind = 'job' and c.name = any (v_lanes) and c.status = 'active';

  -- the cutover: settings-backup-daily
  for r in select t.target_code, j.jobid from pipeline.rollup_targets t join cron.job j on j.jobname = t.legacy_job where t.target_code = 'settings-backup-daily' loop
    perform cron.alter_job(r.jobid, active => false);
    update pipeline.rollup_targets set mode = 'live', updated_at = now(),
           note = coalesce(note || '; ', '') || 'live from cutover 20261119095000 (consolidation PR 4; early cutover authorised 19 Nov 07:47, shadow covered every legacy start)'
     where target_code = r.target_code;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('scheduler', 'dispatcher_cutover', 'settings-backup-daily',
            jsonb_build_object('dispatcher', 'rollup-scheduler', 'target', r.target_code, 'legacy_job_active', false, 'mode', 'live', 'shadow_from', v_from, 'by', 'migration 20261119095000'), null);
  end loop;
  update pipeline.component_register c
     set status = 'retiring', replaced_by = 'rollup-scheduler (pipeline.rollup_targets, group A, mode live)',
         retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, updated_at = now(),
         note = 'switched off at the consolidation PR 4 cutover (20261119095000); unscheduled by docs/paste/PASTE-20261119-pr4-legacy-unschedule.sql after retire_after'
   where c.kind = 'job' and c.name = 'settings-backup-daily' and c.status = 'active';
end $cut$;

do $post$
declare v_lanes text[] := array['coverage-discover', 'coverage-discover-2', 'coverage-ai-match', 'central-find', 'logo-find', 'ops-diagnose', 'scholarship-listing', 'page-text'];
begin
  if (select count(*) from pipeline.field_execution_registry where lane_code = any (v_lanes) and mode = 'live') <> 8 then raise exception 'post-check: not all 8 lanes are live'; end if;
  if (select count(*) from pipeline.rollup_targets where target_code = 'settings-backup-daily' and mode = 'live' and enabled) <> 1 then raise exception 'post-check: settings-backup-daily is not live'; end if;
  if exists (select 1 from cron.job where active and jobname in ('coverage-discover', 'coverage-discover-2', 'coverage-ai-match', 'central-find', 'logo-find', 'ops-diagnose',
               'scholarship-listing', 'page-text', 'settings-backup-daily')) then
    raise exception 'post-check: a legacy job is still switched on';
  end if;
  if (select count(*) from pipeline.component_register where kind = 'job' and status = 'retiring' and name in ('coverage-discover', 'coverage-discover-2', 'coverage-ai-match',
        'central-find', 'logo-find', 'ops-diagnose', 'scholarship-listing', 'page-text', 'settings-backup-daily')) <> 9 then
    raise exception 'post-check: not all 9 legacy jobs are retiring';
  end if;
  if (select count(*) from cron.job where active and jobname in ('coverage-lane-dispatch', 'coverage-lane-dispatch-b', 'coverage-lane-dispatch-c', 'rollup-scheduler')) <> 4 then
    raise exception 'post-check: the dispatchers must be switched on';
  end if;
end $post$;
