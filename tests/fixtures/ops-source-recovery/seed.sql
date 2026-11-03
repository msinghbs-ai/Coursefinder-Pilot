-- Seed for the workstream B source recovery fixtures: settings as live (3 Nov 2026 15:43 AEDT, with proof.feed_per_run 1 so capacity runs out
-- in the fixture), one AU university with a search recipe and stored lists, and one course for each recovery case.
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values
 ('pipeline', 'course_url.fill_countries', 'Official link countries', 'list', '["NZ", "AU", "CA"]'),
 ('pipeline', 'relink.url_pattern_countries', 'Relink countries', 'list', '["AU", "CA"]'),
 ('pipeline', 'relink.pattern_min_pages', 'Relink min pages', 'number', '10'), ('pipeline', 'relink.pattern_min_share', 'Relink min share', 'number', '0.5'),
 ('pipeline', 'proof.feed_per_run', 'Free per run', 'number', '1'), ('pipeline', 'proof.search_per_run', 'Paid per run', 'number', '0'),
 ('pipeline', 'proof.max_attempts', 'Tries', 'number', '3'), ('pipeline', 'proof.scan_per_run', 'Scan', 'number', '2000'), ('pipeline', 'proof.request_hold_days', 'Hold', 'number', '7')
on conflict (toolset_key, key) do nothing;
insert into catalogue.providers(id, canonical_name, website) values ('a1000000-0000-0000-0000-000000000001', 'Uni One', 'https://u1.example');
insert into pipeline.course_link_recipes values ('a1000000-0000-0000-0000-000000000001', 'u1.example', true);
insert into pipeline.coverage_provider_urls(provider_id, url, title) values
 ('a1000000-0000-0000-0000-000000000001', 'https://u1.example/study/bachelor-of-te-reo-maori', 'Bachelor of Te Reo Maori | Uni One'),
 ('a1000000-0000-0000-0000-000000000001', 'http://u1.example/study/ba-arts-studies-program', null),
 ('a1000000-0000-0000-0000-000000000001', 'https://u1.example/programs/nursing-master-of-science', null);
insert into catalogue.courses(id, provider_id, canonical_title, course_code) values
 ('c0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'Course One Mismatch', null),
 ('c0000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'Course Two Mismatch', null),
 ('c0000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000001', 'Course Three Refused By Check', null),
 ('c0000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000001', 'Bachelor of Te Reo Māori (Level 7)', null),
 ('c0000000-0000-0000-0000-000000000005', 'a1000000-0000-0000-0000-000000000001', 'Course Five Read Blocked', null),
 ('c0000000-0000-0000-0000-000000000006', 'a1000000-0000-0000-0000-000000000001', 'Course Six Searched Before', null),
 ('c0000000-0000-0000-0000-000000000007', 'a1000000-0000-0000-0000-000000000001', 'Course Seven Old Handbook', null),
 ('c0000000-0000-0000-0000-000000000008', 'a1000000-0000-0000-0000-000000000001', 'Course Eight Proven', null),
 ('c0000000-0000-0000-0000-000000000009', 'a1000000-0000-0000-0000-000000000001', 'Course Nine Layer Four', null),
 ('c0000000-0000-0000-0000-000000000010', 'a1000000-0000-0000-0000-000000000001', 'Course Ten Locked', null),
 ('c0000000-0000-0000-0000-000000000011', 'a1000000-0000-0000-0000-000000000001', 'Course Eleven Nothing Left', null),
 ('c0000000-0000-0000-0000-000000000012', 'a1000000-0000-0000-0000-000000000001', 'Course Twelve No Page', '012345A'),
 ('c0000000-0000-0000-0000-000000000013', 'a1000000-0000-0000-0000-000000000001', 'Ba Arts Studies Program', null),
 ('c0000000-0000-0000-0000-000000000014', 'a1000000-0000-0000-0000-000000000001', 'Nursing: Master of Science (MSN) - UBCO', null),
 ('c0000000-0000-0000-0000-000000000015', 'a1000000-0000-0000-0000-000000000001', 'Course Fifteen Stored Candidates', null);
insert into pipeline.evidence_artifacts(id, storage_path) values ('e0000000-0000-0000-0000-000000000008', 'stored/8.html');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status, identity_basis, evidence_id, read_attempts, read_at) values
 ('c0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/other-1', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/other-2', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/other-3', 'mismatch', 'identity_refused', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/other-4', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000005', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/c5', 'bound', 'fetch_failed', null, null, 3, now() - interval '2 days'),
 ('c0000000-0000-0000-0000-000000000006', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/other-6', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000007', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/handbook/2022/courses/X7', 'mismatch', 'identity_refused', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000008', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/c8', 'bound', 'read', 'cricos_code', 'e0000000-0000-0000-0000-000000000008', 1, now() - interval '1 day'),
 ('c0000000-0000-0000-0000-000000000009', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/other-9', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000010', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/other-10', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000011', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/other-11', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000013', 'a1000000-0000-0000-0000-000000000001', 'https://www.u1.example/study/ba-arts-studies-program/', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000014', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/other-14', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000015', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/c15', 'bound', 'too_thin', null, null, 3, now() - interval '2 days');
-- the gap queue's page proofs (every case but 12, which has no proof row: its absence is the only record of it)
insert into pipeline.course_page_proofs(course_id, page_key, proven)
select g.course_id, security.course_page_key_v1(g.course_id), g.course_id = 'c0000000-0000-0000-0000-000000000008' from pipeline.coverage_course_pages g;
-- course-relink tried these once (rule 2) and found no address; 1, 2, 3 and 7 were never relinked
insert into pipeline.course_relink(course_id, provider_id, old_url, state, reason, decided_at, rule)
select g.course_id, g.provider_id, g.url, 'absent', 'no address from the university''s address forms or stored lists', now() - interval '5 days', 2
  from pipeline.coverage_course_pages g where g.course_id in ('c0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-000000000011',
                                                             'c0000000-0000-0000-0000-000000000014');
-- course 6 and 11 were searched before (paid); 6's search left candidates b and c untried, c was since rejected for the course
insert into pipeline.course_link_search(course_id, provider_id, stage, state, candidates, cand_idx, done_at) values
 ('c0000000-0000-0000-0000-000000000006', 'a1000000-0000-0000-0000-000000000001', 'title', 'none', '["https://u1.example/cand-a", "https://u1.example/cand-b", "https://u1.example/cand-c/"]', 1, now() - interval '6 days'),
 ('c0000000-0000-0000-0000-000000000011', 'a1000000-0000-0000-0000-000000000001', 'title', 'none', '["https://u1.example/other-11"]', 1, now() - interval '6 days'),
 ('c0000000-0000-0000-0000-000000000015', 'a1000000-0000-0000-0000-000000000001', 'title', 'none', '["https://u1.example/c15", "https://u1.example/c15-alt"]', 1, now() - interval '6 days');
insert into pipeline.page_rejections(course_id, url, provider_id, source, reason) values
 ('c0000000-0000-0000-0000-000000000006', 'https://U1.example/cand-c', 'a1000000-0000-0000-0000-000000000001', 'binding_check', 'another course');
insert into pipeline.firecrawl_calls(at, use_case, endpoint, course_id, credits_used, outcome) values
 (now() - interval '6 days', 'find_page', 'search', 'c0000000-0000-0000-0000-000000000006', 2, 'provider_site_no_title_match'),
 (now() - interval '6 days', 'find_page', 'search', 'c0000000-0000-0000-0000-000000000011', 2, 'provider_site_no_title_match'),
 (now() - interval '5 days', 'find_page', 'search', 'c0000000-0000-0000-0000-000000000011', 2, 'provider_site_no_title_match'),
 (now() - interval '6 days', 'find_page', 'search', 'c0000000-0000-0000-0000-000000000008', 2, 'found_on_provider_site'),
 (now() - interval '6 days', 'read_page', 'scrape', 'c0000000-0000-0000-0000-000000000008', 1, 'read_course_page');
insert into pipeline.course_link_search(course_id, provider_id, stage, state) values ('c0000000-0000-0000-0000-000000000008', 'a1000000-0000-0000-0000-000000000001', 'title', 'verified');
insert into pipeline.layer4_review_items(entity_id, field_code) values ('c0000000-0000-0000-0000-000000000009', 'official_course_url');
insert into pipeline.manual_locks values ('course', 'c0000000-0000-0000-0000-000000000010', 'official_url');
insert into pipeline.course_field_absence(course_id, field, absence_class, reason) values
 ('c0000000-0000-0000-0000-000000000012', 'intakes', 'needs_source_discovery', 'no allowed source had a value'),
 ('c0000000-0000-0000-0000-000000000004', 'intakes', 'identity_unresolved', 'no correct course page: the page found is for another course');
