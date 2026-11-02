-- AU catalogue export, scaled fixtures (2 Nov 2026 run 41377240304 OOM): adds AU courses and children up to the live AU counts of
-- 2 Nov (26,912 courses, 179,621 fees, 101,422 scholarship links, 48,732 campus rows, 23,732 projection rows, 21,814 Layer 4 items),
-- with descriptions, projection JSON and Layer 4 states of realistic size. Run after fixtures.sql: psql -v n=26652 -f scale.sql
insert into catalogue.campuses(id, stable_key, provider_id, name, country_id, subdivision_id, city) values
  ('00000000-0000-0000-0000-00000000cc02', 'campus-b', '00000000-0000-0000-0000-00000000aa01', 'North campus', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'Bundoora');
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, course_code, study_level_id, primary_field_id, description, course_url, duration_value, duration_unit, delivery_mode, lifecycle_status, publication_status)
select ('00000000-0000-0000-0003-' || lpad(to_hex(g), 12, '0'))::uuid, 's-' || g, '00000000-0000-0000-0000-00000000aa01', 'Scaled course ' || g, 'S' || g,
  '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000c2', repeat('A course description, with commas and "quotes". ', 30) || g,
  'https://a.example/s/' || g, 3, 'years', 'on_campus', case when g % 20 = 0 then 'inactive' else 'active' end, 'unpublished'
from generate_series(1, :n) g;
insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, course_stable_key, provider_stable_key, course_code,
  country_code, study_level_code, primary_field_code, primary_field_name, delivery_modes, subdivision_codes, official_course_url, intake_options, english_requirement_options, scholarship_options,
  provider_annual_tuition_amount, provider_tuition_options, description, enrichment_semantic_text, updated_at)
select c.id, c.provider_id, '00000000-0000-0000-0000-0000000000a1', 'Uni A', c.canonical_title, c.canonical_title, to_tsvector('english', c.canonical_title), c.publication_status, c.stable_key, 'au-uni-a', c.course_code,
  'AU', 'bachelor', '01', 'Natural and Physical Sciences', array['on_campus'], array['AU-VIC'], c.course_url,
  (select jsonb_agg(jsonb_build_object('year', 2027, 'label', m, 'start_date', '2027-02-22', 'application_deadline', null, 'campus_id', null)) from unnest(array['February', 'July']) m),
  '[{"test_code":"IELTS","test_name":"IELTS Academic","overall_score":6.5,"component_scores":{"listening":6,"reading":6,"writing":6,"speaking":6},"notes":"Course page"}]',
  (select jsonb_agg(jsonb_build_object('scholarship_key', 'sch-a', 'name', 'Merit award ' || k, 'award_value_text', 'Up to 20% of tuition', 'source_url', 'https://a.example/sch')) from generate_series(1, 4) k),
  41000, '[{"fee_year":2027,"amount":41000,"currency":"AUD","basis":"annual"}]', c.description, repeat('semantic ', 40), now()
from catalogue.courses c where c.stable_key like 's-%' and c.lifecycle_status = 'active' and right(c.stable_key, 1) <> '7';
insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, status, source_id, notes)
select c.id, 2020 + k, 'international', case when k = 0 then 'tuition' else 'provider_current_tuition' end, 30000 + k * 1000, 'AUD', case when k = 0 then 'registered_total_course' else 'annual' end,
  case when k = 6 then 'active' when k = 0 then 'active' else 'superseded' end, case when k = 0 then '00000000-0000-0000-0000-0000000000d2' else '00000000-0000-0000-0000-0000000000d1' end::uuid, 'Fee note for year ' || (2020 + k)
from catalogue.courses c, generate_series(0, 6) k where c.stable_key like 's-%' and (k < 6 or right(c.stable_key, 1) in ('1', '2', '3', '4', '5', '6', '7'));
insert into catalogue.course_intakes(course_id, intake_year, intake_label, start_date, status, source_id)
select id, 2027, 'February', date '2027-02-22', 'active', '00000000-0000-0000-0000-0000000000d1' from catalogue.courses where stable_key like 's-%';
insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, status, source_id)
select id, '00000000-0000-0000-0000-0000000000c3', 6.5, '{"listening":6,"reading":6,"writing":6,"speaking":6}', 'active', '00000000-0000-0000-0000-0000000000d1' from catalogue.courses where stable_key like 's-%';
insert into catalogue.course_links(course_id, link_type, url, is_primary, status, source_id)
select id, 'official', course_url, true, 'active', '00000000-0000-0000-0000-0000000000d1' from catalogue.courses where stable_key like 's-%' and right(stable_key, 1) not in ('8', '9', '0');
insert into catalogue.course_campuses(course_id, campus_id, delivery_mode, is_primary)
select c.id, k.id, 'on_campus', k.stable_key = 'campus-a' from catalogue.courses c, catalogue.campuses k where c.stable_key like 's-%' and (k.stable_key = 'campus-a' or right(c.stable_key, 1) not in ('9', '0'));
insert into catalogue.course_identifiers(course_id, provider_id, scheme, identifier) select id, provider_id, 'studysearch', 'SS' || stable_key from catalogue.courses where stable_key like 's-%';
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status, candidates)
select id, provider_id, course_url, 'bound', 'read', jsonb_build_array(jsonb_build_object('url', course_url, 'score', 0.9), jsonb_build_object('url', course_url || '/x', 'score', 0.4)) from catalogue.courses where stable_key like 's-%' and right(stable_key, 1) <> '0';
insert into scholarship.course_mappings(scholarship_id, course_id, mapping_basis) select s, c.id, 'provider_wide'
from catalogue.courses c, unnest(array['00000000-0000-0000-0002-000000000001', '00000000-0000-0000-0002-000000000002', '00000000-0000-0000-0002-000000000004', '00000000-0000-0000-0002-000000000005']::uuid[]) s
where c.stable_key like 's-%' and (s <> '00000000-0000-0000-0002-000000000005' or right(c.stable_key, 1) in ('1', '2', '3', '4', '5', '6', '7', '8'));
insert into scholarship.scholarships(id, stable_key, provider_id, name, audience, lifecycle_status, publication_status) values
  ('00000000-0000-0000-0002-000000000004', 'sch-a2', '00000000-0000-0000-0000-00000000aa01', 'Scaled award', 'international', 'active', 'published'),
  ('00000000-0000-0000-0002-000000000005', 'sch-a3', '00000000-0000-0000-0000-00000000aa01', 'Scaled award two', 'international', 'active', 'published');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, decided_at, before_value, proposed_value, layer2_state, layer3_state)
select 'course', id, 'course_intake', case when right(stable_key, 1) = '3' then 'pending' else 'superseded' end, case when right(stable_key, 1) = '3' then null else now() end,
  jsonb_build_object('intakes', '[]'::jsonb), jsonb_build_object('intakes', jsonb_build_array('February 2027', 'July 2027')), jsonb_build_object('note', repeat('layer two state ', 20)), jsonb_build_object('note', repeat('layer three state ', 20))
from catalogue.courses where stable_key like 's-%' and right(stable_key, 2) <> '00' and right(stable_key, 1) <> '9';
