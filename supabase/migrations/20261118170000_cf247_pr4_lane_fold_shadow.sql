-- CF-247 consolidation PR 4, in shadow (Platform Admin 18 Nov 2026 14:24, chat S1-Build: "Fold page-text and the 7 single-mode coverage-sweep
-- jobs onto coverage-lane-dispatch, and move settings-backup-daily onto rollup-scheduler"; scope from the job governance audit of 18 Nov 2026
-- 12:20 AEDT, admin docs/CURRENT-STATE.md "Job governance").
-- Pattern: Pilot CLAUDE.md "Cron dispatchers": register each legacy job byte for byte with its own cron schedule and start in shadow (the
-- dispatcher records what was due and runs nothing); after a 24-hour shadow cycle whose report matches the legacy starts, the cutover makes the
-- targets live, switches the legacy cron rows off and marks them retiring; the cron.unschedule paste file waits hygiene.retire_after_days.
--   1. pipeline.field_execution_registry (consolidation PR 3, 20261116220000): 8 worker lanes copied from the live legacy jobs, command and schedule
--      byte for byte, mode shadow: coverage-discover, coverage-discover-2, coverage-ai-match (every minute), central-find (5 min), logo-find
--      (10 min), ops-diagnose (:27 and :57), scholarship-listing (15 min), page-text (2 min). coverage-lane-dispatch, -b and -c already tick every
--      minute; nothing about them changes. Budget = the legacy job's longest run in 7 days, expected = its 95th percentile (all under 2 s).
--   2. pipeline.rollup_targets (consolidation PR 1, 20261115210000): settings-backup-daily (security.settings_backup_take_v1('daily'), 19:50 UTC)
--      as a group A target, mode shadow. rollup-scheduler already ticks every minute.
--   3. pipeline.component_register: the 9 legacy jobs keep status active; their note says which dispatcher shadows them.
-- Kept on their own jobs (not taken): coverage-read and coverage-read-2 (every 30 seconds; a minute dispatcher would halve them);
--   boost-extract, boost-fields and boost-benchmark (S2 - BOOST's lane); every other job.
-- Shadow only: the 9 legacy jobs keep running exactly as they are; no cron job is added, changed or switched off, so G1 stays at 0 unregistered.
-- G2: no new setting (the dispatchers' settings coverage_lane.* and rollup.* apply); no number in any job command. G3: no consumer API object is
-- read or changed. Nothing dropped or deleted.
-- Replaces: nothing (shadow: no legacy job changes).
-- Retires: nothing (the cutover change switches the 9 legacy jobs off and marks them retiring).

set local lock_timeout = '5s'; -- fixed: lock wait guard for the registry writes below

-- 0. Pre-checks: the dispatchers are running, the 9 jobs are on, catalogued and registered, and none is held by any dispatcher yet
do $pre$
begin
  if to_regclass('pipeline.field_execution_registry') is null or to_regclass('pipeline.rollup_targets') is null
     or to_regprocedure('security.coverage_lane_run_v1(text,text,timestamp with time zone,timestamp with time zone,integer)') is null
     or to_regprocedure('security.rollup_run_target_v1(text,timestamp with time zone,timestamp with time zone,integer)') is null then
    raise exception 'pre-check: a dispatcher this change builds on is missing';
  end if;
  if to_regnamespace('cron') is not null then
    if (select count(*) from cron.job where active and schedule = '* * * * *' and command in (
          $j$call security.coverage_lane_tick_v1('a')$j$, $j$call security.coverage_lane_tick_v1('b')$j$, $j$call security.coverage_lane_tick_v1('c')$j$,
          $j$call security.rollup_tick_v1()$j$)) <> 4 then
      raise exception 'pre-check: coverage-lane-dispatch (a, b, c) and rollup-scheduler must be on, every minute';
    end if;
    if (select count(*) from cron.job j
         where j.active and j.jobname in ('coverage-discover', 'coverage-discover-2', 'coverage-ai-match', 'central-find', 'logo-find', 'ops-diagnose',
                                          'scholarship-listing', 'page-text', 'settings-backup-daily')
           and exists (select 1 from pipeline.automation_catalogue c where c.jobname = j.jobname)
           and exists (select 1 from pipeline.component_register r where r.kind = 'job' and r.name = j.jobname and r.status = 'active')) <> 9 then
      raise exception 'pre-check: the 9 jobs must be on, catalogued and registered active';
    end if;
  end if;
  if exists (select 1 from pipeline.field_execution_registry r where r.legacy_job in ('coverage-discover', 'coverage-discover-2', 'coverage-ai-match', 'central-find',
               'logo-find', 'ops-diagnose', 'scholarship-listing', 'page-text', 'settings-backup-daily'))
     or exists (select 1 from pipeline.rollup_targets t where t.legacy_job in ('coverage-discover', 'coverage-discover-2', 'coverage-ai-match', 'central-find',
               'logo-find', 'ops-diagnose', 'scholarship-listing', 'page-text', 'settings-backup-daily'))
     or (to_regclass('pipeline.admission_rules') is not null and exists (select 1 from pipeline.admission_rules a where a.legacy_job in ('coverage-discover',
               'coverage-discover-2', 'coverage-ai-match', 'central-find', 'logo-find', 'ops-diagnose', 'scholarship-listing', 'page-text', 'settings-backup-daily'))) then
    raise exception 'pre-check: one of the 9 jobs is already held by a dispatcher';
  end if;
end $pre$;

-- 1. The 8 coverage worker lanes, copied from the live legacy jobs (command and schedule byte for byte)
insert into pipeline.field_execution_registry(lane_code, kind, legacy_job, call_sql, call_md5, schedule, priority, mode, budget_ms, expected_ms, owner, note)
select j.jobname, 'worker_lane', j.jobname, j.command, md5(j.command), j.schedule, 50, 'shadow',
       (select round(max(extract(epoch from d.end_time - d.start_time)) * 1000)::int
          from cron.job_run_details d where d.jobid = j.jobid and d.status = 'succeeded' and d.start_time > now() - make_interval(days => 7)),
       (select round(percentile_cont(0.95) within group (order by (extract(epoch from d.end_time - d.start_time) * 1000)::float8))::int
          from cron.job_run_details d where d.jobid = j.jobid and d.status = 'succeeded' and d.start_time > now() - make_interval(days => 7)),
       'S1-Build (consolidation PR 4)', 'registered in shadow by 20261118170000 (consolidation PR 4); the legacy job still runs'
  from cron.job j
 where j.active and j.jobname in ('coverage-discover', 'coverage-discover-2', 'coverage-ai-match', 'central-find', 'logo-find', 'ops-diagnose', 'scholarship-listing', 'page-text')
on conflict (lane_code) do nothing;

-- 2. settings-backup-daily as a rollup-scheduler group A target (command and schedule byte for byte)
insert into pipeline.rollup_targets(target_code, legacy_job, call_sql, call_md5, schedule, rollup_group, priority, enabled, mode, expected_ms, note)
select j.jobname, j.jobname, j.command, md5(j.command), j.schedule, 'A', 50, true, 'shadow',
       (select round(max(extract(epoch from d.end_time - d.start_time)) * 1000)::int
          from cron.job_run_details d where d.jobid = j.jobid and d.status = 'succeeded' and d.start_time > now() - make_interval(days => 7)),
       'registered in shadow by 20261118170000 (consolidation PR 4); the legacy job still runs'
  from cron.job j
 where j.active and j.jobname = 'settings-backup-daily'
on conflict (target_code) do nothing;

-- 3. The register notes which dispatcher shadows each legacy job (status stays active until the cutover)
update pipeline.component_register r
   set note = 'Consolidation PR 4 (20261118170000): shadowed by ' ||
              case when r.name = 'settings-backup-daily' then 'rollup-scheduler (pipeline.rollup_targets, group A)' else 'coverage-lane-dispatch (pipeline.field_execution_registry)' end ||
              ' from 18 Nov 2026; the job keeps running until the cutover after a 24-hour shadow cycle.' ||
              coalesce(' Before: ' || nullif(r.note, ''), ''),
       updated_at = now()
 where r.kind = 'job' and r.name in ('coverage-discover', 'coverage-discover-2', 'coverage-ai-match', 'central-find', 'logo-find', 'ops-diagnose', 'scholarship-listing',
                                      'page-text', 'settings-backup-daily')
   and coalesce(r.note, '') not like 'Consolidation PR 4 (20261118170000)%';

-- 4. Post-checks
do $post$
declare v_n int;
begin
  if to_regnamespace('cron') is not null then
    select count(*) into v_n from pipeline.field_execution_registry r join cron.job j on j.jobname = r.legacy_job
     where r.kind = 'worker_lane' and r.mode = 'shadow' and r.call_sql = j.command and r.call_md5 = md5(j.command) and r.schedule = j.schedule and j.active
       and r.lane_code in ('coverage-discover', 'coverage-discover-2', 'coverage-ai-match', 'central-find', 'logo-find', 'ops-diagnose', 'scholarship-listing', 'page-text');
    if v_n <> 8 then raise exception 'post-check: % of 8 coverage lanes match their live legacy job', v_n; end if;
    if (select count(*) from pipeline.rollup_targets t join cron.job j on j.jobname = t.legacy_job
         where t.target_code = 'settings-backup-daily' and t.mode = 'shadow' and t.enabled and t.rollup_group = 'A'
           and t.call_sql = j.command and t.call_md5 = md5(j.command) and t.schedule = j.schedule and j.active) <> 1 then
      raise exception 'post-check: settings-backup-daily is not registered byte for byte in shadow';
    end if;
    if (select count(*) from cron.job where active and jobname in ('coverage-discover', 'coverage-discover-2', 'coverage-ai-match', 'central-find', 'logo-find',
          'ops-diagnose', 'scholarship-listing', 'page-text', 'settings-backup-daily')) <> 9 then
      raise exception 'post-check: a legacy job was switched off (this change is shadow only)';
    end if;
    if exists (select 1 from pipeline.field_execution_registry r where r.legacy_job in ('coverage-read', 'coverage-read-2', 'boost-extract', 'boost-fields', 'boost-benchmark')) then
      raise exception 'post-check: a job kept on its own was registered';
    end if;
  end if;
  if exists (select 1 from pipeline.field_execution_registry where note like 'registered in shadow by 20261118170000%' and mode <> 'shadow')
     or exists (select 1 from pipeline.rollup_targets where note like 'registered in shadow by 20261118170000%' and mode <> 'shadow') then
    raise exception 'post-check: a PR 4 target is live (this change is shadow only)';
  end if;
end $post$;
