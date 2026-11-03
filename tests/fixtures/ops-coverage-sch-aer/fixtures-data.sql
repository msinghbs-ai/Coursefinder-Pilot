-- Workstream C fixture data (shapes as live on 3 Nov 2026; names are fixture names). AU and NZ scholarship countries; AER countries AU, NZ.
insert into ref.countries(id, iso_alpha2, name) values ('a0000000-0000-0000-0000-0000000000a1', 'AU', 'Australia'), ('a0000000-0000-0000-0000-0000000000a2', 'NZ', 'New Zealand');
insert into ref.provider_types(id, code, name) values ('b0000000-0000-0000-0000-000000000001', 'university', 'University'), ('b0000000-0000-0000-0000-000000000002', 'private_vet', 'Private VET'),
  ('b0000000-0000-0000-0000-000000000003', 'school', 'School'), ('b0000000-0000-0000-0000-000000000004', 'higher_education_institute', 'HE institute');
insert into ref.study_levels(id, code, name) values ('c0000000-0000-0000-0000-000000000001', 'bachelor', 'Bachelor'), ('c0000000-0000-0000-0000-000000000002', 'masters_coursework', 'Masters (Coursework)'),
  ('c0000000-0000-0000-0000-000000000003', 'doctorate', 'Doctorate');
-- providers: d..01 small private VET (5 courses, AU: refused), d..02 AU university (40 courses), d..03 AU school (mapped, refused), d..04 AU private VET mapped
-- recently (refused, not due), d..05 unpublished AU VET (pending), d..06 leased refused VET, d..07 AU university with zero scholarships, d..08 NZ university
-- (AER: enrols_international not recorded), d..09 AU university with domestic-only course requirements, d..10 AU private VET (AER: no source, grouped)
insert into catalogue.providers(id, display_name, country_id, provider_type_id, publication_status, enrols_international, website) values
  ('d0000000-0000-0000-0000-000000000001', 'Small VET College', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000002', 'published', true, 'https://smallvet.example.edu.au'),
  ('d0000000-0000-0000-0000-000000000002', 'Harbour University', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000001', 'published', true, 'https://harbour.example.edu.au'),
  ('d0000000-0000-0000-0000-000000000003', 'Hills Grammar', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000003', 'published', true, 'https://hills.example.edu.au'),
  ('d0000000-0000-0000-0000-000000000004', 'Coast VET', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000002', 'published', true, 'https://coastvet.example.edu.au'),
  ('d0000000-0000-0000-0000-000000000005', 'Hidden VET', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000002', 'unpublished', true, 'https://hiddenvet.example.edu.au'),
  ('d0000000-0000-0000-0000-000000000006', 'Leased VET', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000002', 'published', true, 'https://leasedvet.example.edu.au'),
  ('d0000000-0000-0000-0000-000000000007', 'Plains University', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000001', 'published', true, 'https://plains.example.edu.au'),
  ('d0000000-0000-0000-0000-000000000008', 'Fiord University', 'a0000000-0000-0000-0000-0000000000a2', 'b0000000-0000-0000-0000-000000000001', 'published', null, 'https://fiord.example.ac.nz'),
  ('d0000000-0000-0000-0000-000000000009', 'River University', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000001', 'published', true, 'https://river.example.edu.au'),
  ('d0000000-0000-0000-0000-000000000010', 'Valley VET', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000002', 'published', true, 'https://valleyvet.example.edu.au');
-- courses (every one 'unpublished', as live): 5 at d..01, 40 at d..02, 10 at d..09, 2 at d..10; d..03..06 have none
insert into catalogue.courses(provider_id, canonical_title, publication_status, open_to_international)
select p, 'Course ' || g, 'unpublished', true from (values ('d0000000-0000-0000-0000-000000000001'::uuid, 5), ('d0000000-0000-0000-0000-000000000002', 40),
  ('d0000000-0000-0000-0000-000000000009', 10), ('d0000000-0000-0000-0000-000000000010', 2), ('d0000000-0000-0000-0000-000000000007', 35)) v(p, n), generate_series(1, v.n) g;

-- scholarship discovery rows (the IQ-00041 shape: pending with 0 attempts, pushed by the picker's 6-hour hold)
insert into pipeline.scholarship_discovery_providers(provider_id, website, status, reason, attempts, next_discover_at, discovered_at, updated_at, leased_until) values
  ('d0000000-0000-0000-0000-000000000001', 'https://smallvet.example.edu.au', 'pending', 'on_demand', 0, now() + interval '5 hours', null, '2026-10-13', null),
  ('d0000000-0000-0000-0000-000000000002', 'https://harbour.example.edu.au', 'mapped', 'largest_unsearched', 1, now() + interval '20 days', now() - interval '10 days', '2026-10-24', null),
  ('d0000000-0000-0000-0000-000000000003', 'https://hills.example.edu.au', 'mapped', 'on_demand', 1, now() + interval '4 hours', now() - interval '40 days', '2026-09-29', null),
  ('d0000000-0000-0000-0000-000000000004', 'https://coastvet.example.edu.au', 'empty', 'on_demand', 1, now() + interval '25 days', now() - interval '5 days', '2026-10-29', null),
  ('d0000000-0000-0000-0000-000000000005', 'https://hiddenvet.example.edu.au', 'pending', 'on_demand', 0, now() + interval '3 hours', null, '2026-10-18', null),
  ('d0000000-0000-0000-0000-000000000006', 'https://leasedvet.example.edu.au', 'pending', 'on_demand', 0, now() - interval '1 hour', null, '2026-10-18', now() + interval '4 minutes'),
  ('d0000000-0000-0000-0000-000000000007', 'https://plains.example.edu.au', 'empty', 'largest_unsearched', 1, now() + interval '20 days', now() - interval '10 days', '2026-10-24', null),
  ('d0000000-0000-0000-0000-000000000009', 'https://river.example.edu.au', 'pending', 'on_demand', 0, now() + interval '2 hours', null, '2026-10-30', null);

-- scholarships of Harbour University (d..02): the national register lists 10 (6 postgraduate, 4 undergraduate); a listing page holds 3 items, never fanned out
insert into scholarship.register_listings(register_code, listing_id, provider_id, name, level_text, scholarship_id)
select 'au_study_australia', 'H' || g, 'd0000000-0000-0000-0000-000000000002', 'Harbour Award ' || g, case when g <= 6 then 'Postgraduate' else 'Undergraduate / VET' end, null
  from generate_series(1, 10) g;
insert into pipeline.scholarship_listing_pages(provider_id, url, source, active, status, read_at, items) values
  ('d0000000-0000-0000-0000-000000000002', 'https://harbour.example.edu.au/scholarships', 'manual', true, 'read', now() - interval '2 days',
   '[{"name": "Harbour Research Stipend", "url": "https://harbour.example.edu.au/s/1"}, {"name": "Harbour PhD Top-up", "url": "https://harbour.example.edu.au/s/2"}, {"name": "Harbour International Merit", "url": "https://harbour.example.edu.au/s/3"}]');
insert into scholarship.scholarships(id, provider_id, name, audience, award_value_type, award_amount, application_close_date, publication_status, updated_at) values
  ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'Harbour Bachelor Excellence', 'international', 'fixed_amount', 5000, '2027-01-31', 'published', now() - interval '3 days'),
  ('e0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000002', 'Harbour Bachelor Access', 'international', null, null, null, 'unpublished', now() - interval '3 days');
insert into scholarship.scopes(scholarship_id, scope_type, study_level_id) values
  ('e0000000-0000-0000-0000-000000000001', 'study_level', 'c0000000-0000-0000-0000-000000000001'), ('e0000000-0000-0000-0000-000000000002', 'study_level', 'c0000000-0000-0000-0000-000000000001');
insert into pipeline.scholarship_page_candidates(provider_id, url, admit_status) values
  ('d0000000-0000-0000-0000-000000000002', 'https://harbour.example.edu.au/s/9', 'rejected'), ('d0000000-0000-0000-0000-000000000002', 'https://harbour.example.edu.au/s/10', null);

-- AER: Harbour University (d..02) has one read source whose manifests name Nepal and the International Baccalaureate; matrix rows held only for India;
-- 20 of its courses have a bound official page and none has a requirement; no intake has a date. River University (d..09): course rows all domestic.
insert into pipeline.entry_matrix_sources(id, provider_id, url, found_via, status, read_at) values
  ('f0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'https://harbour.example.edu.au/entry/international', 'manual', 'read', now() - interval '10 days'),
  ('f0000000-0000-0000-0000-000000000009', 'd0000000-0000-0000-0000-000000000009', 'https://river.example.edu.au/entry', 'manual', 'read', now() - interval '10 days');
insert into pipeline.aer_source_manifests(source_id, provider_id, content_hash, basis, shape, heading, scope_country, scope_label, expected_cells, matched_cells, omitted_cells) values
  ('f0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'h1', 'manifest-v1', 'country_table', 'Nepal | NEB Grade 12 | International Baccalaureate Diploma', 'NP', 'Harbour country equivalency: nepal', 12, 10, 2);
insert into catalogue.provider_entry_matrix(provider_id, country_id, country_code, qualification_name, quote, source_url, status, audience) values
  ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-0000000000a1', 'IN', 'CBSE Senior School Certificate', 'q', 'https://harbour.example.edu.au/entry/international', 'proposed', 'international');
insert into pipeline.aer_course_outcomes(course_id, provider_id, country, provider_published, outcome, detail, course_url, page_status, built_at)
select c.id, c.provider_id, 'AU', true, 'awaiting_review', 'fixture', 'https://harbour.example.edu.au/c/' || c.canonical_title, 'bound', now()
  from catalogue.courses c where c.provider_id = 'd0000000-0000-0000-0000-000000000002' and c.canonical_title in (select 'Course ' || g from generate_series(1, 20) g);
insert into catalogue.course_entry_requirements(course_id, kind, audience, description, quote, status)
select c.id, 'minimum_grade', 'domestic', 'ATAR 70', 'ATAR 70', 'proposed' from catalogue.courses c where c.provider_id = 'd0000000-0000-0000-0000-000000000009';
insert into catalogue.course_intakes(course_id, intake_label, start_date, application_deadline)
select c.id, 'Semester 1', '2027-03-01', '2026-12-01' from catalogue.courses c where c.provider_id = 'd0000000-0000-0000-0000-000000000009';

-- d..11 a school and d..12 an HE institute, each named by the national register (schools are never in scope; the HE institute is refused by the admission rule)
insert into catalogue.providers(id, display_name, country_id, provider_type_id, publication_status, enrols_international, website) values
  ('d0000000-0000-0000-0000-000000000011', 'Bay College (school)', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000003', 'published', true, 'https://bay.example.edu.au'),
  ('d0000000-0000-0000-0000-000000000012', 'Metro Institute', 'a0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-000000000004', 'published', true, 'https://metro.example.edu.au');
insert into scholarship.register_listings(register_code, listing_id, provider_id, name, level_text)
select 'au_study_australia', 'B' || g, 'd0000000-0000-0000-0000-000000000011'::uuid, 'Bay Award ' || g, 'Secondary schooling' from generate_series(1, 3) g
union all select 'au_study_australia', 'M' || g, 'd0000000-0000-0000-0000-000000000012', 'Metro Award ' || g, 'Undergraduate / VET' from generate_series(1, 6) g;
