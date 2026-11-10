insert into ref.countries values (1, 'AU', 'Australia'), (2, 'NZ', 'New Zealand');
insert into pipeline.platform_toolset_settings values
  ('pipeline', 'aer.schedule_layer4_max', '10'), ('pipeline', 'batch.aer_schedule_courses', '20'), ('pipeline', 'aer.schedule_daily_max', '200'),
  ('pipeline', 'central.min_suggest_score', '4'), ('pipeline', 'aer.source_stored_find_on', '0'), ('pipeline', 'wc.aer_fair_on', '0');
insert into security.roles values ('platform_admin', 7, 'active');
insert into pipeline.field_gap_queue_control values (1, '00000000-0000-0000-0000-0000000000aa');
insert into security.user_roles values ('00000000-0000-0000-0000-0000000000aa', 'platform_admin', null);
insert into cron.job(jobname, schedule, active) values ('aer-scheduled-read', '13 * * * *', true), ('aer-source-stored-find', '37 * * * *', false), ('entry-matrix-read', '4-59/5 * * * *', true), ('aer-replay', '33 * * * *', true);
-- providers: id prefix tells the story
insert into catalogue.providers(id, canonical_name, website, country_id) values
  ('10000000-0000-0000-0000-000000000001', 'P1 course pages waiting', 'https://p1.edu.au', 1),
  ('10000000-0000-0000-0000-000000000002', 'P2 stored entry page', 'https://p2.edu.au', 1),
  ('10000000-0000-0000-0000-000000000003', 'P3 title matched only', 'https://p3.edu.au', 1),
  ('10000000-0000-0000-0000-000000000004', 'P4 nothing stored', 'https://p4.edu.au', 2),
  ('10000000-0000-0000-0000-000000000005', 'P5 weak page', 'https://p5.edu.au', 2),
  ('10000000-0000-0000-0000-000000000006', 'P6a shared host', 'https://shared.edu.au', 1),
  ('10000000-0000-0000-0000-000000000007', 'P6b shared host', 'https://shared.edu.au', 1),
  ('10000000-0000-0000-0000-000000000008', 'P7 has a source', 'https://p7.edu.au', 1),
  ('10000000-0000-0000-0000-000000000009', 'P8 link on another host', 'https://p8.edu.au', 1);
insert into pipeline.entry_matrix_sources(provider_id, url, status) values ('10000000-0000-0000-0000-000000000008', 'https://p7.edu.au/entry', 'read');
insert into pipeline.evidence_artifacts(id, storage_path) values ('20000000-0000-0000-0000-000000000001', 'x/1'), ('20000000-0000-0000-0000-000000000002', 'x/2');
-- P1: three courses with a stored, confidently matched page; P3: two courses matched by title only
insert into catalogue.courses(id, provider_id, canonical_title) select ('30000000-0000-0000-0000-00000000000' || g)::uuid, '10000000-0000-0000-0000-000000000001', 'P1 course ' || g from generate_series(1, 3) g;
insert into catalogue.courses(id, provider_id, canonical_title) select ('31000000-0000-0000-0000-00000000000' || g)::uuid, '10000000-0000-0000-0000-000000000003', 'P3 course ' || g from generate_series(1, 2) g;
insert into pipeline.coverage_course_pages select c.id, 'bound', '20000000-0000-0000-0000-000000000001', 'cricos_code' from catalogue.courses c where c.provider_id = '10000000-0000-0000-0000-000000000001';
insert into pipeline.coverage_course_pages select c.id, 'bound', '20000000-0000-0000-0000-000000000002', 'exact_title' from catalogue.courses c where c.provider_id = '10000000-0000-0000-0000-000000000003';
-- stored links
insert into pipeline.coverage_provider_urls(provider_id, url, title) values
  ('10000000-0000-0000-0000-000000000002', 'https://www.p2.edu.au/international/entry-requirements-by-country', null),
  ('10000000-0000-0000-0000-000000000005', 'https://p5.edu.au/study/entry-requirements', null),
  ('10000000-0000-0000-0000-000000000006', 'https://shared.edu.au/international/academic-entry-requirements', null),
  ('10000000-0000-0000-0000-000000000009', 'https://elsewhere.org/international/academic-entry-requirements', null);
insert into pipeline.provider_discovery_links(provider_id, url, anchor_text) values ('10000000-0000-0000-0000-000000000004', 'https://p4.edu.au/news/open-day', 'Open day');
