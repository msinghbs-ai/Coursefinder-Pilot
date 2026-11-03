-- Fixture rows modelled on live 3 Nov 2026 (ids and addresses as live; page text is not needed: the worker is simulated by the cases)
truncate pipeline.scholarship_ai_queue, pipeline.scholarship_ai_extractions, pipeline.scholarship_ai_reviews, pipeline.scholarship_page_candidates, pipeline.evidence_artifacts,
         scholarship.scholarships, pipeline.scholarship_pages, catalogue.providers, catalogue.provider_aliases, pipeline.fx_calls, pipeline.scholarship_discovery_providers,
         pipeline.scholarship_ai_models cascade;
do $$ begin
  if to_regclass('pipeline.scholarship_read_requests') is not null then execute 'truncate pipeline.scholarship_read_requests, pipeline.scholarship_owner_proposals'; end if;
end $$;
delete from pipeline.platform_toolset_settings where key in ('scholarship.single_read_daily_max');
insert into pipeline.scholarship_ai_models values ('qwen3-30b', 'qwen/qwen3-30b-a3b-instruct-2507'), ('gpt-4.1-mini', 'openai/gpt-4.1-mini');
insert into pipeline.scholarship_ai_prompts values (2, 'instructions v2', true) on conflict do nothing;
insert into pipeline.scholarship_ai_extract_settings(id, ai_admission, chain) values (1, true, array['qwen3-30b', 'gpt-4.1-mini'])
  on conflict (id) do update set ai_admission = true, chain = excluded.chain;

insert into catalogue.providers(id, canonical_name, display_name, website, country) values
 ('739948f6-6338-4ee9-8d0c-a8c8e953c29d', 'Bond University Limited', 'Bond University Limited', 'http://www.bond.edu.au/', 'AU'),
 ('bac82321-ded7-4e10-a71d-b18f3ae4d1c7', 'Victoria University', 'Victoria University', 'http://www.vu.edu.au/', 'AU'),
 ('188103a5-1aba-4f99-bd3e-0416659086d3', 'Macquarie University', 'Macquarie University', 'https://www.mq.edu.au', 'AU'),
 ('159328df-fb4b-4bb8-a6b8-5f24546437a3', 'Lexis TESOL Training Centres', 'Lexis TESOL Training Centres', 'https://lexis-training.com', 'AU'),
 ('1bdef519-6927-4765-8a06-632d396fa2ae', 'Prime Education Group Pty Ltd', 'Prime Education Group Pty Ltd', 'https://wattle.edu.au', 'AU'),
 ('8e1adb6c-e069-43db-9584-bd054255e702', 'RMIT University', 'RMIT University (RMIT)', 'https://www.rmit.edu.au', 'AU'),
 ('30b81368-9003-4775-81af-60439fc3b109', 'RMIT University Pathways', 'RMIT University Pathways, RMIT UP', 'https://www.rmit.edu.au/up', 'AU'),
 ('cb666a5e-3874-45b9-9e77-588cd9f750ab', 'Alphacrucis College', 'Alphacrucis College', 'http://ac.edu.au', 'AU'),
 ('447c6c27-5ba8-4f54-b292-6790a03e2c2a', 'Alphacrucis Limited', 'Alphacrucis Limited', 'https://www.acnz.ac.nz', 'NZ'),
 ('275fdac8-0000-0000-0000-000000000001', 'Kauri Academy (NZ) International Ltd', 'Kauri Academy (NZ) International Ltd', 'https://kauri.example', 'NZ'),
 ('1822b40a-0000-0000-0000-000000000001', 'The University of Newcastle', 'The University of Newcastle (UoN), The University of Newcastle Language Centre, Sydney', 'https://www.newcastle.edu.au', 'AU'),
 ('030992c3-72c6-452d-8a3b-10ceb0fd77f2', 'Australian Catholic University', 'Australian Catholic University', 'https://www.acu.edu.au', 'AU');
insert into scholarship.scholarships(id, name, provider_id) values
 ('a347e086-55a5-557c-ae62-352b1459881a', 'Vice-Chancellor''s International Scholarship', '188103a5-1aba-4f99-bd3e-0416659086d3'),
 ('00000000-0000-0000-0000-00000000aa01', 'RMIT UP General English Bursary for Asia', '8e1adb6c-e069-43db-9584-bd054255e702');
insert into pipeline.scholarship_pages(scholarship_id, url) values
 ('a347e086-55a5-557c-ae62-352b1459881a', 'https://www.mq.edu.au/study/admissions-and-entry/scholarships/international/vice-chancellor-s-international-scholarship/');
insert into scholarship.scholarships(id, name, provider_id) values ('00000000-0000-0000-0000-00000000aa02', 'Macquarie University ASEAN Scholarship', '188103a5-1aba-4f99-bd3e-0416659086d3');
insert into pipeline.scholarship_pages(scholarship_id, url) values ('00000000-0000-0000-0000-00000000aa02', 'https://students.mq.edu.au/study/course/overseas/staging/details/macquarie-university-asean-scholarship');
insert into pipeline.scholarship_discovery_providers values ('159328df-fb4b-4bb8-a6b8-5f24546437a3', 'map_search(67)'), ('1bdef519-6927-4765-8a06-632d396fa2ae', 'map_search(85)');

-- candidates: Bond 6712 holds the 29 Sep 2026 copy; VU 7700 has none; Macquarie 7347 (staging); directory pages; a plain Macquarie page for the regression case
insert into pipeline.scholarship_page_candidates(id, provider_id, url, title, source, storage_path, read_status, facts) overriding system value values
 (6712, '739948f6-6338-4ee9-8d0c-a8c8e953c29d', 'https://bond.edu.au/scholarship/abedian-foundation-master-of-architecture-scholarship', 'The Abedian Foundation Master of Architecture Scholarship', 'sitemap',
  'layer2/AU/scholarships/739948f6-6338-4ee9-8d0c-a8c8e953c29d/candidates/6712/9d25e2f7.html.gz', 'read', null),
 (7700, 'bac82321-ded7-4e10-a71d-b18f3ae4d1c7', 'https://www.vu.edu.au/bachelor-of-it-professional-placement-scholarship-application', null, 'sitemap', null, 'gone', null),
 (7347, '188103a5-1aba-4f99-bd3e-0416659086d3', 'https://students.mq.edu.au/study/course/overseas/staging/details/vice-chancellors-international-scholarship', 'Vice-Chancellor''s International Scholarship - Current Students MQ', 'search',
  'layer2/AU/scholarships/188103a5/ai/745/99794849.html.gz', 'read', null),
 (15138, '159328df-fb4b-4bb8-a6b8-5f24546437a3', 'https://search.studyqueensland.qld.gov.au/scholarship/acu-refugee-scholarship/1dcc0e690ac4beb52668da916d7917ec', 'ACU Refugee Scholarship', 'map', null, 'scrape_failed', null),
 (26080, '1bdef519-6927-4765-8a06-632d396fa2ae', 'https://coursesearch.studymelbourne.vic.gov.au/scholarship/rmit-up-general-english-bursary-for-asia/3ed9fa68865a1b3041c913ade5d2c8ae', 'RMIT UP General English Bursary for Asia - Study Melbourne', 'map',
  'layer2/AU/scholarships/1bdef519/candidates/26080/x.html.gz', 'read', '{"h1": "RMIT UP General English Bursary for Asia", "page_title": "RMIT UP General English Bursary for Asia - Study Melbourne"}'),
 (15620, '1bdef519-6927-4765-8a06-632d396fa2ae', 'https://coursesearch.studymelbourne.vic.gov.au/scholarship/alphacrucis-higher-degree-scholarship/8d3513b5dc559c1b3fd5fa00222ca836', 'Alphacrucis Higher Degree Scholarship', 'map',
  'layer2/AU/scholarships/1bdef519/candidates/15620/y.html.gz', 'read', '{"h1": "Alphacrucis Higher Degree Scholarship"}'),
 (15625, '1bdef519-6927-4765-8a06-632d396fa2ae', 'https://coursesearch.studymelbourne.vic.gov.au/scholarship/vice-chancellor-international-excellence-scholarship/b41fc253a66c1dff5db456042a9b34dd', 'Vice-Chancellor International Excellence Scholarship', 'map', null, 'scrape_failed', null),
 (5000, '188103a5-1aba-4f99-bd3e-0416659086d3', 'https://www.mq.edu.au/study/scholarships/regression', 'Regression page', 'sitemap', 'layer2/AU/scholarships/188103a5/candidates/5000/r.html.gz', 'read', null);

-- held items (Layer 4 refs as live)
insert into pipeline.scholarship_ai_reviews(id, candidate_id, provider_id, url, storage_path, extraction_ids, reason) overriding system value values
 (1230, 6712, '739948f6-6338-4ee9-8d0c-a8c8e953c29d', 'https://bond.edu.au/scholarship/abedian-foundation-master-of-architecture-scholarship', 'layer2/AU/scholarships/739948f6-6338-4ee9-8d0c-a8c8e953c29d/candidates/6712/9d25e2f7.html.gz', '{19994,20041}', 'who it is for is not proven by a quote on the page'),
 (1323, 7700, 'bac82321-ded7-4e10-a71d-b18f3ae4d1c7', 'https://www.vu.edu.au/bachelor-of-it-professional-placement-scholarship-application', null, '{23123,23143,23349,23490}', 'the model''s reply failed: the page could not be read'),
 (1184, 7347, '188103a5-1aba-4f99-bd3e-0416659086d3', 'https://students.mq.edu.au/study/course/overseas/staging/details/vice-chancellors-international-scholarship', 'layer2/AU/scholarships/188103a5/ai/745/99794849.html.gz', '{}', 'who it is for is not proven by a quote on the page'),
 (1174, 15138, '159328df-fb4b-4bb8-a6b8-5f24546437a3', 'https://search.studyqueensland.qld.gov.au/scholarship/acu-refugee-scholarship/1dcc0e690ac4beb52668da916d7917ec', null, '{}', 'the model''s reply failed: the page could not be read'),
 (1176, 26080, '1bdef519-6927-4765-8a06-632d396fa2ae', 'https://coursesearch.studymelbourne.vic.gov.au/scholarship/rmit-up-general-english-bursary-for-asia/3ed9fa68865a1b3041c913ade5d2c8ae', 'layer2/AU/scholarships/1bdef519/candidates/26080/x.html.gz', '{}', 'the value is not proven by a quote on the page'),
 (1177, 15620, '1bdef519-6927-4765-8a06-632d396fa2ae', 'https://coursesearch.studymelbourne.vic.gov.au/scholarship/alphacrucis-higher-degree-scholarship/8d3513b5dc559c1b3fd5fa00222ca836', 'layer2/AU/scholarships/1bdef519/candidates/15620/y.html.gz', '{}', 'the value is not proven by a quote on the page'),
 (1287, 15625, '1bdef519-6927-4765-8a06-632d396fa2ae', 'https://coursesearch.studymelbourne.vic.gov.au/scholarship/vice-chancellor-international-excellence-scholarship/b41fc253a66c1dff5db456042a9b34dd', null, '{}', 'the model''s reply failed: the page could not be read');
-- 1184's last extraction names the published scholarship (duplicate measure)
insert into pipeline.scholarship_ai_extractions(id, candidate_id, provider_id, url, answer, verdict) overriding system value values
 (19883, 7347, '188103a5-1aba-4f99-bd3e-0416659086d3', 'https://students.mq.edu.au/study/course/overseas/staging/details/vice-chancellors-international-scholarship', '{"name": "Vice-Chancellor''s International Scholarship"}', 'scholarship');
update pipeline.scholarship_ai_reviews set extraction_ids = '{19883}' where id = 1184;
select setval(pg_get_serial_sequence('pipeline.scholarship_ai_reviews', 'id'), 5000);
select setval(pg_get_serial_sequence('pipeline.scholarship_ai_extractions', 'id'), 60000);
select setval(pg_get_serial_sequence('pipeline.scholarship_page_candidates', 'id'), 60000);
