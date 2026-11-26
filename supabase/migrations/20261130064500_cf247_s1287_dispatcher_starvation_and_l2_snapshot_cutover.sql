-- CF-247 s1287 (S1-Build; SS-Programme-Control 27 Nov 2026 00:08 AEDT, "Production reliability and consumer integrity", items 3, 4 and 5).
-- What was read live (27 Nov 2026 00:25-00:40 AEDT, rolled-back read-backs; pipeline.rollup_runs, seven days):
--   rollup-scheduler (security.rollup_tick_v1, live only, md5 36a8d4f3) runs a tick's due targets in priority order and defers a target once
--   the tick has run longer than rollup.tick_budget_seconds (60) or when its estimate would take the tick past rollup.tick_finish_by_seconds
--   (100); the first target of a tick always runs. The estimate is the target's longest successful run in rollup.keep_days (14). The group A
--   priority 10 targets are due every minute (admin-read-snapshots, data-delivery, lane-funnel), so a later target whose estimate is long never
--   fits and is retried each minute for rollup.catch_up_minutes:
--     ops-cost-guard (p90, :43, longest 114.6 s): 9,338 of 9,370 executions deferred, 32 runs in seven days (the cost guard is starved).
--     coursefinder-data-quality-overview-refresh (p50, daily 16:17 UTC, longest 108.6 s): 910 of 912 deferred; last run 21 Nov 03:25 AEDT.
--     course-field-readiness (p90, every 4 minutes, longest 94.4 s, median 33.9 s): 5,057 of 6,894 deferred.
--     course-completeness-build (p50, :52, longest 85.9 s): 88 of 256 deferred. adapter-build-readiness (p50, :17, 80.3 s): 76 of 244.
--     evidence-filter-options-refresh (p50, :04 every two hours, 67.5 s): 11 of 95.
--   layer2-onboarding-snapshot: cron job 36 is live (12 of 12 runs succeeded in 24 hours, about 50 s); rollup-scheduler holds the same command
--   (call_md5 4aa400e3 = md5 of the cron command) as a disabled shadow target, so the cutover was never finished.
-- What it changes (data only; the dispatcher function is not changed, no table or function is added):
--   1. Starved and often-deferred targets run first in their own due ticks (the s720 method used for course-coverage-build):
--        priority 3: ops-cost-guard, coursefinder-data-quality-overview-refresh (protective / once a day; never on the same minute);
--        priority 4: course-completeness-build, adapter-build-readiness, evidence-filter-options-refresh, layer2-onboarding-snapshot;
--        priority 11: course-field-readiness (every 4 minutes: straight after the every-minute group, not ahead of it, so data-delivery keeps
--        its minute). A target deferred at its due minute still runs first in the next minute.
--   2. The layer2-onboarding-snapshot cutover: the target goes live and enabled (from this minute, so the slot the cron job already ran is not
--      run again), cron job 36 is switched off (active = false) and the job is marked retiring in pipeline.component_register; the
--      cron.unschedule paste file is held for hygiene.retire_after_days (admin docs/paste/PASTE-20261127-s1287-l2-snapshot-unschedule.sql).
--      Parity: the target's command is byte for byte the cron command (md5 checked below). No shadow soak is added (Standing Mandate,
--      21 Nov 2026 10:07; the assignment asks for the existing cutover to be completed).
-- G1: no job created (one switched off; active jobs go down by one). G2: priorities are each target's own schedule data (marked fixed), no
-- new setting. G3: no consumer object changed (75/48 checked before and after). Manual locks checked unchanged. Nothing dropped or deleted.
-- Replaces: the priorities of the seven targets above; cron job 36 layer2-onboarding-snapshot (by rollup-scheduler target layer2-onboarding-snapshot).
-- Retires: cron job 36 layer2-onboarding-snapshot (component register retiring; unscheduled by paste file after retire_after).
set local lock_timeout = '5s';  -- fixed: lock wait for the target and job updates

create temp table s1287_guard on commit drop as select (select count(*) from pipeline.manual_locks) locks_before, (select count(*) from cron.job where active) active_before;
create temp table s1287_cron on commit drop as select jobid from cron.job;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v; end if;
  if (select count(*) from pipeline.rollup_targets where rollup_group = 'A' and (target_code, priority) in (('ops-cost-guard', 90), ('coursefinder-data-quality-overview-refresh', 50),
        ('course-completeness-build', 50), ('adapter-build-readiness', 50), ('evidence-filter-options-refresh', 50), ('layer2-onboarding-snapshot', 50), ('course-field-readiness', 90))) <> 7 then
    raise exception 'guard: a target priority is not as read on 27 Nov 2026';
  end if;
  if not exists (select 1 from pipeline.rollup_targets t join cron.job j on j.jobname = t.legacy_job
                  where t.target_code = 'layer2-onboarding-snapshot' and t.mode = 'shadow' and not t.enabled and j.active and t.call_md5 = md5(j.command) and t.call_md5 = md5(t.call_sql) and t.schedule = j.schedule) then
    raise exception 'guard: layer2-onboarding-snapshot is not the disabled byte-for-byte shadow of a live cron job';
  end if;
end $g$;

update pipeline.rollup_targets
   set priority = case target_code when 'ops-cost-guard' then 3 when 'coursefinder-data-quality-overview-refresh' then 3 when 'course-field-readiness' then 11 else 4 end,  -- fixed: each target's order in its group, as the target's own schedule
       updated_at = now(),
       note = coalesce(note, '') || ' | 27 Nov 2026 (20261130064500, s1287): first in its due ticks; the 14-day longest run kept it deferred behind the every-minute targets'
 where rollup_group = 'A' and target_code in ('ops-cost-guard', 'coursefinder-data-quality-overview-refresh', 'course-completeness-build', 'adapter-build-readiness',
                                              'evidence-filter-options-refresh', 'layer2-onboarding-snapshot', 'course-field-readiness');

do $cut$
declare r record;
begin
  for r in select t.target_code, j.jobid, j.jobname from pipeline.rollup_targets t join cron.job j on j.jobname = t.legacy_job where t.target_code = 'layer2-onboarding-snapshot' loop
    perform cron.alter_job(r.jobid, active => false);
    update pipeline.rollup_targets
       set mode = 'live', enabled = true, last_due_at = date_trunc('minute', now()), updated_at = now(),
           note = coalesce(note || '; ', '') || 'live from cutover 20261130064500 (s1287; SS-Programme-Control 27 Nov 2026 00:08 item 5; command byte for byte the cron command)'
     where target_code = r.target_code;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('scheduler', 'dispatcher_cutover', r.jobname,
            jsonb_build_object('dispatcher', 'rollup-scheduler', 'target', r.target_code, 'legacy_job_active', false, 'mode', 'live', 'priority', 4,
                               'parity', 'call_md5 = md5(cron command)', 'by', 'migration 20261130064500 (CF-247 s1287)'), null);
  end loop;
  update pipeline.component_register c
     set status = 'retiring', replaced_by = 'rollup-scheduler (pipeline.rollup_targets, group A, mode live)',
         retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, updated_at = now(),
         note = 'switched off at the s1287 cutover (20261130064500); unscheduled by admin docs/paste/PASTE-20261127-s1287-l2-snapshot-unschedule.sql after retire_after'
   where c.kind = 'job' and c.name = 'layer2-onboarding-snapshot' and c.status = 'active';
end $cut$;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1287_cron b where b.jobid = j.jobid)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: active cron jobs above 140'; end if;
  if exists (select 1 from cron.job where jobname = 'layer2-onboarding-snapshot' and active) then raise exception 'post-check: the legacy job is still on'; end if;
  if not exists (select 1 from pipeline.rollup_targets where target_code = 'layer2-onboarding-snapshot' and mode = 'live' and enabled and priority = 4) then raise exception 'post-check: the target is not live'; end if;
  if not exists (select 1 from pipeline.component_register where kind = 'job' and name = 'layer2-onboarding-snapshot' and status = 'retiring') then raise exception 'post-check: the job is not retiring'; end if;
  if (select count(*) from pipeline.rollup_targets where rollup_group = 'A' and enabled and priority < 5 and target_code not in ('ops-cost-guard', 'coursefinder-data-quality-overview-refresh',
        'course-completeness-build', 'adapter-build-readiness', 'evidence-filter-options-refresh', 'layer2-onboarding-snapshot')) > 0 then raise exception 'post-check: another target runs before priority 5'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1287_guard) then raise exception 'post-check: manual locks changed'; end if;
end $c$;
