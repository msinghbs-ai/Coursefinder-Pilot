-- CF-247 Decision 254 (5 Oct 2026, night run wave 1). College pages word delivery in ways the delivery wording rule
-- did not know: "Classroom learning", "classroom-based", "delivered in the classroom", "in class", "Onsite study",
-- "on-site" (on campus) and "Study From Home", "from home" (online). These now count. Everything else is unchanged.
-- md5-guarded. No text value in this file contains a semicolon.

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.delivery_mode_from_text(text)'::regprocedure) is distinct from '77aa100f89d2130e4ad4793c2cd48d69' then
    raise exception 'delivery_mode_from_text changed, not replacing'; end if;
end $p$;

create or replace function security.delivery_mode_from_text(p_text text) returns text
language sql immutable set search_path = '' as $f$
  with a0 as (select lower(coalesce(p_text, '')) s),
       a1 as (select regexp_replace(s, '(online\s*-\s*no\M|online[^.]{0,40}only for non-international[^.]{0,120}|not offered online|\(includes blended\)|distance\s*\((?:assessment|recognition) of prior learning[^)]{0,60}\))', ' ', 'g') s from a0),
       a2 as (select regexp_replace(s, '(online with (?:some )?(?:face[ -]to[ -]face|on[ -]?campus|block)|mixed attendance mode|virtual classroom)', ' blended ', 'g') s from a1),
       a3 as (select regexp_replace(regexp_replace(s, '\mon-line\M', 'online', 'g'), '\mexternal\M', ' distance ', 'g') s from a2),
       a4 as (select regexp_replace(regexp_replace(s, '(study(ing)? from home|\mfrom home\M)', ' online ', 'g'), '(\mclassroom\M|\min[ -]class\M|\monsite\M|\mon-site\M)', ' on campus ', 'g') s from a3),
       b as (select regexp_replace(s, 'off[ -]campus', ' distance ', 'g') s from a4),
       c as (select s ~ '(100% online|\monline\M|\mdistance\M)' o, s ~ '(on[ -]?campus|face[ -]to[ -]face|in[ -]person|\mcampus\M)' k, s ~ '(blended|mixed mode|multi[ -]?modal|hybrid)' m from b)
  select case when o and k then 'on_campus_and_online'
              when m then 'blended'
              when o then 'online'
              when k then 'on_campus'
              else null end
  from c
$f$;
