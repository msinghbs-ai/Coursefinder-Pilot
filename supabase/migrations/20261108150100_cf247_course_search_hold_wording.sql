-- CF-247 AER (lane aer2): the two course page search hold messages say why course search is held when the Firecrawl priority floor is what holds it
-- (Platform Admin priority order 8 Nov 2026; released with 20261108060000 / PR #910).
--
-- Finding (live read 8 Nov 2026 03:25 UTC, project fxcwkweaxjtknorudmwp): security.link_search_block_v1 (shown on a Find course pages task and in the plan
-- step hold) and public.admin_course_search_queue (Adapter builder: why a university's queued searches are not running) say "Today's Firecrawl share for
-- course search is used ... Waits for tomorrow's share" / "... it continues tomorrow" whenever security.fc_budget_left_v1('course_link_search') is under
-- one search (2 credits). Since #910 that is also true while the plan's balance is kept back by firecrawl / priority_floor_course_search, and then it does
-- NOT continue tomorrow: it continues when the balance is back above the floor. Live now: room above the floor 98,711 credits, so today's hold is the daily
-- share and "tomorrow" is right; the wording matters the first time the floor binds.
-- Change: when security.fc_priority_room_v1() is under one search the message names the priority floor and the setting that sets it; otherwise the
--   message is as before. The hold code ('day_budget'), the policy-hold lists that read it, every other branch and the Firecrawl budget functions are unchanged.
-- Checked, no change needed: security.queue_watch_run_v1 says "it carries on when the budget comes back" (true for both). security.course_search_paid_cap_v1 passes
--   security.lane_paid_hold_v1's text (already floor-worded by #910); its resumes_at is still the next UTC day for a floor hold (it feeds the parked work item's
--   next_eligible_at in security.page_find_continuity_v1): that is Firecrawl budget scheduling, owned by the Integration Controller, and is NOT changed here.
-- Consumer API: neither function is in it (not website_v2_*, website_edge_*, zoho_edge_*, api.*, svc_website_settings_v1).
--
-- Live definitions this change edits (read 8 Nov 2026, md5 of pg_get_functiondef), then the md5 after:
--   security.link_search_block_v1(uuid,uuid[])  95e26930e1a9ae9e2e989febf95bfbf7 -> 49d6595413e966e6b6ee758b26950d21
--   public.admin_course_search_queue(uuid)      e970d9a3c2b1d398d0c7387e37b484d9 -> fc9a80fd7e3d7f8534ebac530cba2344
-- Called, not edited: security.fc_priority_room_v1() (live md5 75f30155de83056c896be1637c322d08), security.fc_setting_num_v1(text,numeric).
-- Replaces: the wording of two hold messages in security.link_search_block_v1 and public.admin_course_search_queue (edited in place; same names and signatures)
-- Retires: nothing
-- Nothing is dropped or deleted. No setting, flag, job or Layer 4 item is changed.

do $g$
begin
  if to_regprocedure('security.fc_priority_room_v1()') is null or to_regprocedure('security.fc_setting_num_v1(text,numeric)') is null then
    raise exception 'the Firecrawl priority floor functions (20261108060000) are missing; nothing changed';
  end if;
end $g$;

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

-- 1 the Find course pages task / plan step hold ------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.link_search_block_v1(uuid,uuid[])', '95e26930e1a9ae9e2e989febf95bfbf7', '49d6595413e966e6b6ee758b26950d21',
  array[
    [E'  if v_left < 2 then return jsonb_build_object(''code'', ''day_budget'', ''words'', ''Today''''s Firecrawl share for course search is used'', ''fix'', ''Waits for tomorrow''''s share''); end if;',
     E'  if v_left < 2 then\n    -- 8 Nov 2026 (lane aer2): while the priority floor is what holds it (the plan''s balance is kept for higher-priority work) it does not continue tomorrow\n    if coalesce(security.fc_priority_room_v1(), 2) < 2 then  -- fixed: 2 credits are one search, as this function and the picker count it\n      return jsonb_build_object(''code'', ''day_budget'', ''words'', ''Course page search is paused to keep the Firecrawl balance for higher-priority work (credits kept back: '' || security.fc_setting_num_v1(''priority_floor_course_search'', 0)::bigint || '')'',\n                                ''fix'', ''Starts again by itself when the balance is back above the floor; the floor is set at Models & services › Toolsets & limits › Firecrawl › Credits kept back from course page search'');\n    end if;\n    return jsonb_build_object(''code'', ''day_budget'', ''words'', ''Today''''s Firecrawl share for course search is used'', ''fix'', ''Waits for tomorrow''''s share'');\n  end if;']
  ], array[1]);

-- 2 the Adapter builder queue line ---------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('public.admin_course_search_queue(uuid)', 'e970d9a3c2b1d398d0c7387e37b484d9', 'fc9a80fd7e3d7f8534ebac530cba2344',
  array[
    [E'                when v_left < 2 then ''today''''s Firecrawl share for course search is used up; it continues tomorrow''',
     E'                when v_left < 2 and coalesce(security.fc_priority_room_v1(), 2) < 2 then ''course page search is paused to keep the Firecrawl balance for higher-priority work (priority floor); it starts again by itself when the balance is back above the floor''  -- fixed: 2 credits are one search\n                when v_left < 2 then ''today''''s Firecrawl share for course search is used up; it continues tomorrow''']
  ], array[1]);

do $v$
begin
  if position('fc_priority_room_v1' in pg_get_functiondef('security.link_search_block_v1(uuid,uuid[])'::regprocedure)) = 0
     or position('fc_priority_room_v1' in pg_get_functiondef('public.admin_course_search_queue(uuid)'::regprocedure)) = 0 then
    raise exception 'the hold wording is not in place after this change';
  end if;
end $v$;
