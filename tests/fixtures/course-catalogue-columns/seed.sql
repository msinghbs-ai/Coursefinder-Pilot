-- Guards: Platform Admin mandate 5 Nov 2026 17:31, Course Catalogue columns: production-volume fixture data (no production user data).
-- Volumes follow production (5 Nov 2026): 35,700 courses, 1,200 providers, 4,300 campuses, 54,900 course-campus links, 171,000 field items,
-- 34,000 adapter overwrites, 21,800 adapter results, 35,000 course pages, 6 coverage attributes a course, 25,000 raised flags. Every row goes in
-- through the production constraints and foreign keys built by schema.sql. The named cases (k_*) carry the acceptance facts the specs check.
\set ON_ERROR_STOP on
set session_replication_role = default;
create or replace function pg_temp.u(text) returns uuid language sql immutable as $$ select md5($1)::uuid $$;

-- people: Platform Admin, a second operator, a Viewer (read-only) and a signed-in person with no role
insert into auth.users(id, email) values (pg_temp.u('admin'), 'admin@fixture'), (pg_temp.u('operator2'), 'operator2@fixture'),
  (pg_temp.u('viewer'), 'viewer@fixture'), (pg_temp.u('norole'), 'norole@fixture');
insert into security.user_roles(user_id, role_code) values (pg_temp.u('admin'), 'platform_admin'), (pg_temp.u('operator2'), 'pipeline_operator'), (pg_temp.u('viewer'), 'viewer');

-- reference
insert into ref.currencies values ('AUD'), ('NZD');
insert into ref.countries(id, iso_alpha2, iso_alpha3, name, default_currency_code) values (pg_temp.u('AU'), 'AU', 'AUS', 'Australia', 'AUD'), (pg_temp.u('NZ'), 'NZ', 'NZL', 'New Zealand', 'NZD');
insert into ref.subdivisions(id, country_id, code, name) values
 (pg_temp.u('VIC'), pg_temp.u('AU'), 'AU-VIC', 'Victoria'), (pg_temp.u('NSW'), pg_temp.u('AU'), 'AU-NSW', 'New South Wales'),
 (pg_temp.u('QLD'), pg_temp.u('AU'), 'AU-QLD', 'Queensland'), (pg_temp.u('WA'), pg_temp.u('AU'), 'AU-WA', 'Western Australia'),
 (pg_temp.u('AUK'), pg_temp.u('NZ'), 'NZ-AUK', 'Auckland');
insert into ref.study_levels(id, code, name) select pg_temp.u('lvl' || g), 'lvl' || g, (array['Bachelor', 'Master', 'Diploma', 'Certificate IV', 'Doctorate'])[g] from generate_series(1, 5) g;
insert into ref.fields_of_study(id, code, name) select pg_temp.u('fos' || g), 'fos' || g, 'Field ' || lpad(g::text, 2, '0') from generate_series(1, 24) g;
insert into ref.course_code_schemes(scheme, printed, label) values ('cricos', true, 'CRICOS'), ('studysearch', false, 'StudySearch');
insert into ref.english_tests(id) values (pg_temp.u('IELTS'));
insert into ref.course_link_types(code) values ('official_course');
insert into pipeline.admin_jobs(id) values (pg_temp.u('job'));
insert into pipeline.sources(id) values (pg_temp.u('src'));
insert into pipeline.evidence_artifacts(id) select pg_temp.u('ev' || g) from generate_series(1, 200) g;
insert into pipeline.course_fact_source_records(id) select pg_temp.u('sr' || g) from generate_series(1, 1300) g;
insert into pipeline.layer4_decisions(id) select pg_temp.u('dec' || g) from generate_series(1, 1500) g;
insert into pipeline.layer4_intervention_classes(code) values ('missing_official_url');

-- providers: 1,200; headquarters city Geelong on every provider (must never be shown as a course city)
insert into pim.entity_registry(id) select pg_temp.u('p' || g) from generate_series(1, 1200) g;
insert into catalogue.providers(id, stable_key, canonical_name, country_id, subdivision_id, primary_city)
select pg_temp.u('p' || g), 'provider:' || g, 'Provider ' || lpad(g::text, 4, '0'), case when g % 10 = 0 then pg_temp.u('NZ') else pg_temp.u('AU') end,
       case when g % 10 = 0 then pg_temp.u('AUK') else (array[pg_temp.u('VIC'), pg_temp.u('NSW'), pg_temp.u('QLD'), pg_temp.u('WA')])[1 + g % 4] end, 'Geelong'
  from generate_series(1, 1200) g;
-- campuses: 4,300 (cities by state; two different states each have a "Richmond")
insert into catalogue.campuses(id, stable_key, provider_id, name, country_id, subdivision_id, city)
select pg_temp.u('ca' || g), 'campus:' || g, pg_temp.u('p' || (1 + g % 1200)), 'Campus ' || g,
       case when (1 + g % 1200) % 10 = 0 then pg_temp.u('NZ') else pg_temp.u('AU') end,
       case when (1 + g % 1200) % 10 = 0 then pg_temp.u('AUK') else (array[pg_temp.u('VIC'), pg_temp.u('NSW'), pg_temp.u('QLD'), pg_temp.u('WA')])[1 + g % 4] end,
       case when (1 + g % 1200) % 10 = 0 then 'Auckland' else (array['Melbourne', 'Sydney', 'Brisbane', 'Perth'])[1 + g % 4] end
  from generate_series(1, 4300) g;

-- courses: 35,700, updated_at spread over 90 days; the provider of course g is g % 1200 + 1
insert into pim.entity_registry(id) select pg_temp.u('c' || g) from generate_series(1, 35700) g;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, course_code, study_level_id, primary_field_id, duration_value, duration_unit, delivery_mode,
  lifecycle_status, publication_status, last_verified_at, created_at, updated_at, description, open_to_international)
select pg_temp.u('c' || g), 'course:' || g, pg_temp.u('p' || (1 + g % 1200)), 'Course ' || lpad(g::text, 5, '0') || ' ' || (array['Arts', 'Science', 'Business', 'Nursing', 'Law'])[1 + g % 5],
       lpad(g::text, 6, '0') || 'K', pg_temp.u('lvl' || (1 + g % 5)), pg_temp.u('fos' || (1 + g % 24)), case when g % 7 = 0 then null else 1 + g % 4 end, 'years',
       case when g % 9 = 0 then null else 'on_campus' end, case when g % 40 = 0 then 'archived' else 'active' end, 'published',
       case when g % 6 = 0 then null else timestamptz '2026-08-01' + (g % 90) * interval '1 day' end,
       timestamptz '2026-06-01' + (g % 60) * interval '1 day', timestamptz '2026-08-01' + (g % 90) * interval '1 day' + (g % 1440) * interval '1 minute',
       case when g % 3 = 0 then null else 'Description of course ' || g end, case when g % 11 = 0 then null else true end
  from generate_series(1, 35700) g;
-- each course at its provider's first campus; every second course also at the provider's second campus (campus k belongs to provider 1 + k % 1200)
insert into catalogue.course_campuses(course_id, campus_id, delivery_mode, is_primary)
select pg_temp.u('c' || g), pg_temp.u('ca' || (case when g % 1200 = 0 then 1200 else g % 1200 end)), '', true from generate_series(1, 35700) g
union all
select pg_temp.u('c' || g), pg_temp.u('ca' || (1200 + case when g % 1200 = 0 then 1200 else g % 1200 end)), '', false from generate_series(1, 35700) g where g % 2 = 0;
insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, status)
select pg_temp.u('c' || g), 2026, 'international', 'provider_current_tuition', 20000 + (g * 37) % 30000, 'AUD', 'annual', 'active' from generate_series(1, 35700) g where g % 4 <> 0;
insert into catalogue.course_intakes(course_id, intake_year, intake_label) select pg_temp.u('c' || g), 2027, 'February' from generate_series(1, 35700) g where g % 5 <> 0;
insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score) select pg_temp.u('c' || g), pg_temp.u('IELTS'), 6.5 from generate_series(1, 35700) g where g % 3 <> 0;

-- adapters: 1,190 providers (827 admitting, 360 testing, 3 off); providers 1191..1200 have none
insert into pipeline.uni_adapters(provider_id, enabled, admit, reason)
select pg_temp.u('p' || g), g > 3, g > 363, 'fixture' from generate_series(1, 1190) g;
-- course pages: 35,000 (bound and read, a share failed, a share mismatched), none leased except named cases
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status, read_at, evidence_id, identity_basis)
select pg_temp.u('c' || g), pg_temp.u('p' || (1 + g % 1200)), 'https://provider.example/course/' || g,
       case when g % 13 = 0 then 'mismatch' else 'bound' end, case when g % 17 = 0 then 'fetch_failed' when g % 13 = 0 then 'identity_mismatch' else 'read' end,
       timestamptz '2026-10-01' + (g % 30) * interval '1 day', case when g % 17 = 0 then null else pg_temp.u('ev' || (1 + g % 200)) end, 'cricos_code'
  from generate_series(1, 35000) g;
insert into pipeline.uni_adapter_results(provider_id, course_id, before_read_status, before_identity, identity, how, fields, at)
select pg_temp.u('p' || (1 + g % 1200)), pg_temp.u('c' || g), 'read', 'cricos_code', 'adapter_title', 'fields only, page already confirmed (cricos_code)', '{}'::jsonb,
       timestamptz '2026-10-15' + (g % 20) * interval '1 day'
  from generate_series(1, 35000) g where g % 13 <> 0 and g % 17 <> 0 and g % 8 <> 0;

-- admission ledgers at production volume
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, value, updated_at, created_at)
select pg_temp.u('job'), pg_temp.u('p' || (1 + (g % 35700) % 1200)), pg_temp.u('c' || (1 + g % 35700)), (array['english', 'intakes', 'duration', 'delivery', 'level'])[1 + (g / 35700) % 5],
       (array['skipped', 'skipped', 'skipped', 'filled', 'review', 'failed'])[1 + g % 6], 'ai_stored', '{"value": 1}'::jsonb,
       timestamptz '2026-09-01' + (g % 60) * interval '1 day', timestamptz '2026-09-01'
  from generate_series(0, 170999) g on conflict do nothing;
insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, at)
select pg_temp.u('c' || (1 + g % 35700)), pg_temp.u('p' || (1 + (1 + g % 35700) % 1200)), 'delivery', '"online"'::jsonb, case when g % 10 = 0 then '"online"'::jsonb else '"on_campus"'::jsonb end,
       timestamptz '2026-09-15' + (g % 40) * interval '1 day' from generate_series(1, 34000) g;
insert into pipeline.layer2_field_admissions(source_record_id, course_id, source_id, evidence_id, field_key, status, canonical_changed, decided_at)
select pg_temp.u('sr' || g), pg_temp.u('c' || (g * 29 % 35700 + 1)), pg_temp.u('src'), pg_temp.u('ev1'), 'official_url', case when g % 8 = 0 then 'unchanged' else 'admitted' end, g % 8 <> 0,
       timestamptz '2026-09-20' + (g % 30) * interval '1 day' from generate_series(1, 1216) g;
insert into pipeline.layer4_admission_checks(decision_id, review_item_id, field_code, entity_type, entity_id, decided_at, result, admitted)
select pg_temp.u('dec' || g), pg_temp.u('ri' || g), 'official_url', 'course', pg_temp.u('c' || (g * 31 % 35700 + 1)), timestamptz '2026-10-10' + (g % 20) * interval '1 day',
       case when g % 10 = 0 then 'not_admitted' else 'admitted' end, g % 10 <> 0 from generate_series(1, 1447) g;
insert into pipeline.manual_edit_log(entity, entity_id, field, action, at)
select 'course', pg_temp.u('c' || (g * 7 % 35700 + 1)), 'official_url', case when g % 9 = 0 then 'archive' else 'set_official_url' end, timestamptz '2026-08-20' + (g % 50) * interval '1 day'
  from generate_series(1, 4500) g;

-- field states: six coverage attributes a course
insert into pipeline.course_attribute_coverage(course_id, provider_id, attribute, state, tier, absence_class)
select pg_temp.u('c' || g), pg_temp.u('p' || (1 + g % 1200)), a, (array['admitted', 'admitted', 'not_on_page', 'in_queue', 'in_review', 'site_known', 'blocked', 'candidate'])[1 + (g + length(a)) % 8], 'core',
       case when (g + length(a)) % 8 = 2 and g % 4 = 0 then 'not_applicable' end
  from generate_series(1, 35700) g, unnest(array['official_url', 'provider_tuition', 'english', 'intakes', 'deadline', 'description']) a;
insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source, state)
select 'course', pg_temp.u('c' || g)::text, pg_temp.u('p' || (1 + g % 1200)), 'deadline', 'no_deadline_on_page', 'fixture', 'fixture', 'raised' from generate_series(1, 35700) g where g % 7 = 3;
