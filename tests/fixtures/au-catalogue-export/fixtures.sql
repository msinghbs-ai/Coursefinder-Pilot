-- AU catalogue export fixtures: two AU providers (one published, one unpublished), one NZ provider, 260 AU courses and 20 NZ courses, with
-- children in every status, a quoted/multi-line description, an empty string beside a null, scholarships linked across countries, Layer 4
-- items and a search block. Ids are fixed so the expected counts are exact.
insert into ref.countries(id, iso_alpha2, iso_alpha3, name) values ('00000000-0000-0000-0000-0000000000a1', 'AU', 'AUS', 'Australia'), ('00000000-0000-0000-0000-0000000000a2', 'NZ', 'NZL', 'New Zealand');
insert into ref.subdivisions(id, country_id, code, name) values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'AU-VIC', 'Victoria');
insert into ref.study_levels(id, code, name) values ('00000000-0000-0000-0000-0000000000c1', 'bachelor', 'Bachelor');
insert into ref.fields_of_study(id, code, name) values ('00000000-0000-0000-0000-0000000000c2', '01', 'Natural and Physical Sciences');
insert into ref.english_tests(id, code, name) values ('00000000-0000-0000-0000-0000000000c3', 'IELTS', 'IELTS Academic');
insert into ref.ranking_sources(id, code, name) values ('00000000-0000-0000-0000-0000000000c4', 'QS', 'QS World University Rankings');
insert into pipeline.sources(id, source_type, label) values ('00000000-0000-0000-0000-0000000000d1', 'provider_site', 'Provider course pages'), ('00000000-0000-0000-0000-0000000000d2', 'register', 'CRICOS Providers, Courses and Locations');
insert into search.projection_country_gates values ('courses', '00000000-0000-0000-0000-0000000000a1', 'approved', 'fixture'), ('courses', '00000000-0000-0000-0000-0000000000a2', 'approved', 'fixture');
insert into search.enrichment_gates(projection_code, domain_code, gate_status, approval_ref)
  select 'courses', d, 'approved', 'fixture' from unnest(array['regulatory_tuition', 'provider_current_tuition', 'official_course_url', 'course_intake', 'course_english', 'scholarship']) d;
insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref)
  select 'courses', d, '00000000-0000-0000-0000-0000000000d1', 'approved', 'fixture' from unnest(array['provider_current_tuition', 'official_course_url', 'course_intake', 'course_english']) d;
insert into catalogue.providers(id, stable_key, canonical_name, country_id, subdivision_id, lifecycle_status, publication_status) values
  ('00000000-0000-0000-0000-00000000aa01', 'au-uni-a', 'Uni A', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'active', 'published'),
  ('00000000-0000-0000-0000-00000000aa02', 'au-uni-b', 'Uni B', '00000000-0000-0000-0000-0000000000a1', null, 'active', 'unpublished'),
  ('00000000-0000-0000-0000-00000000aa03', 'nz-uni-c', 'Uni C', '00000000-0000-0000-0000-0000000000a2', null, 'active', 'published');
insert into catalogue.campuses(id, stable_key, provider_id, name, country_id, subdivision_id, city) values
  ('00000000-0000-0000-0000-00000000cc01', 'campus-a', '00000000-0000-0000-0000-00000000aa01', 'City campus', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'Melbourne');
-- 240 courses at Uni A (every 7th inactive), 20 at Uni B, 20 NZ
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, course_code, study_level_id, primary_field_id, description, course_url, duration_value, duration_unit, delivery_mode, lifecycle_status, publication_status)
select ('00000000-0000-0000-0001-' || lpad(to_hex(g), 12, '0'))::uuid, 'c-' || g,
  case when g <= 240 then '00000000-0000-0000-0000-00000000aa01' when g <= 260 then '00000000-0000-0000-0000-00000000aa02' else '00000000-0000-0000-0000-00000000aa03' end::uuid,
  'Course ' || g, case when g % 50 = 0 then '' when g % 11 = 0 then null else 'CODE' || g end,
  '00000000-0000-0000-0000-0000000000c1', case when g % 5 = 0 then null else '00000000-0000-0000-0000-0000000000c2' end::uuid,
  case when g = 1 then E'Line one, with a comma\nline two "quoted"' when g % 4 = 0 then null else 'About course ' || g end,
  'https://a.example/c/' || g, case when g % 6 = 0 then null else 3 end, 'years', 'on_campus',
  case when g % 7 = 0 then 'inactive' else 'active' end, 'unpublished'
from generate_series(1, 280) g;
-- the projection: active courses of the published, active AU and NZ providers
insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, course_stable_key, provider_stable_key, course_code,
  country_code, study_level_code, primary_field_code, primary_field_name, delivery_modes, subdivision_codes, official_course_url, intake_options, english_requirement_options, scholarship_options,
  provider_annual_tuition_amount, provider_tuition_options, regulatory_tuition_amount, description, updated_at)
select c.id, c.provider_id, p.country_id, p.canonical_name, c.canonical_title, c.canonical_title, to_tsvector('english', c.canonical_title), c.publication_status, c.stable_key, p.stable_key, c.course_code,
  trim(co.iso_alpha2), 'bachelor', fos.code, fos.name, array['on_campus'], case when co.iso_alpha2 = 'AU' then array['AU-VIC'] else '{}' end,
  case when right(c.stable_key, 1) in ('1', '2') then c.course_url end, '[{"label":"February","year":2027}]', '[]', '[]',
  case when right(c.stable_key, 1) = '3' then 41000 end, '[]', case when right(c.stable_key, 1) = '3' then 120000 end, c.description, now()
from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id left join ref.fields_of_study fos on fos.id = c.primary_field_id
where c.lifecycle_status = 'active' and p.publication_status = 'published' and p.lifecycle_status = 'active';
insert into catalogue.course_campuses(course_id, campus_id, delivery_mode, is_primary) select id, '00000000-0000-0000-0000-00000000cc01', 'on_campus', true from catalogue.courses where provider_id = '00000000-0000-0000-0000-00000000aa01';
-- fees: three per course (active provider fee, superseded, CRICOS registered total), one unverified on every tenth
insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, status, source_id)
select c.id, y, 'international', t, a, 'AUD', b, s, src::uuid
from catalogue.courses c, (values (2027, 'provider_current_tuition', 41000, 'annual', 'active', '00000000-0000-0000-0000-0000000000d1'), (2026, 'provider_current_tuition', 39000, 'annual', 'superseded', '00000000-0000-0000-0000-0000000000d1'),
  (2026, 'tuition', 120000, 'registered_total_course', 'active', '00000000-0000-0000-0000-0000000000d2')) v(y, t, a, b, s, src);
insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, status, source_id)
select id, 2027, 'international', 'provider_current_tuition', 42000, 'AUD', 'annual', 'unverified', '00000000-0000-0000-0000-0000000000d1' from catalogue.courses where right(stable_key, 1) = '0';
insert into catalogue.course_intakes(course_id, intake_year, intake_label, start_date, application_deadline, status, source_id)
select id, 2027, 'February', case when right(stable_key, 1) = '4' then null else date '2027-02-22' end, null, case when right(stable_key, 1) = '5' then 'withdrawn' else 'active' end, '00000000-0000-0000-0000-0000000000d1' from catalogue.courses;
insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, status, source_id)
select id, '00000000-0000-0000-0000-0000000000c3', 6.5, '{"listening":6}', 'active', '00000000-0000-0000-0000-0000000000d1' from catalogue.courses where right(stable_key, 1) <> '9';
insert into catalogue.course_links(course_id, link_type, url, is_primary, status, source_id)
select id, 'official', course_url, true, case when right(stable_key, 1) = '8' then 'unverified' else 'active' end, '00000000-0000-0000-0000-0000000000d1' from catalogue.courses;
insert into catalogue.course_identifiers(course_id, provider_id, scheme, identifier) select id, provider_id, 'studysearch', 'SS' || stable_key from catalogue.courses;
insert into catalogue.course_entry_requirements(course_id, kind, audience, description, min_entry_score, min_entry_score_basis, quote, status)
select id, 'minimum_grade', 'international', 'ATAR 80', 80, 'atar', 'ATAR 80', case when right(stable_key, 1) = '6' then 'proposed' else 'active' end from catalogue.courses where right(stable_key, 1) in ('6', '7');
insert into catalogue.provider_entry_matrix(provider_id, country_id, country_code, qualification_name, min_grade, quote, source_url, status)
values ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a2', 'NZ', 'NCEA Level 3', '120', 'NCEA 120', 'https://a.example/entry', 'active'),
       ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a2', 'NZ', 'NCEA Level 3', '110', 'NCEA 110', 'https://a.example/entry', 'proposed');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status) select id, provider_id, course_url, 'bound', 'read' from catalogue.courses where right(stable_key, 1) <> '0';
insert into scholarship.scholarships(id, stable_key, provider_id, name, audience, lifecycle_status, publication_status) values
  ('00000000-0000-0000-0002-000000000001', 'sch-a', '00000000-0000-0000-0000-00000000aa01', 'Merit award', 'international', 'active', 'published'),
  ('00000000-0000-0000-0002-000000000002', 'sch-nz', '00000000-0000-0000-0000-00000000aa03', 'NZ award also open to AU courses', 'international', 'active', 'published'),
  ('00000000-0000-0000-0002-000000000003', 'sch-nz-only', '00000000-0000-0000-0000-00000000aa03', 'NZ only', 'international', 'active', 'published');
insert into scholarship.course_mappings(scholarship_id, course_id, mapping_basis) select '00000000-0000-0000-0002-000000000001', id, 'provider_wide' from catalogue.courses where provider_id = '00000000-0000-0000-0000-00000000aa01';
insert into scholarship.course_mappings(scholarship_id, course_id, mapping_basis) select '00000000-0000-0000-0002-000000000002', id, 'listed' from catalogue.courses where stable_key in ('c-1', 'c-2', 'c-261');
insert into scholarship.course_mappings(scholarship_id, course_id, mapping_basis) select '00000000-0000-0000-0002-000000000003', id, 'listed' from catalogue.courses where stable_key = 'c-262';
insert into scholarship.award_tiers(scholarship_id, label, amount, currency_code) values ('00000000-0000-0000-0002-000000000001', 'Up to', 10000, 'AUD'), ('00000000-0000-0000-0002-000000000003', 'NZ', 5000, 'NZD');
insert into scholarship.criteria(scholarship_id, criterion_type, human_text) values ('00000000-0000-0000-0002-000000000001', 'gpa', 'GPA 3.0');
insert into scholarship.course_financial_calculations(mapping_id, scholarship_id, course_id, calculation_status) select id, scholarship_id, course_id, 'calculated' from scholarship.course_mappings where scholarship_id = '00000000-0000-0000-0002-000000000001' limit 10;
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, decided_at)
select 'course', id, 'course_english', case when stable_key = 'c-9' then 'pending' else 'rejected' end, case when stable_key = 'c-9' then null else now() end from catalogue.courses where right(stable_key, 1) = '9' and stable_key in ('c-9', 'c-19');
insert into security.layer4_active_blocks values ('course', '00000000-0000-0000-0001-000000000003', 'search');
insert into cron.job(jobname, schedule) values ('coverage-admit', '*/10 * * * *'), ('adapter-overwrite', '3-59/10 * * * *'), ('coverage-admit-intakes', '8-59/10 * * * *'), ('exit-awards-apply', '37 * * * *'), ('unrelated', '1 * * * *');
