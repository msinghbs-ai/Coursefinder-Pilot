-- CF-247 IQ-00064 (P0 release blocker, consolidated mandate 3 Nov 2026 13:09 §3): an enrichment plan step is never marked done while its
-- work is unfinished (Agent D, orchestration; Release A; admin docs/platform/nz-enrichment-brief/
-- 2026-11-03-consolidated-enrichment-developer-readiness-mandate-1309.md; builds on 20261103190000, v2.15.424 candidate).
-- Why (live, read-only, 3 Nov 2026 12:45-13:20 AEDT):
--   * The five Find course pages steps started by the automatic plans at 11:41 AEDT (admin_jobs kind course_page_find, created 00:45 UTC,
--     providers 00e5f26c, 229dc07d, 87576ec2, e2dd4b2b, ea5a3fa6): ea5a3fa6 searched all 117 courses by 00:54 UTC. The other four searched 62
--     of 173, 28 of 100, 40 of 92 and 40 of 79 by about 00:53 UTC, then nothing moved: from 00:55 UTC every course-page search call answered
--     idle (the picker gives no rows once today's Firecrawl share for course search is spent: fc_budget_left_v1('course_link_search') < 2;
--     the five tasks used 752 credits in 8 minutes). 274 of their courses are still queued in pipeline.course_link_search.
--   * Cause 1, the idle guard (security.flag_jobs_v1, job flag-recheck): it pauses a coverage-sweep job after flag.empty_calls_to_pause (30)
--     calls in a row with nothing done, whatever the reason the calls found nothing. It paused course-link-search-worker at 01:30 UTC while
--     four running tasks had 274 courses queued for it, and released it as a trial at 01:40. A budget hold is not "nothing to do".
--   * Cause 2, the task watcher (security.admin_job_watch_v1, called by admin_job_slice_v1): a task with nothing moving for its stall time
--     (45 minutes for course_page_find, 30 for scholarship scans and provider fill) is finished and security.admin_jobs_tick_v1 sets it done,
--     whatever its remaining scope; the plan tick (security.enrich_plan_tick_v1) reads a done task as a done step, and the plan finishes done.
--   * Measured (plan runs of the last 7 days, 13:16 AEDT): steps that ended done with work unfinished: Find course pages 4 of 410 (274
--     courses, all 3 Nov, the four above), scholarship scans 13 of 953 (38 pages), provider fill
--     1 of 160 (2 of its 3 parts); 18 steps, 314 items, every one in the latest plan run of its university (so the re-plan sees it); task id
--     set md5 effa0dc2788015cfbef9c66247d5bade. They are reconciled below (section 8).
-- What (switch tasks.lane_hold_on ships ON (1): the mandate makes the correction a P0 release blocker; 0 restores the previous behaviour):
--   1 security.lane_task_waiting_v1(mode) (new, read-only): a queued or running task has work queued for the worker lane (the course page
--     search lane, link_search, which the task depends on; the scholarship and provider fill tasks fire their own work each minute and do not
--     depend on a scheduled lane). security.flag_jobs_v1 (md5-guarded edit) does not idle-pause a lane while it is true, and wakes a paused
--     lane when it is true.
--   2 security.admin_job_watch_v1 (md5-guarded edit): a task of a kind in tasks.hold_kinds (course_page_find, scholarship_provider_scan,
--     provider_fill) with work left (done < total) is never finished by the stall rule. Once nothing has moved for tasks.stall_seconds it is
--     held: it stays running and its result carries held {code, reason, since, resumes, ends_at, checkpoint {done, total, last_change_at,
--     phase}} and unprocessed (the remaining items); the note says why (the gate security.link_search_block_v1 names, or the phase it waits
--     in) and when it gives up; one event when the hold starts. It carries on by itself when its lane has room. Bounded: nothing moved for
--     tasks.lane_hold_max_hours (24) ends it failed with the reason and the items not processed.
--   3 security.admin_jobs_tick_v1 (md5-guarded edit): a finished task whose result says end_state failed is failed, its note the error.
--   4 security.enrich_plan_tick_v1 (md5-guarded edit): parent and child reconcile. A step completes only when its task's scope is processed,
--     or the task failed or was cancelled with a reason: a task of tasks.hold_kinds that ended done with work unfinished is a failed step; a
--     failed or cancelled task's reason is the step's note; a step is not timed out while its task of tasks.hold_kinds is open; a running
--     step shows its task's hold (held, remaining, note) on the Enrichment plan screen; a failed, timed-out or cancelled step records its
--     restart eligibility (security.plan_step_restart_v1: when plans.replan_on_retry may retry it, or that it waits for a change).
--   5 Monitoring: security.plan_unfinished_done_v1() (new, read-only) lists plan steps (plan runs of the last tasks.unfinished_lookback_days)
--     that are done while their task finished done with work unfinished, and tasks of tasks.hold_kinds that finished done with work
--     unfinished after the reconciliation below. security.integration_yield_checks_v1 (md5-guarded edit) raises one issue,
--     plan_unfinished_done:plans (P1, A7 Scheduling), while any is listed, and marks it cleared when none is.
--   6 Reconciliation (section 8): exactly the measured steps (guarded by count and the md5 of their task ids; refused on any mismatch;
--     nothing deleted) are set failed with "ended done with N items unprocessed (IQ-00064)" and their restart eligibility, so the governed
--     re-plan trigger plans.replan_on_retry (on) reschedules them through the automatic planner; no per-course dispatch. One
--     admin_control_events row records it.
-- Budgets: a budget hold is a hold, not done. No Firecrawl or AI value is raised; nothing reads a page or calls a model that did not before;
-- the pickers, their gates, the day shares and the month caps are unchanged. A lane not paused while a task waits keeps calling the worker each
-- minute, which answers held at no cost (lanes.skip_held_paid_calls, v2.15.423, records the hold instead of a call when switched on).
-- md5 (before = live v2.15.423, re-read 3 Nov 2026 13:19 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/plan-step-lane-hold/run.sh):
--   security.flag_jobs_v1()                     22fa89f4c0c3c238b3d281bd481309b2 -> 668251ec6027c1e9e6dd7d7a9b340bb9
--   security.admin_job_watch_v1(uuid)           ad21305f89ee441bde462cc35e5a8a98 -> 34a1cfd57b367d0e60ccb4a85f56e228
--   security.admin_jobs_tick_v1(integer)        e760363a6af21d850f7e6e1c86bca0cb -> fc698f9912cffd90a7b8ae32e33dd09e
--   security.enrich_plan_tick_v1(uuid)          613782d4a04d3e6ce123c8837339d5e0 -> cab734df6715e25014935bd22058343b
--   security.integration_yield_checks_v1()      2bcba102aa776a21c888bae711fd3374 -> 265d5fa8637185016018b3b81dad1b39
-- Consumer API (G3): untouched.
-- Replaces: the stall finish of tasks with work left in security.admin_job_watch_v1 and the unconditional idle pause in security.flag_jobs_v1
--   (same functions, md5-guarded edits, behind tasks.lane_hold_on); security.admin_jobs_tick_v1, security.enrich_plan_tick_v1 and
--   security.integration_yield_checks_v1 edited in place (md5-guarded)
-- Retires: nothing
-- Nothing is dropped or deleted.

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

-- 0. the definitions the new code reads are the ones it was written against (not changed here) ------------------------------------------------
do $g$
declare r record;
begin
  -- the slice still hands these task kinds to the watcher (security.link_search_block_v1 and security.worker_mode_waiting_v1 are only called,
  -- as the live definitions already call them; their answers are read by shape, not edited)
  for r in select * from (values ('security.admin_job_slice_v1(uuid,integer)', '88f82c974b0ecde708a0550413791d86')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. settings (G2) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'tasks.lane_hold_on', 'Tasks: hold a task while its work waits',
  '1: a task of the kinds in tasks.hold_kinds with work left stays running, held with the reason, while its lane is held (idle guard, Firecrawl share or month cap, work waiting its turn), and carries on when the lane has room; the idle guard does not pause a lane while a task has work waiting for it; a plan step completes only when its task''s work is done or the task failed or was cancelled with a reason. 0: as before 3 Nov 2026 (a task with nothing moving for its stall time ends done).',
  'number', '1'::jsonb, '0', '1', 'on (1) or off (0)', 785, 'Platform upkeep',
  'security.admin_job_watch_v1, security.flag_jobs_v1, security.enrich_plan_tick_v1, security.plan_unfinished_done_v1', 'CF-247 IQ-00064 (P0), consolidated mandate 3 Nov 2026 13:09 §3: on'),
 ('pipeline', 'tasks.lane_hold_max_hours', 'Tasks: a held task gives up after',
  'With tasks.lane_hold_on, a held task on which nothing has moved for this many hours ends failed, with the reason and the items not processed. The plan''s retry (plans.replan_on_retry) can start it again.',
  'number', '24'::jsonb, '1', '168', 'hours', 786, 'Platform upkeep', 'security.admin_job_watch_v1', 'CF-247 IQ-00064 (P0), 3 Nov 2026'),
 ('pipeline', 'tasks.hold_kinds', 'Tasks: kinds held, never ended done, while work is left',
  'The task kinds a plan step starts whose work is counted (done of total): with tasks.lane_hold_on, these are held while work is left instead of ending done when nothing moves, and a plan step of these kinds is done only when the task''s work is.',
  'list', '["course_page_find", "scholarship_provider_scan", "provider_fill"]'::jsonb, null, null, 'task kinds', 787, 'Platform upkeep',
  'security.admin_job_watch_v1, security.enrich_plan_tick_v1, security.plan_unfinished_done_v1', 'CF-247 IQ-00064 (P0), consolidated mandate 3 Nov 2026 13:09 §3.4'),
 ('pipeline', 'tasks.unfinished_lookback_days', 'Tasks: unfinished-work check looks back',
  'The integration check plan_unfinished_done looks at plan runs and tasks of the last this many days for a step or task that ended done with work unfinished.',
  'number', '7'::jsonb, '1', '90', 'days', 788, 'Platform upkeep', 'security.plan_unfinished_done_v1', 'CF-247 IQ-00064 (P0), consolidated mandate 3 Nov 2026 13:09 §3.8')
on conflict (toolset_key, key) do nothing;

-- 2. work waiting for a lane from a task; a step's restart eligibility; steps and tasks done with work unfinished (read-only) -----------------
create or replace function security.lane_task_waiting_v1(p_mode text) returns boolean
language sql stable security definer set search_path = '' as $$
  -- CF-247 IQ-00064: a queued or running task (a person's, or an enrichment plan step's) still has work queued for this worker lane
  select case p_mode
    when 'link_search' then exists (select 1 from pipeline.admin_jobs j
                                     cross join lateral jsonb_array_elements_text(coalesce(j.args->'course_ids', '[]'::jsonb)) c(id)
                                     join pipeline.course_link_search s on s.course_id = c.id::uuid and s.state = 'queued'
                                    where j.kind = 'course_page_find' and j.state in ('queued', 'running'))
    else false end
$$;
revoke all on function security.lane_task_waiting_v1(text) from public, anon, authenticated;
comment on function security.lane_task_waiting_v1(text) is 'CF-247 IQ-00064: true while a queued or running task (a person''s or an enrichment plan step''s) has work queued for the worker lane (link_search: Find course pages courses still queued); the idle guard does not pause such a lane (tasks.lane_hold_on)';

create or replace function security.plan_step_restart_v1(p_step jsonb) returns jsonb
language sql stable security definer set search_path = '' as $$
  -- CF-247 IQ-00064: when the governed re-plan (security.enrich_plan_inputs_v1) may retry an ended step, or that it waits for a change
  select jsonb_build_object(
    'retry_on', security.pipeline_num_v1('plans.replan_on_retry', 0) >= 1,
    'after', coalesce((p_step->>'finished_at')::timestamptz, now()) + make_interval(hours => security.pipeline_num_v1('plans.retry_after_hours', 6)::int),
    'waits_for_change', exists (select 1 from pipeline.platform_toolset_settings w cross join lateral jsonb_array_elements_text(coalesce(w.value, '[]'::jsonb)) k(t)
                                 where w.toolset_key = 'pipeline' and w.key = 'plans.retry_waits_for_change' and position(lower(k.t) in lower(coalesce(p_step->>'note', ''))) > 0),
    'retry_max', security.pipeline_num_v1('plans.step_retry_max', 3))
$$;
revoke all on function security.plan_step_restart_v1(jsonb) from public, anon, authenticated;
comment on function security.plan_step_restart_v1(jsonb) is 'CF-247 IQ-00064: an ended plan step''s restart eligibility as security.enrich_plan_inputs_v1 judges it (re-plan on retry on, retry after plans.retry_after_hours from the end, or waits for a change by plans.retry_waits_for_change), kept on the step';

create or replace function security.plan_unfinished_done_v1()
returns table(kind text, run_id uuid, step_no int, step text, job_id uuid, job_kind text, provider_id uuid, unprocessed numeric, finished_at timestamptz)
language sql stable security definer set search_path = '' as $$
  -- CF-247 IQ-00064: plan steps done while their task ended done with work unfinished, and tasks of tasks.hold_kinds that ended done with
  -- work unfinished after the IQ-00064 reconciliation (earlier ones were reconciled or are not plan work)
  with k as (select array(select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'tasks.hold_kinds'),
                                                                   '["course_page_find", "scholarship_provider_scan", "provider_fill"]'::jsonb))) kinds,
                    now() - make_interval(days => security.pipeline_num_v1('tasks.unfinished_lookback_days', 7)::int) since,
                    coalesce((select max(e.created_at) from pipeline.admin_control_events e where e.action = 'iq64_plan_step_reconcile'), '-infinity') cut),
       u as (select j.*, (j.result->>'total')::numeric - (j.result->>'done')::numeric n from pipeline.admin_jobs j, k
              where j.kind = any (k.kinds) and j.state = 'done' and jsonb_typeof(j.result->'done') = 'number' and jsonb_typeof(j.result->'total') = 'number'
                and (j.result->>'done')::numeric < (j.result->>'total')::numeric),
       st as (select 'step'::text kind, r.id run_id, (e.o - 1)::int step_no, e.x->>'step' step, u.id job_id, u.kind job_kind, r.provider_id, u.n, u.finished_at
                from pipeline.enrich_plan_runs r cross join k cross join lateral jsonb_array_elements(r.steps) with ordinality e(x, o)
                join u on u.id = nullif(e.x->'ref'->>'id', '')::uuid
               where r.created_at >= k.since and e.x->>'status' = 'done' and e.x->'ref'->>'kind' = 'job')
  select * from st
  union all
  select 'task', nullif(u.args->>'plan_run', '')::uuid, null, null, u.id, u.kind, nullif(u.args->>'provider_id', '')::uuid, u.n, u.finished_at
    from u, k where u.finished_at >= greatest(k.since, k.cut) and not exists (select 1 from st where st.job_id = u.id)
$$;
revoke all on function security.plan_unfinished_done_v1() from public, anon, authenticated;
comment on function security.plan_unfinished_done_v1() is 'CF-247 IQ-00064: plan steps done while their task ended done with work unfinished, and tasks of tasks.hold_kinds that ended done with work unfinished after the reconciliation (last tasks.unfinished_lookback_days); the integration check plan_unfinished_done:plans';

-- 3. the idle guard: never pauses a lane a task is waiting for --------------------------------------------------------------------------------
select pg_temp.edit_once('security.flag_jobs_v1()', '22fa89f4c0c3c238b3d281bd481309b2', '668251ec6027c1e9e6dd7d7a9b340bb9', array[
 [$o$      if v_n >= v_need and v_work = 0 then$o$,
  $n$      if v_n >= v_need and v_work = 0
         and not (security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 and security.lane_task_waiting_v1(j.mode)) then  -- CF-247 IQ-00064: a lane a task waits for is held, not idle$n$],
 [$o$(f.next_check_at <= now() or security.worker_mode_waiting_v1(j.mode))$o$,
  $n$(f.next_check_at <= now() or security.worker_mode_waiting_v1(j.mode)
                                                                                or (security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 and security.lane_task_waiting_v1(j.mode)))$n$]
], array[1, 1]);

-- 4. the task watcher: a task with work left is held, never done ---------------------------------------------------------------------------------
select pg_temp.edit_once('security.admin_job_watch_v1(uuid)', 'ad21305f89ee441bde462cc35e5a8a98', '34a1cfd57b367d0e60ccb4a85f56e228', array[
 [$o$        v_pid uuid; v_site text; v_cok boolean; v_c int := 0; v_c2 int := 0;$o$,
  $n$        v_pid uuid; v_site text; v_cok boolean; v_c int := 0; v_c2 int := 0; v_hold_h int; v_why text; v_unit text;$n$],
 [$o$  if not v_fin and v_stall is not null and now() - v_last_at > v_stall then$o$,
  $n$  -- CF-247 IQ-00064 (tasks.lane_hold_on): a task of tasks.hold_kinds with work left is never finished by the stall rule. Once nothing has
  -- moved for tasks.stall_seconds it is held (still running) with the reason, its checkpoint and when it gives up, and carries on by itself
  -- when its lane has room; nothing moved for tasks.lane_hold_max_hours ends it failed with the reason.
  if not v_fin and v_done < v_total and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1
     and v_j.kind = any (security.pipeline_list_v1('tasks.hold_kinds', '["course_page_find", "scholarship_provider_scan", "provider_fill"]')) then
    v_stall := null;
    v_hold_h := security.pipeline_num_v1('tasks.lane_hold_max_hours', 24)::int;
    v_unit := case when v_j.kind = 'course_page_find' then 'course(s)' else 'item(s)' end;
    v_why := coalesce(v_extra->'blocked'->>'words',
                      case when v_j.kind = 'course_page_find' then (v_total - v_done) || ' search(es) waiting their turn in the course page search lane'
                           else (v_total - v_done) || ' item(s) waiting their turn (' || coalesce(v_phase, 'working') || ')' end);
    if now() - v_last_at > make_interval(hours => v_hold_h) then
      v_fin := true;
      v_note := 'Held too long: ' || (v_total - v_done) || ' of ' || v_total || ' ' || v_unit || ' not processed; nothing moved for ' || v_hold_h || ' hour(s) ('
                || v_why || '). The plan''s retry can start it again';
      v_extra := coalesce(v_extra, '{}'::jsonb) || jsonb_build_object('end_state', 'failed', 'unprocessed', v_total - v_done);
    elsif now() - v_last_at > make_interval(secs => security.pipeline_num_v1('tasks.stall_seconds', 60)) then
      v_extra := coalesce(v_extra, '{}'::jsonb) || jsonb_build_object('unprocessed', v_total - v_done,
                   'held', jsonb_build_object('code', coalesce(v_extra->'blocked'->>'code', 'waiting_turn'), 'reason', v_why, 'since', v_last_at,
                                              'resumes', coalesce(v_extra->'blocked'->>'fix', 'Carries on by itself'),
                                              'ends_at', v_last_at + make_interval(hours => v_hold_h),
                                              'checkpoint', jsonb_build_object('done', v_done, 'total', v_total, 'last_change_at', v_last_at, 'phase', v_phase)));
      v_note := 'Held: ' || v_why || '. ' || (v_total - v_done) || ' of ' || v_total || ' ' || v_unit || ' still to '
                || case when v_j.kind = 'course_page_find' then 'search' else 'process' end || '; it carries on by itself when the lane has room (gives up '
                || to_char((v_last_at + make_interval(hours => v_hold_h)) at time zone 'Australia/Melbourne', 'DD Mon HH24:MI') || ' if nothing moves)';
      if v_j.result->'held' is null then insert into pipeline.admin_job_events(job_id, note) values (p_id, v_note); end if;
    end if;
  end if;
  if not v_fin and v_stall is not null and now() - v_last_at > v_stall then$n$]
], array[1, 1]);

-- 5. the task runner: a task the watcher ended failed is failed ------------------------------------------------------------------------------
select pg_temp.edit_once('security.admin_jobs_tick_v1(integer)', 'e760363a6af21d850f7e6e1c86bca0cb', 'fc698f9912cffd90a7b8ae32e33dd09e', array[
 [$o$      update pipeline.admin_jobs set state = 'done', finished_at = now(), updated_at = now() where id = v_j.id;$o$,
  $n$      -- CF-247 IQ-00064: a task the watcher ended with end_state failed (held past tasks.lane_hold_max_hours) is failed, its note the error
      update pipeline.admin_jobs set state = case when result->>'end_state' = 'failed' then 'failed' else 'done' end,
             error = case when result->>'end_state' = 'failed' then left(result->>'note', 500) else error end,
             finished_at = now(), updated_at = now() where id = v_j.id;$n$]
], array[1]);

-- 6. the plan tick: parent and child reconcile -------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.enrich_plan_tick_v1(uuid)', '613782d4a04d3e6ce123c8837339d5e0', 'cab734df6715e25014935bd22058343b', array[
 [$o$(select case when j.state in ('done') then 'done' when j.state in ('failed', 'cancelled') then j.state end$o$,
  $n$(select case when j.state = 'done' and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1  -- CF-247 IQ-00064: done with work unfinished is not done
                                                                   and j.kind = any (security.pipeline_list_v1('tasks.hold_kinds', '["course_page_find", "scholarship_provider_scan", "provider_fill"]'))
                                                                   and jsonb_typeof(j.result->'done') = 'number' and jsonb_typeof(j.result->'total') = 'number'
                                                                   and (j.result->>'done')::numeric < (j.result->>'total')::numeric then 'failed'
                                                    when j.state in ('done') then 'done' when j.state in ('failed', 'cancelled') then j.state end$n$],
 [$o$      if v_state is null and (s->>'started_at')::timestamptz < now() - make_interval(hours => v_max) then v_state := 'timed_out'; end if;$o$,
  $n$      if v_state is null and (s->>'started_at')::timestamptz < now() - make_interval(hours => v_max)
         -- CF-247 IQ-00064: not while its task of tasks.hold_kinds is open (that task is bounded by tasks.lane_hold_max_hours)
         and not (s->'ref'->>'kind' = 'job' and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1
                  and exists (select 1 from pipeline.admin_jobs j where j.id = (s->'ref'->>'id')::uuid and j.state in ('queued', 'running')
                                 and j.kind = any (security.pipeline_list_v1('tasks.hold_kinds', '["course_page_find", "scholarship_provider_scan", "provider_fill"]')))) then
        v_state := 'timed_out'; end if;$n$],
 [$o$when 'timed_out' then 'still running after ' || v_max || ' hours; the task carries on' end))$o$,
  $n$when 'timed_out' then 'still running after ' || v_max || ' hours; the task carries on'
                                              -- CF-247 IQ-00064: a failed or cancelled task's reason is the step's note
                                              when 'failed' then case when s->'ref'->>'kind' = 'job' and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 then
                                                (select left(case when j.state = 'done' then 'ended done with ' || ((j.result->>'total')::numeric - (j.result->>'done')::numeric) || ' of '
                                                                                             || (j.result->>'total') || ' items unprocessed (IQ-00064): ' else '' end
                                                             || coalesce(nullif(j.error, ''), j.result->>'note', 'the task ' || j.state), 300)
                                                   from pipeline.admin_jobs j where j.id = (s->'ref'->>'id')::uuid) end
                                              when 'cancelled' then case when s->'ref'->>'kind' = 'job' and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 then
                                                (select left(coalesce(nullif(j.error, ''), j.result->>'note', 'the task was cancelled'), 300) from pipeline.admin_jobs j where j.id = (s->'ref'->>'id')::uuid) end end))$n$],
 [$o$      end if;
    end if;
    end loop;  -- tracks$o$,
  $n$      end if;
      if security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 and s->'ref'->>'kind' = 'job' then
        if v_state in ('failed', 'timed_out', 'cancelled') then
          -- CF-247 IQ-00064: an ended step keeps its remaining items and its restart eligibility
          update pipeline.enrich_plan_runs x set steps = jsonb_set(x.steps, array[i::text], (x.steps->i) - 'held'
                   || jsonb_build_object('restart', security.plan_step_restart_v1(x.steps->i))
                   || coalesce((select jsonb_build_object('remaining', (j.result->>'total')::numeric - (j.result->>'done')::numeric) from pipeline.admin_jobs j
                                 where j.id = (s->'ref'->>'id')::uuid and jsonb_typeof(j.result->'done') = 'number' and jsonb_typeof(j.result->'total') = 'number'
                                   and (j.result->>'done')::numeric < (j.result->>'total')::numeric), '{}'::jsonb))
           where x.id = r.id;
        elsif v_state is null then
          -- CF-247 IQ-00064: a running step shows its task's hold (reason, remaining items, checkpoint, when it resumes or gives up)
          update pipeline.enrich_plan_runs x set updated_at = now(), steps = jsonb_set(x.steps, array[i::text],
                   case when j.result ? 'held' then (x.steps->i) || jsonb_build_object('held', j.result->'held', 'remaining', j.result->'unprocessed', 'note', j.result->>'note')
                        else (x.steps->i) - 'held' - 'remaining' || case when x.steps->i->>'note' like 'Held:%' then jsonb_build_object('note', null) else '{}'::jsonb end end)
            from pipeline.admin_jobs j
           where x.id = r.id and j.id = (s->'ref'->>'id')::uuid and (x.steps->i->'held') is distinct from (j.result->'held');
        end if;
      end if;
    end if;
    end loop;  -- tracks$n$]
], array[1, 1, 1, 1]);

-- 7. monitoring: a plan step or task done with work unfinished raises one issue, cleared when none remains ---------------------------------
select pg_temp.edit_once('security.integration_yield_checks_v1()', '2bcba102aa776a21c888bae711fd3374', '265d5fa8637185016018b3b81dad1b39', array[
 [$o$  -- 5. condition cleared for the checks that ran; P0 alert path (none of these is P0 today)$o$,
  $n$  -- 4b. CF-247 IQ-00064 (mandate 3 Nov 2026 13:09 §3.8): a plan step or task that ended done with work unfinished
  begin
    select count(*), coalesce(jsonb_agg(distinct u.provider_id) filter (where u.provider_id is not null), '[]'::jsonb), coalesce(sum(u.unprocessed), 0)::int
      into v_n, v_res, v_m from security.plan_unfinished_done_v1() u;
    if v_n > 0 then
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'plan_unfinished_done:plans',
        'title', 'Plan steps or tasks ended done with work unfinished', 'layer', 'Scheduling', 'subsystem', 'enrichment plans and tasks (enrich_plan_tick_v1, admin_job_watch_v1)',
        'failure', v_n || ' plan step(s) or task(s) in the last ' || security.pipeline_num_v1('tasks.unfinished_lookback_days', 7) || ' days ended done with ' || v_m || ' item(s) not processed',
        'expected', 'A step or task with work left is held, carries on when its lane has room, and ends failed with a reason if it cannot (IQ-00064)',
        'source', 'integration-validate (yield checks)', 'validation_layer', 'V4', 'provider_ids', v_res,
        'evidence', jsonb_build_object('items', v_n, 'unprocessed', v_m, 'sample', (select jsonb_agg(to_jsonb(x)) from (select * from security.plan_unfinished_done_v1() limit 10) x)),
        'severity', 'P1', 'root_cause_class', 'code_defect', 'workstream', 'A7'), 'integration-validate');
      v_seen := v_seen || 'plan_unfinished_done:plans'::text;
    end if;
    v_ok := v_ok || 'plan_unfinished_done'::text; v_out := v_out || jsonb_build_object('plan_unfinished_done', v_n);
  exception when others then v_err := v_err || jsonb_build_object('plan_unfinished_done', left(sqlerrm, 300));
  end;

  -- 5. condition cleared for the checks that ran; P0 alert path (none of these is P0 today)$n$]
], array[1]);

-- 8. reconciliation: exactly the measured steps that ended done with work unfinished (7 days to 3 Nov 2026 13:16 AEDT) are failed with the
--    reason, so plans.replan_on_retry reschedules them through the planner. Guarded by count and the md5 of their task ids; refused on any
--    mismatch; nothing deleted; once only (its admin_control_events row).
do $r$
declare v_want text[] := array[
    '316bf0b2-1e98-48bb-816f-62fedb32733e', '31c01095-fdce-4495-80c6-5187adc0b2d9', '3daf6428-a61a-48f5-8f70-a12e6bef3f70',
    '530cd23a-50ae-4e6c-b2e8-09e71e869af2', '5b5f5d3f-5972-48e8-b47f-c0f3c168b9b1', '63014f13-a64e-4731-8503-cd97f9d1754e',
    '66933787-b937-40ad-86c9-dc456f608034', '80e98946-30ab-43b3-b6e9-1f2f52e1dfa6', '86cf79ca-3e36-4702-aac8-f71a04a56795',
    '8bf3e9af-0c4d-46c0-b732-25b55d5abeea', '8c12b05c-b9b7-4f5b-9b74-c1ced82b7088', 'a8042193-44a9-4322-a221-e1ca8579990d',
    'b29022a2-545d-4e96-951f-865b864c3032', 'b95281a2-2f96-408c-9c19-849b577cd89f', 'eb1f211d-c7c9-4df8-8de6-d59cabd869f5',
    'f201a700-da26-40f9-bd69-0022961ce347', 'fa579433-070c-4433-9fd1-1b2b2cfdd236', 'fba22606-c3a5-42c8-bc18-2f22ff5c1410']; v_n int; v_md5 text; v_steps jsonb; v_s record;
begin
  if exists (select 1 from pipeline.admin_control_events e where e.action = 'iq64_plan_step_reconcile') then
    raise notice 'IQ-00064 reconciliation: already applied'; return;
  end if;
  if cardinality(v_want) <> 18 or md5(array_to_string(array(select x from unnest(v_want) x order by x), ',')) <> 'effa0dc2788015cfbef9c66247d5bade' then
    raise exception 'IQ-00064 reconciliation: the measured id set in this migration is not the one recorded (count %, md5 %)', cardinality(v_want),
      md5(array_to_string(array(select x from unnest(v_want) x order by x), ','));
  end if;
  create temp table iq64_steps on commit drop as
    select r.id run_id, (e.o - 1)::int step_no, j.id job_id, ((j.result->>'total')::numeric - (j.result->>'done')::numeric) n
      from pipeline.enrich_plan_runs r cross join lateral jsonb_array_elements(r.steps) with ordinality e(x, o)
      join pipeline.admin_jobs j on j.id = nullif(e.x->'ref'->>'id', '')::uuid
     where e.x->'ref'->>'kind' = 'job' and j.id::text = any (v_want) and e.x->>'status' = 'done' and j.state = 'done'
       and jsonb_typeof(j.result->'done') = 'number' and jsonb_typeof(j.result->'total') = 'number' and (j.result->>'done')::numeric < (j.result->>'total')::numeric;
  select count(*), md5(string_agg(job_id::text, ',' order by job_id::text)) into v_n, v_md5 from iq64_steps;
  if v_n <> 18 or v_md5 <> 'effa0dc2788015cfbef9c66247d5bade' then
    raise exception 'IQ-00064 reconciliation: % of the % measured steps still ended done with work unfinished (md5 %); nothing changed', v_n, 18, v_md5;
  end if;
  for v_s in select * from iq64_steps order by run_id, step_no loop
    update pipeline.enrich_plan_runs x set updated_at = now(), steps = jsonb_set(x.steps, array[v_s.step_no::text],
             (x.steps->v_s.step_no) || jsonb_build_object('status', 'failed', 'note', 'ended done with ' || v_s.n || ' items unprocessed (IQ-00064)', 'remaining', v_s.n,
                                                        'reconciled', jsonb_build_object('at', now(), 'was', 'done', 'by', 'IQ-00064 migration 20261103200000')))
     where x.id = v_s.run_id;
    update pipeline.enrich_plan_runs x set steps = jsonb_set(x.steps, array[v_s.step_no::text], (x.steps->v_s.step_no) || jsonb_build_object('restart', security.plan_step_restart_v1(x.steps->v_s.step_no)))
     where x.id = v_s.run_id;
  end loop;
  select jsonb_agg(jsonb_build_object('run', run_id, 'step', step_no, 'job', job_id, 'unprocessed', n) order by job_id::text) into v_steps from iq64_steps;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('plans', 'iq64_plan_step_reconcile', 'IQ-00064', jsonb_build_object('count', v_n, 'id_md5', v_md5, 'steps', v_steps,
          'note', 'Plan steps that ended done with work unfinished (7 days to 3 Nov 2026 13:16 AEDT) set failed with the reason; plans.replan_on_retry reschedules them. tasks.lane_hold_on shipped on (mandate 3 Nov 2026 13:09 §3).'));
  raise notice 'IQ-00064 reconciliation: % step(s) set failed', v_n;
end $r$;

-- 9. catalogue and component register ------------------------------------------------------------------------------------------------------
update pipeline.automation_catalogue set description = description || ' With tasks.lane_hold_on, it does not pause a lane while a queued or running task has work waiting for it (security.lane_task_waiting_v1).'
 where jobname = 'flag-recheck' and description not like '%lane_task_waiting_v1%';
update pipeline.automation_catalogue set description = description || ' With tasks.lane_hold_on, a task of tasks.hold_kinds with work left is held (still running, with the reason and its checkpoint) while its lane is held, never done; nothing moved for tasks.lane_hold_max_hours ends it failed with the reason.'
 where jobname = 'admin-jobs' and description not like '%tasks.lane_hold_on%';
update pipeline.automation_catalogue set description = description || ' Checks also that no plan step or task ended done with work unfinished (plan_unfinished_done, IQ-00064).'
 where jobname = 'integration-validate' and description not like '%plan_unfinished_done%';
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.lane_task_waiting_v1', 'Platform', 'Platform upkeep', 'A queued or running task has work waiting for a worker lane (idle guard)', 'active', '{}', '20261103200000'),
 ('function', 'security.plan_step_restart_v1', 'Platform', 'Platform upkeep', 'An ended plan step''s restart eligibility (governed re-plan)', 'active', '{}', '20261103200000'),
 ('function', 'security.plan_unfinished_done_v1', 'Platform', 'Platform upkeep', 'Plan steps and tasks done with work unfinished (integration check)', 'active', '{}', '20261103200000')
on conflict do nothing;

-- 10. post-check ------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline'
        and key in ('tasks.lane_hold_on', 'tasks.lane_hold_max_hours', 'tasks.hold_kinds', 'tasks.unfinished_lookback_days')) <> 4 then
    raise exception 'IQ-00064 post-check: a setting is missing'; end if;
  if not exists (select 1 from pipeline.admin_control_events where action = 'iq64_plan_step_reconcile') then
    raise exception 'IQ-00064 post-check: the reconciliation was not recorded'; end if;
  if exists (select 1 from security.plan_unfinished_done_v1() u where u.kind = 'step' and u.job_id::text = any (array[
    '316bf0b2-1e98-48bb-816f-62fedb32733e', '31c01095-fdce-4495-80c6-5187adc0b2d9', '3daf6428-a61a-48f5-8f70-a12e6bef3f70',
    '530cd23a-50ae-4e6c-b2e8-09e71e869af2', '5b5f5d3f-5972-48e8-b47f-c0f3c168b9b1', '63014f13-a64e-4731-8503-cd97f9d1754e',
    '66933787-b937-40ad-86c9-dc456f608034', '80e98946-30ab-43b3-b6e9-1f2f52e1dfa6', '86cf79ca-3e36-4702-aac8-f71a04a56795',
    '8bf3e9af-0c4d-46c0-b732-25b55d5abeea', '8c12b05c-b9b7-4f5b-9b74-c1ced82b7088', 'a8042193-44a9-4322-a221-e1ca8579990d',
    'b29022a2-545d-4e96-951f-865b864c3032', 'b95281a2-2f96-408c-9c19-849b577cd89f', 'eb1f211d-c7c9-4df8-8de6-d59cabd869f5',
    'f201a700-da26-40f9-bd69-0022961ce347', 'fa579433-070c-4433-9fd1-1b2b2cfdd236', 'fba22606-c3a5-42c8-bc18-2f22ff5c1410'])) then
    raise exception 'IQ-00064 post-check: a reconciled step is still done'; end if;
end $$;
