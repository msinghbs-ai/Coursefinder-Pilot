-- CF-247 integration queue fixtures, AFTER the 20261102120000 migration (applied twice by run.sh). Each case starts from fx.reset().
-- Prints one NOTICE "ok: ..." per assertion; any failure raises and stops the run.
set timezone = 'UTC';  -- as live (session time zone UTC)
create or replace function fx.ok(p boolean, p_msg text) returns void language plpgsql as $f$
begin if p is not true then raise exception 'FAILED: %', p_msg; end if; raise notice 'ok: %', p_msg; end $f$;
create or replace function fx.raises(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return null; exception when others then return sqlerrm; end $f$;
create or replace function fx.reset() returns void language plpgsql as $f$
begin
  truncate pipeline.integration_issue_events, pipeline.integration_issues restart identity cascade;
  truncate pipeline.integration_validate_state, pipeline.integration_deploy_checks, pipeline.platform_alerts, pipeline.platform_issues cascade;
  truncate pipeline.layer4_review_items, pipeline.course_url_fills, pipeline.uni_adapter_drafts, pipeline.coverage_vendor_usage, pipeline.ai_spend_ledger,
           search.course_documents, catalogue.courses, catalogue.providers, cron.job_run_details, supabase_migrations.schema_migrations,
           pipeline.coverage_ai_match, pipeline.field_enrich_items, pipeline.scholarship_ai_queue, pipeline.central_ai_queue, pipeline.entry_matrix_runs,
           pipeline.provider_description_reads, pipeline.layer1_run_queue, pipeline.fee_reader_queue, pipeline.provider_central_search, pipeline.source_find_runs;
  delete from cron.job where jobname <> 'integration-validate';
  update pipeline.platform_toolset_settings set value = 'false' where toolset_key = 'firecrawl' and key = 'daily_budget_on';
  -- two providers (one archived) and three courses (one not active, one of the archived provider)
  insert into catalogue.providers(id, stable_key, canonical_name, country_id, lifecycle_status, publication_status) values
    ('00000000-0000-0000-0000-0000000000a1', 'p-active', 'Active University', '00000000-0000-0000-0000-0000000000c1', 'active', 'published'),
    ('00000000-0000-0000-0000-0000000000a2', 'p-archived', 'Archived College', '00000000-0000-0000-0000-0000000000c1', 'archived', 'unpublished');
  insert into catalogue.courses(id, stable_key, provider_id, canonical_title, lifecycle_status, publication_status) values
    ('00000000-0000-0000-0000-0000000000b1', 'c1', '00000000-0000-0000-0000-0000000000a1', 'Bachelor of Active', 'active', 'published'),
    ('00000000-0000-0000-0000-0000000000b2', 'c2', '00000000-0000-0000-0000-0000000000a1', 'Bachelor of Retired', 'inactive', 'unpublished'),
    ('00000000-0000-0000-0000-0000000000b3', 'c3', '00000000-0000-0000-0000-0000000000a2', 'Diploma of Archived', 'active', 'unpublished');
  -- the active course is published in search (a clean consumer state)
  perform fx.doc('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'published');
end $f$;
create or replace function fx.doc(p_course uuid, p_provider uuid, p_pub text) returns void language sql as $f$
  insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status)
  values (p_course, p_provider, '00000000-0000-0000-0000-0000000000c1', 'P', 'C', 'c', to_tsvector('c'), p_pub)
$f$;
create or replace function fx.fps() returns text[] language sql as $f$ select coalesce(array_agg(fingerprint order by fingerprint), '{}') from pipeline.integration_issues $f$;
create or replace function fx.issue(p_fp text) returns pipeline.integration_issues language sql as $f$ select * from pipeline.integration_issues where fingerprint = p_fp $f$;
create or replace function fx.verified() returns jsonb language sql as $f$
  select jsonb_build_object('outcome', 'passed', 'evidence', 'Re-ran the original failing query on production: 0 rows (was 3).', 'checked_at', now()) $f$;

-- 0. the migration: settings, catalogue (job inactive), mode 1 recorded, register ------------------------------------------------------
do $t$ begin
  perform fx.ok((select count(*) from pipeline.platform_toolset_settings where key like 'integration.%') = 7, 'seven integration.* settings, each with label, range, unit and used_by');
  perform fx.ok(not exists (select 1 from pipeline.platform_toolset_settings where key like 'integration.%' and (label is null or min_value is null or max_value is null or unit is null or used_by is null)), 'every setting is complete (G2)');
  perform fx.ok((select active from cron.job where jobname = 'integration-validate') is false, 'job integration-validate created inactive');
  perform fx.ok((select schedule from cron.job where jobname = 'integration-validate') = '21,51 * * * *', 'job at :21 and :51');
  perform fx.ok((select command from cron.job where jobname = 'integration-validate') = 'select security.integration_validate_v1()', 'job command has no number');
  perform fx.ok(exists (select 1 from pipeline.automation_catalogue where jobname = 'integration-validate'), 'job catalogued (G1)');
  perform fx.ok((select mode from pipeline.integration_operating_mode) = 1, 'operating mode 1 recorded');
  perform fx.ok((select count(*) from pipeline.admin_control_events where area = 'integration' and action = 'operating_mode') = 1, 'mode recorded once in admin_control_events (twice applied)');
  perform fx.ok((select count(*) from pipeline.component_register where introduced_in = '20261102120000') = 17, 'component register: 6 tables, 1 job, 10 functions');
  perform fx.ok(not has_function_privilege('anon', 'public.admin_integration_queue(text,jsonb)', 'execute'), 'anon cannot read the queue');
  perform fx.ok(not has_function_privilege('authenticated', 'security.integration_issue_upsert_v1(jsonb,text)', 'execute'), 'clients cannot write the queue');
  perform fx.ok(not has_function_privilege('authenticated', 'security.integration_mode_set_v1(integer,text,text)', 'execute'), 'clients cannot change the mode');
end $t$;

-- 1. dedupe by fingerprint ------------------------------------------------------------------------------------------------------------------
select fx.reset();
do $t$ declare a jsonb; b jsonb; c jsonb;
begin
  a := security.integration_issue_upsert_v1('{"fingerprint": "fx:dup", "title": "t", "failure": "f", "expected": "e", "severity": "P2", "workstream": "A4", "course_ids": ["00000000-0000-0000-0000-0000000000b1"]}');
  b := security.integration_issue_upsert_v1('{"fingerprint": "fx:dup", "title": "t", "failure": "f", "expected": "e", "severity": "P2", "workstream": "A4", "course_ids": ["00000000-0000-0000-0000-0000000000b1"]}');
  perform fx.ok(a->>'action' = 'created' and b->>'action' = 'unchanged' and a->>'id' = b->>'id', 'dedupe: the same problem twice is one issue');
  perform fx.ok((select count(*) from pipeline.integration_issues) = 1, 'dedupe: one row');
  perform fx.ok((fx.issue('fx:dup')).retry_count = 1, 'dedupe: retry count 1');
  perform fx.ok((select count(*) from pipeline.integration_issue_events) = 1, 'dedupe: an unchanged repeat adds no history line');
  c := security.integration_issue_upsert_v1('{"fingerprint": "fx:dup", "failure": "f", "expected": "e", "severity": "P1", "workstream": "A4", "course_ids": ["00000000-0000-0000-0000-0000000000b2"]}');
  perform fx.ok(c->>'action' = 'escalated' and (fx.issue('fx:dup')).severity = 'P1', 'a higher severity escalates the same issue');
  perform fx.ok(cardinality((fx.issue('fx:dup')).course_ids) = 2, 'new affected entities are added, not hidden');
  perform security.integration_issue_upsert_v1('{"fingerprint": "fx:dup", "failure": "f", "expected": "e", "severity": "P2", "workstream": "A4"}');
  perform fx.ok((fx.issue('fx:dup')).severity = 'P1', 'severity is never lowered automatically');
  perform fx.ok(fx.raises($q$select security.integration_issue_upsert_v1('{"title": "no fingerprint"}')$q$) like '%fingerprint%', 'a fingerprint is required');
end $t$;

-- 2. close refused without verification; reopen as regression --------------------------------------------------------------------------
do $t$ declare v bigint := (fx.issue('fx:dup')).id; r jsonb;
begin
  perform fx.ok(fx.raises(format('select security.integration_issue_close_v1(%s, %L, null)', v, 'controller')) like 'closing needs production verification evidence%', 'close refused: no verification');
  perform fx.ok(fx.raises(format('select security.integration_issue_close_v1(%s, %L, %L)', v, 'controller', '{"outcome": "failed", "evidence": "Re-ran the query: 3 rows remain.", "checked_at": "2026-11-02T06:00:00Z"}')) like 'closing needs%', 'close refused: verification failed');
  perform fx.ok(fx.raises(format('select security.integration_issue_close_v1(%s, %L, %L)', v, 'controller', '{"outcome": "passed", "evidence": "ok", "checked_at": "2026-11-02T06:00:00Z"}')) like 'closing needs%', 'close refused: evidence too thin');
  perform fx.ok(fx.raises(format('select security.integration_issue_close_v1(%s, %L, %L)', v, 'controller', '{"outcome": "passed", "evidence": "Re-ran the original failing query: 0 rows."}')) like 'closing needs%', 'close refused: no time or reference');
  perform fx.ok(fx.raises(format('select security.integration_issue_transition_v1(%s, %L, %L)', v, 'closed', 'controller')) like '%verification evidence%', 'the lifecycle refuses closed');
  perform fx.ok((fx.issue('fx:dup')).status = 'detected', 'still open after the refusals');
  r := security.integration_issue_close_v1(v, 'controller', fx.verified());
  perform fx.ok(r->>'status' = 'closed' and (fx.issue('fx:dup')).verification_outcome = 'passed', 'closes with verification evidence');
  r := security.integration_issue_upsert_v1('{"fingerprint": "fx:dup", "failure": "back again", "expected": "e", "severity": "P2", "workstream": "A4"}');
  perform fx.ok(r->>'action' = 'reopened' and (r->>'id')::bigint = v, 'a recurrence after Closed reopens the same issue');
  perform fx.ok((fx.issue('fx:dup')).status = 'reopened' and (fx.issue('fx:dup')).regression_count = 1 and (fx.issue('fx:dup')).verification_outcome = 'regressed', 'recorded as a regression');
  perform fx.ok((select count(*) from pipeline.integration_issues) = 1, 'no new row for the regression');
  perform fx.ok(exists (select 1 from pipeline.integration_issue_events where issue_id = v and kind = 'reopened_regression'), 'history: reopened_regression');
end $t$;

-- 3. lifecycle: allowed steps; failed validation returns with evidence -----------------------------------------------------------------
do $t$ declare v bigint := (fx.issue('fx:dup')).id;
begin
  perform fx.ok(fx.raises(format('select security.integration_issue_transition_v1(%s, %L, %L)', v, 'deployed', 'controller')) like 'an issue cannot move from reopened to deployed', 'no skipping the lifecycle');
  perform security.integration_issue_transition_v1(v, 'assigned', 'controller', null, '{"assignee": "agent A4"}');
  perform security.integration_issue_transition_v1(v, 'in_progress', 'agent A4');
  perform security.integration_issue_transition_v1(v, 'code_ready', 'agent A4', null, '{"fix_commit": "abc1234", "fix_migration": "20261103000000"}');
  perform security.integration_issue_transition_v1(v, 'integration_testing', 'controller');
  perform security.integration_issue_transition_v1(v, 'deployed', 'controller', null, '{"deployed_version": "v2.15.407"}');
  perform fx.ok(fx.raises(format('select security.integration_issue_transition_v1(%s, %L, %L, %L)', v, 'in_progress', 'controller', 'no')) like 'failed validation returns the issue with its new evidence%', 'failed validation needs its evidence');
  perform security.integration_issue_transition_v1(v, 'in_progress', 'controller', 'Production check still finds 2 rows after v2.15.407');
  perform fx.ok((fx.issue('fx:dup')).status = 'in_progress' and (fx.issue('fx:dup')).verification_outcome = 'failed', 'failed validation returns to In progress');
  perform fx.ok((fx.issue('fx:dup')).fix_commit = 'abc1234' and (fx.issue('fx:dup')).deployed_version = 'v2.15.407', 'fix and deployment recorded');
  perform fx.ok((select count(*) from pipeline.integration_issue_events where issue_id = v and kind = 'status') = 6, 'every step in the history');
end $t$;

-- 4. operating mode: only the controller path, audited, Mode 2 only on acceptance ------------------------------------------------------
do $t$ begin
  perform fx.ok(fx.raises('update pipeline.integration_operating_mode set mode = 2') like 'the operating mode is changed only by the Integration Controller%', 'a direct write is refused');
  perform fx.ok(fx.raises($q$select security.integration_mode_set_v1(2, 'Integration Controller (session x)', 'programme accepted')$q$) like 'Mode 2 needs programme acceptance: 1 P0/P1%', 'Mode 2 refused while a P1 is open');
  perform fx.ok(fx.raises($q$select security.integration_mode_set_v1(2, 'IC', 'x')$q$) like 'name the Integration Controller%', 'controller and reason required');
  perform security.integration_issue_transition_v1((fx.issue('fx:dup')).id, 'code_ready', 'agent A4');
  perform security.integration_issue_transition_v1((fx.issue('fx:dup')).id, 'integration_testing', 'controller');
  perform security.integration_issue_transition_v1((fx.issue('fx:dup')).id, 'deployed', 'controller');
  perform security.integration_issue_transition_v1((fx.issue('fx:dup')).id, 'production_verification', 'controller');
  perform security.integration_issue_close_v1((fx.issue('fx:dup')).id, 'controller', fx.verified());
  perform security.integration_mode_set_v1(2, 'Integration Controller (session x)', 'CF-247 programme accepted on verified production evidence');
  perform fx.ok((select mode from pipeline.integration_operating_mode) = 2 and (select set_by from pipeline.integration_operating_mode) = 'Integration Controller (session x)', 'mode 2 set, with who set it');
  perform fx.ok(exists (select 1 from pipeline.admin_control_events where area = 'integration' and action = 'operating_mode' and detail->>'from' = '1' and detail->>'to' = '2'), 'the change is in admin_control_events');
  perform security.integration_mode_set_v1(1, 'Integration Controller (session x)', 'regression reopened: back to active remediation');
  perform fx.ok((select count(*) from pipeline.admin_control_events where area = 'integration' and action = 'operating_mode') = 3, 'every change audited');
end $t$;

-- 5. V4 invariants: silent on a clean platform --------------------------------------------------------------------------------------------
select fx.reset();
do $t$ declare r jsonb;
begin
  insert into cron.job(jobname, schedule, command) values ('coverage-admit', '3-59/10 * * * *', 'select security.pipeline_num_v1(''x'', 1)');
  insert into cron.job_run_details(jobid, status, start_time) select jobid, 'succeeded', now() - interval '5 minutes' from cron.job where jobname = 'coverage-admit';
  insert into pipeline.coverage_ai_match(state, leased_until) values ('leased', now() + interval '5 minutes'), ('done', now() - interval '3 hours');
  insert into pipeline.uni_adapter_drafts(provider_id, status, updated_at) values ('00000000-0000-0000-0000-0000000000a1', 'capturing', now() - interval '1 hour'),
    ('00000000-0000-0000-0000-0000000000a1', 'captured', now() - interval '10 days');
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, proposed_value, status, created_at, decided_at) values
    ('course', '00000000-0000-0000-0000-0000000000b1', 'course_intake', '"Feb"', 'approved', now() - interval '3 days', now() - interval '2 days'),
    ('course', '00000000-0000-0000-0000-0000000000b1', 'course_intake', '"Jul"', 'pending', now() - interval '1 hour', null),
    ('course', '00000000-0000-0000-0000-0000000000b1', 'official_course_url', '"https://a.example/x"', 'pending', now() - interval '1 hour', null);
  insert into pipeline.course_url_fills(course_id, url, evidence_id, identity_basis, filled_at) values ('00000000-0000-0000-0000-0000000000b1', 'https://a.example/y', gen_random_uuid(), 'adapter_title', now() - interval '2 hours');
  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id) values (gen_random_uuid(), 30000, 'scrape', '00000000-0000-0000-0000-0000000000a1');
  insert into pipeline.ai_spend_ledger(lane, source, cost_usd) values ('enrich_fields', 'fx', 2);
  insert into pipeline.platform_issues(check_key, severity, area, title) values ('field_stalled:NZ', 'info', 'coverage sweep', 'info only');
  r := security.integration_validate_v1();
  perform fx.ok(r->'errors' = '{}'::jsonb, 'every check ran without error');
  perform fx.ok(cardinality(fx.fps()) = 0, 'clean platform: no issue (failed runs, leases, drafts, Layer 4, fill before the item, spend with the budget off, info issues)');
end $t$;

-- 6. V4 invariants: each fires on its synthetic case ----------------------------------------------------------------------------------
do $t$ declare r jsonb;
begin
  -- Platform health and queue-watch output
  insert into pipeline.platform_issues(check_key, severity, area, title, detail) values
    ('scholarship_queues:candidates', 'critical', 'scholarships', 'Scholarship candidate page reading has stalled', '{"next_step": "Look at scholarship-discover"}'),
    ('queue_watch:fee_reader', 'warning', 'coverage sweep', 'Fee reader is stuck', '{}'),
    ('cron:failed:coverage-admit', 'warning', 'scheduled jobs', 'coverage-admit failed', '{}');
  -- failed job run
  insert into cron.job_run_details(jobid, status, start_time, return_message) select jobid, 'failed', now() - interval '2 minutes', 'canceling statement due to statement timeout' from cron.job where jobname = 'coverage-admit';
  -- stale lease
  insert into pipeline.coverage_ai_match(state, leased_until) values ('leased', now() - interval '2 hours');
  -- stuck draft
  insert into pipeline.uni_adapter_drafts(provider_id, status, updated_at) values ('00000000-0000-0000-0000-0000000000a1', 'proposing', now() - interval '3 days');
  -- Layer 4: duplicate, orphan (inactive course), regenerated (same value already decided)
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, proposed_value, status, created_at) values
    ('course', '00000000-0000-0000-0000-0000000000b1', 'course_intake', '"Jul"', 'pending', now() - interval '30 minutes'),
    ('course', '00000000-0000-0000-0000-0000000000b2', 'course_english', '{"ielts": 6.5}', 'pending', now() - interval '30 minutes'),
    ('course', '00000000-0000-0000-0000-0000000000b1', 'course_duration', '"3 years"', 'rejected', now() - interval '5 days'),
    ('course', '00000000-0000-0000-0000-0000000000b1', 'course_duration', '"3 years"', 'pending', now() - interval '10 minutes');
  update pipeline.layer4_review_items set decided_at = now() - interval '4 days' where field_code = 'course_duration' and status = 'rejected';
  -- course-url-fill wrote after the pending official_course_url item was raised
  update pipeline.course_url_fills set filled_at = now() where course_id = '00000000-0000-0000-0000-0000000000b1';
  -- Firecrawl spent on the archived provider
  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, provider_id) values (gen_random_uuid(), 3, 'scrape', '00000000-0000-0000-0000-0000000000a2');
  -- archived provider's course and an inactive course published in search
  perform fx.doc('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000a2', 'published');
  perform fx.doc('00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000a1', 'published');
  -- spend above the settings: AI over the ceiling; Firecrawl over the daily budget once it is on
  insert into pipeline.ai_spend_ledger(lane, source, cost_usd) values ('enrich_fields', 'fx', 13);
  update pipeline.platform_toolset_settings set value = 'true' where toolset_key = 'firecrawl' and key = 'daily_budget_on';
  r := security.integration_validate_v1();
  perform fx.ok(r->'errors' = '{}'::jsonb, 'every check ran without error');
  perform fx.ok(fx.fps() = array['archived_provider_work:firecrawl', 'course_url_fill:pending_official_course_url', 'draft_stuck:proposing', 'health:queue_watch:fee_reader',
    'health:scholarship_queues:candidates', 'job_failed:coverage-admit', 'l4_duplicate:course_intake', 'l4_orphan:course_english', 'l4_regenerated:course_duration',
    'search_leak:archived_provider', 'search_leak:inactive_course', 'spend:ai_day', 'spend:firecrawl_day', 'stale_lease:pipeline.coverage_ai_match'], 'each invariant fires once: ' || array_to_string(fx.fps(), ', '));
  perform fx.ok((fx.issue('job_failed:coverage-admit')).retry_count = 1, 'the health cron issue and the failed run are one issue (same fingerprint)');
  perform fx.ok((fx.issue('course_url_fill:pending_official_course_url')).course_ids = array['00000000-0000-0000-0000-0000000000b1']::uuid[], 'course-url-fill issue names the course');
  perform fx.ok((fx.issue('search_leak:archived_provider')).severity = 'P0' and (fx.issue('search_leak:inactive_course')).severity = 'P0', 'consumer-visible leaks are P0');
  perform fx.ok((fx.issue('health:scholarship_queues:candidates')).severity = 'P1' and (fx.issue('health:queue_watch:fee_reader')).workstream = 'A7', 'health severity and owner mapped');
  perform fx.ok((select count(*) from pipeline.platform_issues where check_key like 'integration:%' and resolved_at is null) = 2, 'one Platform health issue per P0 fingerprint');
  perform fx.ok(not exists (select 1 from pipeline.integration_issues where fingerprint like 'health:integration:%'), 'the queue''s own alert rows are not fed back');
  -- run again: nothing duplicated
  r := security.integration_validate_v1();
  perform fx.ok((select count(*) from pipeline.integration_issues) = 14, 'second run: no duplicate issues');
  perform fx.ok((fx.issue('stale_lease:pipeline.coverage_ai_match')).retry_count = 1, 'second run: retry count rises');
  perform fx.ok((fx.issue('job_failed:coverage-admit')).condition_cleared_at is null, 'a job failure still reported by Platform health is not cleared');
end $t$;

-- 7. no duplicate alert: one raised alert per P0 fingerprint, one recovery notice ----------------------------------------------------------
do $t$ declare r jsonb;
begin
  update pipeline.platform_issues set first_seen = now() - interval '20 minutes' where check_key like 'integration:%';
  r := security.platform_alerts_evaluate_v1();
  perform fx.ok((select count(*) from pipeline.platform_alerts where kind = 'raised' and check_key like 'integration:%') = 2, 'platform-alerts raises one alert per P0 issue');
  perform security.integration_validate_v1();
  perform security.platform_alerts_evaluate_v1();
  perform security.integration_validate_v1();
  perform security.platform_alerts_evaluate_v1();
  perform fx.ok((select count(*) from pipeline.platform_alerts where check_key like 'integration:%') = 2, 'repeated checks and alert runs: still two alerts');
  -- the archived provider's document leaves search: the alert recovers once; the issue stays open until verified
  update search.course_documents set publication_status = 'unpublished' where course_id = '00000000-0000-0000-0000-0000000000b3';
  perform security.integration_validate_v1();
  perform fx.ok((select resolved_at from pipeline.platform_issues where check_key = 'integration:search_leak:archived_provider') is not null, 'condition cleared: the Platform health issue resolves');
  perform fx.ok((fx.issue('search_leak:archived_provider')).status <> 'closed' and (fx.issue('search_leak:archived_provider')).condition_cleared_at is not null, 'the integration issue stays open, marked cleared');
  perform security.platform_alerts_evaluate_v1();
  perform security.platform_alerts_evaluate_v1();
  perform fx.ok((select count(*) from pipeline.platform_alerts where check_key = 'integration:search_leak:archived_provider' and kind = 'recovered') = 1, 'one recovery notice');
  perform fx.ok((select count(*) from pipeline.platform_alerts where check_key like 'integration:%') = 3, 'three alerts in all (two raised, one recovered)');
  -- back within the quiet period: the issue is observed again, the alert is not repeated
  update search.course_documents set publication_status = 'published' where course_id = '00000000-0000-0000-0000-0000000000b3';
  perform security.integration_validate_v1();
  update pipeline.platform_issues set first_seen = now() - interval '20 minutes' where check_key = 'integration:search_leak:archived_provider' and resolved_at is null;
  perform security.platform_alerts_evaluate_v1();
  perform fx.ok((select count(*) from pipeline.platform_alerts where check_key = 'integration:search_leak:archived_provider' and kind = 'raised') = 1, 'back within the quiet period: no second raised alert');
  perform fx.ok(exists (select 1 from pipeline.integration_issue_events e join pipeline.integration_issues i on i.id = e.issue_id where i.fingerprint = 'search_leak:archived_provider' and e.kind = 'observed_again'), 'history: observed again');
  -- closing the issue with verification resolves its Platform health issue
  update search.course_documents set publication_status = 'unpublished' where course_id in ('00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000b2');
  perform security.integration_issue_close_v1((fx.issue('search_leak:inactive_course')).id, 'controller', fx.verified());
  perform fx.ok(not exists (select 1 from pipeline.platform_issues where check_key = 'integration:search_leak:inactive_course' and resolved_at is null), 'closing resolves the alert issue');
end $t$;

-- 8. windowed checks clear; a recurrence after closure reopens -----------------------------------------------------------------------------
do $t$ declare v bigint;
begin
  delete from pipeline.platform_issues where check_key = 'cron:failed:coverage-admit';
  perform security.integration_validate_v1();
  perform fx.ok((fx.issue('job_failed:coverage-admit')).condition_cleared_at is not null, 'failed runs: no new failure since the watermark, cleared');
  v := (fx.issue('job_failed:coverage-admit')).id;
  perform security.integration_issue_close_v1(v, 'controller', fx.verified());
  insert into cron.job_run_details(jobid, status, start_time) select jobid, 'failed', now() - interval '1 minute' from cron.job where jobname = 'coverage-admit';
  perform security.integration_validate_v1();
  perform fx.ok((fx.issue('job_failed:coverage-admit')).id = v and (fx.issue('job_failed:coverage-admit')).status = 'reopened', 'the same job failing after closure reopens the original issue');
  perform fx.ok((select count(*) from pipeline.integration_issues where fingerprint like 'job_failed:%') = 1, 'no second issue for it');
end $t$;

-- 9. V3 deployment check --------------------------------------------------------------------------------------------------------------
select fx.reset();
do $t$ declare r jsonb; v_sig text := 'security.integration_l4_pending_v1(integer)'; v_md5 text;
begin
  insert into supabase_migrations.schema_migrations(version, statements, name) values ('20261102120000', array['-- file text'], 'cf247_integration_queue');
  insert into cron.job(jobname, schedule, command) values ('fx-ok', '1 * * * *', 'select security.integration_validate_v1()'), ('fx-broken', '2 * * * *', 'select security.not_there_v1()');
  v_md5 := md5(pg_get_functiondef(v_sig::regprocedure));
  r := security.integration_deploy_check_v1('v2.15.407', jsonb_build_array(jsonb_build_object('version', '20261102120000', 'md5', md5('-- file text'))),
                                            jsonb_build_object(v_sig, v_md5), now() - interval '10 minutes', array['fx-ok']);
  perform fx.ok((r->>'ok')::boolean and cardinality(fx.fps()) = 0, 'V3: matching migration and function, compatible job: passes, no issue');
  insert into supabase_migrations.schema_migrations(version, statements, name) values ('20261102110500', array[E'select 1;\r\nselect 2;\r\n\n'], 'crlf');
  r := security.integration_deploy_check_v1('v2.15.407b', jsonb_build_array(jsonb_build_object('version', '20261102110500', 'md5', md5(E'select 1;\nselect 2;'))), '{}', now() - interval '10 minutes', array['fx-ok']);
  perform fx.ok((r->>'ok')::boolean and cardinality(fx.fps()) = 0, 'V3: line endings and a trailing newline are not a mismatch');
  r := security.integration_deploy_check_v1('v2.15.408', jsonb_build_array(jsonb_build_object('version', '20261102120000', 'md5', md5('-- other text')), jsonb_build_object('version', '20991231000000', 'md5', 'x')),
                                            jsonb_build_object(v_sig, 'deadbeef'), now() - interval '10 minutes', null);
  perform fx.ok(not (r->>'ok')::boolean, 'V3: mismatches fail');
  perform fx.ok(fx.fps() = array['v3_function:security.integration_l4_pending_v1(integer)', 'v3_job:fx-broken', 'v3_migration:20261102120000', 'v3_migration:20991231000000'],
                'V3 issues: ' || array_to_string(fx.fps(), ', '));
  perform fx.ok((select count(*) from pipeline.integration_deploy_checks) = 3, 'V3 results kept');
  insert into cron.job_run_details(jobid, status, start_time) select jobid, 'failed', now() - interval '1 minute' from cron.job where jobname = 'fx-ok';
  r := security.integration_deploy_check_v1('v2.15.409', '[]', '{}', now() - interval '5 minutes', array['fx-ok']);
  perform fx.ok((fx.issue('v3_errors:v2.15.409')).severity = 'P2' and (r->'failed_runs'->>'fx-ok')::int = 1, 'V3: a failed run since the deploy is counted and opens an issue');
end $t$;

-- 10. the screen: PIM Admin and above, read only ----------------------------------------------------------------------------------------
do $t$ declare r jsonb;
begin
  update fx.caller set uid = gen_random_uuid(), rank = 4;
  perform fx.ok(fx.raises($q$select public.admin_integration_queue('summary', '{}')$q$) like 'PIM Admin role or above required', 'Pipeline Operator refused');
  update fx.caller set rank = 5;
  r := public.admin_integration_queue('summary', '{"scope": "open"}');
  perform fx.ok((r->'mode'->>'mode')::int = 1 and r ? 'by_status' and r ? 'by_severity' and r ? 'by_workstream' and r ? 'reopened', 'PIM Admin: counts and mode');
  perform fx.ok(jsonb_array_length(r->'issues') = 5, 'open issues listed');
  r := public.admin_integration_queue('issue', jsonb_build_object('id', (fx.issue('v3_job:fx-broken')).id));
  perform fx.ok(r->'issue'->>'issue_ref' like 'IQ-%' and jsonb_array_length(r->'events') >= 1, 'an issue with its history');
  update fx.caller set uid = null, rank = null;
  perform fx.ok(fx.raises($q$select public.admin_integration_queue('summary', '{}')$q$) like 'PIM Admin role or above required', 'no session refused');
end $t$;

-- 11. IQ-00112 collector protocol (6 Nov 2026 mandate; Admin ff7ef0a2e63ca68b6333cfc4ab0fabb311b4f559) --------------------------
-- Synthetic events only. A local transport acceptance and a local recipient receipt are deliberately separate evidence;
-- neither is a real push/e-mail delivery. Production acceptance still requires the configured destination and an independent watchdog PASS.
-- Reuses the existing add/evaluate/take/confirm functions. Existing budget-enforcement fixtures guard the read-only watchdog.
select fx.reset();
create table fx.alert_transport_acceptances(alert_id bigint primary key references pipeline.platform_alerts(id), receipt_id text not null unique);
create table fx.alert_recipient_receipts(alert_id bigint primary key references fx.alert_transport_acceptances(alert_id), received_at timestamptz not null);
create table fx.alert_original_events(id bigint primary key, event jsonb not null);

do $t$
declare
  v_issue uuid; v_ids bigint[]; v_claimed bigint[]; v_deferred bigint; v_retry bigint; v_sent bigint; v_expired bigint; v_exhausted bigint; v_confirm_exhausted bigint; v_recovery bigint;
  r jsonb; v_before jsonb; v_added boolean; v_n int;
  v_mutable text[] := array['status','attempts','next_attempt_at','lease_until','sent_via','sent_at','net_request_id','last_error'];
begin
  insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values
    ('pipeline', 'alerts.max_attempts', 'number', '5'), ('pipeline', 'alerts.retry_minutes', 'number', '10')
    on conflict (toolset_key,key) do update set value = excluded.value;
  update pipeline.platform_toolset_settings set value = 'true' where toolset_key = 'pipeline' and key = 'alerts.delivery_enabled';
  update pipeline.platform_toolset_settings set value = 'false' where toolset_key = 'pipeline' and key = 'alerts.webhook_enabled';
  insert into pipeline.platform_issues(check_key, severity, area, title, first_seen)
    values ('fixture:collector', 'critical', 'scheduled jobs', 'Synthetic collector protocol', now() - interval '4 hours') returning id into v_issue;
  for v_n in 1..79 loop
    v_added := security.platform_alerts_add_v1(v_issue, 'fixture:collector', case when v_n = 1 then 'raised' else 'reminder' end,
      'critical', 'Synthetic alert ' || v_n, 'Fixture-only event ' || v_n, 'fixture:original:' || v_n);
    if not v_added then raise exception 'synthetic original event was not created: %', v_n; end if;
    update pipeline.platform_alerts set created_at = now() - interval '3 hours' + v_n * interval '1 second'
      where dedupe_key = 'fixture:original:' || v_n;
  end loop;
  select array_agg(id order by id) into v_ids from pipeline.platform_alerts;
  insert into fx.alert_original_events select a.id, to_jsonb(a) - v_mutable from pipeline.platform_alerts a;
  perform fx.ok(cardinality(v_ids) = 79 and (select count(*) from fx.alert_original_events) = 79,
    'collector: 79 synthetic original event IDs captured before collection');
  v_added := security.platform_alerts_add_v1(v_issue, 'fixture:collector', 'raised', 'critical', 'Duplicate input', 'Not a second event', 'fixture:original:1');
  perform fx.ok(not v_added and (select count(*) from pipeline.platform_alerts) = 79,
    'collector: generation dedupe preserves all original IDs without copying events');

  -- The route switches stop collection; they do not relabel or discard the existing backlog.
  update pipeline.platform_toolset_settings set value = 'false' where toolset_key = 'pipeline' and key = 'alerts.delivery_enabled';
  r := security.platform_alerts_take_v1('fixture transport');
  perform fx.ok((r->>'count')::int = 0 and (select count(*) from pipeline.platform_alerts where status = 'pending' and attempts = 0) = 79,
    'collector: delivery off leaves 79 pending events unattempted');
  update pipeline.platform_toolset_settings set value = 'true' where toolset_key = 'pipeline' and key in ('alerts.delivery_enabled','alerts.webhook_enabled');
  r := security.platform_alerts_take_v1('fixture transport');
  perform fx.ok((r->>'count')::int = 0 and (select count(*) from pipeline.platform_alerts where status = 'pending' and attempts = 0) = 79,
    'collector: webhook route excludes scheduled-task collection without changing events');
  update pipeline.platform_toolset_settings set value = 'false' where toolset_key = 'pipeline' and key = 'alerts.webhook_enabled';

  v_deferred := v_ids[79]; v_retry := v_ids[1]; v_sent := v_ids[2]; v_expired := v_ids[3]; v_exhausted := v_ids[4]; v_confirm_exhausted := v_ids[5];
  update pipeline.platform_alerts set next_attempt_at = now() + interval '1 hour' where id = v_deferred;
  r := security.platform_alerts_take_v1('fixture transport');
  select array_agg((a->>'id')::bigint order by (a->>'id')::bigint) into v_claimed from jsonb_array_elements(r->'alerts') a;
  perform fx.ok((r->>'count')::int = 78 and v_claimed = v_ids[1:78],
    'collector: takes only due pending events and returns their original IDs');
  perform fx.ok((select count(*) from pipeline.platform_alerts where status = 'sending' and attempts = 1 and sent_via = 'fixture transport'
    and lease_until = now() + interval '15 minutes' and sent_at is null) = 78,
    'collector: claims increment attempts and establish leases without claiming delivery');
  perform fx.ok((select status = 'pending' and attempts = 0 and lease_until is null from pipeline.platform_alerts where id = v_deferred),
    'collector: a future retry is not claimed early');
  r := security.platform_alerts_take_v1('fixture transport');
  perform fx.ok((r->>'count')::int = 0 and (select sum(attempts) from pipeline.platform_alerts) = 78,
    'collector: a second take cannot reclaim active leases or consume another attempt');
  perform fx.ok(not exists (select 1 from pipeline.platform_alerts where sent_at is not null)
    and not exists (select 1 from fx.alert_transport_acceptances) and not exists (select 1 from fx.alert_recipient_receipts),
    'collector: collection alone is neither transport acceptance nor recipient receipt');
  perform fx.ok((select acknowledged_at is null from pipeline.platform_issues where id = v_issue),
    'collector: collection does not acknowledge the operator issue');

  r := security.platform_alerts_confirm_v1(array[v_retry], false, 'fixture transport refused');
  perform fx.ok((r->>'updated')::int = 1 and not (r->>'delivered')::boolean,
    'collector: a refused transport confirms failure for the exact claimed ID');
  perform fx.ok((select status = 'pending' and attempts = 1 and lease_until is null and sent_at is null
    and last_error = 'fixture transport refused' and next_attempt_at = now() + interval '10 minutes'
    from pipeline.platform_alerts where id = v_retry),
    'collector: first failure keeps the event and schedules the configured first backoff');
  r := security.platform_alerts_take_v1('fixture transport');
  perform fx.ok((r->>'count')::int = 0, 'collector: retry backoff cannot be bypassed by another take');
  update pipeline.platform_alerts set next_attempt_at = now() - interval '1 second' where id = v_retry; -- fixture clock advance, never production retry reset
  r := security.platform_alerts_take_v1('fixture transport');
  perform fx.ok((r->>'count')::int = 1 and (r->'alerts'->0->>'id')::bigint = v_retry
    and (select attempts = 2 from pipeline.platform_alerts where id = v_retry),
    'collector: due retry reuses the original event ID and increments its attempt once');
  r := security.platform_alerts_confirm_v1(array[v_retry], false, 'fixture transport refused again');
  perform fx.ok((select status = 'pending' and attempts = 2 and next_attempt_at = now() + interval '20 minutes'
    from pipeline.platform_alerts where id = v_retry),
    'collector: repeated failure doubles backoff without changing event identity');

  -- A collector may confirm only after its transport accepted this exact event; this local table stands for that evidence.
  insert into fx.alert_transport_acceptances values (v_sent, 'fixture-transport:' || v_sent);
  perform fx.ok(not exists (select 1 from fx.alert_recipient_receipts) and (select sent_at is null from pipeline.platform_alerts where id = v_sent),
    'collector: transport acceptance precedes confirmation and is not recipient receipt');
  r := security.platform_alerts_confirm_v1(array[v_sent], true);
  perform fx.ok((r->>'updated')::int = 1 and (r->>'delivered')::boolean
    and (select status = 'sent' and sent_at = now() and lease_until is null and attempts = 1 from pipeline.platform_alerts where id = v_sent),
    'collector: exact-ID success records caller-reported transport delivery and clears its lease');
  perform fx.ok((select count(*) from pipeline.platform_alerts where status = 'sent') = 1
    and not exists (select 1 from fx.alert_recipient_receipts)
    and (select acknowledged_at is null from pipeline.platform_issues where id = v_issue),
    'collector: confirmation neither delivers other IDs nor proves receipt or operator acknowledgement');
  r := security.platform_alerts_confirm_v1(array[v_sent], true);
  perform fx.ok((r->>'updated')::int = 0, 'collector: repeated successful confirmation is idempotent');
  r := security.platform_alerts_confirm_v1(array[v_deferred], true);
  perform fx.ok((r->>'updated')::int = 0 and (select status = 'pending' and sent_at is null from pipeline.platform_alerts where id = v_deferred),
    'collector: confirming an unclaimed pending ID cannot mark it delivered');
  insert into fx.alert_recipient_receipts values (v_sent, now());
  perform fx.ok((select count(*) from fx.alert_recipient_receipts) = 1
    and (select acknowledged_at is null from pipeline.platform_issues where id = v_issue),
    'collector: independently modeled recipient receipt remains separate from operator acknowledgement');

  -- Use the real rank-6 acknowledgement branch; the existing fixture caller/auth helpers supply the local operator.
  select jsonb_agg(to_jsonb(a) order by id) into v_before from pipeline.platform_alerts a;
  update fx.caller set uid = '00000000-0000-0000-0000-000000000066', rank = 6;
  r := public.admin_platform_alerts('acknowledge', jsonb_build_object('id', v_issue, 'reason', 'Fixture recipient receipt reviewed'));
  perform fx.ok((r->>'ok')::boolean and (select acknowledged_at = now() and acknowledged_by = auth.uid()
    and acknowledged_note = 'Fixture recipient receipt reviewed' from pipeline.platform_issues where id = v_issue),
    'collector: actual operator acknowledgement records its separate identity and reason');
  perform fx.ok(exists (select 1 from pipeline.admin_control_events where area = 'platform health' and action = 'acknowledge'
    and target = v_issue::text and actor = auth.uid()),
    'collector: actual operator acknowledgement is audited');
  perform fx.ok(v_before = (select jsonb_agg(to_jsonb(a) order by id) from pipeline.platform_alerts a),
    'collector: operator acknowledgement cannot mark the backlog delivered or discard an event');
  update pipeline.platform_toolset_settings set value = '2' where toolset_key = 'pipeline' and key = 'alerts.reminder_hours';
  r := security.platform_alerts_evaluate_v1();
  perform fx.ok((r->>'reminders')::int = 0 and (select count(*) from pipeline.platform_alerts) = 79,
    'collector: acknowledged operator issue suppresses otherwise-due reminders without draining its alerts');
  update pipeline.platform_toolset_settings set value = '12' where toolset_key = 'pipeline' and key = 'alerts.reminder_hours';

  update pipeline.platform_alerts set attempts = 5 where id = v_confirm_exhausted;
  r := security.platform_alerts_confirm_v1(array[v_confirm_exhausted], false, 'fixture final transport refusal');
  perform fx.ok((r->>'updated')::int = 1 and (select status = 'failed' and attempts = 5 and sent_at is null
    and last_error = 'fixture final transport refusal' from pipeline.platform_alerts where id = v_confirm_exhausted),
    'collector: final refused transport attempt becomes failed while retaining its event');
  r := security.platform_alerts_confirm_v1(array[v_confirm_exhausted], true);
  perform fx.ok((r->>'updated')::int = 0 and (select status = 'failed' from pipeline.platform_alerts where id = v_confirm_exhausted),
    'collector: an exhausted unclaimed event cannot be changed to sent by confirmation');

  update pipeline.platform_alerts set lease_until = now() - interval '1 second' where id = v_expired;
  r := security.platform_alerts_evaluate_v1();
  perform fx.ok((r->>'lease_expired')::int = 1 and (select status = 'pending' and attempts = 1 and lease_until is null
    and next_attempt_at = now() + interval '10 minutes' and last_error = 'delivery not confirmed before the lease ended'
    from pipeline.platform_alerts where id = v_expired),
    'collector: an unconfirmed expired lease requeues the same ID with backoff');
  update pipeline.platform_alerts set attempts = 5, lease_until = now() - interval '1 second' where id = v_exhausted;
  r := security.platform_alerts_evaluate_v1();
  perform fx.ok((r->>'lease_expired')::int = 1 and (select status = 'failed' and attempts = 5 and lease_until is null and sent_at is null
    from pipeline.platform_alerts where id = v_exhausted),
    'collector: exhausting configured attempts fails visibly without deletion or false delivery');
  perform fx.ok((select count(*) from pipeline.platform_alerts) = 79
    and (select array_agg(id order by id) from pipeline.platform_alerts) = v_ids,
    'collector: retries and lease recovery preserve all 79 original event IDs');

  -- Resolution creates a new recovery event; it does not rewrite the historical alerts or imply they reached the destination.
  update pipeline.platform_issues set resolved_at = now() where id = v_issue;
  r := security.platform_alerts_evaluate_v1();
  perform fx.ok((r->>'recovered')::int = 1 and (select count(*) from pipeline.platform_alerts where kind = 'recovered') = 1,
    'collector: issue resolution generates one separate recovery alert');
  select id into v_recovery from pipeline.platform_alerts where kind = 'recovered';
  perform fx.ok(not (v_recovery = any(v_ids)) and (select status = 'pending' and attempts = 0 and sent_at is null
    from pipeline.platform_alerts where id = v_recovery),
    'collector: the new recovery alert starts pending and unattempted');
  r := security.platform_alerts_evaluate_v1();
  perform fx.ok((r->>'recovered')::int = 0 and (select count(*) from pipeline.platform_alerts where kind = 'recovered') = 1,
    'collector: repeated evaluation does not duplicate the recovery alert');
  r := security.platform_alerts_take_v1('fixture transport');
  perform fx.ok((r->>'count')::int = 1 and (r->'alerts'->0->>'id')::bigint = v_recovery,
    'collector: recovery uses the same due-pending collection protocol');
  insert into fx.alert_transport_acceptances values (v_recovery, 'fixture-transport:' || v_recovery);
  r := security.platform_alerts_confirm_v1(array[v_recovery], true);
  perform fx.ok((r->>'updated')::int = 1 and (select status = 'sent' and attempts = 1 from pipeline.platform_alerts where id = v_recovery)
    and not exists (select 1 from fx.alert_recipient_receipts where alert_id = v_recovery),
    'collector: recovery confirmation still requires separate recipient receipt evidence');
  perform fx.ok((select count(*) from pipeline.platform_alerts) = 80 and (select count(*) from fx.alert_original_events) = 79,
    'collector: one recovery event is additive to the preserved original backlog');
  perform fx.ok((select count(*) = 79 and bool_and(o.event = to_jsonb(a) - v_mutable)
    from fx.alert_original_events o join pipeline.platform_alerts a on a.id = o.id),
    'collector: original timestamps, content, dedupe keys and event identities are unchanged');
  perform fx.ok((select count(*) from pipeline.platform_alerts where status = 'sent') = 2
    and (select count(*) from fx.alert_transport_acceptances) = 2
    and (select count(*) from fx.alert_recipient_receipts) = 1,
    'collector: collection, caller-reported delivery and modeled receipt have independently measured totals');
  raise notice 'PASS alert collector protocol: 79 original IDs preserved; fixture transport acceptance is not recipient receipt';
end $t$;
