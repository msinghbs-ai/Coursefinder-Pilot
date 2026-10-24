-- CF-247 R2 (24 Oct 2026, v2.15.350). Throughput record section 3.3 (C-Q1), standing order audit → O10 → R2; Platform Admin O10 decision
-- 24 Oct 19:12 and approval 23:07 ("apply tranche 1 as part of the R2 release"). Record: admin repo
-- docs/platform/nz-enrichment-brief/2026-10-24-target-only-audit.md and 2026-10-23-platform-throughput-gap-schema.md section 3.3.
-- 1. search.daily_picked_cap (100, 10–2,000 courses a UTC day): the course search picker takes no more than this many courses a UTC day
--    (counted from the picker's own "sent" mark, the same count the per-mode ledger records as items). A person's running Find course
--    pages task is counted but not held by it (same on-demand rule as the search stop, setting search.person_task_bypass).
-- 2. search.stop_per_course_after (6, 3–20 distinct wrong pages): a course with that many distinct rejected pages (pipeline.page_rejections,
--    S1 negative evidence) is not searched again. The university-wide stop (search_stop_after) stays as the ceiling behind it.
-- 3. The stall cause names the cap (Task manager, watcher, gap causes read security.link_search_block_v1).
-- Ramp: 100 for the first ledger week; the Platform Admin raises it on the ledger's correct-page rate. Tranche 1 (25 named overrides,
-- PASTE-20261024-target-tranche-1-overrides.sql) is applied after this lands; its guard requires search.daily_picked_cap.
-- Replaces: nothing (public.svc_course_link_search_next and security.link_search_block_v1 edited in place, md5-guarded)
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

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'search.daily_picked_cap', 'Course search: courses a day', 'The course page search takes no more than this many courses a UTC day (11:00 Melbourne in summer). A person''s running Find course pages task is counted but not held. 100 for the first ledger week; raise it on the ledger''s correct-page rate.', 'number', '100'::jsonb, '10', '2000', 'courses a day', 779, 'Course page search', 'public.svc_course_link_search_next, security.link_search_block_v1', 'R2 (C-Q1), O10 approved 24 Oct 2026'),
 ('pipeline', 'search.stop_per_course_after', 'Course search: stop a course after', 'A course with this many different pages rejected as wrong (negative evidence) is not searched again; the university-wide stop stays behind it.', 'number', '6'::jsonb, '3', '20', 'wrong pages', 780, 'Course page search', 'public.svc_course_link_search_next', 'R2 (C-Q1), O10 approved 24 Oct 2026')
on conflict (toolset_key, key) do nothing;

create index if not exists course_link_search_sent_at_idx on pipeline.course_link_search (sent_at);

select pg_temp.edit_n('public.svc_course_link_search_next(integer)', '1e80c0641e6d73a2b7f756c45a7a9c5e', array[
  array[$o$declare v_person boolean := security.pipeline_num_v1('search.person_task_bypass', 1) >= 1;$o$,
        $n$declare v_person boolean := security.pipeline_num_v1('search.person_task_bypass', 1) >= 1;
        v_daycap int := security.pipeline_num_v1('search.daily_picked_cap', 100)::int; v_room int;
        v_course_stop int := security.pipeline_num_v1('search.stop_per_course_after', 6)::int;$n$],
  array[$o$  v_stopped := array(select x.provider_id from security.fc_search_stopped_v1() x);$o$,
        $n$  -- R2 (C-Q1): the day's picked-courses cap (UTC day); a person's running Find course pages task is counted but not held
  select v_daycap - count(*) into v_room from pipeline.course_link_search where sent_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC');
  if v_room > 0 then v_lim := least(v_lim, v_room); end if;
  v_stopped := array(select x.provider_id from security.fc_search_stopped_v1() x);$n$],
  array[$o$       and (pv.focus or s.requested_at is not null)$o$,
        $n$       and (v_room > 0 or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id)))  -- R2: the daily cap
       and (select count(distinct r.url) from pipeline.page_rejections r where r.course_id = s.course_id) < v_course_stop  -- R2: per-course stop
       and (pv.focus or s.requested_at is not null)$n$]],
  array[1, 1, 1]);

select pg_temp.edit_n('security.link_search_block_v1(uuid,uuid[])', '8b891f7366267c1f3b4729bfa8f3cb5a', array[
  array[$o$  if v_left < 2 then return jsonb_build_object('code', 'day_budget', 'words', 'Today''s Firecrawl share for course search is used', 'fix', 'Waits for tomorrow''s share'); end if;$o$,
        $n$  if v_left < 2 then return jsonb_build_object('code', 'day_budget', 'words', 'Today''s Firecrawl share for course search is used', 'fix', 'Waits for tomorrow''s share'); end if;
  -- R2: the day's picked-courses cap (a person's running task is not held by it)
  if not (v_bypass and v_person) and (select count(*) from pipeline.course_link_search s where s.sent_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'))
       >= security.pipeline_num_v1('search.daily_picked_cap', 100) then
    return jsonb_build_object('code', 'daily_cap', 'words', 'Today''s course search cap (' || security.pipeline_num_v1('search.daily_picked_cap', 100)::int || ' courses) is reached; searching resumes at 00:00 UTC', 'fix', 'Settings › Pipeline settings › Course search: courses a day');
  end if;$n$]],
  array[1]);

select 'R2: daily picked-courses cap and per-course stop' ok;
