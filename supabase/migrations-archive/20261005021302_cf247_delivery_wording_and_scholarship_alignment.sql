-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 11:48: delivery is an attribute, scholarships stay aligned as data is admitted).
-- 1. Delivery wording found by the cross-check of all 75 adapters (12:00 to 13:00):
--    "Face-to-face (includes blended)" (UNSW) is attendance in person            -> on_campus
--    "Distance (online with some face-to-face)", "Online with block course(s)"    -> blended
--    "Mixed Attendance Mode" (Melbourne), "Virtual classroom" (Melbourne Polytechnic) -> blended
--    "on-line" (Massey) is online, "External" (UQ) is distance study              -> online
--    "Distance (Assessment of Prior Learning only)" (Otago Polytechnic) is not a study option and is ignored.
--    Whole replacement of security.delivery_mode_from_text, md5-guarded. Values already admitted change on the next
--    adapter overwrite only where the new reading differs, and never where a value was entered by hand.
-- 2. Scholarship savings follow admitted fees. Each hour, scholarship.refresh_course_financial_calculations runs for every
--    course whose international tuition changed in the last 70 minutes (the daily full refresh stays as it is).
-- No text value in this file contains a semicolon.

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.delivery_mode_from_text(text)'::regprocedure) is distinct from 'e33a70da498a4c6d211296e61c3a4662' then
    raise exception 'delivery_mode_from_text changed, not replacing'; end if;
end $p$;

create or replace function security.delivery_mode_from_text(p_text text) returns text
language sql immutable set search_path = '' as $f$
  with a0 as (select lower(coalesce(p_text, '')) s),
       a1 as (select regexp_replace(s, '(online\s*-\s*no\M|online[^.]{0,40}only for non-international[^.]{0,120}|not offered online|\(includes blended\)|distance\s*\((?:assessment|recognition) of prior learning[^)]{0,60}\))', ' ', 'g') s from a0),
       a2 as (select regexp_replace(s, '(online with (?:some )?(?:face[ -]to[ -]face|on[ -]?campus|block)|mixed attendance mode|virtual classroom)', ' blended ', 'g') s from a1),
       a3 as (select regexp_replace(regexp_replace(s, '\mon-line\M', 'online', 'g'), '\mexternal\M', ' distance ', 'g') s from a2),
       b as (select regexp_replace(s, 'off[ -]campus', ' distance ', 'g') s from a3),
       c as (select s ~ '(100% online|\monline\M|\mdistance\M)' o, s ~ '(on[ -]?campus|face[ -]to[ -]face|in[ -]person|\mcampus\M)' k, s ~ '(blended|mixed mode|multi[ -]?modal|hybrid)' m from b)
  select case when o and k then 'on_campus_and_online'
              when m then 'blended'
              when o then 'online'
              when k then 'on_campus'
              else null end
  from c
$f$;
revoke all on function security.delivery_mode_from_text(text) from public, anon, authenticated;

create or replace function security.scholarship_fee_alignment_v1() returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare r record; v_courses int := 0; v_refreshed int := 0;
begin
  for r in
    select distinct x.course_id from (
      select f.course_id from catalogue.course_fees f
       where f.audience = 'international' and f.fee_type = 'provider_current_tuition' and f.updated_at > now() - interval '70 minutes'
      union
      select c.course_id from pipeline.adapter_overwrite_changes c where c.field = 'fee' and c.at > now() - interval '70 minutes') x
    where exists (select 1 from scholarship.course_mappings m where m.course_id = x.course_id and m.mapping_state = 'mapped')
  loop
    v_courses := v_courses + 1;
    v_refreshed := v_refreshed + coalesce((scholarship.refresh_course_financial_calculations(r.course_id, null)->>'refreshed')::int, 0);
  end loop;
  return jsonb_build_object('courses', v_courses, 'refreshed', v_refreshed);
end $f$;
revoke all on function security.scholarship_fee_alignment_v1() from public, anon, authenticated;

select cron.schedule('scholarship-fee-alignment', '47 * * * *', 'select security.scholarship_fee_alignment_v1()');
