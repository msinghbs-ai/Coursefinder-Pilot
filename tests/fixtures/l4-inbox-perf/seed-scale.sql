-- CF-247 Layer 4 Inbox performance fixture: a production-scale Inbox (live shape 4 Nov 2026 06:56 AEDT: 4,995 waiting items, 838 universities,
-- the largest 376 items with 303 AER; 28k review items in all; 200k stored copies; 86k flags). Here: about 5,000 waiting items over 200
-- universities, the same kinds in about the same shares, one university with 303 AER items, many items sharing a creation time (so the cursor's
-- tie-break is exercised), 20,000 decided review items, 60,000 stored copies with repeated addresses (newer copies) and 40,000 cleared flags.
-- Deterministic (setseed). Scratch PostgreSQL only; nothing here is live data.
do $$ begin perform setseed(0.4410); end $$;
-- the earlier fixtures insert their own ids: move each sequence past them
do $$ declare t text; begin
  foreach t in array array['pipeline.enrichment_flags', 'pipeline.scholarship_ai_reviews', 'pipeline.data_flags', 'pipeline.layer1_provider_departures', 'pipeline.admin_control_events'] loop
    execute format('select setval(pg_get_serial_sequence(%L, ''id''), (select coalesce(max(id), 0) + 1 from %s))', t, t);
  end loop;
end $$;
alter table pipeline.layer4_review_items disable trigger user;

insert into ref.countries(id, iso_alpha2) values ('a0000000-0000-0000-0000-0000000000a1', 'AU'), ('a0000000-0000-0000-0000-0000000000a2', 'NZ'), ('a0000000-0000-0000-0000-0000000000a3', 'CA');
create function pg_temp.pid(g int) returns uuid language sql immutable as $f$ select ('10000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid $f$;
create function pg_temp.cid(g int) returns uuid language sql immutable as $f$ select ('20000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid $f$;
create function pg_temp.eid(g int) returns uuid language sql immutable as $f$ select ('30000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid $f$;
-- a skewed university for item g: a few universities hold most items, as live
create function pg_temp.skew() returns int language sql volatile as $f$ select 1 + floor(200 * power(random(), 2))::int $f$;

insert into catalogue.providers(id, canonical_name, country_id)
select pg_temp.pid(g), 'Scale University ' || lpad(g::text, 3, '0'),
       case when g % 10 = 0 then 'a0000000-0000-0000-0000-0000000000a2'::uuid when g % 10 = 1 then 'a0000000-0000-0000-0000-0000000000a3'::uuid else 'a0000000-0000-0000-0000-0000000000a1'::uuid end
  from generate_series(1, 200) g;
insert into catalogue.courses(id, provider_id, canonical_title, course_code, lifecycle_status)
select pg_temp.cid(g), pg_temp.pid(1 + (g - 1) / 125), 'Scale Course ' || g, 'SC' || g, case when g % 50 = 0 then 'archived' else 'active' end from generate_series(1, 25000) g;
insert into pipeline.evidence_artifacts(id, entity_id, source_url, captured_at)
select pg_temp.eid(g), pg_temp.cid(1 + g % 25000), 'https://u' || (1 + (g % 25000) / 125) || '.example.edu/course/' || (g % 30000), timestamptz '2026-10-01 00:00+00' + (g % 700) * interval '1 hour'
  from generate_series(1, 60000) g;

-- review items: 20,000 decided, then the waiting ones
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, escalation_reason, created_at)
select 'course', pg_temp.cid(1 + g % 25000), 'official_course_url', pg_temp.eid(1 + g % 60000), '["https://a.example.edu/x"]', '["https://a.example.edu/y"]', 'approved', 'decided', timestamptz '2026-09-01 00:00+00' + g * interval '1 minute'
  from generate_series(1, 20000) g;
-- course links (about 3,300), on skewed universities; creation times to the hour, so many items share one
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, status, escalation_reason, created_at)
select 'course', pg_temp.cid((p - 1) * 125 + 1 + g % 125), 'official_course_url', case when g % 4 = 0 then null else pg_temp.eid(1 + (g * 7) % 60000) end,
       jsonb_build_array('https://u' || p || '.example.edu/course/old-' || g), jsonb_build_object('url', 'https://u' || p || '.example.edu/course/' || g, 'note', repeat('proposed page detail ', 30)),
       'pending', 'A different page was found for this course', timestamptz '2026-10-20 00:00+00' + (g % 300) * interval '1 hour'
  from (select g, pg_temp.skew() p from generate_series(1, 3300) g) s;
-- AER: 303 for university 7, the rest spread (course entry first reads)
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, proposed_value, status, escalation_reason, created_at)
select 'course', pg_temp.cid((p - 1) * 125 + 1 + g % 125), 'course_entry_first_read', pg_temp.eid(1 + (g * 13) % 60000),
       jsonb_build_object('rows', (select jsonb_agg(jsonb_build_object('kind', 'atar', 'score', 80 + r, 'quote', repeat('minimum entry score ', 8))) from generate_series(1, 6) r)),
       'pending', 'Entry requirements to review', timestamptz '2026-10-25 00:00+00' + (g % 120) * interval '1 hour'
  from (select g, case when g <= 303 then 7 else pg_temp.skew() end p from generate_series(1, 600) g) s;
-- university descriptions (465) and first runs (60)
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, proposed_value, status, escalation_reason, created_at)
select 'provider', pg_temp.pid(1 + g % 200), 'provider_description',
       jsonb_build_object('description', repeat('A university description sentence. ', 12), 'sentences', (select jsonb_agg(jsonb_build_object('text', 'Sentence ' || r, 'quote', repeat('quoted words ', 10))) from generate_series(1, 5) r)),
       'pending', 'Approve as read or reject', timestamptz '2026-10-28 00:00+00' + (g % 48) * interval '1 hour'
  from generate_series(1, 465) g;
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, proposed_value, status, escalation_reason, created_at)
select 'provider', pg_temp.pid(1 + (g * 3) % 200), case when g <= 55 then 'no_page_first_run' else 'conjoint_rule_first_run' end, jsonb_build_object('sample', '[]'::jsonb),
       'pending', 'First run', timestamptz '2026-10-26 00:00+00' + g * interval '1 hour'
  from generate_series(1, 60) g;

-- held scholarships (132)
insert into pipeline.scholarship_ai_reviews(provider_id, extraction_ids, url, reason, recheck, status, created_at)
select pg_temp.pid(pg_temp.skew()), '{}', 'https://example.edu/scholarship/' || g, 'Held by the publish checks', jsonb_build_object('why', 'International students not named'), 'pending',
       timestamptz '2026-10-22 00:00+00' + (g % 40) * interval '1 hour'
  from generate_series(1, 132) g;
-- stopped onboarding (one each for 150 universities)
insert into pipeline.provider_onboarding(provider_id, status, stop_reason, note, created_at, updated_at)
select pg_temp.pid(g), 'stopped', (array['nothing_ready', 'nothing_ready', 'nothing_ready', 'too_few_pages', 'no_website', 'approve_central', 'proposal_failed'])[1 + g % 7], null,
       timestamptz '2026-10-01 00:00+00', timestamptz '2026-10-15 00:00+00' + (g % 20) * interval '1 hour'
  from generate_series(1, 150) g;
-- provider holds (60), course holds (80) and 40,000 cleared flags
insert into pipeline.enrichment_flags(entity, entity_key, provider_id, state, reason_code, reason, evidence, flagged_at)
select 'provider', pg_temp.pid(151 + g % 50)::text || ':' || g, pg_temp.pid(151 + g % 50), 'raised', case when g % 10 = 0 then 'adapter_fee_fails_check' else 'course_pages_not_found' end, 'Held', '{}', timestamptz '2026-10-10 00:00+00' + g * interval '1 hour'
  from generate_series(1, 60) g;
insert into pipeline.enrichment_flags(entity, entity_key, provider_id, state, reason_code, reason, evidence, flagged_at)
select 'course', pg_temp.cid(g * 211)::text, null, 'raised', (array['not_offered', 'not_on_provider_site', 'fee_crosscheck'])[1 + g % 3], 'Held course', '{}', timestamptz '2026-10-12 00:00+00' + (g % 10) * interval '1 hour'
  from generate_series(1, 80) g;
insert into pipeline.enrichment_flags(entity, entity_key, provider_id, state, reason_code, reason, flagged_at)
select 'course', 'cleared-' || g, pg_temp.pid(1 + g % 200), 'cleared', 'not_offered', 'Cleared', timestamptz '2026-09-01 00:00+00' from generate_series(1, 40000) g;
-- course page needed (75), counsellor reports (20), departures (7)
insert into pipeline.course_page_needed(course_id, provider_id, state, refused, last_refused_url, last_refused_reason, created_at)
select pg_temp.cid(g * 300 + 1), pg_temp.pid(1 + (g * 300) / 125), 'open', 1 + g % 3, 'https://example.edu/wrong/' || g, 'not this course', timestamptz '2026-11-01 00:00+00' + (g % 5) * interval '1 hour'
  from generate_series(1, 75) g;
insert into pipeline.data_flags(entity_type, entity_id, field_code, detail, flag_code, status, created_at)
select 'course', pg_temp.cid(g * 997), 'fee', jsonb_build_object('label', 'Fee looks wrong', 'note', 'Counsellor note ' || g), 'reported', 'open', timestamptz '2026-10-30 00:00+00' + g * interval '1 hour'
  from generate_series(1, 20) g;
insert into pipeline.layer1_provider_departures(provider_id, courses_retired, note, status, created_at)
select pg_temp.pid(190 + g), 3 + g, null, 'needs_review', timestamptz '2026-10-29 00:00+00' from generate_series(1, 7) g;

alter table pipeline.layer4_review_items enable trigger user;
analyze;
