-- CF-247 consolidation PR 3 prerequisite (S2-Build, 17 Nov 2026 23:xx AEDT; Platform Admin 22:45 "prepare PR 3 (coverage-lane-dispatch) 06:45 AEDT cutover").
-- Finding from the read-only shadow checks (17 Nov 22:46 AEDT, 24 h window): 7 of 13 lanes match; the other 6 differ because flag-recheck
-- (security.flag_jobs_v1) switches an idle coverage-sweep job off after its last runs found nothing to do and security.flag_requeue_v1 switches
-- it on again later, while the shadow runner keeps counting every due minute (coverage-reextract +323, coverage-reidentify +177,
-- provider-contact-page +48, coverage-find-site +42, course-list-read +4). Every command and schedule still matches its live job byte for byte.
-- Two consequences at cutover: (1) flag_requeue_v1 switches the legacy cron row back on with cron.alter_job, so a legacy job switched off by the
-- cutover while it holds a raised idle flag would run again beside its live lane (double running); (2) the idle pause would stop applying, so the
-- live lanes would call the worker every due minute when there is nothing to do.
-- Change:
--   security.job_switched_on_v1 and security.job_switch_v1: a job whose PR 3 lane is live is held and released on the lane (field_execution_registry
--   .enabled, which coverage_lane_tick_v1 already honours), never by switching its legacy cron row on; and no switch-on path turns on a job the
--   component register marks retiring or retired (UR-07, as Automations already does; today course-link-reverse is retiring with a raised idle flag).
--   security.flag_jobs_v1 and security.flag_requeue_v1 use them (md5-guarded edits, three and one exact replacements).
--   security.coverage_lane_run_v1 in shadow: when the legacy job is switched off at that minute, the dispatch is recorded 'deferred' (not counted by
--   the shadow report), so the report compares like with like from this change on. Live dispatching is unchanged.
-- No lane changes mode; no job is created, switched or scheduled; nothing is dropped. G3 surface untouched.
-- Replaces: the direct cron.alter_job switch in security.flag_jobs_v1 and security.flag_requeue_v1.
-- Retires: nothing.

create or replace function security.job_switched_on_v1(p_jobid bigint, p_job text)
 returns boolean
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select case
    when exists (select 1 from pipeline.field_execution_registry r where r.kind = 'worker_lane' and r.legacy_job = p_job and r.mode = 'live')
      then coalesce((select bool_and(r.enabled) from pipeline.field_execution_registry r where r.kind = 'worker_lane' and r.legacy_job = p_job and r.mode = 'live'), false)
    else coalesce((select c.active from cron.job c where c.jobid = p_jobid), false)
  end
$function$;
comment on function security.job_switched_on_v1(bigint, text) is 'CF-247 PR 3 prerequisite (17 Nov 2026): whether a scheduled job is switched on. For a job whose coverage lane is live (pipeline.field_execution_registry, mode live) the lane decides; otherwise its cron.job row.';
revoke all on function security.job_switched_on_v1(bigint, text) from public, anon, authenticated;

create or replace function security.job_switch_v1(p_jobid bigint, p_job text, p_on boolean)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if exists (select 1 from pipeline.field_execution_registry r where r.kind = 'worker_lane' and r.legacy_job = p_job and r.mode = 'live') then
    -- the legacy cron row stays off after the cutover: the hold is on the lane, which coverage_lane_tick_v1 skips while enabled is false
    update pipeline.field_execution_registry r set enabled = coalesce(p_on, false), updated_at = now()
     where r.kind = 'worker_lane' and r.legacy_job = p_job and r.mode = 'live';
    return case when coalesce(p_on, false) then 'lane switched on' else 'lane held' end;
  end if;
  if coalesce(p_on, false) and exists (select 1 from pipeline.component_register cr where cr.kind = 'job' and cr.name = p_job and cr.status in ('retiring', 'retired')) then
    return 'left off: retiring';  -- UR-07: a retiring or retired job is never switched on again
  end if;
  perform cron.alter_job(p_jobid, active := coalesce(p_on, false));
  return case when coalesce(p_on, false) then 'switched on' else 'switched off' end;
end $function$;
comment on function security.job_switch_v1(bigint, text, boolean) is 'CF-247 PR 3 prerequisite (17 Nov 2026): switches a scheduled job on or off for the idle pause (flag-recheck) and its release. A job whose coverage lane is live is held or released on the lane, never by its legacy cron row; a retiring or retired job is never switched on (UR-07).';
revoke all on function security.job_switch_v1(bigint, text, boolean) from public, anon, authenticated;

-- md5-guarded edits: each old text must be found exactly once, and the body after the edit must be the expected one
do $e$
declare
  t record; v_src text; v_def text; v_out text; v_c int; i int;
begin
  for t in
    select * from (values
      ('security.flag_jobs_v1()'::regprocedure, '30be1ecbedad83271a31d81d8e77c46e',
        array[$o$    if j.active and (f.id is null or f.state <> 'raised') then$o$,
              $o$    elsif not j.active and f.state = 'raised'$o$,
              $o$        perform cron.alter_job(j.jobid, active := false);$o$],
        array[$n$    if security.job_switched_on_v1(j.jobid, j.jobname) and (f.id is null or f.state <> 'raised') then  -- PR 3 prerequisite (17 Nov 2026): a live lane decides$n$,
              $n$    elsif not security.job_switched_on_v1(j.jobid, j.jobname) and f.state = 'raised'$n$,
              $n$        perform security.job_switch_v1(j.jobid, j.jobname, false);$n$]),
      ('security.flag_requeue_v1(bigint)'::regprocedure, 'b25306d3229537b6f0e942d5693e5b49',
        array[$o$    if v_jobid is not null then perform cron.alter_job(v_jobid, active := true); end if;$o$],
        array[$n$    if v_jobid is not null then perform security.job_switch_v1(v_jobid, f.entity_key, true); end if;  -- PR 3 prerequisite (17 Nov 2026): a live lane is released on the lane; a retiring job stays off$n$]),
      ('security.coverage_lane_run_v1(text,text,timestamptz,timestamptz,int)'::regprocedure, '6c9a778785ff4ab5f04ece8bd0c49978',
        array[$o$  if v_r.mode = 'shadow' then
$o$],
        array[$n$  if v_r.mode = 'shadow' and not exists (select 1 from cron.job c where c.jobname = v_r.legacy_job and c.active) then
    -- PR 3 prerequisite (17 Nov 2026): the legacy job is switched off this minute (idle pause, hold or pause), so the runner would not run it either
    insert into pipeline.coverage_lane_runs(tick_at, lane, lane_code, mode, due_at, due_minutes, started_at, finished_at, ms, status, error)
    values (p_tick, p_lane, p_code, 'shadow', p_due, p_due_minutes, v_t0, clock_timestamp(), 0, 'deferred', 'legacy job switched off: not due in shadow');
    update pipeline.field_execution_registry set last_due_at = p_due, last_status = 'deferred', updated_at = now() where lane_code = p_code;
    return 'deferred';
  end if;
  if v_r.mode = 'shadow' then
$n$])
    ) x(sig, md5_before, olds, news)
  loop
    v_src := (select p.prosrc from pg_proc p where p.oid = t.sig);
    if position('PR 3 prerequisite (17 Nov 2026)' in v_src) > 0 then raise notice '%: already applied', t.sig; continue; end if;
    if md5(v_src) <> t.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', t.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(t.sig), chr(13), '');
    v_out := v_src;
    for i in 1 .. array_length(t.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, t.olds[i], ''))) / length(t.olds[i]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', t.sig, i, v_c; end if;
      v_def := replace(v_def, t.olds[i], t.news[i]);
      v_out := replace(v_out, t.olds[i], t.news[i]);
    end loop;
    execute v_def;
    if md5((select p.prosrc from pg_proc p where p.oid = t.sig)) <> md5(v_out) then raise exception '% after the edit is not the expected body', t.sig; end if;
  end loop;
end $e$;

do $$
begin
  if position('security.job_switch_v1(j.jobid, j.jobname, false)' in (select prosrc from pg_proc where oid = 'security.flag_jobs_v1()'::regprocedure)) = 0
     or position('cron.alter_job' in (select prosrc from pg_proc where oid = 'security.flag_jobs_v1()'::regprocedure)) > 0 then raise exception 'post-check: flag_jobs_v1'; end if;
  if position('cron.alter_job' in (select prosrc from pg_proc where oid = 'security.flag_requeue_v1(bigint)'::regprocedure)) > 0 then raise exception 'post-check: flag_requeue_v1'; end if;
  if position('''deferred'', ''legacy job switched off' in (select prosrc from pg_proc where oid = 'security.coverage_lane_run_v1(text,text,timestamptz,timestamptz,int)'::regprocedure)) = 0 then raise exception 'post-check: coverage_lane_run_v1'; end if;
  if exists (select 1 from pipeline.field_execution_registry where kind = 'worker_lane' and mode <> 'shadow') then raise exception 'post-check: no lane may be live before the cutover'; end if;
end $$;
