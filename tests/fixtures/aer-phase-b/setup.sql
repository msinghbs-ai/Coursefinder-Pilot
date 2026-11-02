-- AER Phase B fixtures: the data, AFTER the 20261102110000 migration (applied twice by run.sh).
-- REAL (live, read-only, 2 Nov 2026 15:26 AEDT; and the 27 Oct 2026 export in ../entry-matrix/rmit-stored): RMIT's provider id, its eight
--   source titles, the stored reasons of its seven held runs (as read live; the Nigeria column name as the Phase A baseline quotes it), the Nepal run id and its
--   11 admitted rows (rows.mjs). Nothing is invented for RMIT.
-- SYNTHETIC (named "Synthetic ..." or marked synthetic below): the other providers, their sources and runs, the run that later reads the UK
--   page complete, the course outcomes, and the Layer 4 items. They carry no admission value: no synthetic row holds a minimum.
create function fx.uid(p text) returns uuid language sql immutable as $f$ select md5(p)::uuid $f$;
create function fx.rmit() returns uuid language sql immutable as $f$ select '8e1adb6c-e069-43db-9584-bd054255e702'::uuid $f$;
create function fx.country(p text) returns uuid language sql stable as $f$ select id from ref.countries where iso_alpha2 = p $f$;
create function fx.src(p text) returns uuid language sql immutable as $f$ select fx.uid('src:' || p) $f$;
create function fx.ev(p text) returns uuid language sql immutable as $f$ select fx.uid('ev:' || p) $f$;
create function fx.prov(p text) returns uuid language sql immutable as $f$ select fx.uid('prov:' || p) $f$;

insert into ref.countries(iso_alpha2, iso_alpha3, name) values ('AU', 'AUS', 'Australia'), ('NZ', 'NZL', 'New Zealand'), ('NP', 'NPL', 'Nepal'),
  ('GB', 'GBR', 'United Kingdom'), ('NG', 'NGA', 'Nigeria'), ('NE', 'NER', 'Niger'), ('NO', 'NOR', 'Norway'), ('VN', 'VNM', 'Vietnam'), ('CH', 'CHE', 'Switzerland'),
  ('CA', 'CAN', 'Canada');
insert into ref.study_levels(code, short_code, name, sort_order) values ('bachelor', 'BA', 'Bachelor', 1), ('masters_coursework', 'MC', 'Masters (coursework)', 2);

insert into ref.provider_types(code, name) values ('university', 'University'), ('university_college', 'University College'), ('higher_education_institute', 'Higher Education Institute'),
  ('tafe_polytechnic', 'TAFE / Polytechnic'), ('private_vet', 'Private VET college'), ('school', 'School'), ('other', 'Other');  -- the live active codes
create function fx.ptype(p text) returns uuid language sql stable as $f$ select id from ref.provider_types where code = p $f$;

-- providers: RMIT (real id) and synthetic ones, eligible and not
insert into catalogue.providers(id, display_name, short_name, country_id, lifecycle_status, publication_status, enrols_international) values
  (fx.rmit(), 'RMIT University', 'RMIT', fx.country('AU'), 'active', 'published', true),
  (fx.prov('au1'), 'Synthetic AU College 1', null, fx.country('AU'), 'active', 'published', true),
  (fx.prov('au2'), 'Synthetic AU College 2', null, fx.country('AU'), 'active', 'published', true),
  (fx.prov('au3'), 'Synthetic AU College 3', null, fx.country('AU'), 'active', 'published', true),
  (fx.prov('aub'), 'Synthetic AU Institute B', null, fx.country('AU'), 'active', 'published', true),
  (fx.prov('nz1'), 'Synthetic NZ Polytechnic', null, fx.country('NZ'), 'active', 'published', true),
  -- not eligible: not published; international intent unknown; archived; a country outside AU/NZ
  (fx.prov('au_unpub'), 'Synthetic AU unpublished', null, fx.country('AU'), 'active', 'unpublished', true),
  (fx.prov('nz_unknown'), 'Synthetic NZ unknown intent', null, fx.country('NZ'), 'active', 'published', null),
  (fx.prov('au_arch'), 'Synthetic AU archived', null, fx.country('AU'), 'archived', 'unpublished', true),
  (fx.prov('ca1'), 'Synthetic Canadian college', null, fx.country('CA'), 'active', 'published', true),
  (fx.prov('auc'), 'Synthetic AU Institute C', null, fx.country('AU'), 'active', 'published', true);
-- REAL catalogue identities (ids and names as live, 2 Nov 2026; Platform Admin 15:43 acceptance list): the eight universities with no AER source,
-- UWA (one source, read, its rows not active), and the related providers kept apart from their namesakes (Deakin College, RMIT UP)
insert into catalogue.providers(id, display_name, country_id, lifecycle_status, publication_status, enrols_international) values
  ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'Charles Darwin University', fx.country('AU'), 'active', 'published', true),
  ('c5c5d225-3d4c-4e41-8275-78eddd261073', 'Deakin University (Deakin)', fx.country('AU'), 'active', 'published', true),
  ('fa0e0d13-838a-42ff-b6a3-9cea84bd80b2', 'University of New England', fx.country('AU'), 'active', 'published', true),
  ('fec52f92-a8a3-4de8-a862-06f355e4e2f7', 'Torrens University Australia', fx.country('AU'), 'active', 'published', true),
  ('030992c3-72c6-452d-8a3b-10ceb0fd77f2', 'Australian Catholic University', fx.country('AU'), 'active', 'published', true),
  ('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113', 'James Cook University', fx.country('AU'), 'active', 'published', true),
  ('f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6', 'Central Queensland University', fx.country('AU'), 'active', 'published', true),
  ('551383f9-7732-4588-a843-dd2b97c13f6f', 'University of Southern Queensland', fx.country('AU'), 'active', 'published', true),
  ('9109fe0c-9f44-4e2d-a136-eb00dec24701', 'The University of Western Australia', fx.country('AU'), 'active', 'published', true),
  ('d090e283-9894-49ce-baf3-e9d47f80e468', 'Deakin College', fx.country('AU'), 'active', 'published', true),
  ('30b81368-9003-4775-81af-60439fc3b109', 'RMIT University Pathways, RMIT UP', fx.country('AU'), 'active', 'published', true);
create function fx.eight() returns uuid[] language sql immutable as $f$ select array['6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'c5c5d225-3d4c-4e41-8275-78eddd261073',
  'fa0e0d13-838a-42ff-b6a3-9cea84bd80b2', 'fec52f92-a8a3-4de8-a862-06f355e4e2f7', '030992c3-72c6-452d-8a3b-10ceb0fd77f2', 'fe6af182-f5ca-4a3c-bfb4-b0773ff1b113',
  'f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6', '551383f9-7732-4588-a843-dd2b97c13f6f']::uuid[] $f$;
create function fx.uwa() returns uuid language sql immutable as $f$ select '9109fe0c-9f44-4e2d-a136-eb00dec24701'::uuid $f$;
-- provider types: the universities as university (as the register types them); the rest synthetic assignments
update catalogue.providers set provider_type_id = fx.ptype('university') where id = any (fx.eight() || array[fx.rmit(), fx.uwa()]);
update catalogue.providers set provider_type_id = fx.ptype('private_vet') where display_name like 'Synthetic%' or id in ('d090e283-9894-49ce-baf3-e9d47f80e468', '30b81368-9003-4775-81af-60439fc3b109');
update catalogue.providers set provider_type_id = fx.ptype('tafe_polytechnic') where id = fx.prov('nz1');

-- RMIT sources (real titles) and their latest runs (real states and stored reasons)
insert into pipeline.entry_matrix_sources(id, provider_id, url, title, found_via, status, read_via, evidence_id, content_hash, read_at)
select fx.src(s), fx.rmit(), 'https://www.rmit.edu.au/study-with-us/international-students/apply-to-rmit-international-students/entry-requirements/country-equivalency/' || s,
       'RMIT country equivalency: ' || s, 'manual', 'read', 'direct', fx.ev(s), md5('hash:' || s), timestamptz '2026-10-26 10:00+11'
  from unnest(array['nepal', 'foundation-equivalencies', 'global-assessment-certificate', 'international-baccalaureate', 'nigeria', 'norway', 'united-kingdom', 'vietnam']) s;
insert into pipeline.entry_matrix_runs(id, provider_id, source_id, content_hash, state, error, result, created_at) values
  (fx.uid('run:foundation'), fx.rmit(), fx.src('foundation-equivalencies'), md5('hash:foundation-equivalencies'), 'failed',
   'held_unparsed: not a country table: requirement-type columns, not qualifications (English Requirement 1; Academic Requirement; Prerequisites)', null, timestamptz '2026-10-26 10:00+11'),
  (fx.uid('run:gac'), fx.rmit(), fx.src('global-assessment-certificate'), md5('hash:global-assessment-certificate'), 'failed',
   'held_unparsed: not a country table: no country named in the page heading ("Global Assessment Certificate | Global Assessment Certificate")', null, timestamptz '2026-10-26 10:00+11'),
  (fx.uid('run:ib'), fx.rmit(), fx.src('international-baccalaureate'), md5('hash:international-baccalaureate'), 'failed',
   'held_unparsed: not a country table: no country named in the page heading ("International Baccalaureate Diploma")', null, timestamptz '2026-10-26 10:00+11'),
  (fx.uid('run:nigeria'), fx.rmit(), fx.src('nigeria'), md5('hash:nigeria'), 'failed',
   'held_incomplete: column left out: Senior School Certificate and completion of first year at a recognised university; 6 of 17 published minimums not read', null, timestamptz '2026-10-26 10:00+11'),
  (fx.uid('run:norway'), fx.rmit(), fx.src('norway'), md5('hash:norway'), 'failed',
   'held_unparsed: no printed scale: bare numbers in Vitnemal fra den videregaende skolen / Vitnemal for videregaende opplaering', null, timestamptz '2026-10-27 10:00+11'),
  (fx.uid('run:uk'), fx.rmit(), fx.src('united-kingdom'), md5('hash:united-kingdom'), 'failed', 'held_incomplete: 2 of 31 published minimums not read', null, timestamptz '2026-10-27 10:00+11'),
  (fx.uid('run:vietnam'), fx.rmit(), fx.src('vietnam'), md5('hash:vietnam'), 'failed',
   'held: AER PR B (table context) not yet built; not read in the PR A recovery (Platform Admin 27 Oct 2026 14:35)', null, timestamptz '2026-10-27 10:00+11');
-- the Nepal run (real id) finished and was admitted; its completeness block is synthetic (status only, no values)
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) values (fx.uid('l4:nepal'), 'provider', fx.rmit(), 'entry_matrix_first_run', 'approved');
insert into pipeline.entry_matrix_runs(id, provider_id, source_id, content_hash, state, result, review_item_id, created_at) values
  ('9aaf9f81-bb57-42c6-97c7-634e180e1a65', fx.rmit(), fx.src('nepal'), md5('hash:nepal'), 'done',
   '{"completeness": {"status": "complete", "basis": "manifest-v1", "expected": 11, "matched": 11}, "rows": []}', fx.uid('l4:nepal'), timestamptz '2026-10-26 10:00+11');

-- synthetic: Institute B's page was read without a hold, but its stored completeness check is incomplete (an omission the guard did not hold)
insert into pipeline.entry_matrix_sources(id, provider_id, url, title, found_via, status, read_via, content_hash, read_at) values
  (fx.src('aub'), fx.prov('aub'), 'https://synthetic.example/aub/entry', 'Synthetic AU Institute B: country equivalency, Nigeria', 'manual', 'read', 'direct', md5('hash:aub'), now() - interval '2 days');
insert into pipeline.entry_matrix_runs(id, provider_id, source_id, content_hash, state, result) values
  (fx.uid('run:aub'), fx.prov('aub'), fx.src('aub'), md5('hash:aub'), 'done',
   '{"completeness": {"status": "incomplete", "basis": "manifest-v1", "expected": 9, "matched": 7, "omitted_columns": ["Synthetic column"], "omitted": [{"column": "Synthetic column"}, {"column": "Synthetic column"}]}, "rows": []}');
-- synthetic: the NZ polytechnic has a complete read and a course that resolves to an admitted requirement (course outcome register)
insert into pipeline.entry_matrix_sources(id, provider_id, url, title, found_via, status, read_via, content_hash, read_at) values
  (fx.src('nz1'), fx.prov('nz1'), 'https://synthetic.example/nz1/entry', 'Synthetic NZ Polytechnic: entry requirements', 'manual', 'read', 'direct', md5('hash:nz1'), now() - interval '2 days');
insert into pipeline.entry_matrix_runs(id, provider_id, source_id, content_hash, state, result) values
  (fx.uid('run:nz1'), fx.prov('nz1'), fx.src('nz1'), md5('hash:nz1'), 'done', '{"completeness": {"status": "not_applicable"}, "rows": [{"synthetic": true}]}');
insert into catalogue.courses(id, provider_id, study_level_id, canonical_title) values
  (fx.uid('course:nz1'), fx.prov('nz1'), (select id from ref.study_levels where short_code = 'BA'), 'Synthetic course'),
  (fx.uid('course:rmit'), fx.rmit(), (select id from ref.study_levels where short_code = 'BA'), 'Synthetic RMIT course'),
  (fx.uid('course:rmit-mc'), fx.rmit(), (select id from ref.study_levels where short_code = 'MC'), 'Synthetic RMIT master''s course');
insert into pipeline.aer_course_outcomes(course_id, provider_id, country, provider_published, outcome, detail, read_state, read_reason, built_at) values
  (fx.uid('course:nz1'), fx.prov('nz1'), 'NZ', true, 'admitted_course', 'synthetic', 'filled', null, now()),
  (fx.uid('course:rmit'), fx.rmit(), 'AU', true, 'admitted_provider', 'synthetic', null, null, now()),
  (fx.uid('course:rmit-mc'), fx.rmit(), 'AU', true, 'source_unreadable', 'synthetic', 'failed', 'held_partial: page text is 185647 characters (synthetic copy of a live reason)', now());

-- UWA (real id): one source, read, its run finished complete, its rows proposed in Layer 4 (synthetic source text, run block and rows; no minimum)
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) values (fx.uid('l4:uwa'), 'provider', fx.uwa(), 'entry_matrix_first_run', 'pending');
insert into pipeline.entry_matrix_sources(id, provider_id, url, title, found_via, status, read_via, content_hash, read_at) values
  (fx.src('uwa'), fx.uwa(), 'https://synthetic.example/uwa/entry', 'Synthetic UWA source', 'manual', 'read', 'direct', md5('hash:uwa'), now() - interval '5 days');
insert into pipeline.entry_matrix_runs(id, provider_id, source_id, content_hash, state, result, review_item_id) values
  (fx.uid('run:uwa'), fx.uwa(), fx.src('uwa'), md5('hash:uwa'), 'done', '{"completeness": {"status": "complete", "basis": "manifest-v1", "expected": 3, "matched": 3}, "rows": []}', fx.uid('l4:uwa'));
insert into catalogue.provider_entry_matrix(provider_id, country_id, country_code, qualification_name, quote, source_url, source_id, run_id, status)
select fx.uwa(), fx.country('GB'), 'GB', 'Synthetic qualification ' || g, 'Synthetic quote', 'https://synthetic.example/uwa/entry', fx.src('uwa'), fx.uid('run:uwa'), 'proposed' from generate_series(1, 3) g;
-- Deakin College (real id) has a source whose fetch failed (synthetic); Deakin University has none and must stay not discovered
insert into pipeline.entry_matrix_sources(id, provider_id, url, title, found_via, status, error) values
  (fx.src('deakin-college'), 'd090e283-9894-49ce-baf3-e9d47f80e468', 'https://synthetic.example/deakin-college/entry', 'Synthetic Deakin College source', 'manual', 'failed', 'blocked_pdf');
-- synthetic course-only provider: no AER source, an active course-level requirement admitted in Layer 4 (no minimum)
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) values (fx.uid('l4:auc'), 'course', fx.uid('course:auc'), 'course_entry_first_read', 'approved');
insert into catalogue.courses(id, provider_id, study_level_id, canonical_title) values (fx.uid('course:auc'), fx.prov('auc'), (select id from ref.study_levels where short_code = 'BA'), 'Synthetic course C');
insert into catalogue.course_entry_requirements(course_id, kind, description, quote, evidence_id, status, provenance) values
  (fx.uid('course:auc'), 'prior_qualification', 'Synthetic requirement', 'Synthetic quote', fx.ev('auc'), 'active', jsonb_build_object('review_item_id', fx.uid('l4:auc')));
-- the NZ polytechnic's admitted course outcome rests on an active course-level requirement (synthetic, no minimum)
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) values (fx.uid('l4:nz1'), 'course', fx.uid('course:nz1'), 'course_entry_first_read', 'approved');
insert into catalogue.course_entry_requirements(course_id, kind, description, quote, evidence_id, status, provenance) values
  (fx.uid('course:nz1'), 'prior_qualification', 'Synthetic requirement', 'Synthetic quote', fx.ev('nz1'), 'active', jsonb_build_object('review_item_id', fx.uid('l4:nz1')));
