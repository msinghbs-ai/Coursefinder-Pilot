-- Fixture data for the AER read-now scenarios. The id prefix tells the story: 1000..00NN providers, 3N.. courses, 4N.. layer 4 items.
insert into ref.countries values (1, 'AU', 'Australia'), (2, 'NZ', 'New Zealand');
insert into ref.provider_types values (1, 'university');
insert into pipeline.platform_toolset_settings values
  ('pipeline', 'aer.schedule_layer4_max', '600'), ('pipeline', 'aer.schedule_daily_max', '200'), ('pipeline', 'aer.schedule_per_provider', '5'), ('pipeline', 'aer.replay_on', '1'), ('pipeline', 'aer.replay_per_provider', '5'),
  ('pipeline', 'aer.replay_daily_max', '100'), ('pipeline', 'aer.e13_recover_on', '0'), ('pipeline', 'aer.source_stored_find_on', '1'), ('pipeline', 'aer.review_packet_rows', '30'), ('pipeline', 'entry.attach_per_provider', '3'),
  ('pipeline', 'aer.schedule_retry_days', '30'), ('pipeline', 'entry.matrix_refresh_days', '30'), ('pipeline', 'entry.course_read_countries', '["AU", "NZ"]'), ('openrouter', 'credit_floor_usd', '5'),
  ('pipeline', 'aer.schedule_lock_fields', '["entry_requirements"]');
insert into pipeline.layer3_openrouter_observations(kind, remaining_usd) values ('credits', 100);
insert into cron.job(jobname, schedule, active) values ('aer-scheduled-read', '13 * * * *', true);
insert into pipeline.evidence_artifacts(id, storage_path, mime_type) values ('20000000-0000-0000-0000-000000000001', 'x/1', 'text/html'), ('20000000-0000-0000-0000-000000000002', 'x/2', 'text/html'), ('20000000-0000-0000-0000-000000000009', null, null);

insert into catalogue.providers(id, canonical_name, country_id, enrols_international) values
  ('10000000-0000-0000-0000-000000000001', 'PA matrix with Nepal and IB rows', 1, true),
  ('10000000-0000-0000-0000-000000000002', 'PB course pages waiting', 1, true),
  ('10000000-0000-0000-0000-000000000003', 'PC title matched only', 1, true),
  ('10000000-0000-0000-0000-000000000004', 'PD nothing stored', 1, true),
  ('10000000-0000-0000-0000-000000000005', 'PF source read failed', 1, true),
  ('10000000-0000-0000-0000-000000000006', 'PG all read', 1, true),
  ('10000000-0000-0000-0000-000000000007', 'PH held reads', 1, true),
  ('10000000-0000-0000-0000-000000000008', 'PI ready course packets', 1, true),
  ('10000000-0000-0000-0000-000000000009', 'PJ New Zealand', 2, true),
  ('10000000-0000-0000-0000-00000000000a', 'PK not eligible', 1, false),
  ('10000000-0000-0000-0000-00000000000b', 'PL course cases', 1, true),
  ('10000000-0000-0000-0000-00000000000c', 'PM read in flight', 1, true);

-- courses and their bound pages
insert into catalogue.courses(id, provider_id, canonical_title) select ('30000000-0000-0000-0000-00000000000' || g)::uuid, '10000000-0000-0000-0000-000000000002', 'PB course ' || g from generate_series(1, 4) g;
insert into catalogue.courses(id, provider_id, canonical_title) select ('31000000-0000-0000-0000-00000000000' || g)::uuid, '10000000-0000-0000-0000-000000000003', 'PC course ' || g from generate_series(1, 2) g;
insert into catalogue.courses(id, provider_id, canonical_title) select ('32000000-0000-0000-0000-00000000000' || g)::uuid, '10000000-0000-0000-0000-000000000007', 'PH course ' || g from generate_series(1, 2) g;
insert into catalogue.courses(id, provider_id, canonical_title) select ('33000000-0000-0000-0000-00000000000' || g)::uuid, '10000000-0000-0000-0000-000000000008', 'PI course ' || g from generate_series(1, 2) g;
insert into catalogue.courses(id, provider_id, canonical_title) values ('34000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000009', 'PJ NZ course 1'), ('35000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000006', 'PG course 1'),
  ('36000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000b', 'PL no page'), ('37000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000b', 'PL page not stored'),
  ('38000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000b', 'PL locked'), ('39000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000b', 'PL title matched'),
  ('3a000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000b', 'PL not bound');
insert into catalogue.courses(id, provider_id, canonical_title, lifecycle_status) values ('3b000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000b', 'PL inactive', 'inactive');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, identity_basis, evidence_id)
  select c.id, c.provider_id, 'https://x.edu.au/' || c.canonical_title, 'bound', case when c.provider_id = '10000000-0000-0000-0000-000000000003' then 'exact_title' else 'cricos_code' end, '20000000-0000-0000-0000-000000000001'
    from catalogue.courses c where c.provider_id in ('10000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000006');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, identity_basis, evidence_id) values
  ('37000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000b', 'https://x.edu.au/nostore', 'bound', 'cricos_code', '20000000-0000-0000-0000-000000000009'),
  ('38000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000b', 'https://x.edu.au/locked', 'bound', 'cricos_code', '20000000-0000-0000-0000-000000000001'),
  ('39000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000b', 'https://x.edu.au/title', 'bound', 'exact_title', '20000000-0000-0000-0000-000000000001'),
  ('3a000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000b', 'https://x.edu.au/candidate', 'candidate', null, null);
insert into pipeline.manual_locks values ('course', '38000000-0000-0000-0000-000000000001', 'entry_requirements', 'locked');

-- the no_source findings (the route names the next step)
insert into pipeline.aer_gap_findings(fingerprint, root_cause, provider_id, evidence) values
  ('fp-pc', 'no_source', '10000000-0000-0000-0000-000000000003', '{"route": "course_pages_unconfirmed"}'), ('fp-pd', 'no_source', '10000000-0000-0000-0000-000000000004', '{"route": "nothing_stored"}');

-- PA: a university matrix with a source, a finished read and one waiting complete packet whose rows state Nepal and IB in different degrees
insert into pipeline.entry_matrix_sources(id, provider_id, url, status, evidence_id, read_at) values ('50000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'https://pa.edu.au/entry', 'read', '20000000-0000-0000-0000-000000000001', now());
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code) values ('40000000-0000-0000-0000-000000000001', 'provider', '10000000-0000-0000-0000-000000000001', 'entry_matrix_first_run');
insert into pipeline.layer4_item_readiness(item_id, entity_type, entity_id, field_code, item_status, readiness, reasons, route, gate) values ('40000000-0000-0000-0000-000000000001', 'provider', '10000000-0000-0000-0000-000000000001', 'entry_matrix_first_run', 'pending', 'judgement_ready', '{}', 'review', '{"complete": true}');
insert into pipeline.entry_matrix_runs(id, provider_id, source_id, state, review_item_id, rows_admitted) values ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', 'done', '40000000-0000-0000-0000-000000000001', 4);
insert into catalogue.provider_entry_matrix(id, provider_id, run_id, status, country_code, qualification_name, min_grade, min_value, grade_scale, level_label, audience, source_url, quote, evidence_id, intake_year, edition) values
  -- every fact printed
  ('70000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'proposed', 'NP', 'International Baccalaureate Diploma', '30', 30, 'IB points out of 45', 'Bachelor', 'international', 'https://pa.edu.au/entry', 'IB Diploma: 30 points', '20000000-0000-0000-0000-000000000001', 2026, null),
  -- the grade is printed but the scale and the year are not
  ('70000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'proposed', 'NP', 'International Baccalaureate Diploma', '28', 28, null, 'Bachelor', 'international', 'https://pa.edu.au/entry', 'IB Diploma: 28', '20000000-0000-0000-0000-000000000001', null, null),
  -- the country is not printed (a Nepal row elsewhere must not fill it)
  ('70000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'proposed', null, 'Higher Secondary Education Board', '60%', 60, 'percent', 'Bachelor', 'international', 'https://pa.edu.au/entry', 'HSEB 60%', '20000000-0000-0000-0000-000000000001', null, '2026 edition'),
  -- no grade is printed: scale does not apply; applicability, source page and the year are not stated either
  ('70000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'proposed', 'NP', 'Foundation year', null, null, null, null, null, null, null, null, null, null);
-- an active row of the same provider is not a proposed row and is not counted as a candidate
insert into catalogue.provider_entry_matrix(id, provider_id, run_id, status, country_code, qualification_name, min_grade, level_label, audience, source_url, quote, evidence_id) values
  ('70000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-000000000001', null, 'active', 'AU', 'ATAR', '70', 'Bachelor', 'domestic', 'u', 'q', '20000000-0000-0000-0000-000000000001');

-- PF: the latest read of its stored source failed technically; a second source held unparsed is not read again here
insert into pipeline.entry_matrix_sources(id, provider_id, url, status, evidence_id, read_at) values ('50000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000005', 'https://pf.edu.au/entry', 'read', '20000000-0000-0000-0000-000000000001', now() - interval '3 days'),
  ('50000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000005', 'https://pf.edu.au/other', 'read', '20000000-0000-0000-0000-000000000001', now() - interval '3 days');
insert into pipeline.entry_matrix_runs(provider_id, source_id, state, error) values ('10000000-0000-0000-0000-000000000005', '50000000-0000-0000-0000-000000000002', 'failed', 'timeout'), ('10000000-0000-0000-0000-000000000005', '50000000-0000-0000-0000-000000000003', 'failed', 'held_unparsed: tables');

-- PG: every source read on its current copy, nothing waiting; one course read already on the same stored copy
insert into pipeline.entry_matrix_sources(id, provider_id, url, status, evidence_id, read_at) values ('50000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000006', 'https://pg.edu.au/entry', 'read', '20000000-0000-0000-0000-000000000001', now());
insert into pipeline.entry_matrix_runs(provider_id, source_id, state, rows_admitted) values ('10000000-0000-0000-0000-000000000006', '50000000-0000-0000-0000-000000000004', 'done', 3);
insert into pipeline.field_enrich_items(provider_id, course_id, field, state, evidence_id) values ('10000000-0000-0000-0000-000000000006', '35000000-0000-0000-0000-000000000001', 'entry_requirements', 'review', '20000000-0000-0000-0000-000000000001');

-- PH: two held course reads; the replay can recover one from its stored records
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code) values ('41000000-0000-0000-0000-000000000001', 'course', '32000000-0000-0000-0000-000000000001', 'course_entry_first_read'), ('41000000-0000-0000-0000-000000000002', 'course', '32000000-0000-0000-0000-000000000002', 'course_entry_first_read');
insert into pipeline.layer4_item_readiness(item_id, entity_type, entity_id, field_code, item_status, readiness, reasons, route, gate) select i.id, i.entity_type, i.entity_id, i.field_code, 'pending', 'technical_blocked', array['repair:completeness_gate'], 'repair', '{"complete": false}' from pipeline.layer4_review_items i where i.id::text like '41000000%';
insert into pipeline.fx_replayable values ('41000000-0000-0000-0000-000000000001');

-- PI: a complete course packet (rows: a grade with no scale, a prior qualification, a score with no basis) and a parked read that needs input
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code) values ('42000000-0000-0000-0000-000000000001', 'course', '33000000-0000-0000-0000-000000000001', 'course_entry_first_read'), ('42000000-0000-0000-0000-000000000002', 'course', '33000000-0000-0000-0000-000000000002', 'course_entry_first_read');
insert into pipeline.layer4_item_readiness(item_id, entity_type, entity_id, field_code, item_status, readiness, reasons, route, gate) values
  ('42000000-0000-0000-0000-000000000001', 'course', '33000000-0000-0000-0000-000000000001', 'course_entry_first_read', 'pending', 'judgement_ready', '{}', 'review', '{"complete": true}'),
  ('42000000-0000-0000-0000-000000000002', 'course', '33000000-0000-0000-0000-000000000002', 'course_entry_first_read', 'pending', 'technical_blocked', array['repair:row_limit'], 'repair', '{"complete": false}');
insert into pipeline.work_items(lane, entity, work_kind, provider_id, stage, failure_class, unresolved_blocker) values ('aer_technical', '42000000-0000-0000-0000-000000000002', 'l4_item', '10000000-0000-0000-0000-000000000008', 'parked', 'row_limit', '{"action": "park", "reason": "the read has more requirements than the row limit", "next_action": "raise the row limit for this university"}');
insert into catalogue.course_entry_requirements(id, course_id, kind, audience, country_id, description, min_grade, min_value, grade_scale, min_entry_score, min_entry_score_basis, quote, source_url, evidence_id, status, provenance) values
  ('80000000-0000-0000-0000-000000000001', '33000000-0000-0000-0000-000000000001', 'minimum_grade', 'international', null, 'Minimum average', '65', 65, null, null, null, 'Minimum average of 65', 'https://pi.edu.au/c1', '20000000-0000-0000-0000-000000000001', 'proposed', '{"review_item_id": "42000000-0000-0000-0000-000000000001"}'),
  ('80000000-0000-0000-0000-000000000002', '33000000-0000-0000-0000-000000000001', 'prior_qualification', 'international', 1, 'Completion of Year 12', null, null, null, null, null, 'Year 12', 'https://pi.edu.au/c1', '20000000-0000-0000-0000-000000000001', 'proposed', '{"review_item_id": "42000000-0000-0000-0000-000000000001"}'),
  ('80000000-0000-0000-0000-000000000003', '33000000-0000-0000-0000-000000000001', 'minimum_grade', 'international', null, 'Minimum score', null, null, null, 70, null, 'Score of 70', 'https://pi.edu.au/c1', '20000000-0000-0000-0000-000000000001', 'proposed', '{"review_item_id": "42000000-0000-0000-0000-000000000001"}');

-- PM: a matrix read already queued
insert into pipeline.entry_matrix_sources(id, provider_id, url, status) values ('50000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-00000000000c', 'https://pm.edu.au/entry', 'found');
insert into pipeline.entry_matrix_runs(provider_id, source_id, state) values ('10000000-0000-0000-0000-00000000000c', '50000000-0000-0000-0000-000000000005', 'queued');

-- PL: a course that already has a queued read
insert into catalogue.courses(id, provider_id, canonical_title) values ('3c000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000b', 'PL queued');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, identity_basis, evidence_id) values ('3c000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000b', 'https://x.edu.au/queued', 'bound', 'cricos_code', '20000000-0000-0000-0000-000000000001');
insert into pipeline.field_enrich_items(provider_id, course_id, field, state) values ('10000000-0000-0000-0000-00000000000b', '3c000000-0000-0000-0000-000000000001', 'entry_requirements', 'queued');

-- Data Delivery: the aer stream with its lane's three switches as live holds them (the E13 pilot is off on purpose), and a lane whose switches are all off
insert into pipeline.lane_funnel_lanes(lane, title, sort, switch_keys, issue_refs) values ('aer', 'AER', 10, array['aer.e13_recover_on', 'aer.replay_on', 'aer.source_stored_find_on'], '{}'), ('alloff', 'All off', 20, array['fx.a', 'fx.b'], '{}'), ('nosw', 'No switch rows', 30, array['fx.missing'], '{}');
insert into pipeline.data_delivery_streams(stream, title, sort, lane, primary_jobs) values ('aer', 'Academic entry requirements', 10, 'aer', array['aer-scheduled-read']), ('alloff', 'All off', 20, 'alloff', array['aer-scheduled-read']), ('nosw', 'No switch rows', 30, 'nosw', array['aer-scheduled-read']);
insert into pipeline.platform_toolset_settings values ('pipeline', 'fx.a', '0'), ('pipeline', 'fx.b', 'false');
insert into pipeline.data_delivery_job_runs(singleton, measured_at, runs) values (true, now(), '{}');

-- Operating Model v1.7 evidence cases (10 Nov 2026): the kind of evidence behind an outcome, from existing state and reason only
update pipeline.evidence_artifacts set content_hash = 'h1' where id = '20000000-0000-0000-0000-000000000001';
insert into pipeline.evidence_artifacts(id, storage_path, mime_type, content_hash) values ('20000000-0000-0000-0000-00000000000a', 'x/a', 'text/html', 'h1'), ('20000000-0000-0000-0000-00000000000b', 'x/b', 'text/html', 'h2');
insert into catalogue.providers(id, canonical_name, country_id, enrols_international) values
  ('10000000-0000-0000-0000-00000000000d', 'PN read, nothing kept', 1, true),
  ('10000000-0000-0000-0000-00000000000e', 'PO source fetch failed', 1, true),
  ('10000000-0000-0000-0000-00000000000f', 'PP robots disallowed', 1, true),
  ('10000000-0000-0000-0000-000000000010', 'PQ course evidence cases', 1, true);
insert into pipeline.entry_matrix_sources(id, provider_id, url, status, evidence_id, read_at, content_hash, rank) values ('50000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-00000000000d', 'https://pn.edu.au/entry', 'read', '20000000-0000-0000-0000-000000000001', now(), 'h1', 1);
insert into pipeline.entry_matrix_runs(provider_id, source_id, content_hash, state, rows_admitted, error) values ('10000000-0000-0000-0000-00000000000d', '50000000-0000-0000-0000-000000000006', 'h1', 'done', 0, null);
insert into pipeline.entry_matrix_sources(id, provider_id, url, status, error, http_status, rank) values ('50000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-00000000000e', 'https://po.edu.au/entry.pdf', 'failed', 'blocked_pdf', null, 1);
insert into pipeline.entry_matrix_sources(id, provider_id, url, status, error, rank) values ('50000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-00000000000f', 'https://pp.edu.au/entry', 'robots_disallowed', 'robots_disallowed', 1);
-- PQ courses: each has a bound, stored, exact page (evidence 20..01, hash h1) and a different last result
insert into catalogue.courses(id, provider_id, canonical_title) values
  ('3d000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000010', 'PQ page does not state it'), ('3d000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000010', 'PQ same hash other copy'),
  ('3d000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000010', 'PQ read failed'), ('3d000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000010', 'PQ over the row limit'),
  ('3d000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000010', 'PQ page changed since the read');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, identity_basis, evidence_id)
  select c.id, c.provider_id, 'https://pq.edu.au/' || c.canonical_title, 'bound', 'cricos_code', '20000000-0000-0000-0000-000000000001' from catalogue.courses c where c.provider_id = '10000000-0000-0000-0000-000000000010';
insert into pipeline.field_enrich_items(provider_id, course_id, field, state, evidence_id, reason) values
  ('10000000-0000-0000-0000-000000000010', '3d000000-0000-0000-0000-000000000001', 'entry_requirements', 'skipped', '20000000-0000-0000-0000-000000000001', 'the page does not state it'),
  ('10000000-0000-0000-0000-000000000010', '3d000000-0000-0000-0000-000000000002', 'entry_requirements', 'skipped', '20000000-0000-0000-0000-00000000000a', 'no quoted requirement was on the page'),
  ('10000000-0000-0000-0000-000000000010', '3d000000-0000-0000-0000-000000000003', 'entry_requirements', 'failed', '20000000-0000-0000-0000-000000000001', 'timeout'),
  ('10000000-0000-0000-0000-000000000010', '3d000000-0000-0000-0000-000000000004', 'entry_requirements', 'skipped', '20000000-0000-0000-0000-000000000001', 'held_partial: over_row_limit: the page has 7 requirements and the limit is 5'),
  ('10000000-0000-0000-0000-000000000010', '3d000000-0000-0000-0000-000000000005', 'entry_requirements', 'skipped', '20000000-0000-0000-0000-00000000000b', 'the page does not state it');
