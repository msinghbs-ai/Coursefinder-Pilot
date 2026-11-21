-- CF-247 s770: per-course field readiness (Platform Admin 19 Nov 2026 11:41). Read only. One row per active course for one part of the courses
-- (__PART__ of __PARTS__, by a hash of the course id, so each Management API answer stays small). Each of the 14 canonical API v3 fields is one
-- cell: the admitted value (at most 80 characters), or one of TRYING, POSSIBLE_NEEDS_SOURCE, NOT_POSSIBLE, EMPTY_NOT_STARTED.
-- scripts/telemetry/course-field-readiness.mjs turns the rows into Course_Field_Readiness_Matrix_YYYY-MM-DD.csv and the summary tabs;
-- workflow course-field-readiness.yml runs it daily at 07:30 AEDT. Nothing here writes. The column raw (s927) feeds
-- scripts/telemetry/data-gap-register.mjs (the daily data gap register).
--
-- States (docs: Dev_Display_Rules tab):
--   TRYING                 a page is found and a read, re-read, Layer 3 or Layer 4 step is queued or running
--                          (coverage in_queue, in_review, awaiting_l3, candidate, page_found; absence evidence_pending; study load pending_extraction)
--   POSSIBLE_NEEDS_SOURCE  no course or provider page found yet, the site only, a blocked site or no reader
--                          (coverage site_known, no_website, blocked, no_reader, missing_l1; absence needs_source_discovery)
--   NOT_POSSIBLE           read against the official source and not published there
--                          (coverage not_on_page; absence explicitly_not_stated, not_applicable, not_on_this_page; month-only intakes;
--                           study load not_published_by_provider; online-only course for campus fields)
--   EMPTY_NOT_STARTED      the country's scope is not switched on yet (Canada entry requirements; destination data where the country has
--                          no approved edition yet)
begin transaction read only;
set local statement_timeout = '110s';
with c as (
  select co.id course_id, co.provider_id, coalesce(pr.display_name, pr.canonical_name) provider_name, k.iso_alpha2::text cc,
         coalesce(co.display_title, co.canonical_title) title, co.description, co.duration_value, co.duration_unit, co.study_load, co.empty_reason_code
    from catalogue.courses co join catalogue.providers pr on pr.id = co.provider_id join ref.countries k on k.id = pr.country_id
   where co.lifecycle_status = 'active' and mod(abs(hashtext(co.id::text)), __PARTS__) = __PART__),
cov as (
  select x.course_id, jsonb_object_agg(x.attribute, jsonb_build_object('s', x.state, 'a', x.absence_class)) m
    from pipeline.course_attribute_coverage x join c using (course_id) group by x.course_id),
lnk as (
  select distinct on (l.course_id) l.course_id, l.url
    from catalogue.course_links l join c using (course_id)
   where l.status = 'active' and l.link_type = 'official_course' order by l.course_id, l.is_primary desc nulls last, l.updated_at desc nulls last),
fee as (
  select distinct on (f.course_id) f.course_id, f.amount, f.currency_code, f.fee_year, coalesce(f.basis, f.load_basis) basis
    from catalogue.course_fees f join c using (course_id)
   where f.status = 'active' and f.fee_type in ('provider_current_tuition', 'tuition') and f.amount is not null
   order by f.course_id, (f.fee_type = 'provider_current_tuition') desc, f.fee_year desc nulls last),
itk as (
  select i.course_id,
         string_agg(distinct to_char(i.start_date, 'YYYY-MM-DD'), ' ') filter (where i.start_date is not null) dates,
         count(*) filter (where i.start_date is null and nullif(btrim(coalesce(i.intake_label, '')), '') is not null) label_only,
         string_agg(distinct to_char(i.application_deadline, 'YYYY-MM-DD'), ' ') filter (where i.application_deadline is not null) deadlines
    from catalogue.course_intakes i join c using (course_id) where coalesce(i.status, 'active') = 'active' group by i.course_id),
eng as (
  select e.course_id, string_agg(distinct coalesce(t.code, t.name) || ' ' || e.overall_score::text, ', ') v
    from catalogue.course_english_requirements e join c using (course_id) left join ref.english_tests t on t.id = e.english_test_id
   where e.status = 'active' and e.overall_score is not null group by e.course_id),
aca as (select distinct a.course_id from catalogue.course_academic_options a join c using (course_id)),
cmp as (
  select distinct on (x.course_id) x.course_id, k.postcode, k.city
    from catalogue.course_campuses x join c using (course_id) join catalogue.campuses k on k.id = x.campus_id
   order by x.course_id, x.is_primary desc nulls last, k.is_primary desc nulls last),
loc as (
  select m.course_id, l.id locality_id, l.name,
         exists (select 1 from destination.locality_postcodes q where q.country_code = c.cc and q.postcode = m.postcode and q.needs_layer4_review) pending
    from cmp m join c using (course_id)
    left join lateral (select l2.id, l2.name from destination.locality_postcodes p join destination.localities l2 on l2.id = p.locality_id
                        where p.country_code = c.cc and p.postcode = nullif(btrim(m.postcode), '') and p.is_primary_match and l2.status in ('approved', 'published')
                        order by p.boundary_vintage desc limit 1) l on true),
lm as (select locality_id, count(*) n from destination.locality_metrics where status = 'approved' group by locality_id),
loc_on as (select distinct country_code from destination.localities where status in ('approved', 'published')),
lm_on as (select distinct l.country_code from destination.locality_metrics m join destination.localities l on l.id = m.locality_id where m.status = 'approved'),
car as (select k.iso_alpha2::text cc, count(*) n from destination.career_outcomes o join ref.countries k on k.id = o.country_id where o.status = 'approved' group by 1),
sch as (
  select m.course_id, count(distinct m.scholarship_id) n
    from scholarship.course_mappings m join c using (course_id) join scholarship.scholarships s on s.id = m.scholarship_id
   where m.mapping_state = 'mapped' and s.lifecycle_status = 'active' and s.publication_status = 'published' group by m.course_id),
psch as (
  select s.provider_id, count(*) filter (where s.publication_status = 'published') published, count(*) filter (where s.publication_status = 'unpublished') pending
    from scholarship.scholarships s where s.lifecycle_status = 'active' and s.provider_id in (select provider_id from c) group by s.provider_id),
cell as (
  select c.*, cov.m, lnk.url, fee.amount, fee.currency_code, fee.fee_year, fee.basis, itk.dates, itk.label_only, itk.deadlines, eng.v eng_v,
         (aca.course_id is not null or cov.m->'academic_entry'->>'s' = 'admitted') aca_ok, cmp.course_id is not null has_campus, cmp.postcode,
         loc.name loc_name, loc.locality_id, coalesce(loc.pending, false) loc_pending, lm.n lm_n, car.n car_n, sch.n sch_n,
         psch.published p_sch_pub, psch.pending p_sch_pending,
         c.cc in (select country_code from loc_on) loc_country_on, c.cc in (select country_code from lm_on) lm_country_on
    from c left join cov using (course_id) left join lnk using (course_id) left join fee using (course_id) left join itk using (course_id)
    left join eng using (course_id) left join aca using (course_id) left join cmp using (course_id) left join loc using (course_id)
    left join lm on lm.locality_id = loc.locality_id left join car on car.cc = c.cc left join sch using (course_id) left join psch on psch.provider_id = c.provider_id),
st as (  -- the coverage state of each attribute as a readiness state
  select x.course_id, k.attr,
         case when x.m->k.attr->>'s' in ('in_queue', 'in_review', 'awaiting_l3', 'candidate', 'page_found') then 'TRYING'
              when x.m->k.attr->>'a' = 'evidence_pending' then 'TRYING'
              when x.m->k.attr->>'s' = 'not_on_page' or x.m->k.attr->>'a' in ('explicitly_not_stated', 'not_applicable', 'not_on_this_page') then 'NOT_POSSIBLE'
              else 'POSSIBLE_NEEDS_SOURCE' end s
    from cell x cross join unnest(array['official_url', 'description', 'provider_tuition', 'intakes', 'deadline', 'duration', 'campus', 'academic_entry', 'english']) k(attr)),
sx as (select course_id, jsonb_object_agg(attr, s) s from st group by course_id)
select x.course_id, x.cc country_code, x.provider_id, left(x.provider_name, 120) provider_name, left(x.title, 160) course_title,
  jsonb_build_object(
    'official_url', coalesce(left(x.url, 80), sx.s->>'official_url'),
    'description', case when nullif(btrim(coalesce(x.description, '')), '') is not null then left(regexp_replace(btrim(x.description), '\s+', ' ', 'g'), 80) else sx.s->>'description' end,
    'study_load', case when x.study_load is not null then left(x.study_load::text, 80)
                       when x.empty_reason_code = 'pending_extraction' then 'TRYING'
                       when x.empty_reason_code in ('not_published_by_provider', 'online_only_no_campus') then 'NOT_POSSIBLE'
                       when x.empty_reason_code in ('source_unavailable', 'not_listed_on_register') then 'POSSIBLE_NEEDS_SOURCE'
                       when x.url is not null then 'TRYING' else 'POSSIBLE_NEEDS_SOURCE' end,
    'tuition_fee', case when x.amount is not null then left(coalesce(x.currency_code, '') || ' ' || trim(to_char(x.amount, 'FM999,999,990.00')) || coalesce(' (' || x.fee_year || ')', ''), 80)
                        else sx.s->>'provider_tuition' end,
    'fee_basis', case when x.amount is not null and x.basis is not null then left(x.basis, 80) when x.amount is not null then 'NOT_POSSIBLE' else sx.s->>'provider_tuition' end,
    'intake_dates', case when x.dates is not null then left(x.dates, 80) when x.label_only > 0 then 'NOT_POSSIBLE' else sx.s->>'intakes' end,
    'application_deadlines', coalesce(left(x.deadlines, 80), sx.s->>'deadline'),
    'duration', case when x.duration_value is not null then left(x.duration_value::text || coalesce(' ' || x.duration_unit, ''), 80) else sx.s->>'duration' end,
    'campus_locality', case when x.loc_name is not null then left(x.loc_name, 80) when not x.loc_country_on then 'EMPTY_NOT_STARTED'
                            when not x.has_campus then case when x.empty_reason_code = 'online_only_no_campus' then 'NOT_POSSIBLE' else sx.s->>'campus' end
                            when x.loc_pending then 'TRYING' else 'POSSIBLE_NEEDS_SOURCE' end,
    'aer_academic', case when x.aca_ok then 'Admitted' when x.cc = 'CA' then 'EMPTY_NOT_STARTED' else sx.s->>'academic_entry' end,
    'english_requirements', coalesce(left(x.eng_v, 80), sx.s->>'english'),
    'scholarships', case when x.sch_n > 0 then x.sch_n || ' scholarship' || case when x.sch_n > 1 then 's' else '' end
                         when coalesce(x.p_sch_pub, 0) > 0 then 'NOT_POSSIBLE' when coalesce(x.p_sch_pending, 0) > 0 then 'TRYING' else 'POSSIBLE_NEEDS_SOURCE' end,
    'destination_city_stats', case when not x.lm_country_on then 'EMPTY_NOT_STARTED' when x.lm_n > 0 then left(x.lm_n || ' figures, ' || x.loc_name, 80)
                                   when not x.has_campus and x.empty_reason_code = 'online_only_no_campus' then 'NOT_POSSIBLE'
                                   when x.loc_pending then 'TRYING' else 'POSSIBLE_NEEDS_SOURCE' end,
    'career_outcomes', case when x.car_n > 0 then x.car_n || ' occupations (national)' else 'EMPTY_NOT_STARTED' end
  ) cells,
  -- s927: the coverage state behind each gap, so the data gap register can say "waiting for a person", "no website on record" and so on
  (select coalesce(jsonb_object_agg(r.key, r.value), '{}'::jsonb) from jsonb_each_text(jsonb_strip_nulls(jsonb_build_object(
    'official_url', x.m->'official_url'->>'s', 'description', x.m->'description'->>'s', 'provider_tuition', x.m->'provider_tuition'->>'s',
    'intakes', x.m->'intakes'->>'s', 'deadline', x.m->'deadline'->>'s', 'duration', x.m->'duration'->>'s', 'campus', x.m->'campus'->>'s',
    'academic_entry', x.m->'academic_entry'->>'s', 'english', x.m->'english'->>'s'))) r where r.value <> 'admitted') raw  -- admitted states left out (smaller answers)
from cell x left join sx using (course_id)
order by x.cc, x.provider_name, x.title;
