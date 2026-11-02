-- IQ-00043: the shared fixture data, then the defect reproduced on the live definitions (rolled back). Prints "defect <case>".
\set ON_ERROR_STOP 1
insert into ref.countries(id, iso_alpha2) values ('00000000-0000-0000-0000-0000000000aa', 'AU');
insert into pipeline.coverage_admission_countries values ('00000000-0000-0000-0000-0000000000aa', true, 'AUD');
insert into catalogue.providers(id, country_id, canonical_name) values ('00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-0000000000aa', 'Fixture University');
insert into pipeline.sources(id, source_type, status) values
  ('00000000-0000-0000-0000-00000000005a', 'provider_course_page_sweep', 'active'),
  ('00000000-0000-0000-0000-00000000005b', 'layer4_human_review', 'active'),
  ('00000000-0000-0000-0000-00000000005c', 'web', 'retired');
insert into pipeline.evidence_artifacts(id, content_hash) values ('00000000-0000-0000-0000-0000000000ee', 'h');
-- courses c01..c14
insert into catalogue.courses(id, provider_id, course_code) select ('00000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid, '00000000-0000-0000-0000-0000000000bb', 'C' || n
  from generate_series(1, 14) n;
-- c01 the La Trobe pattern: the kept page (primary) and its fragment spelling set inactive by the link tranche (event as #28622)
insert into catalogue.course_links(id, course_id, link_type, url, is_primary, status, source_id, updated_at) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'official_course', 'https://www.latrobe.edu.au/courses/bachelor-of-it', true, 'active', '00000000-0000-0000-0000-00000000005a', now()),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'official_course', 'https://www.latrobe.edu.au/courses/bachelor-of-it#/overview?studentType=int', false, 'inactive', '00000000-0000-0000-0000-00000000005a', '2026-11-02 04:57:00+00');
insert into pipeline.admin_control_events(area, action, target, detail, created_at) values
  ('housekeeping', 'h01_duplicate_link_tranche', 'catalogue.course_links', '{"made_inactive":["10000000-0000-0000-0000-000000000002"]}', '2026-11-02 04:57:26+00');
-- c02 a page replaced by another page (the old page inactive), c03 an open remediation hold (link unverified), c04 a pending Layer 4 review on
-- an unverified link, c05 an unverified link with no decision (a dead page that came back), c06 a Layer 4 decision that kept the page we hold,
-- c07 a page rejection of the bare catalogue listing (query-addressed site), c08 a lock, c09 a retired (deprecated) link, c10 a new page
insert into catalogue.course_links(id, course_id, link_type, url, is_primary, status, source_id) values
  ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'official_course', 'https://uni.example/2026/program/new', true, 'active', '00000000-0000-0000-0000-00000000005b'),
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'official_course', 'https://uni.example/2020/program/old', false, 'inactive', '00000000-0000-0000-0000-00000000005a'),
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'official_course', 'https://uni.example/held', false, 'unverified', '00000000-0000-0000-0000-00000000005a'),
  ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'official_course', 'https://uni.example/c4', false, 'unverified', '00000000-0000-0000-0000-00000000005a'),
  ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000005', 'official_course', 'https://uni.example/c5', false, 'unverified', '00000000-0000-0000-0000-00000000005a'),
  ('60000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000006', 'official_course', 'https://uni.example/c6-kept', true, 'active', '00000000-0000-0000-0000-00000000005a'),
  ('80000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000008', 'official_course', 'https://uni.example/c8-set-by-hand', true, 'active', '00000000-0000-0000-0000-00000000005b'),
  ('80000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000008', 'official_course', 'https://uni.example/c8-old', false, 'inactive', '00000000-0000-0000-0000-00000000005a'),
  ('90000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000009', 'official_course', 'https://uni.example/c9-retired', false, 'deprecated', '00000000-0000-0000-0000-00000000005a');
insert into pipeline.course_remediation_holds(course_id, url) values ('00000000-0000-0000-0000-000000000003', 'https://uni.example/held');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, proposed_value, before_value) values
  ('course', '00000000-0000-0000-0000-000000000004', 'official_course_url', 'pending', '{"course_url":"https://uni.example/c4-other"}', '["https://uni.example/c4"]');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, proposed_value, before_value, decided_at) values
  ('course', '00000000-0000-0000-0000-000000000006', 'official_course_url', 'rejected', '{"course_url":"https://uni.example/c6-proposed"}', '["https://uni.example/c6-kept"]', now() - interval '1 day');
insert into pipeline.page_rejections(course_id, url, source, reason) values
  ('00000000-0000-0000-0000-000000000007', 'https://study.auckland.ac.nz/ords/r/uoa/catalogue/program', 'binding_check', 'shared listing page'),
  ('00000000-0000-0000-0000-000000000007', 'https://uni.example/c7-wrong-variant', 'e16_containment', 'variant');
insert into pipeline.manual_locks(entity, entity_id, field) values ('course', '00000000-0000-0000-0000-000000000008', 'official_url');
select search.refresh_course_enrichment_scoped_v1(array(select id from catalogue.courses), true);

-- the defect on the live definitions: the common admission write re-activates the superseded fragment spelling (exit-awards-apply at :37)
begin;
do $c$ declare r jsonb; begin
  r := security.coverage_apply_course_v1('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-0000000000ee',
         'https://www.latrobe.edu.au/courses/bachelor-of-it#/overview?studentType=int', 'h', '{"course_url":"https://www.latrobe.edu.au/courses/bachelor-of-it#/overview?studentType=int"}');
  if (select status from catalogue.course_links where id = '10000000-0000-0000-0000-000000000002') <> 'active' then raise exception 'defect not reproduced: %', r; end if;
  if (select count(*) from catalogue.course_links where course_id = '00000000-0000-0000-0000-000000000001' and status = 'active') <> 2 then raise exception 'defect: count'; end if;
  raise notice 'defect superseded: the live coverage_apply_course_v1 sets the tranche''s inactive fragment link active again (two active links)';
end $c$;
do $c$ begin
  perform security.coverage_apply_course_v1('00000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-0000000000ee',
         'https://uni.example/c6-proposed', 'h', '{"course_url":"https://uni.example/c6-proposed"}');
  if (select status from catalogue.course_links where course_id = '00000000-0000-0000-0000-000000000006' and url = 'https://uni.example/c6-proposed') <> 'active' then raise exception 'defect 2 not reproduced'; end if;
  raise notice 'defect rejected: the live write admits a page a Layer 4 decision rejected';
end $c$;
rollback;
