-- CF-247 HOTFIX 3 (24 Oct 2026, v2.15.347). Platform Admin 15:51 (screenshot): Scheduled jobs › Task manager "could not be read: the
-- database took too long" (ref 9F5R4H), right after the re-open paste file started 22 Find course pages tasks. Record: admin repo
-- docs/platform/ui-audit/2026-10-24-hotfix-manual-task-and-layer4-entry.md section 13.
-- Cause (measured live): the stall cause added in v2.15.342 (security.link_search_block_v1) worked out the search stop for EVERY university
-- (security.fc_search_stopped_v1(), 1.7 s) once per stalled task, plus the month and day credit totals (0.3 s) again per task. The Task
-- manager read gives each running task its status, so with 10 tasks stalled it took 8 s and hit the signed-in 8-second limit; the task
-- runner's watcher asks the same question every minute, so admin-jobs ticks took 16-41 s instead of about 1 s.
-- Fix: the stop for the one university (security.fc_search_stopped_for_v1, 0.09 s); the month and day totals worked out once per request
-- and reused for every task in it (kept for the statement only); "is it a person's task" in one query instead of one per course.
-- The gates, their order and their words are unchanged (the stop's words lose the stop date, which only the slow list held).
-- Replaces: nothing (security.link_search_block_v1 edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.link_search_block_v1(uuid,uuid[])', 'b044c1cf93f3ed66789856d3111031a1', array[
  array[$o$v_stop record; v_rc record; v_person boolean;$o$, $n$v_rc record; v_person boolean; v_memo text := current_setting('cf.link_search_block_totals', true);$n$],
  array[$o$  v_person := p_course_ids is not null and exists (select 1 from unnest(p_course_ids) c where security.link_search_person_task_v1(p_provider, c));$o$,
        $n$  -- hotfix 3: one query, not one per course
  v_person := p_course_ids is not null and exists (select 1 from pipeline.admin_jobs j where j.kind = 'course_page_find' and j.state in ('queued', 'running')
                                                     and j.args->>'provider_id' = p_provider::text and j.args->'course_ids' ?| p_course_ids::text[]);$n$],
  array[$o$  select coalesce(sum(u.units), 0) into v_used from pipeline.coverage_vendor_usage u where u.purpose = 'course_link_search' and u.at >= date_trunc('month', now());
  if v_used + 2 > v_cap$o$,
        $n$  -- hotfix 3: the month and day totals are the same for every task in one request; worked out once per statement and reused
  if v_memo is not null and split_part(v_memo, '|', 1) = statement_timestamp()::text then
    v_used := split_part(v_memo, '|', 2)::numeric; v_left := split_part(v_memo, '|', 3)::numeric;
  else
    select coalesce(sum(u.units), 0) into v_used from pipeline.coverage_vendor_usage u where u.purpose = 'course_link_search' and u.at >= date_trunc('month', now());
    v_left := security.fc_budget_left_v1('course_link_search');
    perform set_config('cf.link_search_block_totals', statement_timestamp()::text || '|' || v_used || '|' || v_left, true);
  end if;
  if v_used + 2 > v_cap$n$],
  array[$o$  v_left := security.fc_budget_left_v1('course_link_search');
  if v_left < 2$o$, $n$  if v_left < 2$n$],
  array[$o$  select x.searches, x.since into v_stop from security.fc_search_stopped_v1() x where x.provider_id = p_provider;
  if v_stop.since is not null and not (v_bypass and v_person) then
    return jsonb_build_object('code', 'search_stopped', 'words', 'The automatic search stopped for this university on ' || to_char(v_stop.since at time zone 'Australia/Melbourne', 'DD Mon') || ' (wrong pages in a row, or too many searches with no page)'$o$,
        $n$  -- hotfix 3: the stop for this one university (fc_search_stopped_v1 works it out for every university)
  if security.fc_search_stopped_for_v1(p_provider) and not (v_bypass and v_person) then
    return jsonb_build_object('code', 'search_stopped', 'words', 'The automatic search stopped for this university (wrong pages in a row, or too many searches with no page)'$n$]],
  array[1, 1, 1, 1, 1]);

select 'hotfix 3: task status stall cause in well under a second per task' ok;
