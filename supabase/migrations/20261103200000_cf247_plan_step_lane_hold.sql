-- CF-247 IQ-00064 (P1): an enrichment plan step is never marked done while its lane is idle-paused with its work unprocessed (Agent D,
-- orchestration; Platform Admin direction 3 Nov 2026 09:32, "the platform must enrich data on its own").
-- Why (live, read-only, 3 Nov 2026 12:45-13:10 AEDT):
--   * The five Find course pages steps started by the automatic plans at 11:41 AEDT (admin_jobs kind course_page_find, created 00:45 UTC,
--     providers 00e5f26c, 229dc07d, 87576ec2, e2dd4b2b, ea5a3fa6): ea5a3fa6 searched all 117 courses by 00:54 UTC. The other four searched 62
--     of 173, 28 of 100, 40 of 92 and 40 of 79 by about 00:53 UTC, then nothing moved: from 00:55 UTC every course-page search call answered
--     idle (the picker gives no rows once today's Firecrawl share for course search is spent: fc_budget_left_v1('course_link_search') < 2;
--     the five tasks used 752 credits in 8 minutes). 274 of their courses are still queued in pipeline.course_link_search now.
--   * Cause 1, the idle guard (security.flag_jobs_v1, job flag-recheck): it pauses a coverage-sweep job after flag.empty_calls_to_pause (30)
--     calls in a row with nothing done, whatever the reason the calls found nothing. It paused course-link-search-worker at 01:30 UTC
--     ("its last 30 runs found nothing to do") while four running tasks had 274 courses queued for it, and released it as a trial at 01:40.
--     A budget hold is not "nothing to do".
--   * Cause 2, the task watcher (security.admin_job_watch_v1, called by admin_job_slice_v1 for course_page_find): a task with no new course
--     searched for 45 minutes is finished (returns true) and security.admin_jobs_tick_v1 sets it done, whatever its remaining scope. The note
--     carried the first gate security.link_search_block_v1 found ("The course page search lane is paused by the idle guard until 12:45. It
--     wakes by itself when work waits; nothing to do"), so the four tasks ended done at 01:32-01:38 UTC with 274 courses unsearched; the plan
--     tick (security.enrich_plan_tick_v1) reads a done task as a done step, and the four plans finished done.
--   * Measured (read-only, plan runs of the last 7 days, 12:57 AEDT): 410 Find course pages steps ended done; 4 of them (all 3 Nov, the four
--     above) with courses unsearched, 274 courses, each with the idle guard note. Outside this change, same stall rule: 13 of 953 scholarship
--     scan steps (38 pages) and 1 of 160 provider fill steps ended done with scope left (reported for a follow-up; not edited here).
-- What (all behind setting tasks.lane_hold_on, which ships OFF (0); with it off every edited function behaves exactly as before):
--   1 security.lane_task_waiting_v1(mode) (new, read-only): true while a queued or running task has work queued for the worker lane (today the
--     course page search lane, link_search: a course of a queued or running Find course pages task still queued in course_link_search; plan
--     steps of this kind are such tasks). security.flag_jobs_v1 (md5-guarded edit) does not idle-pause a lane while it is true, and releases a
--     paused lane when it is true (beside security.worker_mode_waiting_v1).
--   2 security.admin_job_watch_v1 (md5-guarded edit): a Find course pages task with courses still to search is never finished by the 45-minute
--     stall rule. Once nothing has moved for tasks.stall_seconds it is held: it stays running, its result carries held {code, reason, since,
--     resumes, ends_at} and the note says why (the gate security.link_search_block_v1 names: the idle guard, the Firecrawl share or month
--     cap, the search switched off ...; or searches waiting their turn) and when it gives up; an event is written when the hold starts. It
--     carries on by itself when the lane has room. Bounded: nothing moved for tasks.lane_hold_max_hours (24) ends it failed, with the reason
--     and the number of courses not searched (the plan's retry, plans.replan_on_retry, can start it again after plans.retry_after_hours
--     unless the reason is one time does not clear, plans.retry_waits_for_change).
--   3 security.admin_jobs_tick_v1 (md5-guarded edit): a finished task whose result says end_state failed is set failed with its note as the
--     error (only the watcher above writes it).
--   4 security.enrich_plan_tick_v1 (md5-guarded edit): a plan step completes only when its task's scope is processed or the task failed or
--     was cancelled with a reason: a Find course pages task that ended done with courses unsearched is read as a failed step; a failed or
--     cancelled task's reason is the step's note; a step is not timed out (plans.step_max_hours) while its Find course pages task is still
--     open (that task is bounded by tasks.lane_hold_max_hours), so no running task is left without its plan.
-- Budgets: a budget hold is a hold, not done. No Firecrawl or AI value is raised; nothing reads a page or calls a model that did not before;
-- the picker, its gates, the day share and the month cap are unchanged. A lane not paused while a task waits keeps calling the worker each
-- minute, which answers held at no cost (lanes.skip_held_paid_calls, v2.15.423, records the hold instead of a call when switched on).
-- md5 (before = live v2.15.423, read 3 Nov 2026 12:49 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/plan-step-lane-hold/run.sh):
--   security.flag_jobs_v1()                     22fa89f4c0c3c238b3d281bd481309b2 -> 668251ec6027c1e9e6dd7d7a9b340bb9
--   security.admin_job_watch_v1(uuid)           ad21305f89ee441bde462cc35e5a8a98 -> 5025e03969c4ac41f06980936aa14741
--   security.admin_jobs_tick_v1(integer)        e760363a6af21d850f7e6e1c86bca0cb -> fc698f9912cffd90a7b8ae32e33dd09e
--   security.enrich_plan_tick_v1(uuid)          613782d4a04d3e6ce123c8837339d5e0 -> bdd7e639295c5c1acb35a7da39273f79
-- Consumer API (G3): untouched.
-- Replaces: the 45-minute stall finish of Find course pages tasks in security.admin_job_watch_v1 and the unconditional idle pause in
--   security.flag_jobs_v1 (same functions, md5-guarded edits, behind tasks.lane_hold_on); security.admin_jobs_tick_v1 and
--   security.enrich_plan_tick_v1 edited in place (md5-guarded)
-- Retires: nothing
-- Nothing is dropped, deleted or switched on.

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
  -- the slice still hands course_page_find to the watcher (security.link_search_block_v1 and security.worker_mode_waiting_v1 are only called,
  -- as the live definitions already call them; their answers are read by shape, not edited)
  for r in select * from (values ('security.admin_job_slice_v1(uuid,integer)', '88f82c974b0ecde708a0550413791d86')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. settings (G2): the switch ships off; the bound is the plan step's own time-out ------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'tasks.lane_hold_on', 'Tasks: hold a task while its lane is held',
  '1: a Find course pages task with courses still to search stays running, held with the reason, while its lane is held (idle guard, Firecrawl share or month cap, searches waiting their turn), and carries on when the lane has room; the idle guard does not pause a lane while a task has work waiting for it; a plan step completes only when its task''s courses are searched or the task failed or was cancelled with a reason. 0: as before (a task with nothing moving for 45 minutes ends done).',
  'number', '0'::jsonb, '0', '1', 'on (1) or off (0)', 783, 'Platform upkeep',
  'security.admin_job_watch_v1, security.flag_jobs_v1, security.enrich_plan_tick_v1', 'CF-247 IQ-00064 (P1), 3 Nov 2026'),
 ('pipeline', 'tasks.lane_hold_max_hours', 'Tasks: a held task gives up after',
  'With tasks.lane_hold_on, a held Find course pages task on which nothing has moved for this many hours ends failed, with the reason and the courses not searched. The plan''s retry (plans.replan_on_retry) can start it again.',
  'number', '24'::jsonb, '1', '168', 'hours', 784, 'Platform upkeep', 'security.admin_job_watch_v1', 'CF-247 IQ-00064 (P1), 3 Nov 2026')
on conflict (toolset_key, key) do nothing;

-- 2. work waiting for a lane from a task (read-only) ---------------------------------------------------------------------------------------
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

-- 3. the idle guard: never pauses a lane a task is waiting for --------------------------------------------------------------------------------
select pg_temp.edit_once('security.flag_jobs_v1()', '22fa89f4c0c3c238b3d281bd481309b2', '668251ec6027c1e9e6dd7d7a9b340bb9', array[
 [$o$      if v_n >= v_need and v_work = 0 then$o$,
  $n$      if v_n >= v_need and v_work = 0
         and not (security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 and security.lane_task_waiting_v1(j.mode)) then  -- CF-247 IQ-00064: a lane a task waits for is held, not idle$n$],
 [$o$(f.next_check_at <= now() or security.worker_mode_waiting_v1(j.mode))$o$,
  $n$(f.next_check_at <= now() or security.worker_mode_waiting_v1(j.mode)
                                                                                or (security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 and security.lane_task_waiting_v1(j.mode)))$n$]
], array[1, 1]);

-- 4. the task watcher: a Find course pages task with courses still to search is held, never done ------------------------------------------------
select pg_temp.edit_once('security.admin_job_watch_v1(uuid)', 'ad21305f89ee441bde462cc35e5a8a98', '5025e03969c4ac41f06980936aa14741', array[
 [$o$        v_pid uuid; v_site text; v_cok boolean; v_c int := 0; v_c2 int := 0;$o$,
  $n$        v_pid uuid; v_site text; v_cok boolean; v_c int := 0; v_c2 int := 0; v_hold_h int; v_why text;$n$],
 [$o$  if not v_fin and v_stall is not null and now() - v_last_at > v_stall then$o$,
  $n$  -- CF-247 IQ-00064 (tasks.lane_hold_on): a Find course pages task with courses still to search is never finished by the stall rule. Once
  -- nothing has moved for tasks.stall_seconds it is held (still running) with the reason and when it gives up, and carries on by itself when
  -- the lane has room; nothing moved for tasks.lane_hold_max_hours ends it failed with the reason.
  if not v_fin and v_j.kind = 'course_page_find' and v_done < v_total and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 then
    v_stall := null;
    v_hold_h := security.pipeline_num_v1('tasks.lane_hold_max_hours', 24)::int;
    v_why := coalesce(v_extra->'blocked'->>'words', (v_total - v_done) || ' search(es) waiting their turn in the course page search lane');
    if now() - v_last_at > make_interval(hours => v_hold_h) then
      v_fin := true;
      v_note := 'Held too long: ' || (v_total - v_done) || ' of ' || v_total || ' course(s) not searched; nothing moved for ' || v_hold_h || ' hour(s) ('
                || v_why || '). The plan''s retry can start it again';
      v_extra := v_extra || jsonb_build_object('end_state', 'failed', 'unprocessed', v_total - v_done);
    elsif now() - v_last_at > make_interval(secs => security.pipeline_num_v1('tasks.stall_seconds', 60)) then
      v_extra := v_extra || jsonb_build_object('unprocessed', v_total - v_done,
                   'held', jsonb_build_object('code', coalesce(v_extra->'blocked'->>'code', 'waiting_turn'), 'reason', v_why, 'since', v_last_at,
                                              'resumes', coalesce(v_extra->'blocked'->>'fix', 'Carries on by itself'),
                                              'ends_at', v_last_at + make_interval(hours => v_hold_h)));
      v_note := 'Held: ' || v_why || '. ' || (v_total - v_done) || ' of ' || v_total || ' course(s) still to search; it carries on by itself when the lane has room (gives up '
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

-- 6. the plan tick: a step completes only when its task's scope is processed, or the task failed or was cancelled with a reason ---------------
select pg_temp.edit_once('security.enrich_plan_tick_v1(uuid)', '613782d4a04d3e6ce123c8837339d5e0', 'bdd7e639295c5c1acb35a7da39273f79', array[
 [$o$(select case when j.state in ('done') then 'done' when j.state in ('failed', 'cancelled') then j.state end$o$,
  $n$(select case when j.state = 'done' and j.kind = 'course_page_find' and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1  -- CF-247 IQ-00064: done with courses unsearched is not done
                                                                   and jsonb_typeof(j.result->'done') = 'number' and jsonb_typeof(j.result->'total') = 'number'
                                                                   and (j.result->>'done')::numeric < (j.result->>'total')::numeric then 'failed'
                                                    when j.state in ('done') then 'done' when j.state in ('failed', 'cancelled') then j.state end$n$],
 [$o$      if v_state is null and (s->>'started_at')::timestamptz < now() - make_interval(hours => v_max) then v_state := 'timed_out'; end if;$o$,
  $n$      if v_state is null and (s->>'started_at')::timestamptz < now() - make_interval(hours => v_max)
         -- CF-247 IQ-00064: not while its Find course pages task is open (that task is bounded by tasks.lane_hold_max_hours)
         and not (s->'ref'->>'kind' = 'job' and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1
                  and exists (select 1 from pipeline.admin_jobs j where j.id = (s->'ref'->>'id')::uuid and j.kind = 'course_page_find' and j.state in ('queued', 'running'))) then
        v_state := 'timed_out'; end if;$n$],
 [$o$when 'timed_out' then 'still running after ' || v_max || ' hours; the task carries on' end))$o$,
  $n$when 'timed_out' then 'still running after ' || v_max || ' hours; the task carries on'
                                              -- CF-247 IQ-00064: a failed or cancelled task's reason is the step's note
                                              when 'failed' then case when s->'ref'->>'kind' = 'job' and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 then
                                                (select left(case when j.state = 'done' then 'the task ended with ' || ((j.result->>'total')::numeric - (j.result->>'done')::numeric) || ' of '
                                                                                             || (j.result->>'total') || ' not processed: ' else '' end
                                                             || coalesce(nullif(j.error, ''), j.result->>'note', 'the task ' || j.state), 300)
                                                   from pipeline.admin_jobs j where j.id = (s->'ref'->>'id')::uuid) end
                                              when 'cancelled' then case when s->'ref'->>'kind' = 'job' and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1 then
                                                (select left(coalesce(nullif(j.error, ''), j.result->>'note', 'the task was cancelled'), 300) from pipeline.admin_jobs j where j.id = (s->'ref'->>'id')::uuid) end end))$n$]
], array[1, 1, 1]);

-- 7. catalogue and component register ------------------------------------------------------------------------------------------------------
update pipeline.automation_catalogue set description = description || ' With tasks.lane_hold_on, it does not pause a lane while a queued or running task has work waiting for it (security.lane_task_waiting_v1).'
 where jobname = 'flag-recheck' and description not like '%lane_task_waiting_v1%';
update pipeline.automation_catalogue set description = description || ' With tasks.lane_hold_on, a Find course pages task with courses still to search is held (still running, with the reason) while its lane is held, never done; nothing moved for tasks.lane_hold_max_hours ends it failed with the reason.'
 where jobname = 'admin-jobs' and description not like '%tasks.lane_hold_on%';
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.lane_task_waiting_v1', 'Platform', 'Platform upkeep', 'A queued or running task has work waiting for a worker lane (idle guard)', 'active', '{}', '20261103200000')
on conflict do nothing;

-- 8. post-check ------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('tasks.lane_hold_on', 'tasks.lane_hold_max_hours')) <> 2 then
    raise exception 'IQ-00064 post-check: a setting is missing'; end if;
  if (select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'tasks.lane_hold_on') <> 0 then
    raise exception 'IQ-00064 post-check: tasks.lane_hold_on must ship off'; end if;
end $$;
