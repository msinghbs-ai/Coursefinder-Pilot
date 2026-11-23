-- CF-247 s1024 (S1-RM-Design; Platform Admin 24 Nov 2026 07:01 AEDT, REQ-110 follow-up, answer "Percentage-only"): an optional GPA sort and "meets minimum"
-- filter on the Counsellor course list (admin_read 'courses_page' -> security.admin_course_page_fast -> security.admin_course_page_fast_base), for
-- S1-API-Frontend-Delivery to expose. Admin read only: no consumer object is touched (G3 75/48 checked before and after).
-- New optional p_args (all absent = the list behaves exactly as before):
--   gpa_country        ISO 3166-1 alpha-2 country of the student's education (turns the feature on)
--   gpa_percent        the student's result as a percentage (0 to 100), or
--   gpa_scale_code + gpa_value  a result on a scale in ref.grade_scale_conversions, converted only when (a) the Platform Admin lists the scale in
--                      lookups.gpa_comparable_scales (empty: CBSE Class X grade points are not compared with course minimums, which are set on
--                      Class XII results) and (b) the value is a published point of that scale (no interpolation)
--   gpa_qualification  optional text narrowing the course minimum to one qualification (matched within qualification_name)
--   gpa_meets          true keeps only courses whose minimum is at or below the student's percentage
--   sort 'gpa'         by the course's minimum percentage for that country (asc or desc; courses with none last)
-- The course minimum is the lowest active percentage-scale minimum (catalogue.provider_entry_matrix, grade_scale 'percentage', 0 to 100) for the
-- country: the course's own rows first, else the provider-level rows. 'gpa', 'points', 'letter' and other scales are never read as a percentage. A course
-- with no percentage minimum is never "meets". The page carries 'gpa' (country, qualification, student_percent, meets_filter, basis) and
-- 'gpa_minimums' (course id -> minimum percentage) for the screen.
-- The two course-list functions are changed in place from their md5-checked live definitions; each insertion must match exactly once.
-- G1: no job. G2: lookups.gpa_comparable_scales is a setting; 0 and 100 are the bounds of a percentage. Manual locks and active cron jobs checked unchanged.
-- Replaces: nothing
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.admin_course_page_fast(jsonb)'::regprocedure)) <> 'cd2d1610e25ca4fca3cefc33f77b4dc3' then
    raise exception 'guard: admin_course_page_fast is not the definition this change was written against';
  end if;
  if md5(pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure)) <> '22eb2f5e78def853193e672808628e69' then
    raise exception 'guard: admin_course_page_fast_base is not the definition this change was written against';
  end if;
end $g$;
create temp table s1024_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1024_cron on commit drop as select count(*) n from cron.job where active;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, unit, sort, reason, section, used_by)
values ('pipeline', 'lookups.gpa_comparable_scales', 'Grade scales compared with course minimums',
  'Scale codes from the grade scale conversions (ref.grade_scale_conversions) whose converted percentage the Counsellor course list may compare with course entry minimums. A scale is listed only when course minimums are set on that same qualification. Empty: a student result is entered as a percentage.',
  'list', '[]'::jsonb, 'scale codes', 1700, 'Platform Admin 24 Nov 2026 07:01 (s1024): CBSE Class X grade points (CBSE_X_GP10) are not compared, because course minimums are set on Class XII results',
  'Lookups', 'security.gpa_student_percent_v1 (Counsellor course list GPA sort and filter)')
on conflict do nothing;

create or replace function security.gpa_student_percent_v1(p_args jsonb)
returns numeric language plpgsql stable security definer set search_path = '' as $function$
declare v_pct numeric; v_code text := nullif(btrim(coalesce(p_args->>'gpa_scale_code', '')), ''); v_val numeric; v_cc text := upper(nullif(btrim(coalesce(p_args->>'gpa_country', '')), ''));
begin
  begin v_pct := nullif(p_args->>'gpa_percent', '')::numeric; v_val := nullif(p_args->>'gpa_value', '')::numeric;
  exception when others then raise exception 'INVALID_INPUT: gpa_percent and gpa_value are numbers' using errcode = '22023'; end;
  if v_pct is not null then
    if v_pct < 0 or v_pct > 100 then raise exception 'INVALID_INPUT: gpa_percent is 0 to 100' using errcode = '22023'; end if;  -- fixed: a percentage is 0 to 100
    return v_pct;
  end if;
  if v_code is null or v_val is null or v_cc is null then return null; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'lookups.gpa_comparable_scales' and s.value ? v_code) then return null; end if;
  return (select min(g.normalized_0_100) from ref.grade_scale_conversions g join ref.countries k on k.id = g.country_id
           where g.is_active and g.scale_code = v_code and k.iso_alpha2 = v_cc and v_val between g.raw_min_value and coalesce(g.raw_max_value, g.raw_min_value));
end $function$;
comment on function security.gpa_student_percent_v1(jsonb) is 'CF-247 s1024 (REQ-110): the student result for the Counsellor course list GPA sort and filter, as a percentage: gpa_percent as given (0 to 100), or gpa_scale_code + gpa_value converted from a published point of a scale listed in lookups.gpa_comparable_scales; otherwise null.';
revoke all on function security.gpa_student_percent_v1(jsonb) from public, anon, authenticated;

create or replace function security.course_gpa_min_percent_v1(p_course uuid, p_provider uuid, p_country text, p_qualification text)
returns numeric language sql stable security definer set search_path = '' as $function$
  select coalesce(
    (select min(m.min_value) from catalogue.provider_entry_matrix m
      where m.course_id = p_course and m.status = 'active' and m.grade_scale = 'percentage' and m.min_value between 0 and 100  -- fixed: a percentage is 0 to 100
        and m.country_code = upper(p_country) and (p_qualification is null or m.qualification_name ilike '%' || p_qualification || '%')),
    (select min(m.min_value) from catalogue.provider_entry_matrix m
      where m.course_id is null and m.provider_id = coalesce(p_provider, (select c.provider_id from catalogue.courses c where c.id = p_course))
        and m.status = 'active' and m.grade_scale = 'percentage' and m.min_value between 0 and 100  -- fixed: a percentage is 0 to 100
        and m.country_code = upper(p_country) and (p_qualification is null or m.qualification_name ilike '%' || p_qualification || '%')))
$function$;
comment on function security.course_gpa_min_percent_v1(uuid, uuid, text, text) is 'CF-247 s1024 (REQ-110): a course''s lowest active percentage-scale entry minimum for one country of education (its own rows first, else the provider-level rows), optionally for one qualification; null when none is held. Other scales are never read as a percentage.';
revoke all on function security.course_gpa_min_percent_v1(uuid, uuid, text, text) from public, anon, authenticated;

create function pg_temp.s1024_rep(d text, o text, n text) returns text language plpgsql as $f$
begin
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 's1024: expected exactly one "%"', left(o, 80); end if;
  return replace(d, o, n);
end $f$;

do $r$
declare d text := pg_get_functiondef('security.admin_course_page_fast(jsonb)'::regprocedure);
begin
  d := pg_temp.s1024_rep(d, E'    and v_sort=''course'' and v_dir=''asc'';',
    E'    and nullif(p_args->>''gpa_country'','''') is null  -- s1024 (REQ-110): the GPA sort and filter take the bounded path\n    and v_sort=''course'' and v_dir=''asc'';');
  execute d;
  d := pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure);
  d := pg_temp.s1024_rep(d, E'  v_test text:=upper(nullif(trim(coalesce(p_args->>''english_test'','''')),''''));',
    E'  v_test text:=upper(nullif(trim(coalesce(p_args->>''english_test'','''')),''''));\n'
    || E'  -- s1024 (REQ-110): GPA sort and filter on percentage-scale minimums only (security.course_gpa_min_percent_v1)\n'
    || E'  v_gpa_cc text:=upper(nullif(trim(coalesce(p_args->>''gpa_country'','''')),''''));\n'
    || E'  v_gpa_qual text:=nullif(trim(coalesce(p_args->>''gpa_qualification'','''')),'''');\n'
    || E'  v_gpa_pct numeric:=security.gpa_student_percent_v1(p_args);\n'
    || E'  v_gpa_meets boolean:=coalesce(nullif(p_args->>''gpa_meets'','''')::boolean,false);');
  d := pg_temp.s1024_rep(d, E'v_intake_year is null and v_test is null then',
    E'v_intake_year is null and v_test is null and v_gpa_cc is null then');
  d := pg_temp.s1024_rep(d, E'      and (nullif(p_args->>''applicant'','''') is null\n',
    E'      -- s1024: a course meets the student''s percentage only when it holds a percentage minimum for that country at or below it\n'
    || E'      and (v_gpa_cc is null or not v_gpa_meets or v_gpa_pct is null or security.course_gpa_min_percent_v1(c.id, c.provider_id, v_gpa_cc, v_gpa_qual) <= v_gpa_pct)\n'
    || E'      and (nullif(p_args->>''applicant'','''') is null\n');
  d := pg_temp.s1024_rep(d, E'      -- 24 Oct 2026 (UI audit Phase 2): the International fee and City columns sort',
    E'      -- s1024: the GPA sort, by the course''s minimum percentage for the student''s country; courses with none last\n'
    || E'      case when v_sort=''gpa'' and v_dir=''asc'' then security.course_gpa_min_percent_v1(numbered.id, numbered.provider_id, v_gpa_cc, v_gpa_qual) end asc nulls last,\n'
    || E'      case when v_sort=''gpa'' and v_dir=''desc'' then security.course_gpa_min_percent_v1(numbered.id, numbered.provider_id, v_gpa_cc, v_gpa_qual) end desc nulls last,\n'
    || E'      -- 24 Oct 2026 (UI audit Phase 2): the International fee and City columns sort');
  d := pg_temp.s1024_rep(d, E'''sort'',v_sort,''direction'',v_dir,',
    E'''sort'',v_sort,''direction'',v_dir,\n'
    || E'    ''gpa'',case when v_gpa_cc is null then null else jsonb_build_object(''country'',v_gpa_cc,''qualification'',v_gpa_qual,''student_percent'',v_gpa_pct,''meets_filter'',v_gpa_meets and v_gpa_pct is not null,''basis'',''percentage minimums only'') end,\n'
    || E'    ''gpa_minimums'',case when v_gpa_cc is null then null else coalesce(jsonb_object_agg(e.id::text,security.course_gpa_min_percent_v1(e.id,null,v_gpa_cc,v_gpa_qual)) filter (where e.id is not null),''{}''::jsonb) end,');
  execute d;
end $r$;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1024_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1024_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure) !~ 'gpa_minimums' or pg_get_functiondef('security.admin_course_page_fast(jsonb)'::regprocedure) !~ 'gpa_country' then
    raise exception 'post-check: the course list was not changed';
  end if;
  if security.gpa_student_percent_v1('{"gpa_percent":"72.5"}') <> 72.5 or security.gpa_student_percent_v1('{"gpa_country":"IN","gpa_scale_code":"CBSE_X_GP10","gpa_value":"9"}') is not null then
    raise exception 'post-check: the student percentage is not read as designed';
  end if;
  if has_function_privilege('anon', 'security.course_gpa_min_percent_v1(uuid,uuid,text,text)', 'execute') then raise exception 'post-check: anon can call the minimum helper'; end if;
end $post$;
