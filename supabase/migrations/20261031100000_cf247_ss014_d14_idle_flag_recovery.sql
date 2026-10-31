-- CF-247 StudySearch SS-014 decision D14 (Platform Admin mandate 31 Oct 2026 21:54, "SS-014 Recovery and Automation Execution Mandate";
-- admin docs/platform/nz-enrichment-brief/2026-10-31-studysearch-transformation.md §32).
-- Why (verified live 31 Oct 2026): coverage-ai-match was switched on by a person on 19 Oct 2026 12:42 UTC (Automations, reason "Re-find wave
-- refind-1") while its automatic idle-pause flag (raised by the flag unit 19 Oct 08:40 UTC) stayed raised. security.flag_jobs_v1 only
-- re-evaluates a job whose idle flag is not raised, so the idle guard stopped applying to that job, and Flags showed a pause not in force.
-- What:
--   * security.job_idle_flag_person_release_v1(job, reason): releases a job's open idle-pause flag as a person release (audit row in
--     pipeline.enrichment_flag_events through security.flag_release_v1). Only the named job is touched.
--   * security.admin_automation_control_v1 (md5-guarded edit): "resume" of one job, and "resume_area" for each job it switches on, call it.
--     A person's intentional restart is the Automations action itself (Platform Admin role, logged in admin_control_events).
--   * One-off reconciliation: an idle-pause flag still raised on an active job that a person switched on after the flag was raised is released
--     as that person's release, citing the logged event. No job is switched on or off by it.
--   * Fix (SS-014C): job platform-alerts was scheduled '10-59/10', which never fires at minute 0; it now runs every 10 minutes.
-- Replaces: security.admin_automation_control_v1 (same name; md5-guarded edit)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. Consumer API untouched (G3).

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1. the release used by Automations
create or replace function security.job_idle_flag_person_release_v1(p_job text, p_reason text) returns int
language plpgsql security definer set search_path to '' as $function$
declare f record; v_n int := 0;
begin
  -- D14 (31 Oct 2026): a person switching a job on releases that job's automatic idle-pause flag; the audit row is kept in
  -- pipeline.enrichment_flag_events, and the flag unit's idle guard applies to the job again. No other job is touched.
  for f in select x.id from pipeline.enrichment_flags x
            where x.entity = 'job' and x.entity_key = p_job and x.field = '' and x.reason_code = 'idle_paused' and x.cleared_at is null and coalesce(x.state, 'raised') = 'raised' loop
    perform security.flag_release_v1(f.id, coalesce(auth.uid()::text, 'person'), 'person', 'Switched on by a person on Automations: ' || left(coalesce(p_reason, ''), 200),
                                     jsonb_build_object('source', 'Automations', 'decision', 'D14'), true);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$;
revoke all on function security.job_idle_flag_person_release_v1(text, text) from public, anon, authenticated;

select pg_temp.edit_once('security.admin_automation_control_v1(text,text,jsonb)', '8d5a6f103e1ad22a6f4bbd2f15d6a5c5', 'd90af04ccda6b74a88a506c58c0299fb', array[
 array[$o$      perform cron.alter_job(r.jobid, active => p_action='resume_area');$o$, $n$      perform cron.alter_job(r.jobid, active => p_action='resume_area');
      if p_action='resume_area' then perform security.job_idle_flag_person_release_v1(r.jobname, coalesce(nullif(p_args->>'reason',''),'area '||coalesce(p_args->>'area','')||' switched on')); end if;  -- D14$n$],
 array[$o$    perform cron.alter_job(j.jobid, active => p_action='resume');$o$, $n$    perform cron.alter_job(j.jobid, active => p_action='resume');
    -- D14 (31 Oct 2026): a person switching the job on releases its automatic idle-pause flag, so Flags matches and the idle guard applies again
    if p_action='resume' then perform security.job_idle_flag_person_release_v1(p_job, coalesce(nullif(p_args->>'reason',''),'switched on')); end if;$n$]],
 array[1, 1]);

-- 2. one-off reconciliation: flags still raised on active jobs that a person switched on after the flag was raised
do $$
declare f record; v_at timestamptz; v_actor uuid; v_reason text; v_n int := 0;
begin
  for f in select x.id, x.entity_key, x.flagged_at from pipeline.enrichment_flags x join cron.job j on j.jobname = x.entity_key and j.active
            where x.entity = 'job' and x.field = '' and x.reason_code = 'idle_paused' and x.cleared_at is null and coalesce(x.state, 'raised') = 'raised' loop
    v_at := null;
    select e.created_at, e.actor, e.detail ->> 'reason' into v_at, v_actor, v_reason from pipeline.admin_control_events e
     where e.area = 'automations' and e.action in ('resume', 'resume_area') and e.created_at > f.flagged_at
       and e.target in (f.entity_key, (select c.area from pipeline.automation_catalogue c where c.jobname = f.entity_key))
     order by e.created_at desc limit 1;
    continue when v_at is null;  -- an active job with no recorded person restart is left to the flag unit
    perform security.flag_release_v1(f.id, coalesce(v_actor::text, 'person'), 'person',
      'Reconciled (D14, 31 Oct 2026): switched on by a person on Automations on ' || to_char(v_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI')
      || ' (' || coalesce(v_reason, 'no reason given') || '); the idle-pause flag had stayed raised', jsonb_build_object('event_at', v_at, 'decision', 'D14'), true);
    v_n := v_n + 1;
  end loop;
  raise notice 'D14: % stale idle-pause flag(s) reconciled', v_n;
end $$;

-- 3. SS-014C fix: platform-alerts every 10 minutes (minute 0 included), two minutes after the health check
select cron.alter_job((select j.jobid from cron.job j where j.jobname = 'platform-alerts'), schedule => '*/10 * * * *');

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.job_idle_flag_person_release_v1', 'Platform', 'Platform upkeep', 'D14: a person switching a job on releases its idle-pause flag', 'active', '{}', '20261031100000')
on conflict do nothing;

-- post-check
do $$
begin
  if exists (select 1 from pipeline.enrichment_flags x join cron.job j on j.jobname = x.entity_key and j.active
              where x.entity = 'job' and x.reason_code = 'idle_paused' and x.cleared_at is null and coalesce(x.state, 'raised') = 'raised'
                and exists (select 1 from pipeline.admin_control_events e where e.area = 'automations' and e.action in ('resume', 'resume_area') and e.created_at > x.flagged_at
                             and e.target in (x.entity_key, (select c.area from pipeline.automation_catalogue c where c.jobname = x.entity_key)))) then
    raise exception 'D14 post-check: a flag is still raised on a job a person switched on'; end if;
  if (select schedule from cron.job where jobname = 'platform-alerts') <> '*/10 * * * *' then raise exception 'D14 post-check: platform-alerts schedule'; end if;
end $$;
