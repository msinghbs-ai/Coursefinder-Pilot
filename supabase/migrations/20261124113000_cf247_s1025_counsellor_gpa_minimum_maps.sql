-- CF-247 s1025 (S1-RM-Design; Platform Admin 24 Nov 2026 07:01 AEDT, REQ-110 follow-up): the s1024 GPA sort and filter took about 21 s live (Counsellor course list,
-- India, 70%, meets-minimum, sort by GPA), because security.course_gpa_min_percent_v1 ran once per matched course (about 44,000 calls). The country's
-- percentage minimums are now read once per call into two small maps (course rows, provider rows; 752 percentage rows in all), and the filter, the sort and
-- the page's gpa_minimums read from them. Same rule as s1024 (course rows first, else provider rows; percentage scale only), so the same courses match.
-- security.admin_course_page_fast_base is changed in place from its md5-checked live definition (s1024); each change must match the expected number of times.
-- Admin read only: G3 75/48 checked before and after. G1: no job. G2: 0 and 100 are the bounds of a percentage.
-- Replaces: the per-course calls of security.course_gpa_min_percent_v1 inside the course list (the function stays: one course's minimum)
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure)) <> '10437508f09e57ccc9f29f048febbbc7' then
    raise exception 'guard: admin_course_page_fast_base is not the s1024 definition this change was written against';
  end if;
end $g$;
create temp table s1025_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1025_cron on commit drop as select count(*) n from cron.job where active;

create or replace function security.gpa_min_maps_v1(p_country text, p_qualification text)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select jsonb_build_object(
    'course', coalesce((select jsonb_object_agg(z.course_id::text, z.v) from (
        select m.course_id, min(m.min_value) v from catalogue.provider_entry_matrix m
         where m.course_id is not null and m.status = 'active' and m.grade_scale = 'percentage' and m.min_value between 0 and 100  -- fixed: a percentage is 0 to 100
           and m.country_code = upper(p_country) and (p_qualification is null or m.qualification_name ilike '%' || p_qualification || '%') group by m.course_id) z), '{}'::jsonb),
    'provider', coalesce((select jsonb_object_agg(z.provider_id::text, z.v) from (
        select m.provider_id, min(m.min_value) v from catalogue.provider_entry_matrix m
         where m.course_id is null and m.status = 'active' and m.grade_scale = 'percentage' and m.min_value between 0 and 100  -- fixed: a percentage is 0 to 100
           and m.country_code = upper(p_country) and (p_qualification is null or m.qualification_name ilike '%' || p_qualification || '%') group by m.provider_id) z), '{}'::jsonb))
$function$;
comment on function security.gpa_min_maps_v1(text, text) is 'CF-247 s1025 (REQ-110): the lowest active percentage-scale entry minimum for one country of education (optionally one qualification), as two maps read once per Counsellor course list call: course id -> minimum (course rows) and provider id -> minimum (provider-level rows).';
revoke all on function security.gpa_min_maps_v1(text, text) from public, anon, authenticated;

create function pg_temp.s1025_rep(d text, o text, n text, k int) returns text language plpgsql as $f$
begin
  if (length(d) - length(replace(d, o, ''))) / length(o) <> k then raise exception 's1025: expected % of "%"', k, left(o, 80); end if;
  return replace(d, o, n);
end $f$;

do $r$
declare d text := pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure);
begin
  d := pg_temp.s1025_rep(d, E'  v_gpa_meets boolean:=coalesce(nullif(p_args->>''gpa_meets'','''')::boolean,false);',
    E'  v_gpa_meets boolean:=coalesce(nullif(p_args->>''gpa_meets'','''')::boolean,false);\n'
    || E'  -- s1025: the country''s percentage minimums, read once per call (course rows, provider rows)\n'
    || E'  v_gpa_maps jsonb:=case when v_gpa_cc is null then null else security.gpa_min_maps_v1(v_gpa_cc,v_gpa_qual) end;', 1);
  d := pg_temp.s1025_rep(d, E'security.course_gpa_min_percent_v1(c.id, c.provider_id, v_gpa_cc, v_gpa_qual)',
    E'coalesce((v_gpa_maps->''course''->>c.id::text)::numeric,(v_gpa_maps->''provider''->>c.provider_id::text)::numeric)', 1);
  d := pg_temp.s1025_rep(d, E'security.course_gpa_min_percent_v1(numbered.id, numbered.provider_id, v_gpa_cc, v_gpa_qual)',
    E'coalesce((v_gpa_maps->''course''->>numbered.id::text)::numeric,(v_gpa_maps->''provider''->>numbered.provider_id::text)::numeric)', 2);
  d := pg_temp.s1025_rep(d, E'security.course_gpa_min_percent_v1(e.id,null,v_gpa_cc,v_gpa_qual)',
    E'coalesce((v_gpa_maps->''course''->>e.id::text)::numeric,(v_gpa_maps->''provider''->>(select c9.provider_id from catalogue.courses c9 where c9.id=e.id)::text)::numeric)', 1);
  d := pg_temp.s1025_rep(d, E'(security.course_gpa_min_percent_v1)', E'(s1025: security.gpa_min_maps_v1, read once per call)', 1);
  execute d;
end $r$;

do $post$
declare v_api jsonb := security.consumer_api_check_v1(); d text := pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure);
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1025_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1025_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if d ~ 'course_gpa_min_percent_v1' or d !~ 'v_gpa_maps' then raise exception 'post-check: the course list still calls the per-course helper'; end if;
  -- the maps give the same minimum as the per-course function for every course that holds one (India)
  if exists (select 1 from catalogue.courses c, lateral (select security.gpa_min_maps_v1('IN', null) m) x
              where c.lifecycle_status = 'active'
                and security.course_gpa_min_percent_v1(c.id, c.provider_id, 'IN', null) is distinct from coalesce((x.m->'course'->>c.id::text)::numeric, (x.m->'provider'->>c.provider_id::text)::numeric)
                and (c.id::text in (select jsonb_object_keys(x.m->'course')) or c.provider_id::text in (select jsonb_object_keys(x.m->'provider')))) then
    raise exception 'post-check: the maps and the per-course minimum disagree';
  end if;
  if has_function_privilege('anon', 'security.gpa_min_maps_v1(text,text)', 'execute') then raise exception 'post-check: anon can call the maps helper'; end if;
end $post$;
