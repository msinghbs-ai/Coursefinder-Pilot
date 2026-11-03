-- CF-247 P0 workstream E fixture seed: trusted and untrusted rows of every source the dataset builder reads, shaped like live rows (3 Nov 2026).
-- People P1 and P2 are signed-in users; X is an actor that is not a person (an automated writer). Invented data only.
create schema if not exists fx;
create function fx.u(p text) returns uuid language sql immutable as $$ select ('00000000-0000-0000-0000-' || lpad(p, 12, '0'))::uuid $$;
insert into auth.users values (fx.u('a1')), (fx.u('a2'));   -- P1, P2 (X = fx.u('ff') is not a user)
insert into catalogue.providers(id, canonical_name, display_name, website) values (fx.u('b1'), 'New Gen', 'New Gen', 'https://new.edu.au'), (fx.u('b2'), 'Two Uni', 'Two Uni', 'https://pr2.edu'),
  (fx.u('b3'), 'Three', 'Three', 'https://pr3.edu');
insert into catalogue.courses(id, provider_id, canonical_title, course_url) select fx.u('c' || g), fx.u('b2'), 'Course ' || g, 'https://u.edu/c' || g from generate_series(1, 10) g;

-- Layer 4: review items and decisions
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) values
  (fx.u('d1'), 'course', fx.u('c1'), 'official_course_url', 'approved'),
  (fx.u('d2'), 'course', fx.u('c2'), 'official_course_url', 'rejected'),
  (fx.u('d3'), 'course', fx.u('c3'), 'official_course_url', 'edited_approved'),
  (fx.u('d4'), 'course', fx.u('c4'), 'course_english', 'approved'),
  (fx.u('d5'), 'course', fx.u('c5'), 'course_english', 'rejected'),
  (fx.u('d6'), 'course', fx.u('c6'), 'official_course_url', 'returned_layer2'),
  (fx.u('d7'), 'course', fx.u('c7'), 'course_entry_first_read', 'approved'),
  (fx.u('d8'), 'course', fx.u('c8'), 'course_description_first_read', 'pending');
insert into pipeline.layer4_decisions(id, review_item_id, action, actor_id, reason, proposed_value, final_value, created_at) values
  (fx.u('e1'), fx.u('d1'), 'approve', fx.u('a1'), 'The provider''s own course page', '{"course_url": "https://u.edu/c1"}', null, now() - interval '5 days'),
  (fx.u('e2'), fx.u('d2'), 'reject', fx.u('a1'), 'Rule (Platform Admin 10 Oct 2026: no third-party course directories)', '{"course_url": "https://dir.example.com/c2"}', null, now() - interval '5 days'),
  (fx.u('e3'), fx.u('d3'), 'edit_and_approve', fx.u('a1'), 'Decided by rule (Decision 263): the provider''s course page stays official', '{"course_url": "http://u.edu/handbook/c3"}', '"https://u.edu/c3"', now() - interval '5 days'),
  (fx.u('e4'), fx.u('d4'), 'approve', fx.u('a2'), '[L4B-20261101-1253] English check: Keep', '{"english_requirements": [{"test_code": "IELTS", "overall_score": 6.5}]}', null, now() - interval '1 day'),
  (fx.u('e5'), fx.u('d5'), 'reject', fx.u('ff'), 'automated', '{"english_requirements": []}', null, now() - interval '1 day'),          -- not a person: excluded
  (fx.u('e6'), fx.u('d6'), 'return_layer2', fx.u('a1'), 'RETURN_LAYER2 100', '{"course_url": "https://u.edu/x"}', null, now() - interval '1 day'),  -- a return: excluded
  (fx.u('e7'), fx.u('d7'), 'approve', fx.u('a1'), '', '{"rows": []}', null, now() - interval '1 day');                                     -- no reason: excluded

-- people's corrections
insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor, at) values
  ('course', fx.u('c1'), 'official_url', 'set_official_url', '["https://u.edu/c1", "https://u.edu/c1-old"]', '"https://u.edu/c1"', 'Layer 4: repeats decision e1', fx.u('a1'), now() - interval '5 days'),  -- duplicate label
  ('course', fx.u('c9'), 'official_url', 'remove_official_url', '"https://u.edu/old-c9"', null, 'Page gone (404)', fx.u('a1'), now() - interval '4 days'),
  ('course', fx.u('c10'), 'official_url', 'set_official_url', null, '"https://u.edu/c10"', 'script', fx.u('ff'), now() - interval '4 days'),       -- not a person: excluded
  ('provider', fx.u('b1'), 'website', 'set_core', '"https://info@new.edu"', '"https://new.edu.au"', 'register and first-party evidence', fx.u('a2'), now() - interval '3 days'),
  ('course_entry', fx.u('c7'), 'status', 'withdraw', '"active"', '"inactive"', 'approved in error', fx.u('a1'), now() - interval '2 days'),
  ('provider', fx.u('b1'), 'publication_status', 'publish', '"draft"', '"published"', 'publish', fx.u('a1'), now() - interval '2 days');    -- not an AI task: excluded

-- locks
insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by, set_at) values
  ('course', fx.u('c1'), 'official_url', 'value', fx.u('a1'), now() - interval '5 days'),   -- the correction already labels it: skipped
  ('provider', fx.u('b2'), 'website', 'value', fx.u('a1'), now() - interval '3 days'),
  ('course', fx.u('c2'), 'course_url', 'value', fx.u('a1'), now() - interval '3 days'),     -- not mapped (official_url carries the course link)
  ('provider', fx.u('b3'), 'website', 'value', fx.u('ff'), now() - interval '3 days');      -- not a person: excluded

-- readings
insert into pipeline.field_enrich_items(course_id, provider_id, field, state, source, value, quote, evidence_id, storage_path, updated_at) values
  (fx.u('c1'), fx.u('b2'), 'intakes', 'filled', 'ai_stored', '["February"]', 'Intakes: February', null, 'evidence/c1.txt', now() - interval '6 days'),
  (fx.u('c4'), fx.u('b2'), 'english', 'filled', 'ai_stored', '{"ielts": 6.0}', 'IELTS 6.0 overall', fx.u('f4'), null, now() - interval '6 days'),   -- a person later decided otherwise
  (fx.u('c2'), fx.u('b2'), 'deadline', 'filled', 'ai_stored', '{"date": "2027-01-15"}', 'Applications close 15 January 2027', null, 'evidence/c2.txt', now() - interval '6 days'),
  (fx.u('c3'), fx.u('b2'), 'intakes', 'filled', 'ai_stored', '["July"]', null, null, 'evidence/c3.txt', now() - interval '6 days'),            -- no quote: excluded
  (fx.u('c5'), fx.u('b2'), 'english', 'review', 'ai_stored', '{"ielts": 7}', 'IELTS 7', null, 'evidence/c5.txt', now() - interval '6 days'),    -- not checked yet: excluded
  (fx.u('c6'), fx.u('b2'), 'field_of_study', 'filled', 'register', '"0101"', 'code', null, null, now() - interval '6 days'),                  -- no page: excluded
  (fx.u('c6'), fx.u('b2'), 'campus', 'filled', 'ai_stored', '["City"]', 'City campus', null, 'evidence/c6.txt', now() - interval '6 days'),    -- campus AI quote not checked: excluded
  (fx.u('c6'), fx.u('b2'), 'campus', 'filled', 'adapter', '["City"]', 'Campus: City', null, 'evidence/c6.txt', now() - interval '6 days');

-- scholarship readings
insert into pipeline.scholarship_ai_reviews(scholarship_id, provider_id, url, storage_path, extraction_ids, reason, status, decided_by, decided_at, note, decision) values
  (fx.u('51'), fx.u('b2'), 'https://u.edu/s1', 'sch/s1', '{11,12}', 'the value is not proven by a quote on the page', 'admitted', fx.u('a1'), now() - interval '3 days', 'Admit', '{"decision": "admit"}'),
  (fx.u('52'), fx.u('b2'), 'https://u.edu/s2', 'sch/s2', '{13}', 'who it is for is not proven by a quote on the page', 'refused', fx.u('a2'), now() - interval '3 days', 'Not a scholarship — enquiry form', '{"decision": "refuse"}'),
  (fx.u('53'), fx.u('b2'), 'https://u.edu/s3', 'sch/s3', '{14}', 'the page could not be read', 'pending', null, null, null, null),          -- undecided: excluded
  (fx.u('54'), fx.u('b2'), 'https://u.edu/s4', 'sch/s4', '{15}', 'the value is not proven by a quote on the page', 'superseded', fx.u('a1'), now() - interval '3 days', null, null);  -- superseded: excluded

-- the matcher's candidate lists
insert into pipeline.coverage_ai_match(course_id, provider_id, state, candidates, chosen_url, model) values
  (fx.u('c1'), fx.u('b2'), 'chosen', '[{"url": "https://u.edu/c1", "title": "Course 1"}, {"url": "https://dir.example.com/c1", "title": "Course 1"}]', 'https://u.edu/c1', 'qwen/qwen3-30b-a3b-instruct-2507'),
  (fx.u('c9'), fx.u('b2'), 'chosen', '[{"url": "https://u.edu/old-c9", "title": "Course 9"}]', 'https://u.edu/old-c9', 'qwen/qwen3-30b-a3b-instruct-2507'),   -- only a no-page label: excluded
  (fx.u('c3'), fx.u('b2'), 'none', '[]', null, 'qwen/qwen3-30b-a3b-instruct-2507');                                                                            -- no candidates: excluded
