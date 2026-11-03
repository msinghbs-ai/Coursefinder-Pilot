-- CF-247 D7: the Swinburne shape found live on 3 Nov 2026 22:16 AEDT (088407E bound by exact title to the page that states 095881J), as small
-- fixtures. Courses c…, one provider. Nothing here is live data.
-- the E16 title and level check is not what is tested here (its own fixture tests it): off, so only this guard decides
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'binding.identity_check', '0') on conflict do nothing;
update pipeline.platform_toolset_settings set value = '0' where key = 'binding.identity_check';
insert into catalogue.providers(id, stable_key, canonical_name, website) values ('a0000000-0000-0000-0000-000000000001', 'swin', 'Swinburne University of Technology', 'https://www.swinburne.edu.au');
insert into catalogue.courses(id, provider_id, canonical_title, course_code) values
 ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Bachelor of Information and Communication Technology (Professional)', '088407E'),
 ('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Bachelor of Information and Communication Technology (Professional)', '095881J'),
 ('c0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Bachelor of Design', '111111A'),
 ('c0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Bachelor of ICT (Online)', '222222B'),
 ('c0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'Bachelor of ICT (Professional) (Honours)', '333333C'),
 ('c0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001', 'Bachelor of ICT (Professional) Pathway', '444444D'),
 ('c0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000001', 'Bachelor of ICT (Professional) Accelerated', '555555E');
insert into pipeline.manual_locks(entity, entity_id, field) values ('course', 'c0000000-0000-0000-0000-000000000005', 'official_url');
insert into pipeline.evidence_artifacts(id, source_url, content_hash, metadata) values
 ('e0000000-0000-0000-0000-000000000001', 'https://www.swinburne.edu.au/course/undergraduate/bict-professional/', 'sha1', '{"course_id": "c0000000-0000-0000-0000-000000000002", "identity_basis": "cricos_code"}'),
 ('e0000000-0000-0000-0000-000000000002', 'https://www.swinburne.edu.au/course/undergraduate/bict-professional', 'sha1', '{"course_id": "c0000000-0000-0000-0000-000000000002", "identity_basis": "cricos_code"}');
-- bindings as they stand (the guard is off while they are written)
insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status, identity_basis, evidence_id, candidates) values
 ('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'https://www.swinburne.edu.au/course/undergraduate/bict-professional', 'cricos_code_on_page', 'bound', 'read', 'cricos_code', 'e0000000-0000-0000-0000-000000000002', '{"text_sha": "sha1"}'),
 ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'https://www.swinburne.edu.au/course/undergraduate/bict-professional/', 'title_search', 'bound', 'read', 'exact_title', 'e0000000-0000-0000-0000-000000000001', '{"text_sha": "sha1"}'),
 ('c0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'https://online.swinburne.edu.au/bict', 'title_search', 'bound', 'read', 'title_level', null, '{"text_sha": "sha1"}'),
 ('c0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'https://www.swinburne.edu.au/course/undergraduate/design', 'title_search', 'bound', 'read', 'exact_title', null, '{"text_sha": "sha3"}'),
 ('c0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'https://www.swinburne.edu.au/course/undergraduate/bict-professional', 'title_search', 'bound', 'read', 'exact_title', null, '{"text_sha": "sha1"}');
