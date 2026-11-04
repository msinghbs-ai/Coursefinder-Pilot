-- Production-shaped cases (4 Nov 2026 11:07-11:16 AEDT, read only): 113 admitted scholarships held only by "no stated award value" (109 text_only;
-- e.g. University of Sydney research scholarships "equivalent to the RTP stipend rate"), refusals held by admin ("Refused in Layer 4 › AI could not
-- decide ..."), published scholarships returned by the consumer API, a policy-refused TAFE. Fixed ids so the cases can name them.
insert into ref.countries(id, iso_alpha2) values ('00000000-0000-0000-0000-0000000000a1', 'AU');
insert into ref.provider_types(id, code) values ('00000000-0000-0000-0000-0000000000b1', 'university'), ('00000000-0000-0000-0000-0000000000b2', 'tafe_polytechnic');
insert into catalogue.providers(id, canonical_name, display_name, country_id, provider_type_id, provider_type_basis, website) values
 ('40000000-0000-0000-0000-000000000001', 'The University of Sydney', 'University of Sydney', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
  'TEQSA register: Australian University', 'https://www.sydney.edu.au'),
 ('40000000-0000-0000-0000-000000000002', 'Southern Cross University', 'Southern Cross University', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
  'TEQSA register: Australian University', 'https://www.scu.edu.au'),
 ('40000000-0000-0000-0000-000000000003', 'TAFE Queensland', 'TAFE Queensland', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2',
  'CRICOS Government provider offering VET', 'https://www.tafeqld.edu.au');
insert into pipeline.scholarship_discovery_providers(provider_id, website, site_origin, priority, status, allowed_hosts) values
 ('40000000-0000-0000-0000-000000000001', 'https://www.sydney.edu.au', 'https://www.sydney.edu.au', 0, 'mapped', '{}'),
 ('40000000-0000-0000-0000-000000000002', 'https://www.scu.edu.au', 'https://www.scu.edu.au', 0, 'mapped', '{}'),
 ('40000000-0000-0000-0000-000000000003', 'https://www.tafeqld.edu.au', 'https://www.tafeqld.edu.au', 0, 'mapped', '{}');
insert into pipeline.evidence_artifacts(id) select ('e0000000-0000-0000-0000-00000000000' || n)::uuid from generate_series(1, 9) n;

-- S1..S9 (University of Sydney unless stated); all international, active, with evidence and a provider page
insert into scholarship.scholarships(id, provider_id, name, audience, source_url, publication_status, award_value_type, award_value_text, award_amount, evidence_id) values
 -- S1 the value in words, page read: one person's decision from publication
 ('50000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 'Sydney Research Stipend Scholarship (Computer Science)', 'international',
  'https://www.sydney.edu.au/scholarships/research/cs-stipend', 'unpublished', 'text_only', 'equivalent to the University of Sydney RTP Stipend rate per annum', null, 'e0000000-0000-0000-0000-000000000001'),
 -- S2 refused by a person in Layer 4 (held by admin)
 ('50000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000001', 'Sydney Equity Bursary', 'international',
  'https://www.sydney.edu.au/scholarships/equity-bursary', 'unpublished', 'fixed_amount', null, 5000, 'e0000000-0000-0000-0000-000000000002'),
 -- S3 published and returned by the consumer API
 ('50000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000001', 'Sydney International Excellence Scholarship', 'international',
  'https://www.sydney.edu.au/scholarships/international-excellence', 'published', 'fixed_amount', null, 10000, 'e0000000-0000-0000-0000-000000000003'),
 -- S4 value in words with a Layer 4 decision already waiting (AI could not decide)
 ('50000000-0000-0000-0000-000000000004', '40000000-0000-0000-0000-000000000001', 'Sydney Chemistry PhD Scholarship', 'international',
  'https://www.sydney.edu.au/scholarships/research/chemistry-phd', 'unpublished', 'text_only', 'tuition and stipend at the RTP rate', null, 'e0000000-0000-0000-0000-000000000004'),
 -- S5 value in words, but a person already locked its value (people win)
 ('50000000-0000-0000-0000-000000000005', '40000000-0000-0000-0000-000000000001', 'Sydney Supplementary Scholarship', 'international',
  'https://www.sydney.edu.au/scholarships/supplementary', 'unpublished', 'text_only', 'a supplementary stipend', null, 'e0000000-0000-0000-0000-000000000005'),
 -- S6 value in words, page not read yet (the automated attempt has not run)
 ('50000000-0000-0000-0000-000000000006', '40000000-0000-0000-0000-000000000001', 'Sydney Music Scholarship', 'international',
  'https://www.sydney.edu.au/scholarships/music', 'unpublished', 'text_only', 'full fees', null, 'e0000000-0000-0000-0000-000000000006'),
 -- S7 value in words and not for international students: two checks fail, not a value case
 ('50000000-0000-0000-0000-000000000007', '40000000-0000-0000-0000-000000000001', 'Sydney Regional Bursary', 'domestic_and_local',
  'https://www.sydney.edu.au/scholarships/regional', 'unpublished', 'text_only', 'a bursary', null, 'e0000000-0000-0000-0000-000000000007'),
 -- S8 Southern Cross: value in words (the provider the fixture makes fail)
 ('50000000-0000-0000-0000-000000000008', '40000000-0000-0000-0000-000000000002', 'SCU Vice-Chancellor''s Scholarship', 'international',
  'https://www.scu.edu.au/scholarships/vc', 'unpublished', 'text_only', 'tuition reduction', null, 'e0000000-0000-0000-0000-000000000008'),
 -- S9 TAFE Queensland (policy refuses the provider): value in words
 ('50000000-0000-0000-0000-000000000009', '40000000-0000-0000-0000-000000000003', 'TAFE Queensland Merit Scholarship', 'international',
  'https://www.tafeqld.edu.au/scholarships/merit', 'unpublished', 'text_only', 'course fees', null, 'e0000000-0000-0000-0000-000000000009'),
 -- S10 value in words: the person confirms the page states no award value
 ('50000000-0000-0000-0000-000000000010', '40000000-0000-0000-0000-000000000001', 'Sydney Travel Grant', 'international',
  'https://www.sydney.edu.au/scholarships/travel-grant', 'unpublished', 'text_only', 'support for travel', null, 'e0000000-0000-0000-0000-000000000001');
insert into pipeline.scholarship_pages(scholarship_id, url, read_status, read_at, next_read_at, url_source, evidence_id)
select s.id, s.source_url, case when s.id = '50000000-0000-0000-0000-000000000006' then null else 'read' end,
       case when s.id = '50000000-0000-0000-0000-000000000006' then null else now() - interval '6 days' end, now() + interval '80 days', 'admitted', s.evidence_id
  from scholarship.scholarships s;
insert into pipeline.scholarship_publication_holds(scholarship_id, reason, held_by) values
 ('50000000-0000-0000-0000-000000000002', 'Refused in Layer 4 › AI could not decide: [L4B-20261030-1138] Held scholarship: Not for international students — page quote does not prove international eligibility.', 'admin');
insert into pipeline.scholarship_ai_reviews(scholarship_id, provider_id, url, reason) values
 ('50000000-0000-0000-0000-000000000004', '40000000-0000-0000-0000-000000000001', 'https://www.sydney.edu.au/scholarships/research/chemistry-phd', 'the value is not proven by a quote on the page');
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('scholarship', '50000000-0000-0000-0000-000000000005', 'award_amount', 'value');
insert into pipeline.coverage_provider_reconciliation(domain, provider_id, provider_type, disposition)
select 'scholarship', p.id, case when p.id = '40000000-0000-0000-0000-000000000003' then 'tafe_polytechnic' else 'university' end, 'records_without_listing' from catalogue.providers p;
