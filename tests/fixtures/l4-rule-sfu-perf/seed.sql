-- CF-247 rule executor bounded: five more Simon Fraser items for the strict rule sfu_no_term (after the Layer 4 course-link fixture and v2.15.448).
-- c40 slow (its level reading is made slow in fixtures.sql), c41 and c42 pass, c43 the page shows no level, c44 the page is for another level.
insert into ref.study_levels(id, code) values ('51000000-0000-0000-0000-000000000001', 'bachelor'), ('51000000-0000-0000-0000-000000000002', 'masters') on conflict do nothing;
update pipeline.platform_toolset_settings set value = '0' where key = 'layer4.evidence_link_on';
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'binding.level_patterns',
  '["M=\\mmasters?\\M|\\mmba\\M|(^|/)m[cr]-[a-z]|[-/]m[cr][0-9]{3}([-/]|$)", "B=\\mbachelors?\\M|(^|/)b-[a-z]"]') on conflict do nothing;
insert into catalogue.courses(id, provider_id, canonical_title, course_code, lifecycle_status, open_to_international, study_level_id)
select ('c0000000-0000-0000-0000-0000000000' || n)::uuid, 'd47b6006-396a-4785-b2ae-15186c3e7709', t, null, 'active', true, ('51000000-0000-0000-0000-00000000000' || l)::uuid
  from (values (40, 'Bachelor of Arts in History', 1), (41, 'Bachelor of Arts in English', 1), (42, 'Bachelor of Science in Physics', 1),
               (43, 'Bachelor of Arts in Dance', 1), (44, 'Master of Science in Physics', 2)) v(n, t, l);
insert into pipeline.evidence_artifacts(id, source_id, source_url, content_hash, captured_at, metadata)
select ('e0000000-0000-0000-0000-0000000000' || n)::uuid, 'b0000000-0000-0000-0000-000000000001', 'https://www.sfu.ca/students/calendar/programs/c' || n || '/p.html', 'h' || n,
       now() - interval '1 day', jsonb_build_object('course_id', 'c0000000-0000-0000-0000-0000000000' || n, 'identity_basis', 'field_award')
  from generate_series(40, 44) n;
insert into catalogue.course_links(course_id, link_type, url, is_primary, status)
select ('c0000000-0000-0000-0000-0000000000' || n)::uuid, 'official_course', 'https://www.sfu.ca/students/calendar/2026/fall/programs/c' || n || '/p.html', true, 'active' from generate_series(40, 44) n;
-- the page's read title (the binding check's title source): Bachelor pages, except c43 (no title) and c44 (a Bachelor page for a Master)
insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status, identity_basis, candidates)
select ('c0000000-0000-0000-0000-0000000000' || n)::uuid, 'd47b6006-396a-4785-b2ae-15186c3e7709', 'https://www.sfu.ca/students/calendar/programs/c' || n || '/p.html',
       'title_search', 'bound', 'read', 'field_award', case when n = 43 then '{}'::jsonb else jsonb_build_object('page_title', 'Bachelor of ' || n || ' - Simon Fraser University') end
  from generate_series(40, 44) n
on conflict (course_id) do nothing;
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, before_value, proposed_value, layer2_state, status, escalation_reason, created_at)
select ('10000000-0000-0000-0000-0000000000' || n)::uuid, 'course', ('c0000000-0000-0000-0000-0000000000' || n)::uuid, 'official_course_url',
       jsonb_build_array('https://www.sfu.ca/students/calendar/2026/fall/programs/c' || n || '/p.html'),
       jsonb_build_object('course_url', 'https://www.sfu.ca/students/calendar/programs/c' || n || '/p.html'), '{"source": "coverage sweep"}', 'pending',
       'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.', now() - interval '2 days'
  from generate_series(40, 44) n;
update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.evidence_link_on';
