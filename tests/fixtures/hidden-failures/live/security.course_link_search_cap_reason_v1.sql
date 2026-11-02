CREATE OR REPLACE FUNCTION security.course_link_search_cap_reason_v1()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cap int := security.pipeline_num_v1('search.daily_picked_cap', 100)::int; v_n int;
        v_day timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';  -- fixed: the UTC day the picker counts
begin
  -- SS-014 P2 (2 Nov 2026): the picker's own day count; null while there is room
  select count(*) into v_n from pipeline.course_link_search where sent_at >= v_day;
  if v_cap - v_n > 0 then return null; end if;
  -- over the cap the picker still takes a person's running Find course pages task: that is not a pause
  if security.pipeline_num_v1('search.person_task_bypass', 1) >= 1
     and exists (select 1 from security.course_link_search_eligible_v1() e where security.link_search_person_task_v1(e.provider_id, e.course_id)) then return null; end if;
  return format('Paused: daily cap. %s of %s courses picked today (setting search.daily_picked_cap, counted per UTC day); picking resumes at %s', v_n, v_cap,
                to_char((v_day + interval '1 day') at time zone 'Australia/Melbourne', 'DD Mon HH24:MI'));  -- fixed: the next UTC day
end $function$
