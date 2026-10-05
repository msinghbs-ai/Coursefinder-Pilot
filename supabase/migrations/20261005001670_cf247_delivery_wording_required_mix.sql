-- CF-247 Decision 254 (5 Oct 2026, night run wave 2). A required mix of attendance ("14 hours face-to-face plus 6 hours
-- online", "Face-to-Face 15 hrs / week, Distance 5 hrs / week", "70% face to face, 30% online") is blended study, not a
-- choice of on campus or online. Residential seminars and noho (Māori residential study blocks) are attendance on
-- campus. md5-guarded. No text value in this file contains a semicolon.

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.delivery_mode_from_text(text)'::regprocedure) is distinct from '0a1fa08250dd0e1444b75d35cab7e07a' then
    raise exception 'delivery_mode_from_text changed, not replacing'; end if;
end $p$;

create or replace function security.delivery_mode_from_text(p_text text) returns text
language sql immutable set search_path = '' as $f$
  with a0 as (select lower(coalesce(p_text, '')) s),
       a1 as (select regexp_replace(s, '(online\s*-\s*no\M|online[^.]{0,40}only for non-international[^.]{0,120}|not offered online|\(includes blended\)|distance\s*\((?:assessment|recognition) of prior learning[^)]{0,60}\))', ' ', 'g') s from a0),
       a2 as (select regexp_replace(s, '(online with (?:some )?(?:face[ -]to[ -]face|on[ -]?campus|block)|mixed attendance mode|virtual classroom)', ' blended ', 'g') s from a1),
       a2b as (select regexp_replace(s, '([0-9]+\s*(?:hours?|hrs?|%)[^.]{0,40}(?:face[ -]to[ -]face|classroom|on[ -]?campus|in[ -]person)[^.]{0,80}[0-9]+\s*(?:hours?|hrs?|%)[^.]{0,40}(?:online|distance)|(?:face[ -]to[ -]face|classroom|on[ -]?campus|in[ -]person)[^.]{0,20}[0-9]+\s*(?:hours?|hrs?|%)[^.]{0,80}(?:online|distance)[^.]{0,20}[0-9]+\s*(?:hours?|hrs?|%))', ' blended ', 'g') s from a2),
       a3 as (select regexp_replace(regexp_replace(s, '\mon-line\M', 'online', 'g'), '\mexternal\M', ' distance ', 'g') s from a2b),
       a4 as (select regexp_replace(regexp_replace(s, '(study(ing)? from home|\mfrom home\M)', ' online ', 'g'), '(\mclassroom\M|\min[ -]class\M|\monsite\M|\mon-site\M|residential (?:seminars?|blocks?|study)|\mnoho\M)', ' on campus ', 'g') s from a3),
       b as (select regexp_replace(s, 'off[ -]campus', ' distance ', 'g') s from a4),
       c as (select s ~ '(100% online|\monline\M|\mdistance\M)' o, s ~ '(on[ -]?campus|face[ -]to[ -]face|in[ -]person|\mcampus\M)' k, s ~ '(blended|mixed mode|multi[ -]?modal|hybrid)' m from b)
  select case when o and k then 'on_campus_and_online'
              when m then 'blended'
              when o then 'online'
              when k then 'on_campus'
              else null end
  from c
$f$;
