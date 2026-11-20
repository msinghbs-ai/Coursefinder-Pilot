-- CF-247 s881 (Platform Admin 20 Nov 2026 17:14 and 17:15 AEDT, chat S1-Build): active pg_cron jobs inside the F-OPS ceiling (at most 140) with
-- headroom: at most 136, 0 unregistered. Live read 20 Nov 2026 17:18-17:55 AEDT (rolled-back dry runs only): 140 to 143 active jobs (142 at
-- the 16:54 validation; boost-extract, coverage-read and coverage-read-2 are idle-paused and released by flag-recheck, so the count moves by
-- up to 3 on its own), every one catalogued and registered. Of the 13 consolidation candidates (18 Nov audit; Pilot #1331): 9 folded by PR 4
-- (7 coverage-sweep jobs, page-text, settings-backup-daily) and boost-extract already off; coverage-read and coverage-read-2 stay (30-second
-- cadence); boost-fields stays (live work, S2-BOOST's lane); boost-benchmark is retired here (its round is finished).
-- Switched off here: the 7 active jobs that do no work, each proven live and checked again below before it is switched off:
--   boost-benchmark      every 2 min   benchmark run bench-5 finished: its gate says "nothing left to do"; 0 worker calls in 24 h
--   lean-sections-eval   every 5 min   all 13,079 labelled cases done or failed on 14 Nov; 0 worker calls in 24 h
--   lean-qualify         every minute  reading.lean_qualify_on is 0; 0 worker calls in 24 h
--   aer-v2-shadow        :08 and :38   aer.v2_shadow_on is 0; 0 worker calls in 24 h (the deterministic aer-det-sweep is the live reader)
--   course-url-fill      daily 02:23   course_url.fill_enabled is 0 (paused by its own retraction guard): the job returns "skipped"
--   reread-pilot         daily 05:41   the pilot stopped itself (D13: a pilot page used Firecrawl or produced Layer 4 items); reread.pilot_enabled false
--   course-description-stale-retire  hourly :13  enrich.course_description_stale_supersede_on is 0: the job returns "on": false, examined 0
-- 143 - 7 = 136 with every idle-paused job on.
-- Kept, as the directive says: aer-det-sweep, struct-det-sweep, elr-det-sweep, scholarship-coverage-classify, coverage-reconcile,
-- ops-pulse-refresh, every admission and enrichment pipeline, and every queue poller that would take new work when it arrives.
-- Each job is switched off (active = false) and marked retiring (retire_after = today + hygiene.retire_after_days); its catalogue row and
-- its settings stay, so switching it back on is one cron.alter_job until the unschedule paste file runs (admin
-- docs/paste/PASTE-20261205-s881-idle-jobs-unschedule.sql, on or after retire_after + 1 day). A job whose evidence no longer holds is left on.
-- Replaces: nothing (the work these jobs did is finished or switched off by its own setting).
-- Retires: the 7 jobs above (component register retiring; unscheduled by the paste file after the retention window). Nothing is dropped.
-- Parity before writing (20 Nov 2026 17:40 AEDT): main at #1433 (65414f2c7), migration head 20261120172000; open claims 20261120165000 and
-- 20261120165100 (S1-Fees, Pilot #1425). G1: no job added, catalogue rows kept (0 unregistered). G2: no new setting, no number in a job
-- command. G3: no consumer object (75/48). No spend.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the cron and register updates below

do $s881$
declare r record; v_ok boolean; v_why text; v_off text[] := '{}'; v_kept text[] := '{}';
begin
  for r in select j.jobid, j.jobname from cron.job j
            where j.active and j.jobname in ('boost-benchmark', 'lean-sections-eval', 'lean-qualify', 'aer-v2-shadow', 'course-url-fill', 'reread-pilot',
                                             'course-description-stale-retire')
            order by j.jobname loop
    v_ok := false;
    case r.jobname
      when 'boost-benchmark' then
        v_ok := coalesce(security.boost_benchmark_gate_v1() ->> 'reason', '') = 'nothing left to do'
                and not exists (select 1 from pipeline.boost_benchmark_items b where b.state in ('queued', 'claimed')
                                  and b.run_label = (security.toolset_setting('pipeline', 'boost.benchmark_label') #>> '{}'));
        v_why := 'benchmark run finished (gate: nothing left to do)';
      when 'lean-sections-eval' then
        v_ok := not exists (select 1 from pipeline.lean_section_eval_cases c where c.state = 'pending');
        v_why := 'every labelled case read (none pending)';
      when 'lean-qualify' then
        v_ok := security.pipeline_num_v1('reading.lean_qualify_on', 0) = 0;
        v_why := 'reading.lean_qualify_on is 0';
      when 'aer-v2-shadow' then
        v_ok := security.pipeline_num_v1('aer.v2_shadow_on', 0) = 0;
        v_why := 'aer.v2_shadow_on is 0; aer-det-sweep is the live reader';
      when 'course-url-fill' then
        v_ok := security.pipeline_num_v1('course_url.fill_enabled', 1) <> 1;
        v_why := 'course_url.fill_enabled is 0 (paused by its retraction guard); the job only returns "skipped"';
      when 'reread-pilot' then
        v_ok := not coalesce((security.toolset_setting('pipeline', 'reread.pilot_enabled') #>> '{}')::boolean, false)
                and exists (select 1 from pipeline.page_reread_pilot p where p.outcome_fetched_via = 'firecrawl' or coalesce(p.layer4_items, 0) > 0);
        v_why := 'the pilot stopped itself (D13 stop condition); reread.pilot_enabled is false';
      when 'course-description-stale-retire' then
        v_ok := security.pipeline_num_v1('enrich.course_description_stale_supersede_on', 0) < 1;
        v_why := 'enrich.course_description_stale_supersede_on is 0; the job examines nothing';
    end case;
    if not v_ok then
      v_kept := v_kept || r.jobname;
      raise notice 's881: % kept on: its evidence no longer holds', r.jobname;
      continue;
    end if;
    perform cron.alter_job(r.jobid, active => false);
    update pipeline.component_register c
       set status = 'retiring', replaced_by = 'nothing: no work left (' || v_why || ')',
           retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int, updated_at = now(),
           note = 'switched off by s881 (20261120181000): ' || v_why || '; unscheduled by docs/paste/PASTE-20261205-s881-idle-jobs-unschedule.sql after retire_after; switch back on with cron.alter_job until then'
     where c.kind = 'job' and c.name = r.jobname;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('scheduler', 'job_retire', r.jobname, jsonb_build_object('jobid', r.jobid, 'active', false, 'why', v_why, 'by', 'migration 20261120181000 (s881)'), null);
    v_off := v_off || r.jobname;
  end loop;
  raise notice 's881: switched off %; kept %', v_off, v_kept;
end $s881$;

-- post-checks: the protected jobs are on, no job is unregistered, and the count is reported
do $post$
declare v_active int; v_unreg int; v_missing text;
begin
  select string_agg(n, ', ') into v_missing
    from unnest(array['aer-det-sweep', 'struct-det-sweep', 'elr-det-sweep', 'scholarship-coverage-classify', 'coverage-reconcile', 'ops-pulse-refresh',
                      'admission-rule-runner', 'admission-rule-runner-b', 'admission-rule-runner-c', 'coverage-lane-dispatch', 'coverage-lane-dispatch-b',
                      'coverage-lane-dispatch-c', 'rollup-scheduler', 'enrich-plan-run', 'enrich-plan-auto']) n
   where not exists (select 1 from cron.job j where j.jobname = n and j.active);
  if v_missing is not null then raise exception 'post-check: a protected job is not switched on: %', v_missing; end if;
  if exists (select 1 from cron.job j where j.active and j.jobname in ('boost-benchmark', 'lean-sections-eval', 'lean-qualify', 'aer-v2-shadow', 'course-url-fill', 'reread-pilot',
                                                                       'course-description-stale-retire')
               and exists (select 1 from pipeline.component_register c where c.kind = 'job' and c.name = j.jobname and c.status = 'retiring')) then
    raise exception 'post-check: a job marked retiring is still switched on';
  end if;
  select count(*) into v_active from cron.job where active;
  select count(*) into v_unreg from cron.job j where j.active
     and (not exists (select 1 from pipeline.automation_catalogue a where a.jobname = j.jobname)
          or not exists (select 1 from pipeline.component_register c where c.kind = 'job' and c.name = j.jobname));
  if v_unreg > 0 then raise exception 'post-check: % active jobs are not catalogued and registered', v_unreg; end if;
  perform set_config('cf.diag', 'active ' || v_active || ', unregistered ' || v_unreg, true);
end $post$;
