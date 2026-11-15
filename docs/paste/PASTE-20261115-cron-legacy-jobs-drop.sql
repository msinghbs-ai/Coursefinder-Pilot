-- =====================================================================================================================================
-- PASTE FILE for the Platform Admin (SQL editor, project fxcwkweaxjtknorudmwp ONLY; never coursefinder-demo). A migration drops nothing
-- (CLAUDE.md housekeeping); this file is how the eight switched-off scheduled jobs leave the scheduler.
-- Approved: Platform Admin 15 Nov 2026 20:38 ("Retire legacy jobs: mark the 8 LEGACY_DISABLED jobs as retiring ... and generate the 14-day
-- drop paste file"), following the job governance audit of 15 Nov 2026 20:25 (project doc claude/cron-governance-audit-2026-11-15.md).
-- Prepared by: migration 20261115200500_cf247_cron_quick_wins (marks the last three retiring).
-- Replaces: nothing. Retires: the eight jobs below (cron.unschedule, catalogue row removed, component register row set to retired).
-- Run PART A now or later; run PART B on or after its retire_after date (29 Nov 2026). Each part is one transaction and refuses to run unless
-- every job in it is still switched off, still retiring, past retire_after and has not run for hygiene.idle_days. Nothing else is touched:
-- the functions and tables these jobs called stay (they are retired separately by the hygiene check when nothing uses them).
-- Rollback: each job's original schedule and command is listed in the evidence; re-create it with cron.schedule(...) and set it inactive.
-- =====================================================================================================================================

-- ===== EVIDENCE (read-only, 15 Nov 2026 about 09:30 UTC) =============================================================================
-- | Job (jobid)                      | Schedule          | Command                                                                       | Register before 15 Nov    | Runs 24 h |
-- |----------------------------------|-------------------|-------------------------------------------------------------------------------|---------------------------|-----------|
-- | cron-history-retention (37)      | 37 3 * * *        | delete from cron.job_run_details where end_time < now() - interval '14 days'; | retiring, after 30 Oct    | 0         |
-- | cron-history-trim (151)          | 23 4 * * *        | delete from cron.job_run_details where end_time < now() - interval '3 days'   | retiring, after 30 Oct    | 0         |
-- | l4-rule-low-agreement (130)      | 37 3 * * *        | select security.l4_rule_low_agreement_v1()                                    | retiring, after 14 Nov    | 0         |
-- | provider-calendar-defaults (100) | 3-59/10 * * * *   | select security.calendar_default_intakes_apply_v1()                           | retiring, after 5 Nov     | 0         |
-- | provider-calendar-intakes (99)   | 7-59/10 * * * *   | select security.semester_intake_apply_v1(null)                                | retiring, after 5 Nov     | 0         |
-- | course-link-reverse (76)         | * * * * *         | select security.course_link_reverse_tick_v1(security.pipeline_num_v1('batch.course_link_reverse', 30)::int) | active (switched off) | 0 |
-- | onboarding-pilot-snapshot (158)  | 7 * * * *         | select security.onboarding_pilot_snapshot_v1()                                | active (switched off)     | 0         |
-- | worker-outcome-check (355)       | 4-59/10 * * * *   | select security.worker_outcome_check_v1()                                     | active (switched off)     | 0         |
-- Replacements: cron-history-* -> housekeeping-daily (active); l4-rule-low-agreement -> Layer 4 review (Decision D3, 31 Oct 2026); provider-calendar-*
--   -> intakes from the course's own page only (20261022042000); the last three -> nothing (switched off and not run).
-- Tests: no @deployed spec reads these jobs on live; the specs that name them read migration text only, so the build is unaffected.
-- Callers: no function body, cron command or edge function switches these jobs on; Resume and the maintenance resume never switch on a
--   retiring job (UR-07).

-- ===== PART A: the five jobs already past retire_after (may be run now) ==============================================================
begin;
do $$
declare v_jobs text[] := array['cron-history-retention', 'cron-history-trim', 'l4-rule-low-agreement', 'provider-calendar-defaults', 'provider-calendar-intakes'];
        v_idle int := security.pipeline_num_v1('hygiene.idle_days', 14)::int; v_n int;
begin
  select count(*) into v_n from cron.job j join pipeline.component_register r on r.kind = 'job' and r.name = j.jobname
   where j.jobname = any(v_jobs) and not j.active and r.status = 'retiring' and r.retire_after <= current_date
     and not exists (select 1 from cron.job_run_details d where d.jobid = j.jobid and d.start_time > now() - make_interval(days => v_idle));
  if v_n <> 5 then raise exception 'PART A refused: % of 5 jobs are switched off, retiring, past retire_after and idle; nothing was changed', v_n; end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = any(v_jobs);
  delete from pipeline.automation_catalogue where jobname = any(v_jobs);
  update pipeline.component_register set status = 'retired', note = 'dropped by PASTE-20261115-cron-legacy-jobs-drop.sql PART A', updated_at = now()
   where kind = 'job' and name = any(v_jobs);
  if exists (select 1 from cron.job where jobname = any(v_jobs)) then raise exception 'PART A post-check: a job is still scheduled'; end if;
  raise notice 'PART A done: 5 jobs unscheduled, catalogue rows removed, register rows retired';
end $$;
commit;

-- ===== PART B: the three jobs marked retiring on 15 Nov 2026 (run on or after 29 Nov 2026) ==========================================
begin;
do $$
declare v_jobs text[] := array['course-link-reverse', 'onboarding-pilot-snapshot', 'worker-outcome-check'];
        v_idle int := security.pipeline_num_v1('hygiene.idle_days', 14)::int; v_n int;
begin
  select count(*) into v_n from cron.job j join pipeline.component_register r on r.kind = 'job' and r.name = j.jobname
   where j.jobname = any(v_jobs) and not j.active and r.status = 'retiring' and r.retire_after <= current_date
     and not exists (select 1 from cron.job_run_details d where d.jobid = j.jobid and d.start_time > now() - make_interval(days => v_idle));
  if v_n <> 3 then raise exception 'PART B refused: % of 3 jobs are switched off, retiring, past retire_after and idle (retire_after is 29 Nov 2026); nothing was changed', v_n; end if;
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = any(v_jobs);
  delete from pipeline.automation_catalogue where jobname = any(v_jobs);
  update pipeline.component_register set status = 'retired', note = 'dropped by PASTE-20261115-cron-legacy-jobs-drop.sql PART B', updated_at = now()
   where kind = 'job' and name = any(v_jobs);
  if exists (select 1 from cron.job where jobname = any(v_jobs)) then raise exception 'PART B post-check: a job is still scheduled'; end if;
  raise notice 'PART B done: 3 jobs unscheduled, catalogue rows removed, register rows retired';
end $$;
commit;
