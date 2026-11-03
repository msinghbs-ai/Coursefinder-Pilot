-- CF-247 IQ-00189: three more Simon Fraser items for sfu_no_term (after ../l4-rule-sfu-perf/seed.sql). c50 holds and proposes http:// addresses
-- (the live shape: http://www.sfu.ca/students/calendar/2026/fall/programs/...), c51 https://, c52 an address that is not a web address even with
-- https:// (a space in it). Each course's level is on its page and each has a current stored copy.
update pipeline.platform_toolset_settings set value = '0' where key = 'layer4.evidence_link_on';
insert into catalogue.courses(id, provider_id, canonical_title, course_code, lifecycle_status, open_to_international, study_level_id)
select ('c0000000-0000-0000-0000-0000000000' || n)::uuid, 'd47b6006-396a-4785-b2ae-15186c3e7709', 'Bachelor of Arts in Subject ' || n, null, 'active', true, '51000000-0000-0000-0000-000000000001'::uuid
  from generate_series(50, 52) n;
create temp table fx_u as select n, case n when 50 then 'http://www.sfu.ca/students/calendar/' when 51 then 'https://www.sfu.ca/students/calendar/' else 'http://www.sfu.ca/students/calendar/' end base,
  case n when 52 then 'programs/c52/p q.html' else 'programs/c' || n || '/p.html' end tail from generate_series(50, 52) n;
insert into pipeline.evidence_artifacts(id, source_id, source_url, content_hash, captured_at, metadata)
select ('e0000000-0000-0000-0000-0000000000' || n)::uuid, 'b0000000-0000-0000-0000-000000000001', base || tail, 'h' || n,
       now() - interval '1 day', jsonb_build_object('course_id', 'c0000000-0000-0000-0000-0000000000' || n, 'identity_basis', 'field_award') from fx_u;
insert into catalogue.course_links(course_id, link_type, url, is_primary, status)
select ('c0000000-0000-0000-0000-0000000000' || n)::uuid, 'official_course', base || '2026/fall/' || tail, true, 'active' from fx_u;
insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status, identity_basis, candidates)
select ('c0000000-0000-0000-0000-0000000000' || n)::uuid, 'd47b6006-396a-4785-b2ae-15186c3e7709', base || tail, 'title_search', 'bound', 'read', 'field_award',
       jsonb_build_object('page_title', 'Bachelor of Arts ' || n || ' - Simon Fraser University') from fx_u
on conflict (course_id) do nothing;
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, before_value, proposed_value, layer2_state, status, escalation_reason, created_at)
select ('10000000-0000-0000-0000-0000000000' || n)::uuid, 'course', ('c0000000-0000-0000-0000-0000000000' || n)::uuid, 'official_course_url',
       jsonb_build_array(base || '2026/fall/' || tail), jsonb_build_object('course_url', base || tail), '{"source": "coverage sweep"}', 'pending',
       'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.', now() - interval '2 days'
  from fx_u;
update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.evidence_link_on';
