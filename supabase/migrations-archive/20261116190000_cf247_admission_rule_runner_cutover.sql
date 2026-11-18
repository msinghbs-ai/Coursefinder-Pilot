-- CF-247 consolidation PR 2 cutover: admission-rule-runner takes over the 20 legacy admission rule jobs (Platform Admin 15 Nov 2026 22:36
-- "Cron dispatchers" rule; cutover pulled forward from Tue 17 Nov 22:30 to Mon 16 Nov after 23:28 AEDT by the Platform Admin, 16 Nov 21:03,
-- Path A: clean 24-hour shadow).
-- Replaces: the 20 legacy cron jobs registered in pipeline.admission_rules (switched off, active = false; marked retiring).
-- Retires: those 20 jobs (component register: retiring, replaced_by admission-rule-runner, retire_after = today + hygiene.retire_after_days).
--          They are unscheduled by coursefinder-admin docs/paste/PASTE-20261116-admission-rule-legacy-unschedule.sql after the retention window;
--          a migration drops nothing.
--
-- Gate (in this migration, so it applies only when the rule holds): the shadow report security.admission_rule_shadow_report_v1(24) must cover
-- a full 24 hours (its window starts 24 hours or more ago) and report all_match for all 20 rules; every legacy job must still carry exactly
-- the registered command and schedule (md5) and be active. Otherwise nothing changes and the deploy reports the reason.
-- Read before (16 Nov 21:04 AEDT, 21.6 hours): all_match true for 20 of 20, 0 minutes over capacity, largest projected load 271.7 of 300 s/min.
-- In one transaction: the 20 rules go live (the three runner lanes run them from the next minute) and the 20 legacy jobs are switched off, so
-- no rule is run twice by the two schedulers. Every change is logged in pipeline.admin_control_events. G1: the runner jobs are catalogued
-- (consolidation PR 2); G2: no new setting, no number in a job command; G3: no consumer API object read or changed. Nothing dropped.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the cron and rule updates below

do $cut$
declare v_rep jsonb := security.admission_rule_shadow_report_v1(24); v_from timestamptz; v_n int; r record;
begin
  -- the gate
  if exists (select 1 from pipeline.admission_rules where mode = 'live') then raise exception 'gate: a rule is already live; this cutover runs once'; end if;
  v_from := (v_rep->>'from')::timestamptz;
  if v_from is null or v_from > now() - interval '24 hours' then
    raise exception 'gate: the shadow report covers % hours, not 24 (from %)', round(extract(epoch from now() - v_from) / 3600.0, 2), v_from;
  end if;
  if coalesce((v_rep->>'all_match')::boolean, false) is not true or coalesce((v_rep->>'rules')::int, 0) <> 20 then
    raise exception 'gate: shadow report not clean: all_match %, rules %', v_rep->>'all_match', v_rep->>'rules';
  end if;
  select count(*) into v_n from pipeline.admission_rules ar join cron.job j on j.jobname = ar.legacy_job
   where ar.mode = 'shadow' and j.active and md5(j.command) = ar.call_md5 and j.schedule = ar.schedule;
  if v_n <> 20 then raise exception 'gate: % of 20 legacy jobs still carry the registered command and schedule and are active', v_n; end if;

  -- the cutover
  for r in select a.rule_code, a.legacy_job, j.jobid from pipeline.admission_rules a join cron.job j on j.jobname = a.legacy_job order by a.rule_code loop
    perform cron.alter_job(r.jobid, active => false);
    update pipeline.admission_rules set mode = 'live', updated_at = now(),
           note = coalesce(note || '; ', '') || 'live from cutover 20261116190000 (Platform Admin 16 Nov 2026 21:03; 24-hour shadow all_match)'
     where rule_code = r.rule_code;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('scheduler', 'dispatcher_cutover', r.legacy_job,
            jsonb_build_object('dispatcher', 'admission-rule-runner', 'rule', r.rule_code, 'legacy_job_active', false, 'mode', 'live',
                               'shadow_from', v_from, 'by', 'migration 20261116190000'), null);
  end loop;

  update pipeline.component_register c
     set status = 'retiring', replaced_by = 'admission-rule-runner (pipeline.admission_rules, mode live)',
         retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,
         note = 'switched off at the consolidation PR 2 cutover (20261116190000); unscheduled by docs/paste/PASTE-20261116-admission-rule-legacy-unschedule.sql after retire_after'
    from pipeline.admission_rules a
   where c.kind = 'job' and c.name = a.legacy_job and c.status = 'active';
end $cut$;

do $post$
begin
  if (select count(*) from pipeline.admission_rules where mode = 'live') <> 20 then raise exception 'post-check: not all 20 rules are live'; end if;
  if exists (select 1 from cron.job j join pipeline.admission_rules a on a.legacy_job = j.jobname where j.active) then
    raise exception 'post-check: a legacy admission job is still switched on'; end if;
  if (select count(*) from pipeline.component_register c join pipeline.admission_rules a on c.kind = 'job' and c.name = a.legacy_job where c.status = 'retiring') <> 20 then
    raise exception 'post-check: not all 20 legacy jobs are retiring'; end if;
  if (select count(*) from cron.job where jobname in ('admission-rule-runner', 'admission-rule-runner-b', 'admission-rule-runner-c') and active) <> 3 then
    raise exception 'post-check: the three runner lanes must be switched on'; end if;
  if coalesce((security.pipeline_num_v1('admission_runner.on', 0))::int, 0) <> 1 then raise exception 'post-check: admission_runner.on must be 1'; end if;
end $post$;
