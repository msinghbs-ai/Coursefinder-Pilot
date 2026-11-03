-- The cases, shaped on what production holds on 4 Nov 2026 (read only, 05:10-05:45 AEDT): Torrens (IQ-00215), TAFE SA (IQ-00216), Box Hill
-- (IQ-00219), a university with published scholarships, a university with a complete listing and nothing eligible, and the Macquarie "Read again"
-- pages. Fixed ids so the cases can name them.
insert into ref.countries(id, iso_alpha2) values ('00000000-0000-0000-0000-0000000000a1', 'AU');
insert into ref.provider_types(id, code) values ('00000000-0000-0000-0000-0000000000b1', 'university'), ('00000000-0000-0000-0000-0000000000b2', 'tafe_polytechnic');
insert into catalogue.providers(id, canonical_name, display_name, country_id, provider_type_id, provider_type_basis, website) values
 ('10000000-0000-0000-0000-000000000001', 'Torrens University Australia; Torrens University Language Centre; Chifley Business School at Torrens University Australia CBS at Torrens University Australia Blue Mountains International Hotel Management School at Torrens University Australia BMIHMS at To',
  'Torrens', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 'TEQSA register: Australian University', 'https://www.torrens.edu.au'),
 ('10000000-0000-0000-0000-000000000002', 'TAFE South Australia', 'TAFE South Australia', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2',
  'CRICOS Government provider offering VET', 'http://www.tafesa.edu.au/international'),
 ('10000000-0000-0000-0000-000000000003', 'Box Hill Institute', 'Box Hill Institute', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2',
  'CRICOS Government provider offering VET', 'https://www.boxhill.edu.au'),
 ('10000000-0000-0000-0000-000000000004', 'Example University', 'Example University', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
  'TEQSA register: Australian University', 'https://www.example.edu.au'),
 ('10000000-0000-0000-0000-000000000005', 'Evidence University', 'Evidence University', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
  'TEQSA register: Australian University', 'https://www.evidence.edu.au'),
 ('10000000-0000-0000-0000-000000000006', 'Macquarie University', 'Macquarie University', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
  'TEQSA register: Australian University', 'https://www.mq.edu.au');
insert into pipeline.scholarship_discovery_providers(provider_id, website, site_origin, priority, status, method, url_count, kept_count, allowed_hosts, discovered_at) values
 ('10000000-0000-0000-0000-000000000001', 'https://www.torrens.edu.au', 'https://www.torrens.edu.au', 0, 'mapped', 'map_search(1503)', 1503, 13, '{}', now() - interval '23 days'),
 ('10000000-0000-0000-0000-000000000002', 'http://www.tafesa.edu.au/international', 'http://www.tafesa.edu.au', 0, 'mapped', 'map_search(39)', 39, 8, '{}', now() - interval '23 days'),
 ('10000000-0000-0000-0000-000000000003', 'https://www.boxhill.edu.au', 'https://www.boxhill.edu.au', 0, 'empty', 'map_search(42)', 42, 0, '{}', now() - interval '13 days'),
 ('10000000-0000-0000-0000-000000000004', 'https://www.example.edu.au', 'https://www.example.edu.au', 0, 'mapped', 'map', 100, 5, '{}', now() - interval '5 days'),
 ('10000000-0000-0000-0000-000000000005', 'https://www.evidence.edu.au', 'https://www.evidence.edu.au', 0, 'mapped', 'map', 50, 1, '{}', now() - interval '5 days');

-- candidates (ids 1..13 in this order)
insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, title, source, read_status, storage_path, admit_status, admit_reasons, next_read_at) values
 -- 1 Torrens 7887: both models proved an international scholarship; refused only by the provider name rule
 ('10000000-0000-0000-0000-000000000001', 'https://www.torrens.edu.au/scholarships/international-scholarships/motivational-scholarship', 'torrens.edu.au/scholarships/international-scholarships/motivational-scholarship',
  'Motivational Scholarship', 'search', 'read', 'sch/7887.gz', 'rejected', array['not a university provider in a scholarship country'], now() + interval '60 days'),
 -- 2 Torrens 22849: a provider page from the register, rejected unread
 ('10000000-0000-0000-0000-000000000001', 'https://www.torrens.edu.au/scholarships/international-scholarships/pepea-scholarship', 'torrens.edu.au/scholarships/international-scholarships/pepea-scholarship',
  'PEPEA Scholarship', 'register', null, null, 'rejected', array['register_retired'], 'infinity'),
 -- 3 Torrens 7888: the international listing, already a listing source
 ('10000000-0000-0000-0000-000000000001', 'https://www.torrens.edu.au/scholarships/international-scholarships', 'torrens.edu.au/scholarships/international-scholarships',
  'International Student Scholarships', 'search', 'read', 'sch/7888.gz', 'rejected', array['listing_page'], now() + interval '60 days'),
 -- 4 Torrens 7889: not a scholarship
 ('10000000-0000-0000-0000-000000000001', 'https://www.torrens.edu.au/student-exchange-program', 'torrens.edu.au/student-exchange-program', 'Student Exchange', 'search', 'read', 'sch/7889.gz',
  'rejected', array['not_a_scholarship', 'listing_page'], now() + interval '60 days'),
 -- 5 Torrens 7891: skipped news
 ('10000000-0000-0000-0000-000000000001', 'https://www.torrens.edu.au/stories/blog/x', 'torrens.edu.au/stories/blog/x', 'Blog', 'search', 'skipped', null, 'skipped', array['skipped: News or event'], 'infinity'),
 -- 6 TAFE SA 8435: AI listing of international scholarships, no listing source
 ('10000000-0000-0000-0000-000000000002', 'https://www.tafesa.edu.au/international/before-starting/int-scholarships', 'tafesa.edu.au/international/before-starting/int-scholarships',
  'International Scholarships', 'map', 'read', 'sch/8435.gz', 'rejected', array['listing_page'], now() + interval '60 days'),
 -- 7 TAFE SA 8437: domestic only
 ('10000000-0000-0000-0000-000000000002', 'https://students.tafesa.edu.au/veolia', 'students.tafesa.edu.au/veolia', 'VEOLIA Scholarship Fund', 'map', 'read', 'sch/8437.gz',
  'rejected', array['domestic_only'], now() + interval '60 days'),
 -- 8 TAFE SA 8438: a 2023 news page, pending in Layer 4 (AI could not decide)
 ('10000000-0000-0000-0000-000000000002', 'https://www.tafesa.edu.au/tafe-sa-news/2023/sandy', 'tafesa.edu.au/tafe-sa-news/2023/sandy', 'Scholarship puts Sandy on path', 'map', 'read', 'sch/8438.gz',
  'rejected', array['no_named_title', 'international_not_stated', 'past_year_only'], now() + interval '60 days'),
 -- 9 TAFE SA (shape of 8440): the AI read a scholarship but international eligibility was not proven
 ('10000000-0000-0000-0000-000000000002', 'https://www.tafesa.edu.au/tafe-sa-news/2025/playford', 'tafesa.edu.au/tafe-sa-news/2025/playford', 'Playford Trust Awards', 'map', 'read', 'sch/8440.gz',
  'rejected', array['international_not_stated'], now() + interval '60 days'),
 -- 10 Example University: a register page rejected unread (admission-eligible provider)
 ('10000000-0000-0000-0000-000000000004', 'https://www.example.edu.au/scholarships/global-award', 'example.edu.au/scholarships/global-award', 'Global Award', 'register', null, null,
  'rejected', array['register_retired'], 'infinity'),
 -- 11 Example University: an AI listing of international scholarships with only a suggested (inactive) listing row
 ('10000000-0000-0000-0000-000000000004', 'https://www.example.edu.au/scholarships/international', 'example.edu.au/scholarships/international', 'International scholarships', 'map', 'read', 'sch/11.gz',
  'rejected', array['listing_page'], now() + interval '60 days'),
 -- 12 Evidence University: not a scholarship
 ('10000000-0000-0000-0000-000000000005', 'https://www.evidence.edu.au/news/award', 'evidence.edu.au/news/award', 'Staff award', 'map', 'read', 'sch/12.gz',
  'rejected', array['not_a_scholarship'], now() + interval '60 days'),
 -- 13 Example University: a register page on a directory site (never reopened)
 ('10000000-0000-0000-0000-000000000004', 'https://coursesearch.studymelbourne.vic.gov.au/x', 'coursesearch.studymelbourne.vic.gov.au/x', 'Portal page', 'register', null, null,
  'rejected', array['register_retired'], 'infinity');

insert into pipeline.scholarship_ai_extractions(candidate_id, provider_id, model_code, verdict, answer) values
 (1, '10000000-0000-0000-0000-000000000001', 'gpt-4.1-mini', 'scholarship', '{"name":"Motivational scholarship","audience":"international","is_scholarship":true,"single_scholarship":true}'),
 (3, '10000000-0000-0000-0000-000000000001', 'qwen3-30b', 'listing', '{"name":"Global Scholarships","audience":"international","is_scholarship":true,"single_scholarship":false}'),
 (6, '10000000-0000-0000-0000-000000000002', 'qwen3-30b', 'listing', '{"name":"2026 TAFE SA International Scholarship Programs","audience":"international","is_scholarship":true,"single_scholarship":false}'),
 (9, '10000000-0000-0000-0000-000000000002', 'qwen3-30b', 'scholarship', '{"name":"Playford Trust","audience":"not_stated","is_scholarship":true}'),
 (11, '10000000-0000-0000-0000-000000000004', 'qwen3-30b', 'listing', '{"name":"International scholarships","audience":"international","is_scholarship":true}');
insert into pipeline.scholarship_ai_reviews(candidate_id, provider_id, url, reason) values
 (8, '10000000-0000-0000-0000-000000000002', 'https://www.tafesa.edu.au/tafe-sa-news/2023/sandy', 'who it is for is not proven by a quote on the page');

-- listing sources: Torrens 61 read by the retired recorder (no page_state, no members); Example's suggested row; Evidence complete with nothing listed
insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status, read_at, next_read_at, page_state, items) values
 ('10000000-0000-0000-0000-000000000001', 'https://www.torrens.edu.au/scholarships/international-scholarships', 'torrens.edu.au/scholarships/international-scholarships', 'auto', true, 'read',
  now() - interval '1 day', now() + interval '6 days', null,
  '[{"url":"https://www.torrens.edu.au/scholarships/international-scholarships/pepea-scholarship","name":"PEPEA Scholarship"},
    {"url":"https://www.torrens.edu.au/scholarships/international-scholarships/family-scholarship","name":"Family Scholarship"},
    {"url":"https://www.torrens.edu.au/scholarships/international-scholarships/family-scholarship/","name":"Family Scholarship (listed again, as live listings do)"},
    {"url":null,"name":"Global Scholarships"},
    {"url":"https://www.bluemountains.edu.au/apply/scholarships-available/","name":"BMIHMS"}]'),
 ('10000000-0000-0000-0000-000000000004', 'https://www.example.edu.au/scholarships/international', 'example.edu.au/scholarships/international', 'suggested', false, 'suggested', null, null, null, null),
 ('10000000-0000-0000-0000-000000000005', 'https://www.evidence.edu.au/scholarships', 'evidence.edu.au/scholarships', 'manual', true, 'read', now() - interval '1 day', now() + interval '6 days', 'complete', '[]');

-- register: Torrens BMIHMS award on the sub-brand host (no candidate); the PEPEA entry carried by candidate 2
insert into scholarship.register_listings(register_code, listing_id, provider_id, name, provider_name, website_url, handoff_status, candidate_id) values
 ('au_study_australia', 'bm1', '10000000-0000-0000-0000-000000000001', 'Val Cook Scholarship', 'Blue Mountains International Hotel Management School (BMIHMS)',
  'https://www.bluemountains.edu.au/apply/scholarships-available/', 'provider_page_off_provider_site', null),
 ('au_study_australia', 'pe1', '10000000-0000-0000-0000-000000000001', 'PEPEA Scholarship', 'Torrens University Australia',
  'https://www.torrens.edu.au/scholarships/international-scholarships/pepea-scholarship', 'handed_to_page_reader', 2);

-- Example University: published (consumer API returns it), published but the consumer API misses it, unpublished and ended
insert into scholarship.scholarships(id, provider_id, name, audience, source_url, publication_status) values
 ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000004', 'Example International Excellence', 'international', 'https://www.example.edu.au/s/excellence', 'published'),
 ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000004', 'Example Global Merit', 'international', 'https://www.example.edu.au/s/merit', 'published'),
 ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000004', 'Example 2024 Award', 'international', 'https://www.example.edu.au/s/2024', 'unpublished'),
 -- Macquarie "Read again" pages (D7)
 ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000006', 'Macquarie University ASEAN Scholarship', 'international', 'https://www.mq.edu.au/s/asean', 'published'),
 ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000006', 'Macquarie not requested', 'international', 'https://www.mq.edu.au/s/other', 'published'),
 ('30000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000006', 'Macquarie waiting for the scraper', 'international', 'https://www.mq.edu.au/s/wait', 'published'),
 ('30000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000006', 'Macquarie requested and leased', 'international', 'https://www.mq.edu.au/s/leased', 'published');
insert into pipeline.scholarship_round_states(scholarship_id, state) values ('20000000-0000-0000-0000-000000000003', 'ended');
insert into pipeline.scholarship_pages(scholarship_id, url, read_at, next_read_at, attempts, requested_at, leased_until) values
 ('30000000-0000-0000-0000-000000000001', 'https://www.mq.edu.au/s/asean', now() - interval '22 days', now() + interval '8 days', 0, now() - interval '6 hours', null),
 ('30000000-0000-0000-0000-000000000002', 'https://www.mq.edu.au/s/other', now() - interval '22 days', now() + interval '8 days', 0, null, null),
 ('30000000-0000-0000-0000-000000000003', 'https://www.mq.edu.au/s/wait', now() - interval '10 minutes', now() + interval '50 minutes', 0, now() - interval '6 hours', null),
 ('30000000-0000-0000-0000-000000000004', 'https://www.mq.edu.au/s/leased', now() - interval '22 days', now() + interval '8 days', 1, now() - interval '6 hours', now() + interval '5 minutes');

insert into pipeline.coverage_provider_reconciliation(domain, provider_id, provider_type, disposition, issue_fingerprint) values
 ('scholarship', '10000000-0000-0000-0000-000000000001', 'university', 'zero', 'coverage:scholarship:10000000-0000-0000-0000-000000000001'),
 ('scholarship', '10000000-0000-0000-0000-000000000002', 'tafe_polytechnic', 'zero', 'coverage:scholarship:10000000-0000-0000-0000-000000000002'),
 ('scholarship', '10000000-0000-0000-0000-000000000003', 'tafe_polytechnic', 'zero', 'coverage:scholarship:10000000-0000-0000-0000-000000000003'),
 ('scholarship', '10000000-0000-0000-0000-000000000004', 'university', 'represented', null),
 ('scholarship', '10000000-0000-0000-0000-000000000005', 'university', 'no_evidence', null);
insert into pipeline.integration_issues(issue_ref, fingerprint, title, provider_ids, severity) values
 ('IQ-00215', 'coverage:scholarship:10000000-0000-0000-0000-000000000001', 'Scholarship coverage: Torrens', array['10000000-0000-0000-0000-000000000001'::uuid], 'P1');

-- root causes registered live by workstream C (20261104040000) that this change's remedies also treat
insert into pipeline.ops_root_causes(code, class, title) values ('sch_zero_scholarships', 'data', 'Provider with zero scholarships'),
 ('sch_under_represented', 'data', 'Provider''s sources list many more scholarships than the catalogue holds'),
 ('sch_category_missing', 'data', 'A scholarship category the sources list is missing'), ('sch_listing_not_fanned_out', 'dependency', 'Listing items are never turned into candidates')
on conflict do nothing;
