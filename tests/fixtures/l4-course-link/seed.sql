-- CF-247 Layer 4 course link: the cases found live on 3 Nov 2026 20:50-21:08 AEDT (read-only), as small fixtures. Courses c…, items i…,
-- stored copies e…. Providers: Canberra (AU), Simon Fraser (CA), Adelaide (AU) from stubs.sql. Nothing here is live data.
insert into catalogue.courses(id, provider_id, canonical_title, course_code, lifecycle_status, open_to_international)
select ('c0000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n between 20 and 22 then 'd47b6006-396a-4785-b2ae-15186c3e7709'::uuid else '0e1532b8-de30-4761-87fe-460684608633'::uuid end,
       'Course ' || n, case when n between 20 and 22 then null else lpad((90000 + n)::text, 6, '0') || 'A' end, 'active', true
  from generate_series(1, 30) n;
insert into pipeline.sources(id, source_type) values ('b0000000-0000-0000-0000-000000000001', 'provider_course_page_sweep') on conflict do nothing;

-- stored copies (some written differently from the proposed address)
insert into pipeline.evidence_artifacts(id, source_id, source_url, content_hash, captured_at, metadata) values
 ('e0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'https://www.canberra.edu.au/course/c1/', 'h1', now() - interval '2 days', '{"course_id": "c0000000-0000-0000-0000-000000000001", "identity_basis": "cricos_code"}'),
 ('e0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'https://canberra.edu.au/course/c1', 'h1b', now() - interval '1 day', '{"course_id": "c0000000-0000-0000-0000-000000000001", "identity_basis": "cricos_code"}'),
 ('e0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000001', 'https://canberra.edu.au/course/c3', 'h3', now() - interval '1 day', '{"course_id": "c0000000-0000-0000-0000-000000000003", "identity_basis": "cricos_code"}'),
 ('e0000000-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-000000000001', 'https://canberra.edu.au/course/c5-page', 'h5', now() - interval '1 day', '{"course_id": "c0000000-0000-0000-0000-000000000005", "identity_basis": "cricos_code"}'),
 ('e0000000-0000-0000-0000-000000000010', 'b0000000-0000-0000-0000-000000000001', 'https://www.canberra.edu.au/course/c10/7', 'h10', now() - interval '1 day', '{"course_id": "c0000000-0000-0000-0000-000000000010", "identity_basis": "cricos_code"}'),
 ('e0000000-0000-0000-0000-000000000012', 'b0000000-0000-0000-0000-000000000001', 'https://www.canberra.edu.au/course/c12/7', 'h12', now() - interval '1 day', '{"course_id": "c0000000-0000-0000-0000-000000000012", "identity_basis": "exact_title"}'),
 ('e0000000-0000-0000-0000-000000000020', 'b0000000-0000-0000-0000-000000000001', 'https://www.sfu.ca/students/calendar/programs/c20/ba.html', 'h20', now() - interval '1 day', '{"course_id": "c0000000-0000-0000-0000-000000000020", "identity_basis": "field_award"}'),
 ('e0000000-0000-0000-0000-000000000030', 'b0000000-0000-0000-0000-000000000001', 'https://canberra.edu.au/course/c30', 'h30', now() - interval '1 day', '{"course_id": "c0000000-0000-0000-0000-000000000030", "identity_basis": "cricos_code"}');

-- held pages (active official links) and bindings
insert into catalogue.course_links(course_id, link_type, url, is_primary, status) values
 ('c0000000-0000-0000-0000-000000000004', 'official_course', 'https://canberra.edu.au/course/c4-held', true, 'active'),
 ('c0000000-0000-0000-0000-000000000010', 'official_course', 'https://www.canberra.edu.au/course/c10/7/2027', true, 'active'),
 ('c0000000-0000-0000-0000-000000000011', 'official_course', 'https://www.canberra.edu.au/course/c11/7/2027', true, 'active'),
 ('c0000000-0000-0000-0000-000000000012', 'official_course', 'https://www.canberra.edu.au/course/c12/7/2027', true, 'active'),
 ('c0000000-0000-0000-0000-000000000013', 'official_course', 'https://www.canberra.edu.au/course/c13/7/2027', true, 'active'),
 ('c0000000-0000-0000-0000-000000000020', 'official_course', 'https://www.sfu.ca/students/calendar/2026/fall/programs/c20/ba.html', true, 'active');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, evidence_id) values
 ('c0000000-0000-0000-0000-000000000030', '0e1532b8-de30-4761-87fe-460684608633', 'https://canberra.edu.au/course/c30', 'cricos_search', 'bound', 'e0000000-0000-0000-0000-000000000030');
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', 'c0000000-0000-0000-0000-000000000013', 'official_url', 'value');
-- refusals already recorded by the binding check
insert into pipeline.page_rejections(course_id, url, provider_id, source, reason) values
 ('c0000000-0000-0000-0000-000000000001', 'https://canberra.edu.au/course/c1', '0e1532b8-de30-4761-87fe-460684608633', 'binding_check', 'another level'),
 ('c0000000-0000-0000-0000-000000000004', 'https://canberra.edu.au/course/c4-new', '0e1532b8-de30-4761-87fe-460684608633', 'binding_check', 'shared page'),
 ('c0000000-0000-0000-0000-000000000005', 'https://canberra.edu.au/course/c5-page', '0e1532b8-de30-4761-87fe-460684608633', 'binding_check', 'flyer');

-- waiting items, as they were raised before this change (no stored copy linked on arrival then)
update pipeline.platform_toolset_settings set value = '0' where key = 'layer4.evidence_link_on';
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, status, escalation_reason, created_at, claimed_at) values
 -- refusals of courses with no held page (move to Course page needed), one claimed by a reviewer
 ('10000000-0000-0000-0000-000000000001', 'course', 'c0000000-0000-0000-0000-000000000001', 'official_course_url', null, '[]', '{"course_url": "https://canberra.edu.au/course/c1"}',
  '{"source": "binding check", "lane": "firecrawl_search", "page": "https://canberra.edu.au/course/c1"}', 'pending', 'The page found automatically was not linked: the page is for another qualification level.', now() - interval '1 day', null),
 ('10000000-0000-0000-0000-000000000005', 'course', 'c0000000-0000-0000-0000-000000000005', 'official_course_url', null, '[]', '{"course_url": "https://canberra.edu.au/course/c5-page"}',
  '{"source": "binding check", "lane": "title_search"}', 'pending', 'The page found automatically was not linked: it is a flyer.', now() - interval '1 day', now() - interval '5 minutes'),
 -- a refusal where a page is held (stays in Layer 4)
 ('10000000-0000-0000-0000-000000000004', 'course', 'c0000000-0000-0000-0000-000000000004', 'official_course_url', null, '["https://canberra.edu.au/course/c4-held"]', '{"course_url": "https://canberra.edu.au/course/c4-new"}',
  '{"source": "binding check", "lane": "cricos_search"}', 'pending', 'The page found automatically was not linked: shared page.', now() - interval '1 day', null),
 -- coverage sweep items (CRICOS differs) for the Canberra rule: pass, a stored copy with title identity only, a manual lock, a pattern miss
 ('10000000-0000-0000-0000-000000000010', 'course', 'c0000000-0000-0000-0000-000000000010', 'official_course_url', null, '["https://www.canberra.edu.au/course/c10/7/2027"]', '{"course_url": "https://www.canberra.edu.au/course/c10/7"}',
  '{"source": "coverage sweep"}', 'pending', 'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.', now() - interval '2 days', null),
 ('10000000-0000-0000-0000-000000000012', 'course', 'c0000000-0000-0000-0000-000000000012', 'official_course_url', null, '["https://www.canberra.edu.au/course/c12/7/2027"]', '{"course_url": "https://www.canberra.edu.au/course/c12/7"}',
  '{"source": "coverage sweep"}', 'pending', 'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.', now() - interval '2 days', null),
 ('10000000-0000-0000-0000-000000000013', 'course', 'c0000000-0000-0000-0000-000000000013', 'official_course_url', null, '["https://www.canberra.edu.au/course/c13/7/2027"]', '{"course_url": "https://www.canberra.edu.au/course/c13/7"}',
  '{"source": "coverage sweep"}', 'pending', 'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.', now() - interval '2 days', null),
 ('10000000-0000-0000-0000-000000000011', 'course', 'c0000000-0000-0000-0000-000000000011', 'official_course_url', null, '["https://www.canberra.edu.au/course/c11/7/2027"]', '{"course_url": "https://www.canberra.edu.au/scholarship/x"}',
  '{"source": "coverage sweep"}', 'pending', 'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.', now() - interval '2 days', null),
 -- a Canadian CRICOS-differs item (wording)
 ('10000000-0000-0000-0000-000000000020', 'course', 'c0000000-0000-0000-0000-000000000020', 'official_course_url', null, '["https://www.sfu.ca/students/calendar/2026/fall/programs/c20/ba.html"]',
  '{"course_url": "https://www.sfu.ca/students/calendar/programs/c20/ba.html"}', '{"source": "coverage sweep"}', 'pending',
  'The course page that shows this course''s CRICOS code is a different address from the official page we hold. Please check which page is current.', now() - interval '2 days', null),
 -- a fee item (refuse is not for it)
 ('10000000-0000-0000-0000-000000000030', 'course', 'c0000000-0000-0000-0000-000000000030', 'provider_current_tuition_validation', 'e0000000-0000-0000-0000-000000000030', '{}',
  '{"basis": "annual", "amount": 30000, "currency_code": "AUD", "fee_year": 2027}', '{"page": "https://canberra.edu.au/course/c30"}', 'pending', 'Fee reader: outside the usual range', now() - interval '1 day', null);

update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.evidence_link_on';

-- a fee hold on a course whose page is stored (the card shows that copy)
insert into pipeline.enrichment_flags(id, entity, entity_key, provider_id, state, reason_code, reason) values
 (9001, 'course', 'c0000000-0000-0000-0000-000000000030', '0e1532b8-de30-4761-87fe-460684608633', 'raised', 'fee_crosscheck', 'The page fee is far from the registered total');

-- held scholarships: the Macquarie shape (a duplicate of a published one) and scholarships to name
insert into scholarship.scholarships(id, provider_id, name, publication_status, lifecycle_status) values
 ('a3470000-0000-0000-0000-000000000001', '0e1532b8-de30-4761-87fe-460684608633', 'Vice-Chancellor''s International Scholarship', 'published', 'active'),
 ('a3470000-0000-0000-0000-000000000002', '0e1532b8-de30-4761-87fe-460684608633', 'Held copy of the same scholarship', 'unpublished', 'active'),
 ('a3470000-0000-0000-0000-000000000003', 'd47b6006-396a-4785-b2ae-15186c3e7709', 'Another provider''s scholarship', 'published', 'active');
insert into pipeline.scholarship_ai_reviews(id, provider_id, scholarship_id, url, reason, status) values
 (1184, '0e1532b8-de30-4761-87fe-460684608633', 'a3470000-0000-0000-0000-000000000002', 'https://www.canberra.edu.au/staging/vc-scholarship', 'AI could not decide', 'pending');

-- search spend
insert into pipeline.coverage_vendor_usage(units, purpose, at) values (2, 'fc_search', now() - interval '1 hour'), (2, 'fc_search', now() - interval '1 hour'), (2, 'course_link_search', now() - interval '2 hours');
-- the signed-in reviewer
insert into auth.users(id, email) values ('90000000-0000-0000-0000-0000000000aa', 'admin@example.test'), ('90000000-0000-0000-0000-0000000000bb', 'curator@example.test');

