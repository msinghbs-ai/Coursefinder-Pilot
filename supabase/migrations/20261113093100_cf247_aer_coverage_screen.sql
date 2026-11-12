-- CF-247 AER v2 step 0 (Decision 276; design v0.3 §3.8 "Fix the gap view: Coverage & completeness must compute academic_entry from admitted records").
-- Guards: G1 (no job), G2 (no new value), G3 (no consumer API object: security.course_coverage_build_v1 writes pipeline.course_coverage_daily,
--   course_attribute_coverage and course_coverage_daily_by_country, which no website_, zoho_, svc_website or api function reads; checked on live 12 Nov 2026),
--   Decision 260, Layer 4 authority unchanged.
-- Evidence: academic_entry on Coverage & completeness counted only catalogue.course_academic_options, so an admitted entry requirement never showed (every course
--   "no_reader"). security.aer_resolver_coverage_v1 (#1066) measured 1,072 courses with a published minimum for at least one applicant country.
-- What:
--   1. security.aer_covered_courses_v1(): the courses with a published minimum for any applicant country under the resolver's rules 1 (course override), 2 (course
--      row) and 4 (provider minimum at the course's level or an equivalent level), set-based; the same rules as security.aer_resolver_coverage_v1.
--   2. security.course_coverage_build_v1 (md5-guarded): academic_entry is held when the course has academic options or is covered by (1).
-- Live definition this change edits (md5 of pg_get_functiondef, read 12 Nov 2026 19:55 AEDT): security.course_coverage_build_v1 2f6a9a8314281004d9fa4253527a5488
-- Replaces: security.course_coverage_build_v1 (same name; md5-guarded text edit). Retires: nothing.

create or replace function security.aer_covered_courses_v1() returns table(course_id uuid)
language sql stable security definer set search_path to '' as $f$
  with lv as (select l.id, array_remove(array[l.id] || array(select l2.id from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.level_equivalents'), '[]'::jsonb)) p
                                                          join ref.study_levels l2 on l2.short_code = split_part(p, '=', 2) where split_part(p, '=', 1) = l.short_code), null) ids
              from ref.study_levels l),
  pm as (select m.provider_id, array_agg(distinct x) levels
           from catalogue.provider_entry_matrix m
           cross join lateral unnest(array_remove(array[m.study_level_id], null) || coalesce(security.entry_label_levels_v1(m.level_label), '{}'::uuid[])) x
          where m.status = 'active' and m.course_id is null and m.matrix_kind = 'provider_minimum' and m.min_grade is not null and m.grade_scale is distinct from 'none'
          group by 1)
  select co.id from catalogue.courses co join lv on lv.id = co.study_level_id join pm on pm.provider_id = co.provider_id and pm.levels && lv.ids
   where co.lifecycle_status = 'active'
  union
  select m.course_id from catalogue.provider_entry_matrix m
   where m.status = 'active' and m.course_id is not null and m.min_grade is not null and m.grade_scale is distinct from 'none'
  union
  select r.course_id from catalogue.course_entry_requirements r
   where r.status = 'active' and r.kind = 'override' and r.audience in ('international', 'all') and (r.min_grade is not null or r.min_entry_score is not null)
$f$;
comment on function security.aer_covered_courses_v1() is 'AER coverage (Decision 276): courses with a published minimum for any applicant country under resolver rules 1, 2 and 4 (as security.aer_resolver_coverage_v1)';
revoke all on function security.aer_covered_courses_v1() from public, anon;

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

select pg_temp.edit_n('security.course_coverage_build_v1()', '2f6a9a8314281004d9fa4253527a5488', array[
  array[$o$create temp table _val on commit drop as$o$,
        $n$-- AER v2 step 0 (Decision 276): admitted entry requirements count for academic_entry (resolver rules 1, 2 and 4)
  create temp table _aer_cov on commit drop as select x.course_id from security.aer_covered_courses_v1() x;
  create temp table _val on commit drop as$n$],
  array[$o$exists(select 1 from catalogue.course_academic_options a where a.course_id=c.course_id) academic$o$,
        $n$(exists(select 1 from catalogue.course_academic_options a where a.course_id=c.course_id) or exists(select 1 from _aer_cov x where x.course_id=c.course_id)) academic$n$]
], array[1, 1]);
