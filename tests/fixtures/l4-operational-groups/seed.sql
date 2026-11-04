-- CF-247 Layer 4 operational groups fixtures: production-shaped records for Course Link, AER, scholarship and onboarding (shapes and classes as
-- read live 4 Nov 2026 17:11-17:16 AEDT: readiness routes covered_by_active, entity_retired, invalid_link, manual_lock, completeness_gate,
-- review:curator and review:platform_admin; the approved Course Link rule pattern; onboarding results; hold evidence). No live data is copied.
\set ON_ERROR_STOP on
insert into catalogue.providers(id, stable_key, canonical_name, display_name, website, country_id, publication_status, updated_at) values
 ('6a000000-0000-4000-8000-000000000001', 'groupuni', 'Group University', 'Group University', 'https://www.groupuni.edu.au', '00000000-0000-4000-8000-0000000000a1', 'published', now() - interval '20 days'),
 ('6a000000-0000-4000-8000-000000000002', 'otheruni', 'Other University', 'Other University', 'https://www.otheruni.edu.au', '00000000-0000-4000-8000-0000000000a1', 'published', now() - interval '20 days'),
 ('6a000000-0000-4000-8000-000000000003', 'astra', 'Astra College', 'Astra College', 'https://astra.edu.au', '00000000-0000-4000-8000-0000000000a1', 'unpublished', now() - interval '20 days'),
 ('6a000000-0000-4000-8000-000000000004', 'intia', 'Intia Institute', 'Intia Institute', 'https://www.intia.com.au', '00000000-0000-4000-8000-0000000000a1', 'unpublished', now() - interval '20 days')
on conflict (id) do nothing;
insert into catalogue.courses(id, provider_id, canonical_title, course_code, lifecycle_status)
select ('6c000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, case when n <= 8 then '6a000000-0000-4000-8000-000000000001' else '6a000000-0000-4000-8000-000000000002' end::uuid,
       'Group course ' || n, '30' || lpad(n::text, 4, '0') || 'A', 'active'
  from generate_series(1, 10) n on conflict do nothing;
-- an approved Course Link rule for Group University, in the shape of the three live rules (held address with a year, use the one without)
insert into pipeline.layer4_course_link_rules(code, provider_id, choice, reason_like, held_regex, proposed_replace, identity_bases, approved_by, approved_at, approved_items, approval_ref, strict, note)
values ('fx_group_no_year', '6a000000-0000-4000-8000-000000000001', 'use', '%CRICOS code is a different address%', '/20[0-9]{2}$', '', array['cricos_code'], 'Platform Admin', 'fixture', 1, 'fixture', false, 'fixture')
on conflict do nothing;
-- official-link items, routed by the real Course Link classifier (20261104570000): its class decides their group
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status, escalation_reason, before_value, proposed_value, created_at) values
 ('6e000000-0000-4000-8000-000000000001', 'course', '6c000000-0000-4000-8000-000000000001', 'official_course_url', 'pending', 'The page found by this course''s CRICOS code is a different address',
  '["https://www.groupuni.edu.au/courses/c1/2026"]', '{"course_url": "https://www.groupuni.edu.au/courses/c1"}', now() - interval '6 days'),
 ('6e000000-0000-4000-8000-000000000002', 'course', '6c000000-0000-4000-8000-000000000002', 'official_course_url', 'pending', 'A newer page was found',
  '["https://www.groupuni.edu.au/courses/c2"]', '{"course_url": "https://www.groupuni.edu.au/courses/c2"}', now() - interval '5 days'),
 ('6e000000-0000-4000-8000-000000000003', 'course', '6c000000-0000-4000-8000-000000000003', 'official_course_url', 'pending', 'A newer page was found',
  '["https://www.groupuni.edu.au/courses/c3"]', '{"course_url": "https://www.groupuni.edu.au/courses/c3-new"}', now() - interval '5 days'),
 ('6e000000-0000-4000-8000-000000000004', 'course', '6c000000-0000-4000-8000-000000000004', 'official_course_url', 'pending', 'A newer page was found',
  '["https://www.groupuni.edu.au/courses/c4"]', '{"course_url": "groupuni.edu.au/c4"}', now() - interval '4 days'),
 ('6e000000-0000-4000-8000-000000000005', 'course', '6c000000-0000-4000-8000-000000000005', 'official_course_url', 'pending', 'A newer page was found',
  '["https://www.groupuni.edu.au/courses/c5"]', '{"course_url": "https://www.groupuni.edu.au/courses/c5-b"}', now() - interval '3 days'),
 -- AER: ready (C), held by the completeness gate (B), held with an open Human input needed item (D)
 ('6e000000-0000-4000-8000-000000000006', 'course', '6c000000-0000-4000-8000-000000000006', 'course_entry_first_read', 'pending', 'first read', null, null, now() - interval '3 days'),
 ('6e000000-0000-4000-8000-000000000007', 'course', '6c000000-0000-4000-8000-000000000007', 'course_entry_first_read', 'pending', 'first read', null, null, now() - interval '3 days'),
 ('6e000000-0000-4000-8000-000000000008', 'course', '6c000000-0000-4000-8000-000000000008', 'course_entry_first_read', 'pending', 'first read', null, null, now() - interval '3 days'),
 -- another university's ready item (§10.10: other providers continue)
 ('6e000000-0000-4000-8000-000000000009', 'course', '6c000000-0000-4000-8000-000000000009', 'course_entry_first_read', 'pending', 'first read', null, null, now() - interval '2 days'),
 -- the earlier decision the re-raised item repeats
 ('6e000000-0000-4000-8000-000000000010', 'course', '6c000000-0000-4000-8000-000000000003', 'official_course_url', 'rejected', 'A newer page was found',
  '["https://www.groupuni.edu.au/courses/c3"]', '{"course_url": "https://www.groupuni.edu.au/courses/c3-new"}', now() - interval '30 days');
insert into pipeline.layer4_item_readiness(item_id, entity_type, entity_id, field_code, item_created_at, item_status, readiness, reasons, route, resolution)
select r.id, r.entity_type, r.entity_id, r.field_code, r.created_at, r.status, x.readiness, x.reasons, x.route, x.resolution
  from pipeline.layer4_review_items r join (values
   ('6e000000-0000-4000-8000-000000000001'::uuid, 'judgement_ready', '{}'::text[], 'review:curator', null::jsonb),
   ('6e000000-0000-4000-8000-000000000002', 'resolvable', '{covered_by_active}', 'platform:covered_by_active', '{"reason": "covered_by_active"}'),
   ('6e000000-0000-4000-8000-000000000003', 'resolvable', '{decided_before}', 'platform:decided_before',
    jsonb_build_object('reason', 'decided_before', 'covered_by_item', '6e000000-0000-4000-8000-000000000010', 'decision', 'rejected', 'decided_at', now() - interval '29 days')),
   ('6e000000-0000-4000-8000-000000000004', 'technical_blocked', '{invalid_link}', 'repair:invalid_link', null),
   ('6e000000-0000-4000-8000-000000000005', 'judgement_ready', '{}', 'review:curator', null),
   ('6e000000-0000-4000-8000-000000000006', 'judgement_ready', '{}', 'review:platform_admin', null),
   ('6e000000-0000-4000-8000-000000000007', 'technical_blocked', '{completeness_gate}', 'repair:completeness_gate', null),
   ('6e000000-0000-4000-8000-000000000008', 'technical_blocked', '{completeness_gate}', 'repair:completeness_gate', null),
   ('6e000000-0000-4000-8000-000000000009', 'judgement_ready', '{}', 'review:platform_admin', null)) x(id, readiness, reasons, route, resolution) on x.id = r.id;
insert into pipeline.layer4_interventions(lane, entity, missing_fact, provider_id, course_id, subject, status, issue, required_input, recommended, allowed_actions, resume_target, fingerprint, created_at)
values ('aer_item', '6e000000-0000-4000-8000-000000000008', 'aer_read_rows_missing', '6a000000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000008',
        'Group course 8: dropped requirements to enter', 'awaiting_input', '{"summary": "held"}', '{"ask": "Enter the dropped requirements as rows with quotations"}', '{"action": "enter_value"}', '{}', '{}', 'fp-g8', now() - interval '1 day');
-- scholarship: a held review, decided once in a batch whose first call did not apply
insert into pipeline.scholarship_ai_reviews(id, provider_id, url, reason, status, created_at, extraction_ids) values
 (9911, '6a000000-0000-4000-8000-000000000001', 'https://www.groupuni.edu.au/scholarships/merit', 'AI could not decide', 'pending', now() - interval '20 days', '{}'),
 (9912, '6a000000-0000-4000-8000-000000000001', 'https://www.groupuni.edu.au/scholarships/global', 'AI could not decide', 'pending', now() - interval '20 days', '{}');
-- onboarding: an adapter with nothing ready (live result shape), a failed proposal, and page holds with their evidence
insert into pipeline.provider_onboarding(id, provider_id, status, stop_reason, note, created_at, updated_at, result) values
 ('6b000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000003', 'stopped', 'nothing_ready', 'Nothing passed after 2 AI attempt(s); the Fields column shows why for each field.',
  now() - interval '10 days', now() - interval '10 days',
  '{"held": {"fee": "not read by the adapter", "english": "read on 1 of 4 pages, under the share needed"}, "ready": [], "courses": 11, "website": "https://astra.edu.au", "pages_read": 3, "ai_attempts": 2}'),
 ('6b000000-0000-4000-8000-000000000002', '6a000000-0000-4000-8000-000000000004', 'stopped', 'proposal_failed', 'The proposal failed: the model timed out', now() - interval '9 days', now() - interval '9 days',
  '{"courses": 4, "website": "https://www.intia.com.au", "pages_read": 2, "ai_attempts": 1}');
insert into pipeline.enrichment_flags(id, entity, entity_key, provider_id, state, reason_code, reason, evidence, flagged_at) values
 (8901, 'provider', '6a000000-0000-4000-8000-000000000004', '6a000000-0000-4000-8000-000000000004', 'raised', 'course_pages_not_found', 'no course pages',
  '{"site": "https://www.intia.com.au", "wave": "refind-1", "method": "map(0)+map_search(0)", "addresses": 0, "discovery": "failed", "pages_read": 0}', now() - interval '15 days');
