-- CF-247 AER v2 step 0, part 1 (Decision 276, Platform Admin 12 Nov 2026 17:20: "Build the labelled validation set and independent completeness measurement";
-- coverage measure: "a course is covered for an applicant country when security.entry_resolve_v1(course, country) returns minimum_published").
-- Guards: G1 (no job: a view and a read-only function), G2 (the applicant countries are a setting), G3 (no consumer API object), Decision 260, Layer 4 authority
--   unchanged (nothing is admitted, changed or read here).
-- What:
--   1. pipeline.aer_labelled_rows_v1: every AER row a decision has labelled, with its evidence (stored copy, quote, reader, worker): accepted (admitted by a person or
--      by rule D1), left out by Approve except, or rejected; course-page rows active (accepted) or inactive with their reason. The v2 shadow trial (step 1) reads its
--      examples here; no copy is kept, so the set grows with every decision.
--   2. security.aer_resolver_coverage_v1(countries): for each applicant country, the active courses open to international students that have a published minimum under the
--      resolver's rules 1 (course override), 2 (course row) and 4 (provider minimum at the course's level or an equivalent level, entry.level_equivalents), set-based.
--      Rule 3 (band ladder) needs the course's own band and is counted separately; the result is the lower bound of what entry_resolve_v1 returns.
--   3. Setting aer.coverage_countries: the applicant countries the measure reports by default.
-- Live figures at writing (12 Nov 2026 17:30 AEDT): 918 AER decisions (542 by a person, 376 by rule D1); 107 matrix rows rejected, 18 left out by Approve except;
--   course rows 2,850 active, 691 inactive, 2,025 proposed.
-- Baseline measured with this function (dry run, 12 Nov 2026 17:45 AEDT): 35,338 active international courses; 1,072 have a published minimum for at least one
--   applicant country; by country IN 714, SG 677, BD 494, TH 481, US 470, LK 453, CN 451, ID 431, JP 412, KR 412, VN 401, PH 393, MY 369, HK 332, NP 324, BR 177,
--   CO 177, PK 158, KE 53, NG 22. Course-page rows (2,850 active) are almost all domestic or general (none names an applicant country; resolver rule 1 reads only
--   "override" rows), so they do not reach an applicant country today: v2 course reading must record the applicant country or qualification (design §3.3).
--   Labelled set: country tables 975 accepted by a person, 165 by rule D1, 149 accepted before decisions were recorded, 107 rejected, 18 left out; qualification
--   rows 8 accepted, 365 rejected; course pages 2,850 accepted, 691 rejected.
-- Replaces: nothing. Retires: nothing.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.coverage_countries', 'Entry requirements: applicant countries the coverage measure reports',
  'Coverage of academic entry is reported for each of these applicant countries (ISO codes): a course counts for a country when the platform can show a published minimum for it (security.aer_resolver_coverage_v1).',
  'list', '["IN","CN","NP","VN","PH","ID","PK","BD","LK","MY","TH","KR","HK","SG","JP","NG","KE","CO","BR","US"]'::jsonb, null, null, 'countries', 1537, 'Entry requirements',
  'security.aer_resolver_coverage_v1', 'Decision 276 (12 Nov 2026): one coverage definition before v2 is measured against v1')
on conflict (toolset_key, key) do nothing;

create or replace view pipeline.aer_labelled_rows_v1 with (security_invoker = true) as
select 'country_table'::text as source_kind, m.id as row_id, m.provider_id, m.course_id, m.course_label, m.country_code, null::text as qualification_code,
       m.qualification_name, m.level_label, m.min_grade, m.min_value, m.grade_scale, m.benchmark_band, m.quote, m.source_id, m.evidence_id, m.content_hash, m.run_id,
       d.review_item_id, d.action as decision,
       case when d.actor_id = 'c0ffee00-0000-4000-8000-000000000150'::uuid then 'machine' when d.actor_id is not null then 'person' end as decided_by,  -- fixed: the system actor of rule D1 (aer-machine-v1)
       d.created_at as decided_at,
       case when m.status = 'active' then 'accepted'
            when m.status_reason like 'excluded by approve except%' then 'left_out'
            when m.status_reason like 'quarantined (rejected)%' then 'rejected' end as label,
       m.status_reason, m.provenance->>'reader' as reader, m.provenance->>'worker' as worker
  from catalogue.provider_entry_matrix m
  left join pipeline.entry_matrix_runs r on r.id = m.run_id
  left join lateral (select x.* from pipeline.layer4_decisions x where x.review_item_id = r.review_item_id order by x.created_at desc limit 1) d on true
 where m.status = 'active' or m.status_reason like 'excluded by approve except%' or m.status_reason like 'quarantined (rejected)%'
union all
select 'qualification', q.id, q.provider_id, q.course_id, q.course_label, null, q.qualification_code, q.qualification_label, q.level_label, q.min_grade, q.min_value,
       q.grade_scale, null, q.quote, q.source_id, q.evidence_id, q.content_hash, q.run_id, null, null, null, null,
       case when q.status = 'active' then 'accepted' when q.status = 'inactive' then 'rejected' end, q.status_reason, q.provenance->>'reader', q.provenance->>'worker'
  from catalogue.provider_qualification_requirements q where q.status in ('active', 'inactive')
union all
select 'course_page', c.id, co.provider_id, c.course_id, co.canonical_title, k.iso_alpha2, null, c.description, null, c.min_grade, c.min_value, c.grade_scale,
       c.benchmark_band, c.quote, null, c.evidence_id, null, null, null, null, null, c.updated_at,
       case when c.status = 'active' then 'accepted' when c.status = 'inactive' then 'rejected' end, c.status_reason, c.provenance->>'reader', c.provenance->>'worker'
  from catalogue.course_entry_requirements c join catalogue.courses co on co.id = c.course_id left join ref.countries k on k.id = c.country_id
 where c.status in ('active', 'inactive');
comment on view pipeline.aer_labelled_rows_v1 is 'AER v2 step 0 (Decision 276): every AER row a decision has labelled (accepted, left out, rejected) with its evidence; the labelled validation set of the v2 shadow trial';

create or replace function security.aer_resolver_coverage_v1(p_countries text[] default null) returns jsonb
language sql stable security definer set search_path to '' as $f$
  with cc as (select upper(x) cc from unnest(coalesce(p_countries, array(select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.coverage_countries'), '[]'::jsonb))))) x),
  lv as (select l.id, array_remove(array[l.id] || array(select l2.id from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.level_equivalents'), '[]'::jsonb)) p
                                                          join ref.study_levels l2 on l2.short_code = split_part(p, '=', 2) where split_part(p, '=', 1) = l.short_code), null) ids
           from ref.study_levels l),
  c as (select co.id, co.provider_id, lv.ids from catalogue.courses co join lv on lv.id = co.study_level_id
         where co.lifecycle_status = 'active' and co.open_to_international is not false),
  -- rule 4: a provider minimum with a printed minimum and a stated scale, per provider, country and the levels it applies to
  pm as (select m.provider_id, m.country_code, array_agg(distinct x) levels
           from catalogue.provider_entry_matrix m
           cross join lateral unnest(array_remove(array[m.study_level_id], null) || coalesce(security.entry_label_levels_v1(m.level_label), '{}'::uuid[])) x
          where m.status = 'active' and m.course_id is null and m.matrix_kind = 'provider_minimum' and m.min_grade is not null and m.grade_scale is distinct from 'none'
          group by 1, 2),
  -- rule 2: a course row for the country
  cm as (select distinct m.course_id, m.country_code from catalogue.provider_entry_matrix m
          where m.status = 'active' and m.course_id is not null and m.min_grade is not null and m.grade_scale is distinct from 'none'),
  -- rule 1: a course override for international applicants, for this country or every country, with a minimum
  co as (select r.course_id, k.iso_alpha2 country_code from catalogue.course_entry_requirements r left join ref.countries k on k.id = r.country_id
          where r.status = 'active' and r.kind = 'override' and r.audience in ('international', 'all') and (r.min_grade is not null or r.min_entry_score is not null)),
  per as (select cc.cc, count(*) filter (where exists (select 1 from co where co.course_id = c.id and (co.country_code is null or co.country_code = cc.cc))
                                               or exists (select 1 from cm where cm.course_id = c.id and cm.country_code = cc.cc)
                                               or exists (select 1 from pm where pm.provider_id = c.provider_id and pm.country_code = cc.cc and pm.levels && c.ids)) covered
            from cc cross join c group by cc.cc)
  select jsonb_build_object('courses', (select count(*) from c),
           'courses_with_any', (select count(*) from c where exists (select 1 from co where co.course_id = c.id) or exists (select 1 from cm where cm.course_id = c.id)
                                                           or exists (select 1 from pm where pm.provider_id = c.provider_id and pm.levels && c.ids)),
           'providers_with_table', (select count(distinct provider_id) from pm),
           'by_country', (select jsonb_object_agg(per.cc, per.covered order by per.cc) from per),
           'rules', 'course override, course row, provider minimum at the course level or an equivalent; band ladders not counted (lower bound of entry_resolve_v1)')
$f$;
comment on function security.aer_resolver_coverage_v1(text[]) is 'AER coverage (Decision 276): active international courses with a published minimum per applicant country under resolver rules 1, 2 and 4 (lower bound of entry_resolve_v1)';
revoke all on function security.aer_resolver_coverage_v1(text[]) from public, anon;
