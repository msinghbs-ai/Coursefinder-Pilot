-- Guards: Platform Admin mandate 5 Nov 2026 17:31, Course Catalogue columns: the named acceptance cases (mandate §10).
\set ON_ERROR_STOP on
create or replace function pg_temp.u(text) returns uuid language sql immutable as $$ select md5($1)::uuid $$;
-- three providers: an admitting adapter (pk), a testing adapter (pt), no adapter (pn); headquarters in Geelong, never a course city
insert into pim.entity_registry(id) values (pg_temp.u('pk')), (pg_temp.u('pt')), (pg_temp.u('pn'));
insert into catalogue.providers(id, stable_key, canonical_name, country_id, subdivision_id, primary_city) values
 (pg_temp.u('pk'), 'provider:k', 'Kestrel University', pg_temp.u('AU'), pg_temp.u('VIC'), 'Geelong'),
 (pg_temp.u('pt'), 'provider:t', 'Tern Institute', pg_temp.u('AU'), pg_temp.u('NSW'), 'Geelong'),
 (pg_temp.u('pn'), 'provider:n', 'Nightjar College', pg_temp.u('AU'), pg_temp.u('QLD'), 'Geelong');
insert into pipeline.uni_adapters(provider_id, enabled, admit, reason) values (pg_temp.u('pk'), true, true, 'fixture'), (pg_temp.u('pt'), true, false, 'fixture');
-- campuses: Richmond in Victoria and Richmond in New South Wales (same city name, different state), and Melbourne
insert into catalogue.campuses(id, stable_key, provider_id, name, country_id, subdivision_id, city) values
 (pg_temp.u('k_ca1'), 'campus:k1', pg_temp.u('pk'), 'Richmond Campus', pg_temp.u('AU'), pg_temp.u('VIC'), 'Richmond'),
 (pg_temp.u('k_ca2'), 'campus:k2', pg_temp.u('pk'), 'Hawkesbury Campus', pg_temp.u('AU'), pg_temp.u('NSW'), 'Richmond'),
 (pg_temp.u('k_ca3'), 'campus:k3', pg_temp.u('pk'), 'City Campus', pg_temp.u('AU'), pg_temp.u('VIC'), 'Melbourne');

insert into pim.entity_registry(id) select pg_temp.u(k) from unnest(array['k_multi', 'k_ready', 'k_processing', 'k_completed', 'k_failed', 'k_held_nopage', 'k_held_testing',
  'k_notcfg', 'k_fresh', 'k_unknown', 'k_newest', 'k_oldest']) k;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, course_code, lifecycle_status, publication_status, created_at, updated_at) values
 (pg_temp.u('k_multi'), 'course:k_multi', pg_temp.u('pk'), 'Kestrel Bachelor of Multi-Campus Studies', '100001A', 'active', 'published', '2026-06-01', '2026-08-01'),
 (pg_temp.u('k_ready'), 'course:k_ready', pg_temp.u('pk'), 'Kestrel Ready Course', '100002A', 'active', 'published', '2026-06-01', '2026-08-01'),
 (pg_temp.u('k_processing'), 'course:k_processing', pg_temp.u('pk'), 'Kestrel Processing Course', '100003A', 'active', 'published', '2026-06-01', '2026-08-01'),
 (pg_temp.u('k_completed'), 'course:k_completed', pg_temp.u('pk'), 'Kestrel Completed Course', '100004A', 'active', 'published', '2026-06-01', '2026-08-01'),
 (pg_temp.u('k_failed'), 'course:k_failed', pg_temp.u('pk'), 'Kestrel Failed Course', '100005A', 'active', 'published', '2026-06-01', '2026-08-01'),
 (pg_temp.u('k_held_nopage'), 'course:k_held_nopage', pg_temp.u('pk'), 'Kestrel Course Without A Page', '100006A', 'active', 'published', '2026-06-01', '2026-08-01'),
 (pg_temp.u('k_held_testing'), 'course:k_held_testing', pg_temp.u('pt'), 'Tern Testing Adapter Course', '100007A', 'active', 'published', '2026-06-01', '2026-08-01'),
 (pg_temp.u('k_notcfg'), 'course:k_notcfg', pg_temp.u('pn'), 'Nightjar No Adapter Course', '100008A', 'active', 'published', '2026-06-01', '2026-08-01'),
 (pg_temp.u('k_fresh'), 'course:k_fresh', pg_temp.u('pk'), 'Kestrel Modified After Admission', '100009A', 'active', 'published', '2026-06-01', '2026-11-04 10:00+11'),
 (pg_temp.u('k_unknown'), 'course:k_unknown', pg_temp.u('pk'), 'Kestrel Never Admitted', '100010A', 'active', 'published', '2026-06-01', '2026-08-02'),
 (pg_temp.u('k_newest'), 'course:k_newest', pg_temp.u('pk'), 'Kestrel Newest Admission', '100011A', 'active', 'published', '2026-06-01', '2026-08-01'),
 (pg_temp.u('k_oldest'), 'course:k_oldest', pg_temp.u('pk'), 'Kestrel Oldest Admission', '100012A', 'active', 'published', '2026-06-01', '2026-08-01');
insert into catalogue.course_campuses(course_id, campus_id, delivery_mode, is_primary) values
 (pg_temp.u('k_multi'), pg_temp.u('k_ca1'), '', true), (pg_temp.u('k_multi'), pg_temp.u('k_ca1'), 'online', false),
 (pg_temp.u('k_multi'), pg_temp.u('k_ca2'), '', false), (pg_temp.u('k_multi'), pg_temp.u('k_ca3'), '', false);

-- course pages and adapter results for the adapter states
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status, read_at, leased_until, evidence_id, identity_basis) values
 (pg_temp.u('k_ready'), pg_temp.u('pk'), 'https://kestrel.example/ready', 'bound', null, null, null, null, 'cricos_code'),
 (pg_temp.u('k_processing'), pg_temp.u('pk'), 'https://kestrel.example/processing', 'bound', 'read', '2026-10-01', now() + interval '1 hour', pg_temp.u('ev1'), 'cricos_code'),
 (pg_temp.u('k_completed'), pg_temp.u('pk'), 'https://kestrel.example/completed', 'bound', 'read', '2026-10-01', null, pg_temp.u('ev2'), 'cricos_code'),
 (pg_temp.u('k_failed'), pg_temp.u('pk'), 'https://kestrel.example/failed', 'bound', 'fetch_failed', '2026-10-01', null, null, 'cricos_code'),
 (pg_temp.u('k_held_testing'), pg_temp.u('pt'), 'https://tern.example/testing', 'bound', 'read', '2026-10-01', null, pg_temp.u('ev3'), 'exact_title'),
 (pg_temp.u('k_fresh'), pg_temp.u('pk'), 'https://kestrel.example/fresh', 'bound', 'read', '2026-11-05 09:00+11', null, pg_temp.u('ev4'), 'cricos_code');
insert into pipeline.uni_adapter_results(provider_id, course_id, before_read_status, before_identity, identity, how, fields, at) values
 (pg_temp.u('pk'), pg_temp.u('k_completed'), 'read', 'cricos_code', 'adapter_title', 'fields only, page already confirmed (cricos_code)', '{}', '2026-10-02'),
 (pg_temp.u('pt'), pg_temp.u('k_held_testing'), 'read', 'exact_title', 'adapter_title', 'fields only, page already confirmed (exact_title)', '{}', '2026-10-02'),
 -- a scheduled read of k_fresh on 5 Nov: a read, never an admission
 (pg_temp.u('pk'), pg_temp.u('k_fresh'), 'read', 'cricos_code', 'adapter_title', 'fields only, page already confirmed (cricos_code)', '{}', '2026-11-05 09:00+11');

-- k_fresh: modified 4 Nov 10:00, last admitted 1 Oct 09:00; later rows that are not admissions
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, source, value, updated_at) values
 (pg_temp.u('job'), pg_temp.u('pk'), pg_temp.u('k_fresh'), 'english', 'filled', 'ai_stored', '{"overall": 6.5}', '2026-10-01 09:00+10'),
 (pg_temp.u('job'), pg_temp.u('pk'), pg_temp.u('k_fresh'), 'intakes', 'skipped', 'ai_stored', null, '2026-11-03 12:00+11'),
 (pg_temp.u('job'), pg_temp.u('pk'), pg_temp.u('k_fresh'), 'deadline', 'review', 'ai_stored', '{"date": "2027-01-31"}', '2026-11-03 12:00+11'),
 (pg_temp.u('job'), pg_temp.u('pk'), pg_temp.u('k_fresh'), 'duration', 'filled', 'ai_stored', '{"value": 3}', '2026-11-02 12:00+11');
insert into pipeline.enrich_value_retractions(item_id, course_id, provider_id, field, value, cleared, reason)
select i.id, i.course_id, i.provider_id, i.field, i.value, true, 'fixture: another course''s page' from pipeline.field_enrich_items i where i.course_id = pg_temp.u('k_fresh') and i.field = 'duration';
insert into pipeline.course_fact_source_records(id) values (pg_temp.u('sr_fresh'));
insert into pipeline.layer2_field_admissions(source_record_id, course_id, source_id, evidence_id, field_key, status, canonical_changed, decided_at) values
 (pg_temp.u('sr_fresh'), pg_temp.u('k_fresh'), pg_temp.u('src'), pg_temp.u('ev1'), 'official_url', 'unchanged', false, '2026-11-03 12:00+11');
insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, at) values
 (pg_temp.u('k_fresh'), pg_temp.u('pk'), 'fee', '{"amount": 30000}', '{"amount": 30000}', '2026-11-03 13:00+11');
-- k_newest: the latest admission of all (a confirmed Layer 4 approval); k_oldest: the earliest (a tuition set by hand)
insert into pipeline.layer4_decisions(id) values (pg_temp.u('dec_newest'));
insert into pipeline.layer4_admission_checks(decision_id, review_item_id, field_code, entity_type, entity_id, decided_at, result, admitted) values
 (pg_temp.u('dec_newest'), pg_temp.u('ri_newest'), 'official_url', 'course', pg_temp.u('k_newest'), '2026-11-05 08:00+11', 'admitted', true);
insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, at) values
 (pg_temp.u('k_oldest'), pg_temp.u('k_oldest'), 'tuition', 'set_tuition', null, '{"amount": 41000}', 'fixture: set by hand', '2026-01-01 09:00+11');
update pipeline.manual_edit_log set entity = 'course' where entity_id = pg_temp.u('k_oldest');
insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, run_at, rule, outcome, after_value) values
 (pg_temp.u('i1'), pg_temp.u('k_completed'), pg_temp.u('pk'), '2026-10-20 10:00+11', 'calendar_v2', 'filled', '{"start": "2027-02-24"}'),
 (pg_temp.u('i2'), pg_temp.u('k_completed'), pg_temp.u('pk'), '2026-10-21 10:00+11', 'calendar_v2', 'skipped', null);

-- intakes of k_completed (one dated by the intake-dates job, one a label only) and its website feed item; k_failed withdrawn from the feed
insert into catalogue.course_intakes(id, course_id, intake_year, intake_label, start_date, application_deadline, status) values
 (pg_temp.u('ki1'), pg_temp.u('k_completed'), 2027, 'Semester 1 (February)', '2027-02-24', '2026-12-15', 'active'),
 (pg_temp.u('ki2'), pg_temp.u('k_completed'), 2027, 'July', null, null, 'active'),
 (pg_temp.u('ki3'), pg_temp.u('k_completed'), 2025, 'March', null, null, 'inactive');
insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, outcome, start_precision, deadline_kind) values
 (pg_temp.u('ki1'), pg_temp.u('k_completed'), pg_temp.u('pk'), 'filled', 'day', 'date');
insert into pipeline.website_sync_items(entity, item_key, ref_id, hash, seq, seq_at, removed_at) values
 ('course', 'course:k_completed', pg_temp.u('k_completed'), 'h1', 1, '2026-11-02 10:00+11', null),
 ('course', 'course:k_failed', pg_temp.u('k_failed'), null, 2, '2026-11-03 10:00+11', '2026-11-03 10:00+11');
-- field states of k_fresh, one of each kind
insert into pipeline.course_attribute_coverage(course_id, provider_id, attribute, state, tier, absence_class) values
 (pg_temp.u('k_fresh'), pg_temp.u('pk'), 'english', 'admitted', 'core', null),
 (pg_temp.u('k_fresh'), pg_temp.u('pk'), 'deadline', 'in_review', 'core', null),
 (pg_temp.u('k_fresh'), pg_temp.u('pk'), 'intakes', 'site_known', 'core', null),
 (pg_temp.u('k_fresh'), pg_temp.u('pk'), 'provider_tuition', 'not_on_page', 'core', 'not_applicable'),
 (pg_temp.u('k_fresh'), pg_temp.u('pk'), 'official_url', 'blocked', 'core', null),
 (pg_temp.u('k_fresh'), pg_temp.u('pk'), 'description', 'in_queue', 'core', null);
insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source, state) values
 ('course', pg_temp.u('k_fresh')::text, pg_temp.u('pk'), 'intakes', 'intake_conflict', 'fixture', 'fixture', 'raised');
insert into pipeline.layer4_intervention_classes(code) values ('missing_intake') on conflict do nothing;
insert into pipeline.layer4_interventions(lane, entity, missing_fact, provider_id, course_id, field, subject, issue, required_input, recommended, allowed_actions, resume_target, fingerprint) values
 ('course', pg_temp.u('k_fresh')::text, 'missing_intake', pg_temp.u('pk'), pg_temp.u('k_fresh'), 'intakes', 'Kestrel Modified After Admission', '{}', '{}', '{}', '[]', '{}', 'fx1');
analyze;
