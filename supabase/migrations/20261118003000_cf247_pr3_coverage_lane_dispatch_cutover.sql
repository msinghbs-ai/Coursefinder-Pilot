-- CF-247 consolidation PR 3 cutover: coverage-lane-dispatch takes over the 13 coverage worker lanes (Platform Admin 15 Nov 2026 22:36
-- "Cron dispatchers" rule; cutover brought forward from Wed 18 Nov 06:45 AEDT to tonight by the Platform Admin, 17 Nov 2026 23:02:
-- "Do not wait until tomorrow's 06:45 AEDT scheduled slot ... promote PR 3 live immediately if checks pass").
-- Replaces: the 13 legacy cron jobs registered in pipeline.field_execution_registry (kind worker_lane): switched off, active = false; marked retiring.
-- Retires: those 13 jobs (component register: retiring, replaced_by coverage-lane-dispatch, retire_after = today + hygiene.retire_after_days).
--          They are unscheduled by coursefinder-admin docs/paste/PASTE-20261118-coverage-lane-legacy-unschedule.sql after the retention window;
--          a migration drops nothing.
--
-- Shadow evidence (read only): from 17 Nov 06:22 AEDT, 13 of 13 commands and schedules equal to their live jobs (md5), 3 dispatchers with every tick
-- succeeded (2,961 in 24 h, longest 0.8 s), projected load at most 235.7 of 300 s a minute. Six lanes differed only because flag-recheck switched
-- idle legacy jobs off and on while the shadow runner kept counting; 20261118001000 (#1227) makes the shadow skip minutes the legacy job is off and
-- moves the idle pause and its release onto the live lane, so no legacy row can be switched back on beside its lane.
-- The Platform Admin waived the 24-hour window (23:02). Gate, in this migration, so it applies only when it holds: #1227 is applied; the shadow
-- report for the last hour (all after #1227) shows all_match for all 13 lanes; every legacy job still carries exactly the registered command and
-- schedule (md5); every legacy job that is off holds a raised idle flag (its lane then starts held and is released by flag-recheck). Otherwise
-- nothing changes and the deploy reports the reason.
-- In one transaction: the 13 lanes go live (the three dispatcher lanes run them from the next minute, each held exactly when its legacy job was
-- off) and the 13 legacy jobs are switched off, so no lane is run twice. Every change is logged in pipeline.admin_control_events.
-- Not in PR 3 (unchanged, still on their own cron jobs): coverage-ai-match, calendar-reread, coverage-read, coverage-read-2; the 7 API v3 field
-- lanes stay disabled. G1: the dispatcher jobs are catalogued (20261116220000); G2: no new setting, no number in a job command; G3: no consumer
-- API object read or changed. Nothing dropped.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the cron and registry updates below

do $cut$
declare v_rep jsonb := security.coverage_lane_shadow_report_v1(1); v_n int; r record;  -- fixed: the last hour, all after #1227 (Platform Admin 23:02)
begin
  -- the gate
  if exists (select 1 from pipeline.field_execution_registry where kind = 'worker_lane' and mode = 'live') then raise exception 'gate: a lane is already live; this cutover runs once'; end if;
  if position('PR 3 prerequisite (17 Nov 2026)' in (select prosrc from pg_proc where oid = 'security.coverage_lane_run_v1(text,text,timestamptz,timestamptz,int)'::regprocedure)) = 0
     or position('security.job_switch_v1(v_jobid, f.entity_key, true)' in (select prosrc from pg_proc where oid = 'security.flag_requeue_v1(bigint)'::regprocedure)) = 0 then
    raise exception 'gate: the prerequisite 20261118001000 (#1227) is not applied';
  end if;
  if coalesce((v_rep->>'all_match')::boolean, false) is not true or coalesce((v_rep->>'targets')::int, 0) <> 13 then
    raise exception 'gate: shadow report for the last hour not clean: all_match %, targets %, rows %', v_rep->>'all_match', v_rep->>'targets',
      (select jsonb_agg(e) from jsonb_array_elements(v_rep->'rows') e where not (e->>'matches')::boolean);
  end if;
  select count(*) into v_n from pipeline.field_execution_registry fr join cron.job j on j.jobname = fr.legacy_job
   where fr.kind = 'worker_lane' and fr.mode = 'shadow' and md5(j.command) = fr.call_md5 and md5(fr.call_sql) = fr.call_md5 and j.schedule = fr.schedule;
  if v_n <> 13 then raise exception 'gate: % of 13 legacy jobs still carry the registered command and schedule', v_n; end if;
  if exists (select 1 from pipeline.field_execution_registry fr join cron.job j on j.jobname = fr.legacy_job
              where fr.kind = 'worker_lane' and not j.active
                and not exists (select 1 from pipeline.enrichment_flags f where f.entity = 'job' and f.entity_key = j.jobname and f.field = '' and f.reason_code = 'idle_paused' and f.state = 'raised')) then
    raise exception 'gate: a legacy job is switched off without a raised idle flag (a person paused it): resume or settle it first';
  end if;

  -- the cutover
  for r in select fr.lane_code, fr.legacy_job, j.jobid, j.active from pipeline.field_execution_registry fr join cron.job j on j.jobname = fr.legacy_job
            where fr.kind = 'worker_lane' order by fr.lane_code loop
    perform cron.alter_job(r.jobid, active => false);
    update pipeline.field_execution_registry set mode = 'live', enabled = r.active, updated_at = now(),
           note = coalesce(note || '; ', '') || 'live from cutover 20261118003000 (Platform Admin 17 Nov 2026 23:02; shadow clean for the last hour after #1227)'
             || case when r.active then '' else '; held at cutover: legacy job idle-paused, released by flag-recheck' end
     where lane_code = r.lane_code;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('scheduler', 'dispatcher_cutover', r.legacy_job,
            jsonb_build_object('dispatcher', 'coverage-lane-dispatch', 'lane', r.lane_code, 'legacy_job_active', false, 'mode', 'live', 'lane_enabled', r.active,
                               'shadow_from', v_rep->>'from', 'by', 'migration 20261118003000'), null);
  end loop;

  update pipeline.component_register c
     set status = 'retiring', replaced_by = 'coverage-lane-dispatch (pipeline.field_execution_registry, mode live)',
         retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,
         note = 'switched off at the consolidation PR 3 cutover (20261118003000); unscheduled by docs/paste/PASTE-20261118-coverage-lane-legacy-unschedule.sql after retire_after'
    from pipeline.field_execution_registry fr
   where fr.kind = 'worker_lane' and c.kind = 'job' and c.name = fr.legacy_job and c.status = 'active';
end $cut$;

do $post$
begin
  if (select count(*) from pipeline.field_execution_registry where kind = 'worker_lane' and mode = 'live') <> 13 then raise exception 'post-check: not all 13 lanes are live'; end if;
  if exists (select 1 from pipeline.field_execution_registry where kind <> 'worker_lane' and mode <> 'disabled') then raise exception 'post-check: a field lane is not disabled'; end if;
  if exists (select 1 from cron.job j join pipeline.field_execution_registry fr on fr.legacy_job = j.jobname and fr.kind = 'worker_lane' where j.active) then
    raise exception 'post-check: a legacy coverage job is still switched on'; end if;
  if (select count(*) from pipeline.component_register c join pipeline.field_execution_registry fr on fr.kind = 'worker_lane' and c.kind = 'job' and c.name = fr.legacy_job where c.status = 'retiring') <> 13 then
    raise exception 'post-check: not all 13 legacy jobs are retiring'; end if;
  if (select count(*) from cron.job where jobname in ('coverage-lane-dispatch', 'coverage-lane-dispatch-b', 'coverage-lane-dispatch-c') and active) <> 3 then
    raise exception 'post-check: the three dispatcher lanes must be switched on'; end if;
  if coalesce((security.pipeline_num_v1('coverage_lane.on', 0))::int, 0) <> 1 then raise exception 'post-check: coverage_lane.on must be 1'; end if;
end $post$;
