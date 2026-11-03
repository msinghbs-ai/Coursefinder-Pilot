-- CF-247 P0 Layer 4 readiness: the cases found live on 3 Nov 2026 18:16-18:28 AEDT (read-only), as small fixtures. Ids are readable:
-- providers p…, courses c…, items i…, decisions d…, stored pages e…. Nothing here is live data.
insert into catalogue.providers(id, stable_key, canonical_name, country_id, lifecycle_status) values
 ('a0000000-0000-0000-0000-000000000001', 'p1', 'Provider One', 'f0000000-0000-0000-0000-000000000001', 'active'),
 ('a0000000-0000-0000-0000-000000000002', 'p2', 'Provider Two (deregistered)', 'f0000000-0000-0000-0000-000000000001', 'archived');
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, lifecycle_status, description)
select ('c0000000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'c' || n,
       case when n = 14 then 'a0000000-0000-0000-0000-000000000002'::uuid else 'a0000000-0000-0000-0000-000000000001'::uuid end,
       'Course ' || n, case when n = 13 then 'inactive' else 'active' end, case when n = 11 then 'A description written since the item was raised.' end
  from generate_series(1, 30) n;
insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, official_course_url, has_provider_current_tuition, generated_at)
select c.id, c.provider_id, 'f0000000-0000-0000-0000-000000000001', 'Provider One', c.canonical_title, c.canonical_title, to_tsvector('simple', c.canonical_title), 'published', null, false, now() - interval '1 day'
  from catalogue.courses c;

-- stored pages: e1/e2 the same content (a re-read of the same page), e3 new content
insert into pipeline.evidence_artifacts(id, source_id, source_url, content_hash) values
 ('e0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'https://uni.example/fees/c7', 'hash-fee-c7'),
 ('e0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'https://uni.example/fees/c7', 'hash-fee-c7'),
 ('e0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000001', 'https://uni.example/fees/c8', 'hash-fee-c8-old'),
 ('e0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000001', 'https://uni.example/fees/c8-2027', 'hash-fee-c8-new'),
 ('e0000000-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-000000000001', 'https://uni.example/entry/c9', 'hash-entry-c9'),
 ('e0000000-0000-0000-0000-000000000006', 'b0000000-0000-0000-0000-000000000001', 'https://uni.example/entry/c10', 'hash-entry-c10'),
 ('e0000000-0000-0000-0000-000000000007', 'b0000000-0000-0000-0000-000000000001', 'https://uni.example/c11', 'hash-c11'),
 ('e0000000-0000-0000-0000-000000000008', 'b0000000-0000-0000-0000-000000000002', 'https://uni.example/matrix/s1', 'hash-s1'),
 ('e0000000-0000-0000-0000-000000000009', 'b0000000-0000-0000-0000-000000000003', 'https://uni.example/matrix/s2', 'hash-s2'),
 ('e0000000-0000-0000-0000-000000000010', 'b0000000-0000-0000-0000-000000000001', 'https://uni.example/fees/c16', 'hash-fee-c16'),
 ('e0000000-0000-0000-0000-000000000011', 'b0000000-0000-0000-0000-000000000001', 'https://uni.example/fees/c16', 'hash-fee-c16-v2'),
 ('e0000000-0000-0000-0000-000000000012', 'b0000000-0000-0000-0000-000000000001', 'https://uni.example/fees/c18', 'hash-fee-c18-27oct'),
 ('e0000000-0000-0000-0000-000000000013', 'b0000000-0000-0000-0000-000000000001', 'https://uni.example/fees/c18', 'hash-fee-c18-2nov');
update pipeline.evidence_artifacts set supersedes_evidence_id = 'e0000000-0000-0000-0000-000000000010' where id = 'e0000000-0000-0000-0000-000000000011';

-- hand-set pages (manual locks; live: 3,016 courses)
insert into pipeline.manual_locks(entity, entity_id, field, mode, set_at) values
 ('course', 'c0000000-0000-0000-0000-000000000004', 'official_url', 'value', now() - interval '30 days'),
 ('course', 'c0000000-0000-0000-0000-000000000004', 'course_url', 'value', now() - interval '30 days'),
 ('course', 'c0000000-0000-0000-0000-000000000021', 'official_url', 'value', now() - interval '30 days'),
 ('course', 'c0000000-0000-0000-0000-000000000021', 'course_url', 'value', now() - interval '30 days');

-- decided items (history the waiting ones repeat)
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, proposed_value, status, created_at, decided_at) values
 -- C5: page approved on 18 Oct (IQ-00039 shape: written differently now)
 ('10000000-0000-0000-0000-000000000005', 'course', 'c0000000-0000-0000-0000-000000000005', 'official_course_url', null, '{"course_url": "https://www.uni.example/c5/"}', 'approved', now() - interval '16 days', now() - interval '16 days'),
 -- C7: fee rejected on 27 Oct (IQ-00040 shape)
 ('10000000-0000-0000-0000-000000000007', 'course', 'c0000000-0000-0000-0000-000000000007', 'provider_current_tuition_validation', 'e0000000-0000-0000-0000-000000000001',
  '{"basis": "indicative_annual", "amount": 9913.62, "audience": "international", "fee_year": 2027, "currency_code": "NZD"}', 'rejected', now() - interval '7 days', now() - interval '7 days'),
 -- C8: fee rejected; the same fee is now read from another page
 ('10000000-0000-0000-0000-000000000008', 'course', 'c0000000-0000-0000-0000-000000000008', 'provider_current_tuition_validation', 'e0000000-0000-0000-0000-000000000003',
  '{"basis": "annual", "amount": 30000, "audience": "international", "fee_year": 2027, "currency_code": "AUD"}', 'rejected', now() - interval '7 days', now() - interval '7 days'),
 -- C18: fee rejected on 27 Oct; raised again from a newer copy of the same page (the live IQ-00040 shape: 51 of 51 are this)
 ('10000000-0000-0000-0000-000000000018', 'course', 'c0000000-0000-0000-0000-000000000018', 'provider_current_tuition_validation', 'e0000000-0000-0000-0000-000000000012',
  '{"basis": "annual", "amount": 12000, "audience": "international", "fee_year": 2025, "currency_code": "AUD"}', 'rejected', now() - interval '7 days', now() - interval '7 days');

-- waiting items
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, status, created_at) values
 ('20000000-0000-0000-0000-000000000001', 'course', 'c0000000-0000-0000-0000-000000000001', 'official_course_url', null, '[]', '{"course_url": "https://uni.example/c1"}', '{}', 'pending', now() - interval '3 days'),
 ('20000000-0000-0000-0000-000000000002', 'course', 'c0000000-0000-0000-0000-000000000002', 'official_course_url', null, '[]', '{"course_url": "http://uni.example/c2"}', '{}', 'pending', now() - interval '3 days'),
 ('20000000-0000-0000-0000-000000000003', 'course', 'c0000000-0000-0000-0000-000000000003', 'official_course_url', null, '[]', '{"course_url": "https://www.facebook.com/uni/c3"}', '{}', 'pending', now() - interval '3 days'),
 ('20000000-0000-0000-0000-000000000004', 'course', 'c0000000-0000-0000-0000-000000000004', 'official_course_url', null, '[]', '{"course_url": "https://uni.example/c4-new"}', '{}', 'pending', now() - interval '3 days'),
 ('20000000-0000-0000-0000-000000000005', 'course', 'c0000000-0000-0000-0000-000000000005', 'official_course_url', null, '[]', '{"course_url": "http://uni.example/c5"}', '{}', 'pending', now() - interval '2 days'),
 ('20000000-0000-0000-0000-000000000006', 'course', 'c0000000-0000-0000-0000-000000000013', 'official_course_url', null, '[]', '{"course_url": "https://uni.example/c13"}', '{}', 'pending', now() - interval '3 days'),
 ('20000000-0000-0000-0000-000000000007', 'course', 'c0000000-0000-0000-0000-000000000006', 'official_course_url', null, '[]', '{"course_url": "https://uni.example/c6"}', '{}', 'pending', now() - interval '3 days'),
 ('20000000-0000-0000-0000-000000000008', 'course', 'c0000000-0000-0000-0000-000000000007', 'provider_current_tuition_validation', 'e0000000-0000-0000-0000-000000000002', '{}',
  '{"basis": "indicative_annual", "amount": 9913.62, "audience": "international", "fee_year": 2027, "currency_code": "NZD", "checks": {"n": 2}}', '{}', 'pending', now() - interval '1 day'),
 ('20000000-0000-0000-0000-000000000009', 'course', 'c0000000-0000-0000-0000-000000000008', 'provider_current_tuition_validation', 'e0000000-0000-0000-0000-000000000004', '{}',
  '{"basis": "annual", "amount": 30000, "audience": "international", "fee_year": 2027, "currency_code": "AUD"}', '{}', 'pending', now() - interval '1 day'),
 ('20000000-0000-0000-0000-000000000010', 'provider', 'a0000000-0000-0000-0000-000000000001', 'entry_matrix_first_run', 'e0000000-0000-0000-0000-000000000008', '{"active_rows": 0}',
  '{"url": "https://uni.example/matrix/s1", "rows": 9, "run_id": "30000000-0000-0000-0000-000000000001"}', '{"entry_matrix_source_id": "b0000000-0000-0000-0000-000000000002"}', 'pending', now() - interval '6 days'),
 ('20000000-0000-0000-0000-000000000011', 'provider', 'a0000000-0000-0000-0000-000000000001', 'entry_matrix_first_run', 'e0000000-0000-0000-0000-000000000009', '{"active_rows": 0}',
  '{"url": "https://uni.example/matrix/s2", "rows": 12, "run_id": "30000000-0000-0000-0000-000000000002"}', '{"entry_matrix_source_id": "b0000000-0000-0000-0000-000000000003"}', 'pending', now() - interval '6 days'),
 ('20000000-0000-0000-0000-000000000012', 'course', 'c0000000-0000-0000-0000-000000000009', 'course_entry_first_read', 'e0000000-0000-0000-0000-000000000005', '{"active_rows": 0}',
  '{"url": "https://uni.example/entry/c9", "rows": 6}', '{}', 'pending', now() - interval '5 days'),
 ('20000000-0000-0000-0000-000000000013', 'course', 'c0000000-0000-0000-0000-000000000010', 'course_entry_first_read', 'e0000000-0000-0000-0000-000000000006', '{"active_rows": 0}',
  '{"url": "https://uni.example/entry/c10", "rows": 2}', '{}', 'pending', now() - interval '5 days'),
 ('20000000-0000-0000-0000-000000000014', 'course', 'c0000000-0000-0000-0000-000000000011', 'course_description_first_read', 'e0000000-0000-0000-0000-000000000007', '{"description": null}',
  '{"description": "Course eleven is taught on campus.", "sentences": [{"text": "Course eleven is taught on campus.", "quote": "Course eleven is taught on campus."}], "item_id": 5}', '{}', 'pending', now() - interval '1 day'),
 ('20000000-0000-0000-0000-000000000015', 'course', 'c0000000-0000-0000-0000-000000000012', 'official_course_url', null, '[]', '{"course_url": "https://uni.example/c12"}', '{}', 'pending', now() - interval '3 days'),
 ('20000000-0000-0000-0000-000000000016', 'course', 'c0000000-0000-0000-0000-000000000012', 'official_course_url', null, '[]', '{"course_url": "https://uni.example/c12/"}', '{}', 'pending', now() - interval '2 days'),
 ('20000000-0000-0000-0000-000000000017', 'course', 'c0000000-0000-0000-0000-000000000016', 'provider_current_tuition_validation', 'e0000000-0000-0000-0000-000000000010', '{}',
  '{"basis": "annual", "amount": 21000, "audience": "international", "fee_year": 2027, "currency_code": "AUD"}', '{}', 'pending', now() - interval '2 days'),
 ('20000000-0000-0000-0000-000000000019', 'course', 'c0000000-0000-0000-0000-000000000018', 'provider_current_tuition_validation', 'e0000000-0000-0000-0000-000000000013', '{}',
  '{"basis": "annual", "amount": 12000, "audience": "international", "fee_year": 2025, "currency_code": "AUD"}', '{}', 'pending', now() - interval '1 day'),
 ('20000000-0000-0000-0000-000000000018', 'course', 'c0000000-0000-0000-0000-000000000017', 'course_description_first_read', 'e0000000-0000-0000-0000-000000000007', '{"description": null}',
  '{"description": "Course seventeen is taught online.", "sentences": [{"text": "Course seventeen is taught online.", "quote": "Course seventeen is taught online."}], "item_id": 6}', '{}', 'pending', now() - interval '1 day');
-- C6 already shows the proposed page as its active official page
insert into catalogue.course_links(course_id, link_type, url, is_primary, status) values ('c0000000-0000-0000-0000-000000000006', 'official_course', 'https://uni.example/c6/', true, 'active');
-- C9: a read with waiting rows (the gate holds it); C10: a read with no waiting row left
insert into catalogue.course_entry_requirements(course_id, kind, status, quote, provenance) values
 ('c0000000-0000-0000-0000-000000000009', 'minimum_grade', 'proposed', 'ATAR 80', '{"review_item_id": "20000000-0000-0000-0000-000000000012"}');
insert into catalogue.course_entry_requirements(course_id, kind, status, quote, provenance) values
 ('c0000000-0000-0000-0000-000000000010', 'minimum_grade', 'inactive', 'ATAR 70', '{"review_item_id": "20000000-0000-0000-0000-000000000013"}');
insert into fx.gate values ('20000000-0000-0000-0000-000000000012', false, 'the reader cut 2 requirement(s) on this page at its row limit, so the read is incomplete: reject it'),
                           ('30000000-0000-0000-0000-000000000002', false, 'the run dropped 3 published rows no waiting row covers');

-- approvals to verify (decided items and their decisions; the reviewer u1 decides one every few minutes)
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, proposed_value, status, created_at, decided_at) values
 ('40000000-0000-0000-0000-000000000001', 'course', 'c0000000-0000-0000-0000-000000000020', 'official_course_url', null, '{"course_url": "https://uni.example/c20"}', 'approved', now() - interval '20 days', now() - interval '17 days'),
 ('40000000-0000-0000-0000-000000000002', 'course', 'c0000000-0000-0000-0000-000000000021', 'official_course_url', null, '{"course_url": "https://uni.example/c21-found"}', 'approved', now() - interval '20 days', now() - interval '17 days'),
 ('40000000-0000-0000-0000-000000000003', 'course', 'c0000000-0000-0000-0000-000000000022', 'official_course_url', null, '{"course_url": "https://uni.example/c22"}', 'approved', now() - interval '20 days', now() - interval '17 days'),
 ('40000000-0000-0000-0000-000000000004', 'course', 'c0000000-0000-0000-0000-000000000023', 'provider_current_tuition_validation', 'e0000000-0000-0000-0000-000000000001',
  '{"basis": "annual", "amount": 41000, "audience": "international", "fee_year": 2027, "currency_code": "AUD"}', 'approved', now() - interval '20 days', now() - interval '17 days'),
 ('40000000-0000-0000-0000-000000000005', 'course', 'c0000000-0000-0000-0000-000000000024', 'course_entry_first_read', 'e0000000-0000-0000-0000-000000000005', '{"rows": 1}', 'approved', now() - interval '20 days', now() - interval '17 days'),
 ('40000000-0000-0000-0000-000000000006', 'course', 'c0000000-0000-0000-0000-000000000025', 'official_course_url', null, '{"course_url": "https://uni.example/c25"}', 'rejected', now() - interval '20 days', now() - interval '17 days'),
 ('40000000-0000-0000-0000-000000000007', 'course', 'c0000000-0000-0000-0000-000000000026', 'official_course_url', null, '{"course_url": "https://uni.example/c26"}', 'approved', now() - interval '1 hour', now() - interval '10 minutes'),
 ('40000000-0000-0000-0000-000000000008', 'course', 'c0000000-0000-0000-0000-000000000028', 'course_entry_first_read', 'e0000000-0000-0000-0000-000000000005', '{"rows": 1}', 'approved', now() - interval '20 days', now() - interval '3 days'),
 ('40000000-0000-0000-0000-000000000009', 'course', 'c0000000-0000-0000-0000-000000000029', 'provider_current_tuition', 'e0000000-0000-0000-0000-000000000001', '{"amount": 2027, "currency": "CAD", "basis": "annual"}', 'edited_approved', now() - interval '20 days', now() - interval '4 days');
insert into pipeline.layer4_decisions(id, review_item_id, action, actor_id, reason, proposed_value, final_value, created_at) values
 ('d0000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 'approve', 'e1000000-0000-0000-0000-000000000001', 'own page', '{"course_url": "https://uni.example/c20"}', '{"course_url": "https://uni.example/c20"}', now() - interval '17 days'),
 ('d0000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000002', 'edit_and_approve', 'e1000000-0000-0000-0000-000000000001', 'own page', '{"course_url": "https://uni.example/c21-found"}', '{"url": "https://uni.example/c21-found"}', now() - interval '17 days' + interval '3 minutes'),
 ('d0000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000003', 'approve', 'e1000000-0000-0000-0000-000000000001', 'own page', '{"course_url": "https://uni.example/c22"}', '{"course_url": "https://uni.example/c22"}', now() - interval '17 days' + interval '5 minutes'),
 ('d0000000-0000-0000-0000-000000000004', '40000000-0000-0000-0000-000000000004', 'approve', 'e1000000-0000-0000-0000-000000000001', 'fee checked', null, null, now() - interval '17 days' + interval '9 minutes'),
 ('d0000000-0000-0000-0000-000000000005', '40000000-0000-0000-0000-000000000005', 'approve', 'e1000000-0000-0000-0000-000000000001', 'rows checked', null, null, now() - interval '17 days' + interval '12 minutes'),
 ('d0000000-0000-0000-0000-000000000006', '40000000-0000-0000-0000-000000000006', 'reject', 'e1000000-0000-0000-0000-000000000001', 'not its page', null, null, now() - interval '17 days' + interval '14 minutes'),
 ('d0000000-0000-0000-0000-000000000007', '40000000-0000-0000-0000-000000000007', 'approve', 'e1000000-0000-0000-0000-000000000001', 'own page', '{"course_url": "https://uni.example/c26"}', '{"course_url": "https://uni.example/c26"}', now() - interval '10 minutes'),
 ('d0000000-0000-0000-0000-000000000008', '40000000-0000-0000-0000-000000000008', 'approve', 'e1000000-0000-0000-0000-000000000002', 'rows checked', null, null, now() - interval '3 days'),
 ('d0000000-0000-0000-0000-000000000009', '40000000-0000-0000-0000-000000000009', 'edit_and_approve', 'e1000000-0000-0000-0000-000000000002', 'fee corrected', null, '{"amount": 20270}', now() - interval '4 days');
-- C20: admitted and shown. C21: locked by hand, the pre-E15 apply skipped it (no link). C22: admitted, the projection shows another page. C23: fee
-- admitted and shown. C24: rows active. C26: approved ten minutes ago, the projection has not refreshed yet.
insert into catalogue.course_links(course_id, link_type, url, is_primary, status, created_at, updated_at) values
 ('c0000000-0000-0000-0000-000000000020', 'official_course', 'https://uni.example/c20', false, 'active', now() - interval '17 days', now() - interval '17 days'),
 ('c0000000-0000-0000-0000-000000000021', 'official_course', 'https://uni.example/c21-by-hand', true, 'active', now() - interval '40 days', now() - interval '40 days'),
 ('c0000000-0000-0000-0000-000000000022', 'official_course', 'https://uni.example/c22', true, 'active', now() - interval '17 days', now() - interval '17 days'),
 ('c0000000-0000-0000-0000-000000000026', 'official_course', 'https://uni.example/c26', true, 'active', now() - interval '10 minutes', now() - interval '10 minutes');
update search.course_documents set official_course_url = 'https://uni.example/c20' where course_id = 'c0000000-0000-0000-0000-000000000020';
update search.course_documents set official_course_url = 'https://uni.example/c21-by-hand' where course_id = 'c0000000-0000-0000-0000-000000000021';
update search.course_documents set official_course_url = 'https://uni.example/c22-old' where course_id = 'c0000000-0000-0000-0000-000000000022';
update search.course_documents set has_provider_current_tuition = true where course_id = 'c0000000-0000-0000-0000-000000000023';
insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, notes, status) values
 ('c0000000-0000-0000-0000-000000000023', 2027, 'international', 'provider_current_tuition', 41000, 'AUD', 'annual', 'CF-247 Layer 4 human decision; review item 40000000-0000-0000-0000-000000000004; fee checked', 'active');
insert into catalogue.course_entry_requirements(course_id, kind, status, quote, provenance) values
 ('c0000000-0000-0000-0000-000000000024', 'minimum_grade', 'active', 'ATAR 75', '{"review_item_id": "40000000-0000-0000-0000-000000000005"}');
-- C28: rows admitted, then withdrawn by a later decision (the E14 shape: 105 rows withdrawn on 2 Nov 2026)
insert into catalogue.course_entry_requirements(course_id, kind, status, status_reason, quote, provenance) values
 ('c0000000-0000-0000-0000-000000000028', 'minimum_grade', 'inactive', 'withdrawn: E14 (Platform Admin 2 Nov 2026)', 'ATAR 65 band', '{"review_item_id": "40000000-0000-0000-0000-000000000008"}');
