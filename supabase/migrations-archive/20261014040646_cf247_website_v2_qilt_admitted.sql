-- CF-247 (14 Oct 2026) Website API v2: QILT provider statistics admitted to the website API.
-- Platform Admin decision (multiple choice, 14 Oct): admit QILT to the API. Provider grain only, never presented as a course
-- fact. The course-grain gate courses/qilt (Zoho, admin) stays blocked. The website gate courses/provider_outcomes is read only
-- by public.website_v2_provider and public.website_v2_course.
--  1. Gate courses/provider_outcomes approved.
--  2. Only QILT surveys are returned under this gate (other outcome surveys, if loaded later, need their own decision).
--  3. Course detail read outcome rows with status active or accepted, but every row is current, so it returned none. Fixed.
--  4. Each row adds study_level_name, survey_name and national_benchmark.
-- md5-checked before. nothing is dropped or deleted.
insert into search.enrichment_gates (projection_code, domain_code, gate_status, approval_ref, approved_at)
select 'courses', 'provider_outcomes', 'approved', 'CF-CHG-20260915-247 Platform Admin 14 Oct 2026 - QILT provider statistics admitted to the website API (provider grain, Wix v2)', now()
where not exists (select 1 from search.enrichment_gates g where g.projection_code = 'courses' and g.domain_code = 'provider_outcomes');

do $d$
declare v text; n text;
begin
  v := pg_get_functiondef('public.website_v2_course(text)'::regprocedure);
  if md5(v) <> '9872c3ef67abdf925657e23a77ddd263' then raise exception 'website_v2_course changed since the check'; end if;
  n := replace(v, $o$where o.status in ('active','accepted') and o.external_study_area_id is null$o$,
                  $o$where o.status in ('current','active','accepted') and o.external_study_area_id is null and left(sv.code, 5) = 'qilt_'$o$);
  n := replace(n, $o$'study_level', o.source_cohort_code,$o$,
                  $o$'study_level', o.source_cohort_code,
                          'study_level_name', case o.source_cohort_code when 'UG' then 'Undergraduate' when 'PGC' then 'Postgraduate coursework' when 'PGR' then 'Postgraduate research' when 'ALL' then 'All students' end,
                          'survey_name', sv.name, 'national_benchmark', o.national_benchmark,$o$);
  if (length(n) - length(v)) < 300 then raise exception 'course anchors not found'; end if;
  execute n;

  v := pg_get_functiondef('public.website_v2_provider(text)'::regprocedure);
  if md5(v) <> '70ccdc9b871611f20983ccb807c600c0' then raise exception 'website_v2_provider changed since the check'; end if;
  n := replace(v, $o$where o.provider_id=v_pid and o.external_study_area_id is null$o$,
                  $o$where o.provider_id=v_pid and o.external_study_area_id is null and o.status in ('current','active','accepted') and left(sv.code, 5) = 'qilt_'$o$);
  n := replace(n, $o$'study_level', o.source_cohort_code,$o$,
                  $o$'study_level', o.source_cohort_code,
                   'study_level_name', case o.source_cohort_code when 'UG' then 'Undergraduate' when 'PGC' then 'Postgraduate coursework' when 'PGR' then 'Postgraduate research' when 'ALL' then 'All students' end,
                   'survey_name', sv.name, 'national_benchmark', o.national_benchmark,$o$);
  if (length(n) - length(v)) < 300 then raise exception 'provider anchors not found'; end if;
  execute n;
end $d$
