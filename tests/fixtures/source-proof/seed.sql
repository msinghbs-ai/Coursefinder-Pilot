-- Seed for the source-proof and field backlog fixtures: settings as live (3 Nov 2026), three providers (AU university with a search recipe and
-- stored lists, AU hidden, NZ), courses in each state the lane routes, their page bindings and page proofs, and coverage rows.
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values
 ('pipeline', 'course_url.fill_countries', 'Official link countries', 'list', '["NZ", "AU", "CA"]'),
 ('pipeline', 'relink.url_pattern_countries', 'Relink countries', 'list', '["AU", "CA"]'),
 ('pipeline', 'relink.pattern_min_pages', 'Relink min pages', 'number', '10'), ('pipeline', 'relink.pattern_min_share', 'Relink min share', 'number', '0.5')
on conflict (toolset_key, key) do nothing;
insert into ref.countries(id, iso_alpha2) values ('00000000-0000-0000-0000-0000000000a1', 'AU'), ('00000000-0000-0000-0000-0000000000a2', 'NZ');
insert into ref.provider_types(id, code) values ('00000000-0000-0000-0000-0000000000b1', 'university');
insert into catalogue.providers(id, canonical_name, lifecycle_status, website, country_id, provider_type_id, description) values
 ('a1000000-0000-0000-0000-000000000001', 'Uni One', 'active', 'https://u1.example', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', null),
 ('a1000000-0000-0000-0000-000000000002', 'Hidden Two', 'hidden', 'https://h2.example', '00000000-0000-0000-0000-0000000000a1', null, null),
 ('a1000000-0000-0000-0000-000000000003', 'Kiwi Three', 'active', null, '00000000-0000-0000-0000-0000000000a2', null, 'A provider.');
insert into pipeline.course_link_recipes values ('a1000000-0000-0000-0000-000000000001', 'u1.example', true);
insert into pipeline.coverage_provider_urls values ('a1000000-0000-0000-0000-000000000001', 'https://u1.example/study/bachelor-of-applied-science-studies');
insert into catalogue.courses(id, provider_id, canonical_title, course_code) values
 ('c0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'Bachelor of Applied Science Studies', null),
 ('c0000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'Course Two in Review', null),
 ('c0000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000001', 'Course Three Locked', null),
 ('c0000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000001', 'Course Four Reading', null),
 ('c0000000-0000-0000-0000-000000000005', 'a1000000-0000-0000-0000-000000000001', 'Course Five No Page', '012345A'),
 ('c0000000-0000-0000-0000-000000000006', 'a1000000-0000-0000-0000-000000000002', 'Course Six Hidden', null),
 ('c0000000-0000-0000-0000-000000000007', 'a1000000-0000-0000-0000-000000000001', 'Course Seven Exhausted', null),
 ('c0000000-0000-0000-0000-000000000008', 'a1000000-0000-0000-0000-000000000001', 'Course Eight Proven', null),
 ('c0000000-0000-0000-0000-000000000009', 'a1000000-0000-0000-0000-000000000001', 'Course Nine Not Waiting', null),
 ('c0000000-0000-0000-0000-000000000010', 'a1000000-0000-0000-0000-000000000001', 'Course Ten Nowhere', null),
 ('c0000000-0000-0000-0000-000000000011', 'a1000000-0000-0000-0000-000000000003', 'Course Eleven NZ', null);
insert into pipeline.evidence_artifacts(id, storage_path) values ('e0000000-0000-0000-0000-000000000001', 'stored/1.html'), ('e0000000-0000-0000-0000-000000000008', 'stored/8.html');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status, identity_basis, evidence_id, read_attempts, read_at) values
 ('c0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/other-course', 'mismatch', 'identity_mismatch', null, 'e0000000-0000-0000-0000-000000000001', 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/c2', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/c3', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/c4', 'bound', 'fetch_failed', null, null, 1, now() - interval '1 day'),
 ('c0000000-0000-0000-0000-000000000006', 'a1000000-0000-0000-0000-000000000002', 'https://h2.example/c6', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000007', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/c7', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000008', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/c8', 'bound', 'read', 'cricos_code', 'e0000000-0000-0000-0000-000000000008', 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000009', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/c9', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days'),
 ('c0000000-0000-0000-0000-000000000010', 'a1000000-0000-0000-0000-000000000001', 'https://u1.example/c10', 'mismatch', 'identity_mismatch', null, null, 1, now() - interval '9 days');
-- course-relink tried every refused page once (rule 2), and found no address for any (as 9,841 live courses)
insert into pipeline.course_relink(course_id, provider_id, old_url, state, reason, decided_at, rule)
select g.course_id, g.provider_id, g.url, 'absent', 'no address from the university''s address forms or stored lists', now() - interval '8 days', 2
  from pipeline.coverage_course_pages g where g.read_status = 'identity_mismatch';
insert into pipeline.course_link_search(course_id, provider_id, stage, state, done_at) values ('c0000000-0000-0000-0000-000000000010', 'a1000000-0000-0000-0000-000000000001', 'title', 'none', now() - interval '8 days');
insert into pipeline.layer4_review_items(status, entity_type, entity_id, field_code) values ('pending', 'course', 'c0000000-0000-0000-0000-000000000002', 'official_course_url');
insert into pipeline.manual_locks(entity, entity_id, field) values ('course', 'c0000000-0000-0000-0000-000000000003', 'official_url');
-- the gap queue's page proofs: every course but c08 (proven) and c09 (no page-only gap) waits for page proof
insert into pipeline.course_page_proofs(course_id, page_key, proven, checked_at)
select c.id, security.course_page_key_v1(c.id), c.id = 'c0000000-0000-0000-0000-000000000008', now() - interval '1 hour'
  from catalogue.courses c where c.id <> 'c0000000-0000-0000-0000-000000000009';
-- coverage cache (pipeline.course_attribute_coverage) for the backlog
insert into pipeline.course_attribute_coverage(course_id, provider_id, attribute, state, tier, country_code)
select c.id, c.provider_id, a.attribute,
       case when a.attribute = 'intakes' then case c.id when 'c0000000-0000-0000-0000-000000000001' then 'not_on_page' when 'c0000000-0000-0000-0000-000000000002' then 'in_review'
                                                          when 'c0000000-0000-0000-0000-000000000005' then 'admitted' else 'site_known' end
            when a.attribute = 'academic_entry' then 'no_reader'
            when a.attribute = 'duration' then 'admitted' else 'no_reader' end,
       'core', case when c.provider_id = 'a1000000-0000-0000-0000-000000000003' then 'NZ' else 'AU' end
  from catalogue.courses c cross join (values ('intakes'), ('description'), ('academic_entry'), ('duration')) a(attribute);
update pipeline.course_attribute_coverage set state = 'site_known' where attribute = 'duration' and course_id = 'c0000000-0000-0000-0000-000000000004';
insert into pipeline.aer_course_outcomes values ('c0000000-0000-0000-0000-000000000005', 'excluded'), ('c0000000-0000-0000-0000-000000000004', 'awaiting_review');
-- Enrich fields items: c01's description was read and not stated; c05's intakes were filled two hours ago
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, updated_at, reason) values
 (gen_random_uuid(), 'a1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'description', 'skipped', now() - interval '3 days', 'the page does not state it'),
 (gen_random_uuid(), 'a1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000005', 'intakes', 'filled', now() - interval '2 hours', null),
 (gen_random_uuid(), 'a1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000004', 'intakes', 'skipped', now() - interval '3 days', 'no correct course page: the page found is for another course'),
 (gen_random_uuid(), 'a1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000007', 'description', 'skipped', now() - interval '3 days', 'no correct course page: the page found is for another course');
update pipeline.field_enrich_items set state = 'review', updated_at = now() - interval '1 hour' where course_id = 'c0000000-0000-0000-0000-000000000004' and field = 'intakes';
