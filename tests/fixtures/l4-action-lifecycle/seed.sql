-- CF-247 Layer 4 action lifecycle fixtures: production-shaped records (read 4 Nov 2026 12:28-12:42 AEDT; no live data beyond the RMIT
-- identifiers the Integration Controller named in the brief). RMIT Diploma of Commerce (IQ-00279), one university for the §9 cases, and one
-- waiting item of every Inbox kind.
\set ON_ERROR_STOP on
insert into ref.countries(id, iso_alpha2) values ('00000000-0000-4000-8000-0000000000a1', 'AU') on conflict do nothing;
insert into catalogue.providers(id, stable_key, canonical_name, display_name, website, country_id, publication_status) values
 ('8e1adb6c-e069-43db-9584-bd054255e702', 'rmit', 'RMIT University', 'RMIT University', 'https://www.rmit.edu.au', '00000000-0000-4000-8000-0000000000a1', 'published'),
 ('5a000000-0000-4000-8000-000000000001', 'lifeuni', 'Lifecycle University', 'Lifecycle University', 'https://www.lifeuni.edu.au', '00000000-0000-4000-8000-0000000000a1', 'published'),
 ('5a000000-0000-4000-8000-000000000002', 'quietcol', 'Quiet College', 'Quiet College', 'https://www.quiet.edu.au', '00000000-0000-4000-8000-0000000000a1', 'unpublished')
on conflict (id) do update set publication_status = excluded.publication_status;
-- five universities whose onboarding stopped, one for each reason (the Inbox shows a university's latest run)
insert into catalogue.providers(id, stable_key, canonical_name, display_name, country_id, publication_status)
select ('5a000000-0000-4000-8000-00000000001' || n)::uuid, 'onb' || n, 'Onboarding College ' || n, 'Onboarding College ' || n, '00000000-0000-4000-8000-0000000000a1', 'unpublished'
  from generate_series(1, 5) n on conflict do nothing;
insert into catalogue.courses(id, provider_id, canonical_title, course_code, lifecycle_status) values
 ('b365fde8-d003-4ef6-80c3-4136fbd5587a', '8e1adb6c-e069-43db-9584-bd054255e702', 'Diploma of Commerce', '111278B', 'active'),
 ('5c000000-0000-4000-8000-000000000002', '5a000000-0000-4000-8000-000000000001', 'Bachelor of Science', '200002B', 'active'),
 ('5c000000-0000-4000-8000-000000000004', '5a000000-0000-4000-8000-000000000001', 'Bachelor of Arts', '200004D', 'active'),
 ('5c000000-0000-4000-8000-000000000005', '5a000000-0000-4000-8000-000000000001', 'Bachelor of Nursing', '200005E', 'active'),
 ('5c000000-0000-4000-8000-000000000008', '5a000000-0000-4000-8000-000000000001', 'Master of Teaching', '200008H', 'active'),
 ('5c000000-0000-4000-8000-000000000009', '5a000000-0000-4000-8000-000000000001', 'Diploma of Business', '200009J', 'active'),
 ('5c000000-0000-4000-8000-000000000010', '5a000000-0000-4000-8000-000000000001', 'Bachelor of Laws', '200010K', 'active'),
 ('5c000000-0000-4000-8000-000000000011', '5a000000-0000-4000-8000-000000000001', 'Bachelor of Music', '200011L', 'active'),
 ('5c000000-0000-4000-8000-000000000012', '5a000000-0000-4000-8000-000000000001', 'Bachelor of Design', '200012M', 'active'),
 ('5c000000-0000-4000-8000-000000000013', '5a000000-0000-4000-8000-000000000001', 'Bachelor of Commerce', '200013N', 'active')
on conflict do nothing;
-- the stored copies (pipeline.evidence_artifacts): RMIT's first copy (29 Oct) and the bound page's newer copy (2 Nov), and one a Lifecycle course
insert into pipeline.evidence_artifacts(id, source_url, evidence_type, captured_at) values
 ('6ac70f57-7eba-4fe0-a907-4ca9554bf81f', 'https://www.rmit.edu.au/study-with-us/levels-of-study/undergraduate-study/higher-education-diplomas/diploma-of-commerce-dp020', 'page', '2026-10-29 01:40:00+00'),
 ('a0ffab81-9eff-40dc-9d7b-b5dfbdd7c032', 'https://www.rmit.edu.au/study-with-us/levels-of-study/undergraduate-study/higher-education-diplomas/diploma-of-commerce-dp020', 'page', '2026-11-02 11:08:31+00');
insert into pipeline.evidence_artifacts(id, source_url, evidence_type, captured_at)
select md5('copy:' || c.course_code)::uuid, 'https://www.lifeuni.edu.au/' || c.course_code, 'page', now() - interval '7 days' from catalogue.courses c where c.provider_id = '5a000000-0000-4000-8000-000000000001';
insert into auth.users(id, email) values ('63ba56cb-48d4-4169-98c2-7c4d1f72925b', 'platform.admin@example.org') on conflict do nothing;
-- the settings a corrected read depends on, as live (last changed 2 Nov 2026 17:43 AEDT)
insert into pipeline.platform_toolset_settings(toolset_key, key, value, updated_at) values
 ('pipeline', 'entry.max_rows_per_course', '6', '2026-11-02 06:43:26+00'), ('pipeline', 'entry.max_rows_by_provider', '[]', '2026-11-02 06:43:26+00')
on conflict (toolset_key, key) do update set value = excluded.value, updated_at = excluded.updated_at;
update pipeline.platform_toolset_settings set updated_at = '2026-11-03 09:07:09+00' where toolset_key = 'pipeline' and key like 'entry.%' and key not like 'entry.max_rows%';

-- RMIT Diploma of Commerce, CRICOS 111278B (IQ-00279): held by E13 since 29 Oct 12:44 AEDT; two identical refusals on stored copy a0ffab81
insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, evidence_id, identity_basis, read_status) values
 ('b365fde8-d003-4ef6-80c3-4136fbd5587a', '8e1adb6c-e069-43db-9584-bd054255e702',
  'https://www.rmit.edu.au/study-with-us/levels-of-study/undergraduate-study/higher-education-diplomas/diploma-of-commerce-dp020', 'title_match', 'bound',
  'a0ffab81-9eff-40dc-9d7b-b5dfbdd7c032', 'cricos_code', 'read');
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, status, escalation_reason, proposed_value, created_at) values
 ('a7849f66-bfa7-412e-b26e-4fecc7fdaa6e', 'course', 'b365fde8-d003-4ef6-80c3-4136fbd5587a', 'course_entry_first_read', '6ac70f57-7eba-4fe0-a907-4ca9554bf81f', 'pending',
  'Course entry requirements first read: a person admits the rows before any is active (Track C Step B)', '{"item_id": "228447"}', '2026-10-29 01:44:26.962788+00');
insert into fx.gates values ('a7849f66-bfa7-412e-b26e-4fecc7fdaa6e',
  '{"complete": false, "reasons": ["the reader dropped 2 printed requirement(s) (score_without_basis) that no row covers, so the read is incomplete"]}');
insert into pipeline.field_enrich_items(id, course_id, field, state, value, job_id, provider_id, evidence_id, source, reason, created_at, updated_at) values
 (228447, 'b365fde8-d003-4ef6-80c3-4136fbd5587a', 'entry_requirements', 'review',
  '{"dropped": [{"kind": "minimum_grade", "quote": "Prerequisites Victorian Certificate of Education (VCE) units 3 and 4: a study score of at least 20 in English other than EAL", "reason": "score_without_basis"}, {"kind": "minimum_grade", "quote": "a study score of at least 23 in English as an Additional Language (EAL) or equivalent studies.", "reason": "score_without_basis"}]}',
  'ecf3664a-32ff-4f64-8a9d-44851573d1ad', '8e1adb6c-e069-43db-9584-bd054255e702', '6ac70f57-7eba-4fe0-a907-4ca9554bf81f', 'ai_stored', null, '2026-10-29 01:43:56+00', '2026-10-29 01:44:26+00'),
 (265315, 'b365fde8-d003-4ef6-80c3-4136fbd5587a', 'entry_requirements', 'skipped', '{}', '14d6f338-ec30-48f3-9c37-fd4e8f618957', '8e1adb6c-e069-43db-9584-bd054255e702',
  'a0ffab81-9eff-40dc-9d7b-b5dfbdd7c032', 'ai_stored', 'held_partial: over_row_limit: the page has 9 requirements and the limit is 6; nothing proposed (E13)', '2026-11-03 06:13:00+00', '2026-11-03 06:14:47+00'),
 (270218, 'b365fde8-d003-4ef6-80c3-4136fbd5587a', 'entry_requirements', 'skipped', '{}', '8fb3173c-1de8-448d-ad86-b0ddeb1ac21b', '8e1adb6c-e069-43db-9584-bd054255e702',
  'a0ffab81-9eff-40dc-9d7b-b5dfbdd7c032', 'ai_stored', 'held_partial: over_row_limit: the page has 9 requirements and the limit is 6; nothing proposed (E13)', '2026-11-04 01:17:46+00', '2026-11-04 01:18:11+00');
select setval(pg_get_serial_sequence('pipeline.field_enrich_items', 'id'), 300000);
insert into pipeline.aer_read_supersessions(id, old_item_id, course_id, source_url, old_evidence_id, enrich_item_id, job_id, requested_by, reason, state, outcome, requested_at, closed_at) values
 ('3c06308a-1032-4b80-8cb9-b6fc8e37f487', 'a7849f66-bfa7-412e-b26e-4fecc7fdaa6e', 'b365fde8-d003-4ef6-80c3-4136fbd5587a', 'https://www.rmit.edu.au/x', '6ac70f57-7eba-4fe0-a907-4ca9554bf81f',
  265315, '14d6f338-ec30-48f3-9c37-fd4e8f618957', '63ba56cb-48d4-4169-98c2-7c4d1f72925b',
  'Scheduled entry reading (job aer-scheduled-read): the waiting read dropped printed requirements that no row covers; read again from the same stored page',
  'refused', 'the corrected read was cut at the row limit (E13)', '2026-11-03 06:13:00.287932+00', '2026-11-03 06:14:47.157039+00'),
 ('d05725e2-4814-4b80-957a-3d74357a67a5', 'a7849f66-bfa7-412e-b26e-4fecc7fdaa6e', 'b365fde8-d003-4ef6-80c3-4136fbd5587a', 'https://www.rmit.edu.au/x', '6ac70f57-7eba-4fe0-a907-4ca9554bf81f',
  270218, '8fb3173c-1de8-448d-ad86-b0ddeb1ac21b', '63ba56cb-48d4-4169-98c2-7c4d1f72925b', 'Layer 4 recovery: Rmit read 04111217',
  'refused', 'the corrected read was cut at the row limit (E13)', '2026-11-04 01:17:46.987344+00', '2026-11-04 01:18:11.945536+00');
insert into pipeline.layer4_aer_recovery_actions(review_item_id, case_key, choice, problem_fingerprint, reason, reviewer, work_item_status, next_operation, result, at)
select 'a7849f66-bfa7-412e-b26e-4fecc7fdaa6e', st->>'case_key', 'reread_stored', st->>'problem_fingerprint', 'Rmit read 04111217', '63ba56cb-48d4-4169-98c2-7c4d1f72925b', 'parked',
       'the existing reader reads the stored page again; the new read replaces this one only through the same gates',
       '{"job_id": "8fb3173c-1de8-448d-ad86-b0ddeb1ac21b", "request_id": "d05725e2-4814-4b80-957a-3d74357a67a5", "enrich_item_id": 270218, "review_item_id": "a7849f66-bfa7-412e-b26e-4fecc7fdaa6e"}',
       '2026-11-04 01:17:46.987344+00'
  from (select security.layer4_aer_recovery_state_v1('a7849f66-bfa7-412e-b26e-4fecc7fdaa6e') st) z;
insert into pipeline.admin_control_events(id, area, action, target, detail, actor, created_at) values
 (28863, 'layer4', 'inbox_decide', 'aer_review:a7849f66-bfa7-412e-b26e-4fecc7fdaa6e',
  '{"ref": "a7849f66-bfa7-412e-b26e-4fecc7fdaa6e", "kind": "aer_review", "value": null, "choice": "reread_stored", "reason": "Rmit read 04111217", "result": {"job_id": "8fb3173c-1de8-448d-ad86-b0ddeb1ac21b", "request_id": "d05725e2-4814-4b80-957a-3d74357a67a5", "enrich_item_id": 270218, "review_item_id": "a7849f66-bfa7-412e-b26e-4fecc7fdaa6e"}, "provider_id": "8e1adb6c-e069-43db-9584-bd054255e702", "recovery_action": 0}',
  '63ba56cb-48d4-4169-98c2-7c4d1f72925b', '2026-11-04 01:17:46.987344+00');
select setval(pg_get_serial_sequence('pipeline.admin_control_events', 'id'), 30000);
select security.work_item_report_v1('aer_technical', 'a7849f66-bfa7-412e-b26e-4fecc7fdaa6e', 'l4_item', 'failed',
  jsonb_build_object('class', 'technical_hold', 'provider_id', '8e1adb6c-e069-43db-9584-bd054255e702', 'message', 'technically held: over_row_limit'));

-- Lifecycle University: the §9 cases (each course has its bound page and stored copy)
insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, evidence_id, identity_basis, read_status)
select c.id, c.provider_id, 'https://www.lifeuni.edu.au/' || c.course_code, 'title_match', 'bound', md5('copy:' || c.course_code)::uuid, 'cricos_code', 'read'
  from catalogue.courses c where c.provider_id = '5a000000-0000-4000-8000-000000000001';
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status, escalation_reason, created_at, decided_at) values
 -- accepted but still incomplete; role-disabled; Refresh during the asynchronous read
 ('5e000000-0000-4000-8000-000000000002', 'course', '5c000000-0000-4000-8000-000000000002', 'course_entry_first_read', 'pending', 'held', now() - interval '3 days', null),
 -- duplicate request (open human input twice)
 ('5e000000-0000-4000-8000-000000000004', 'course', '5c000000-0000-4000-8000-000000000004', 'course_entry_first_read', 'pending', 'held', now() - interval '2 days', null),
 -- successful corrected read (the original is superseded)
 ('5e000000-0000-4000-8000-000000000005', 'course', '5c000000-0000-4000-8000-000000000005', 'course_entry_first_read', 'pending', 'held', now() - interval '6 days', null),
 -- admitted and published
 ('5e000000-0000-4000-8000-000000000008', 'course', '5c000000-0000-4000-8000-000000000008', 'course_entry_first_read', 'approved', 'complete', now() - interval '4 days', now() - interval '1 day'),
 -- re-entry after technical recovery: an earlier read withdrawn, the new one waiting
 ('5e000000-0000-4000-8000-000000000090', 'course', '5c000000-0000-4000-8000-000000000009', 'course_entry_first_read', 'withdrawn', 'held', now() - interval '10 days', now() - interval '2 days'),
 ('5e000000-0000-4000-8000-000000000009', 'course', '5c000000-0000-4000-8000-000000000009', 'course_entry_first_read', 'pending', 'held', now() - interval '1 day', null),
 -- the other review-item kinds
 ('5e000000-0000-4000-8000-000000000101', 'course', '5c000000-0000-4000-8000-000000000010', 'course_url', 'pending', 'A newer page was found', now() - interval '5 days', null),
 ('5e000000-0000-4000-8000-000000000102', 'provider', '5a000000-0000-4000-8000-000000000001', 'provider_description', 'pending', 'University description', now() - interval '5 days', null),
 ('5e000000-0000-4000-8000-000000000103', 'course', '5c000000-0000-4000-8000-000000000011', 'course_description_first_read', 'pending', 'Course description', now() - interval '5 days', null),
 ('5e000000-0000-4000-8000-000000000104', 'provider', '5a000000-0000-4000-8000-000000000001', 'no_page_first_run', 'pending', 'No page published', now() - interval '5 days', null),
 ('5e000000-0000-4000-8000-000000000105', 'provider', '5a000000-0000-4000-8000-000000000001', 'conjoint_rule_first_run', 'pending', 'Conjoint', now() - interval '5 days', null);
insert into fx.gates
select id, '{"complete": false, "reasons": ["the reader dropped 1 printed requirement(s) that no row covers, so the read is incomplete"]}'::jsonb
  from pipeline.layer4_review_items where id::text like '5e000000%' and field_code = 'course_entry_first_read' and status = 'pending';
insert into catalogue.course_entry_requirements(course_id, status, quote, provenance, updated_at) values
 ('5c000000-0000-4000-8000-000000000008', 'active', 'A bachelor degree in any discipline', '{"review_item_id": "5e000000-0000-4000-8000-000000000008"}', now() - interval '1 day'),
 ('5c000000-0000-4000-8000-000000000008', 'active', 'IELTS 7.0 overall', '{"review_item_id": "5e000000-0000-4000-8000-000000000008"}', now() - interval '1 day');
insert into pipeline.admin_control_events(area, action, target, detail, actor, created_at) values
 ('layer4', 'inbox_decide', 'aer_review:5e000000-0000-4000-8000-000000000008', '{"kind": "aer_review", "choice": "approve", "reason": "every row quoted", "result": {"status": "approved", "decision_id": "d1", "review_item_id": "5e000000-0000-4000-8000-000000000008"}}',
  '63ba56cb-48d4-4169-98c2-7c4d1f72925b', now() - interval '1 day');
-- the earlier read of the re-entered course went to technical recovery (an intervention, resumed and verified) before the new read arrived
insert into pipeline.layer4_interventions(lane, entity, missing_fact, provider_id, course_id, subject, status, issue, required_input, recommended, allowed_actions, resume_target,
            fingerprint, created_at, input_at, resumed_at, verified_at, verified_outcome, updated_at)
values ('aer_item', '5e000000-0000-4000-8000-000000000090', 'aer_read_rows_missing', '5a000000-0000-4000-8000-000000000001', '5c000000-0000-4000-8000-000000000009',
        'Diploma of Business: dropped requirements to enter', 'resolved', '{"summary": "held"}', '{"ask": "rows"}', '{"action": "enter_value"}', '{}', '{}', 'fp-090', now() - interval '9 days', now() - interval '3 days', now() - interval '3 days', now() - interval '2 days', 'read_replaced', now() - interval '2 days');

-- one waiting item of every other kind
insert into pipeline.scholarship_ai_reviews(id, provider_id, url, reason, status, created_at, extraction_ids) values
 (9901, '5a000000-0000-4000-8000-000000000001', 'https://www.lifeuni.edu.au/scholarships/merit', 'AI could not decide', 'pending', now() - interval '4 days', '{}');
insert into pipeline.provider_onboarding(id, provider_id, status, stop_reason, note, created_at, updated_at)
select ('5b000000-0000-4000-8000-00000000000' || n)::uuid, ('5a000000-0000-4000-8000-00000000001' || n)::uuid, 'stopped', r, 'stopped: ' || r, now() - make_interval(days => 6 - n), now() - make_interval(days => 6 - n)
  from (values (1, 'no_website'), (2, 'too_few_pages'), (3, 'nothing_ready'), (4, 'approve_central'), (5, 'proposal_failed')) v(n, r);
insert into pipeline.enrichment_flags(id, entity, entity_key, provider_id, state, reason_code, reason, evidence, flagged_at) values
 (8801, 'provider', '5a000000-0000-4000-8000-000000000001', '5a000000-0000-4000-8000-000000000001', 'raised', 'course_pages_not_found', 'no course pages', '{}', now() - interval '8 days'),
 (8802, 'provider', '5a000000-0000-4000-8000-000000000001', '5a000000-0000-4000-8000-000000000001', 'raised', 'site_unreachable', 'the site did not answer', '{}', now() - interval '40 days'),
 (8803, 'provider', '5a000000-0000-4000-8000-000000000001', '5a000000-0000-4000-8000-000000000001', 'raised', 'adapter_fee_fails_check', 'fee fails', '{}', now() - interval '8 days'),
 (8804, 'course', '5c000000-0000-4000-8000-000000000012', '5a000000-0000-4000-8000-000000000001', 'raised', 'not_offered', 'not offered', '{}', now() - interval '8 days'),
 (8805, 'course', '5c000000-0000-4000-8000-000000000013', '5a000000-0000-4000-8000-000000000001', 'raised', 'not_on_provider_site', 'not on the site', '{}', now() - interval '8 days'),
 (8806, 'course', '5c000000-0000-4000-8000-000000000013', '5a000000-0000-4000-8000-000000000001', 'raised', 'fee_crosscheck', 'fee cross-check', '{}', now() - interval '8 days');
insert into pipeline.course_page_needed(course_id, provider_id, state, refused, last_refused_reason, searches_requested, created_at, updated_at, last_refused_at) values
 ('5c000000-0000-4000-8000-000000000012', '5a000000-0000-4000-8000-000000000001', 'open', 2, 'title differs', 0, now() - interval '3 days', now() - interval '1 day', now() - interval '1 day');
insert into pipeline.data_flags(id, entity_type, entity_id, field_code, detail, flag_code, status, created_at) values
 ('5d000000-0000-4000-8000-000000000001', 'course', '5c000000-0000-4000-8000-000000000010', 'fee', '{"label": "Fee", "note": "the fee is out of date"}', 'reported', 'open', now() - interval '2 days');
insert into pipeline.layer1_provider_departures(id, provider_id, courses_retired, note, status, created_at) values
 (7701, '5a000000-0000-4000-8000-000000000002', 12, 'all courses left the register', 'needs_review', now() - interval '6 days');
