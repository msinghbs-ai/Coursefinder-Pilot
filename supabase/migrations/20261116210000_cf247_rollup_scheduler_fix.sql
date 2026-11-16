-- CF-247 consolidation PR 1 fix (Platform Admin 16 Nov 2026 22:44, approving the three fixes after the 22:30 cutover review was held:
-- admin docs/CURRENT-STATE.md section 4). The 24-hour shadow matched on every target, but 20 of 1,427 shadow ticks ran 60.5 to 105.5 s
-- (median 0.63 s), every dispatch done within 1 s, so the time was spent after the dispatch loop; and live, a tick is one statement under
-- the database's 120 s limit, so a target near that limit (layer2-onboarding-snapshot: legacy p95 108 s, max 117 s) would be cancelled and,
-- with its due minute not yet recorded, taken again every minute.
--   1. The run history is trimmed by the job housekeeping-daily (security.rollup_runs_trim_v1, the scope's design), no longer inside the tick.
--   2. A live target's due minute is recorded and committed before it runs, so a run cut off by the statement limit is not taken again
--      before its next due minute (shadow targets are unchanged: they record their due minute when dispatched).
--   3. layer2-onboarding-snapshot stays on its own job: its target is disabled (the legacy job is untouched and keeps running), and the
--      shadow report counts enabled targets only (25).
-- Shadow only: every target stays in mode 'shadow'; the 26 legacy jobs keep running exactly as they are. A fresh 24-hour shadow starts when
-- this is live; the cutover is a separate change (Tue 17 Nov 2026 22:30 AEDT at the earliest).
-- G1: no new job (housekeeping-daily gains one call). G2: rollup.keep_days (existing setting) is read by the trim. G3: no consumer API object.
-- Replaces: security.rollup_tick_v1() and security.rollup_shadow_report_v1(int) (md5-guarded edits of the live text); the command of the job
--           housekeeping-daily (adds "select security.rollup_runs_trim_v1();")
-- Retires: nothing

set local lock_timeout = '5s';

create or replace function pg_temp.cf_pr1_edit(p_sig text, p_md5 text, p_done text, p_edits jsonb) returns text language plpgsql as $edit$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_new text; e jsonb; v_n int;
begin
  if position(p_done in v_def) > 0 then return 'already'; end if;
  if md5(v_def) <> p_md5 then raise exception '% differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  v_new := v_def;
  for e in select * from jsonb_array_elements(p_edits) loop
    v_n := (length(v_new) - length(replace(v_new, e->>'old', ''))) / length(e->>'old');
    if v_n <> 1 then raise exception '%: an edit must apply exactly once (found % for: %)', p_sig, v_n, left(e->>'old', 80); end if;
    v_new := replace(v_new, e->>'old', e->>'new');
  end loop;
  execute v_new;
  return 'edited';
end $edit$;

-- 1. The trim, run by housekeeping-daily
create or replace function security.rollup_runs_trim_v1()
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_n int;
begin
  delete from pipeline.rollup_runs where tick_at < now() - make_interval(days => security.pipeline_num_v1('rollup.keep_days', 14)::int);
  get diagnostics v_n = row_count;
  return v_n;
end $function$;
revoke all on function security.rollup_runs_trim_v1() from public, anon, authenticated;
comment on function security.rollup_runs_trim_v1() is 'CF-247 consolidation PR 1 fix (16 Nov 2026): removes rollup scheduler run history older than rollup.keep_days; run by the job housekeeping-daily, never inside the tick.';

do $hk$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'housekeeping-daily' and command = 'select security.housekeeping_daily_v1()';
  if v_job is null and not exists (select 1 from cron.job where jobname = 'housekeeping-daily' and command like '%security.rollup_runs_trim_v1()%') then
    raise exception 'housekeeping-daily is not the job this change edits';
  end if;
  if v_job is not null then
    perform cron.alter_job(v_job, command := 'select security.housekeeping_daily_v1(); select security.rollup_runs_trim_v1();');
  end if;
end $hk$;

-- 2. The tick: due minute first for a live target; no trim inside the tick
select pg_temp.cf_pr1_edit('security.rollup_tick_v1()', '85c2e4a49fc3f55ce38b7cce0b8a934a', 'PR 1 fix (16 Nov 2026)', jsonb_build_array(
  jsonb_build_object('old', E'    perform security.rollup_run_target_v1(v_r.target_code, v_tick, v_r.due_at, v_r.n::int);\n',
                     'new', E'    if v_r.mode = ''live'' then  -- PR 1 fix (16 Nov 2026): the due minute is recorded before a live target runs, so a run cut off by the statement limit is not taken again before its next due minute\n      update pipeline.rollup_targets set last_due_at = v_r.due_at, updated_at = now() where target_code = v_r.target_code;\n      commit;\n    end if;\n    perform security.rollup_run_target_v1(v_r.target_code, v_tick, v_r.due_at, v_r.n::int);\n'),
  jsonb_build_object('old', E'  delete from pipeline.rollup_runs where tick_at < now() - make_interval(days => v_keep);\n  commit;\n',
                     'new', E'  -- the run history is trimmed by housekeeping-daily (security.rollup_runs_trim_v1), not inside the tick\n')));

-- 3. layer2-onboarding-snapshot stays on its own job; the shadow report counts enabled targets only
update pipeline.rollup_targets
   set enabled = false, updated_at = now(),
       note = 'kept on its own job (PR 1 fix, Platform Admin 16 Nov 2026 22:44): legacy p95 108 s and max 117 s are too close to the tick''s 120 s statement limit; the legacy job layer2-onboarding-snapshot keeps running'
 where target_code = 'layer2-onboarding-snapshot' and enabled;

select pg_temp.cf_pr1_edit('security.rollup_shadow_report_v1(integer)', 'c4625e76e28cabca40fa2154783f3686', 'a target kept on its own job', jsonb_build_array(
  jsonb_build_object('old', E'     where t.rollup_group = ''A'') z(x);',
                     'new', E'     where t.rollup_group = ''A'' and t.enabled) z(x);  -- PR 1 fix (16 Nov 2026): a target kept on its own job (enabled false) is not part of the shadow')));

-- 4. Settings metadata and the register
update pipeline.platform_toolset_settings
   set used_by = 'security.rollup_tick_v1 (job rollup-scheduler: window of a target''s longest recent run); security.rollup_runs_trim_v1 (job housekeeping-daily)'
 where toolset_key = 'pipeline' and key = 'rollup.keep_days' and used_by not like '%rollup_runs_trim_v1%';

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.rollup_runs_trim_v1', 'Platform', 'Reports', 'Trims rollup scheduler run history older than rollup.keep_days (job housekeeping-daily)', 'active', '{}', '20261116210000')
on conflict do nothing;

-- 5. Post-checks
do $c$
declare v_tick text := pg_get_functiondef('security.rollup_tick_v1()'::regprocedure); v_rep text := pg_get_functiondef('security.rollup_shadow_report_v1(integer)'::regprocedure); v_n int;
begin
  if position('PR 1 fix (16 Nov 2026)' in v_tick) = 0 or position('delete from pipeline.rollup_runs' in v_tick) > 0 then raise exception 'post-check: the tick is not the fixed one'; end if;
  if position('t.enabled) z(x)' in v_rep) = 0 then raise exception 'post-check: the shadow report still counts disabled targets'; end if;
  if not exists (select 1 from cron.job where jobname = 'housekeeping-daily' and active and command = 'select security.housekeeping_daily_v1(); select security.rollup_runs_trim_v1();') then
    raise exception 'post-check: housekeeping-daily does not trim the rollup history';
  end if;
  if exists (select 1 from pipeline.rollup_targets where target_code = 'layer2-onboarding-snapshot' and enabled) then raise exception 'post-check: layer2-onboarding-snapshot is still a scheduler target'; end if;
  if exists (select 1 from pipeline.rollup_targets where mode <> 'shadow') then raise exception 'post-check: a target is live (this change is shadow only)'; end if;
  select count(*) into v_n from pipeline.rollup_targets t join cron.job j on j.jobname = t.legacy_job
   where t.rollup_group = 'A' and t.call_sql = j.command and t.call_md5 = md5(j.command) and t.schedule = j.schedule and j.active;
  if v_n <> 26 then raise exception 'post-check: % of 26 legacy jobs are unchanged and active', v_n; end if;
  if security.pipeline_num_v1('rollup.scheduler_on', 0) < 1 then raise exception 'post-check: the scheduler is off'; end if;
end $c$;
