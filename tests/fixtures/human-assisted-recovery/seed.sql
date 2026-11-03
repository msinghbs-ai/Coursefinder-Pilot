-- CF-247 human-assisted recovery fixtures: the cases of the decision's §4, §5 and §8, shaped like the live records read 4 Nov 2026 06:35-06:50
-- AEDT (no live data is copied). Providers: Deakin (site refused the free read), ACU (named document unverified), JCU (selector only), CDU (six
-- course reads, no row), UWA (read held), Torrens (shared course page), a scholarship university, a policy-excluded TAFE, a fee course and an
-- intake course.
insert into ref.countries(id, iso_alpha2) values ('00000000-0000-4000-8000-0000000000a1', 'AU') on conflict do nothing;
insert into catalogue.providers(id, stable_key, canonical_name, display_name, website, country_id) values
 ('c5c5d225-3d4c-4e41-8275-78eddd261073', 'deakin', 'Deakin University', 'Deakin', 'https://www.deakin.edu.au', '00000000-0000-4000-8000-0000000000a1'),
 ('030992c3-72c6-452d-8a3b-10ceb0fd77f2', 'acu', 'Australian Catholic University', 'ACU', 'https://www.acu.edu.au', '00000000-0000-4000-8000-0000000000a1'),
 ('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113', 'jcu', 'James Cook University', 'JCU', 'https://www.jcu.edu.au', '00000000-0000-4000-8000-0000000000a1'),
 ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'cdu', 'Charles Darwin University', 'CDU', 'https://www.cdu.edu.au', '00000000-0000-4000-8000-0000000000a1'),
 ('9109fe0c-9f44-4e2d-a136-eb00dec24701', 'uwa', 'The University of Western Australia', 'UWA', 'https://www.uwa.edu.au', '00000000-0000-4000-8000-0000000000a1'),
 ('fec52f92-a8a3-4de8-a862-06f355e4e2f7', 'torrens', 'Torrens University Australia', 'Torrens', 'https://www.torrens.edu.au', '00000000-0000-4000-8000-0000000000a1'),
 ('51000000-0000-4000-8000-000000000001', 'boxuni', 'Box University', 'Box University', 'https://www.boxuni.edu.au', '00000000-0000-4000-8000-0000000000a1'),
 ('51000000-0000-4000-8000-000000000002', 'tafe', 'TAFE Somewhere', 'TAFE Somewhere', 'https://www.tafe.example.edu.au', '00000000-0000-4000-8000-0000000000a1'),
 ('51000000-0000-4000-8000-000000000003', 'feeuni', 'Fee University', 'Fee University', 'https://www.feeuni.edu.au', '00000000-0000-4000-8000-0000000000a1')
on conflict do nothing;
insert into catalogue.courses(id, provider_id, canonical_title, course_code) values
 ('c0000000-0000-4000-8000-000000000001', 'fec52f92-a8a3-4de8-a862-06f355e4e2f7', 'Bachelor of Design (UX)', '099999A'),
 ('c0000000-0000-4000-8000-000000000002', 'fec52f92-a8a3-4de8-a862-06f355e4e2f7', 'Advanced Diploma of UX Design', '099998B'),
 ('c0000000-0000-4000-8000-000000000003', '6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'Bachelor of Nursing', '011111C'),
 ('c0000000-0000-4000-8000-000000000004', '51000000-0000-4000-8000-000000000003', 'Master of Data Science', '022222D'),
 ('c0000000-0000-4000-8000-000000000005', '51000000-0000-4000-8000-000000000003', 'Bachelor of Arts', '033333E')
on conflict do nothing;
insert into fx.directory_hosts values ('studyabroad.example.com') on conflict do nothing;
insert into fx.policy_excluded values ('51000000-0000-4000-8000-000000000002') on conflict do nothing;
insert into auth.users(id, email) values ('a0000000-0000-4000-8000-000000000004', 'operator@example.org'), ('a0000000-0000-4000-8000-000000000006', 'admin@example.org') on conflict do nothing;
insert into pipeline.platform_toolsets(key, enforcement) values ('openrouter', 'observe') on conflict do nothing;
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values
 ('pipeline', 'coverage.aer_priority_providers', '["6f5cb7f7-7c70-4c06-970f-f368c3a786e2", "c5c5d225-3d4c-4e41-8275-78eddd261073", "030992c3-72c6-452d-8a3b-10ceb0fd77f2", "fe6af182-f5ca-4a3c-bfb4-b0773ff1b113"]'),
 ('pipeline', 'ops.ai_diagnosis_on', '0'), ('pipeline', 'entry.matrix_attempts', '3')
on conflict do nothing;

-- the AER source inventory as 20261104090000 recorded it (shapes and outcomes; the evidence trimmed)
insert into pipeline.aer_source_inventory(provider_id, url, role, outcome, shape, audience, boundary, evidence, attach, verified_at) values
 ('c5c5d225-3d4c-4e41-8275-78eddd261073', null, 'landing', 'blocked_site', 'unknown: the official site refused the free read', 'international', 'Deakin University only; Deakin College excluded',
  '{"method": "WebSearch, WebFetch", "fetched": "2026-11-03T16:28+11:00", "tried": ["https://www.deakin.edu.au/international-students/entry-requirements", "https://www.deakin.edu.au/international-students/entry-requirements/english"], "stored_copy": "5106f65f"}', false, '2026-11-03 16:30+11'),
 ('030992c3-72c6-452d-8a3b-10ceb0fd77f2', 'https://www.acu.edu.au/study-at-acu/how-to-apply/international-students/international-undergraduate-students', 'landing', 'unverified_link',
  'landing_text: links "Download the minimum academic entry requirement (PDF, 405KB)" whose exact URL could not be verified', 'international', 'ACU only',
  '{"method": "WebSearch, WebFetch", "fetched": "2026-11-03T16:28+11:00", "next": "take the PDF href from the stored copy of the landing page"}', false, '2026-11-03 16:30+11'),
 ('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113', 'https://www.jcu.edu.au/entry-options/entry-requirements/academic-and-english-language-entry-requirements/country-specific-academic-levels', 'selector',
  'verified_rendered_only', 'selector: course-specific marks loaded dynamically', 'international', 'Australian campuses only',
  '{"method": "WebSearch, WebFetch", "fetched": "2026-11-03T16:27+11:00", "landing_quote": "you must have completed a recognised Year 12"}', false, '2026-11-03 16:30+11'),
 ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'https://www.cdu.edu.au/international/how-apply/entry-requirements', 'country_table', 'verified_attachable', 'html_table', 'international', null, '{}', true, '2026-11-03 16:30+11');
insert into pipeline.entry_matrix_sources(provider_id, url, found_via, status, read_via, attempts) values
 ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'https://www.cdu.edu.au/international/how-apply/entry-requirements', 'manual', 'read', 'direct', 1),
 ('9109fe0c-9f44-4e2d-a136-eb00dec24701', 'https://www.uwa.edu.au/study/how-to-apply/pathways-and-eligibility/international-and-overseas-qualifications', 'search', 'read', 'direct', 1);
insert into pipeline.aer_provider_coverage(provider_id, eligible, disposition, discovery_state, courses_eligible, sources, sources_read, runs_held, root_causes) values
 ('c5c5d225-3d4c-4e41-8275-78eddd261073', true, 'not_discovered', 'not_discovered', 252, 0, 0, 0, '{}'),
 ('030992c3-72c6-452d-8a3b-10ceb0fd77f2', true, 'not_discovered', 'not_discovered', 120, 0, 0, 0, '{}'),
 ('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113', true, 'not_discovered', 'not_discovered', 140, 0, 0, 0, '{}'),
 ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2', true, 'awaiting_layer4', 'source_read', 90, 1, 1, 0, '{}'),
 ('9109fe0c-9f44-4e2d-a136-eb00dec24701', true, 'source_held', 'source_read', 180, 1, 1, 1, '{aer_reader_value_not_printed}'),
 -- a provider never searched: no automatic attempt is recorded, so no person is asked yet (§1 AI-first)
 ('51000000-0000-4000-8000-000000000003', true, 'not_discovered', 'not_discovered', 2, 0, 0, 0, '{}');
-- CDU: six scheduled course reads overnight, no course row (morning measures 4 Nov 2026)
insert into pipeline.aer_schedule_runs(ran_at, detail)
select now() - make_interval(hours => g), jsonb_build_object('new', jsonb_build_array(jsonb_build_object('provider_id', '6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'course_id', 'c0000000-0000-4000-8000-000000000003', 'country', 'AU')))
  from generate_series(1, 6) g;
-- Torrens: a held course read whose page is shared with another programme (parked aer_technical work), with its Layer 4 item
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status, escalation_reason)
values ('e0000000-0000-4000-8000-000000000001', 'course', 'c0000000-0000-4000-8000-000000000001', 'course_entry_first_read', 'pending', 'held');
select security.work_item_report_v1('aer_technical', 'e0000000-0000-4000-8000-000000000001', 'l4_item', 'failed',
  jsonb_build_object('class', 'identity_conflict', 'provider_id', 'fec52f92-a8a3-4de8-a862-06f355e4e2f7', 'message', 'technically held: shared_page',
                     'evidence', jsonb_build_object('blockers', jsonb_build_array(jsonb_build_object('code', 'shared_page', 'why', 'page shared with another programme (Advanced Diploma of UX Design)')))));

-- scholarship coverage cases (as security.scholarship_coverage_classify_v1 keeps them)
insert into pipeline.scholarship_coverage_items(provider_id, item_key, state, reason, evidence, owner) values
 ('51000000-0000-4000-8000-000000000001', 'cand:501', 'international_unresolved', 'international_not_stated',
  '{"candidate_id": 501, "url": "https://www.boxuni.edu.au/scholarships/global-merit", "title": "Global Merit Scholarship", "ai": {"verdict": "scholarship", "audience": null}}', 'Layer 4 reviewer'),
 ('51000000-0000-4000-8000-000000000001', 'reg:R1:77', 'source_not_discovered', 'register_entry_without_candidate: none',
  '{"register": "R1", "name": "Box Excellence Award", "page": "https://www.boxuni.edu.au/scholarships", "host": "boxuni.edu.au"}', 'scholarship discovery'),
 ('51000000-0000-4000-8000-000000000001', 'reg:R1:78', 'ownership_conflict', 'register_page_on_unowned_host',
  '{"register": "R1", "name": "Hotel School Award", "page": "https://www.hotelschool.example.edu.au/award", "host": "hotelschool.example.edu.au", "listed_under": "Box University"}', 'Platform Admin'),
 ('51000000-0000-4000-8000-000000000002', 'provider', 'source_not_discovered', 'discovery done', '{"discovery": "done"}', 'scholarship discovery');
insert into pipeline.scholarship_page_candidates(id, provider_id, url) values (501, '51000000-0000-4000-8000-000000000001', 'https://www.boxuni.edu.au/scholarships/global-merit');
insert into pipeline.scholarship_discovery_providers(provider_id, status, attempts) values ('51000000-0000-4000-8000-000000000001', 'done', 1);

-- the unrelated work the platform must keep doing while people are asked (another lane's eligible items)
select security.work_item_report_v1('ai_extraction', 'c0000000-0000-4000-8000-000000000005:english', 'field_read', 'released', '{}'::jsonb);
