-- CF-247 Decision 254 (5 Oct 2026, Platform Admin 16:49).
-- 3. "On Campus (or remote/Online) (location will detail the campus address/details)". Where a course page prints only
--    its locations (QUT "Gardens Point", Auckland "City, University of Auckland Online", Waikato "Hamilton, Tauranga,
--    Online"), delivery comes from the location reading: campus names only = on_campus, online/remote/distance only =
--    online, both = on_campus_and_online. A delivery printed as such still comes first. The location itself is shown in
--    Coverage › Universities.
-- 4. "Entry requirement or other as mentioned per course (like in nursing: uniform, visits, kits)". New pattern field
--    other_requirements (placements, uniforms, kits, checks, visits), shown with the entry requirement for review.
-- Snippet patches are md5-guarded and each is found exactly once. No text value in this file contains a semicolon.

create or replace function security.delivery_mode_from_location(p_text text) returns text
language sql immutable set search_path = '' as $f$
  with a as (select lower(coalesce(p_text, '')) s),
       b as (select s ~ '(\monline\M|\mon-line\M|\mremote\M|\mdistance\M|\mexternal\M|off[ -]campus)' o,
                    regexp_replace(s, '(university of [a-z]+ online|[a-z]+ online|\monline\M|\mon-line\M|\mremote\M|\mdistance\M|\mexternal\M|off[ -]campus|learning|study|and|or|only|campus(es)?|location(s)?|[^a-z])', ' ', 'g') rest from a)
  select case when btrim(p_text) = '' or p_text is null then null
              when o and length(btrim(rest)) >= 3 then 'on_campus_and_online'
              when o then 'online'
              when length(btrim(rest)) >= 3 then 'on_campus'
              else null end
  from b
$f$;
revoke all on function security.delivery_mode_from_location(text) from public, anon, authenticated;

do $p$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_pattern_fields()'::regprocedure) is distinct from 'e750783fcc2febcc96169274ae5b3cc0' then
    raise exception 'uni_adapter_pattern_fields changed, not replacing'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'security.university_course_requirement_v1(uuid)'::regprocedure) is distinct from '624aa06c010bc05aa0aae369ca0e2b06' then
    raise exception 'university_course_requirement_v1 changed, not replacing'; end if;
end $p$;

create or replace function security.uni_adapter_pattern_fields() returns text[]
language sql immutable set search_path = '' as $f$
  select array['intakes', 'fee', 'ielts_overall', 'campus', 'mode', 'duration', 'study_level', 'student_type', 'not_admitting', 'aqf_level', 'location', 'fee_total', 'course_years', 'exit_awards', 'entry_requirement', 'other_requirements']
$f$;

create or replace function security.university_course_requirement_v1(p_course_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('read', pg.candidates->'adapter_extra'->>'entry_requirement',
                            'other', pg.candidates->'adapter_extra'->>'other_requirements',
                            'source', case when coalesce(pg.candidates->'adapter_extra'->>'entry_requirement', pg.candidates->'adapter_extra'->>'other_requirements') is not null then 'adapter' else 'missing' end)
  from (select 1) one left join pipeline.coverage_course_pages pg on pg.course_id = p_course_id
$f$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.adapter_overwrite_v1(integer)'::regprocedure) is distinct from '05bea27129ff05552aac9a7b1f203310' then
    raise exception 'adapter_overwrite_v1 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.adapter_overwrite_v1(integer)'::regprocedure);
  v_pairs := array[
    array[$s$security.delivery_mode_from_text(pg.candidates->'adapter_extra'->>'mode') new_mode,$s$,
          $s$coalesce(security.delivery_mode_from_text(pg.candidates->'adapter_extra'->>'mode'), security.delivery_mode_from_location(coalesce(pg.candidates->'adapter_extra'->>'location', pg.candidates->'adapter_extra'->>'campus'))) new_mode,$s$],
    array[$s$or pg.candidates->'adapter_extra' ? 'mode')$s$,
          $s$or pg.candidates->'adapter_extra' ? 'mode' or pg.candidates->'adapter_extra' ? 'campus' or pg.candidates->'adapter_extra' ? 'location')$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;
