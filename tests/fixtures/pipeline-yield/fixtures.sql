-- CF-247 pipeline yield checks fixtures, AFTER the 20261103040000 migration (applied twice by run.sh). Each case starts from fx.yreset().
-- Prints one NOTICE "ok: ..." per assertion; any failure raises and stops the run.
set timezone = 'UTC';
create or replace function fx.ok(p boolean, p_msg text) returns void language plpgsql as $f$
begin if p is not true then raise exception 'FAILED: %', p_msg; end if; raise notice 'ok: %', p_msg; end $f$;
create or replace function fx.raises(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return null; exception when others then return sqlerrm; end $f$;
create or replace function fx.fps() returns text[] language sql as $f$ select coalesce(array_agg(fingerprint order by fingerprint), '{}') from pipeline.integration_issues $f$;
create or replace function fx.issue(p_fp text) returns pipeline.integration_issues language sql as $f$ select * from pipeline.integration_issues where fingerprint = p_fp $f$;
create or replace function fx.yreset() returns void language plpgsql as $f$
begin
  truncate pipeline.integration_issue_events, pipeline.integration_issues restart identity cascade;
  truncate pipeline.integration_validate_state, pipeline.integration_yield_buckets, pipeline.platform_issues, pipeline.platform_alerts cascade;
  truncate net._http_response, pipeline.edge_request_log, pipeline.mode_outcome_ledger, fx.waiting, pipeline.provider_course_lists, pipeline.entry_matrix_runs,
           pipeline.scholarship_discovery_providers, pipeline.coverage_course_pages, pipeline.enrichment_flags, catalogue.providers cascade;
  insert into catalogue.providers(id, stable_key, canonical_name, country_id) values
    ('00000000-0000-0000-0000-0000000000a1', 'p1', 'Provider One', '00000000-0000-0000-0000-0000000000c1'),
    ('00000000-0000-0000-0000-0000000000a2', 'p2', 'Provider Two', '00000000-0000-0000-0000-0000000000c1');
end $f$;
-- one edge call: the request log row (ring slot) and its response
create or replace function fx.call(p_id bigint, p_mode text, p_status int, p_content text, p_age interval default '5 minutes') returns void language sql as $f$
  insert into pipeline.edge_request_log(slot, request_id, function_name, mode, created_at) values ((p_id % 50000)::int, p_id, 'coverage-sweep', p_mode, now() - p_age);
  insert into net._http_response(id, status_code, content, timed_out, error_msg, created) values (p_id, p_status, p_content, false, null, now() - p_age);
$f$;

-- 0. the migration --------------------------------------------------------------------------------------------------------------------------
do $t$ begin
  perform fx.ok((select count(*) from pipeline.platform_toolset_settings where key in ('integration.hidden_error_window_minutes', 'integration.hidden_error_min_failures',
    'integration.hidden_error_min_share', 'integration.zero_yield_hours', 'integration.zero_yield_min_calls', 'integration.provider_failed_attempts_min',
    'integration.provider_failed_pages_min', 'integration.bucket_keep_hours', 'integration.yield_window_hours')) = 9, 'nine settings (G2)');
  perform fx.ok((select command from cron.job where jobname = 'integration-validate') = 'select security.integration_validate_v1(), security.integration_yield_checks_v1()', 'the job runs the yield checks after the integration checks');
  perform fx.ok((select active from cron.job where jobname = 'integration-validate') is false, 'the job keeps its state (inactive here)');
  perform fx.ok((select description from pipeline.automation_catalogue where jobname = 'integration-validate') like '%integration_yield_checks_v1%', 'the catalogue says so (once)');
  perform fx.ok((select count(*) from pipeline.component_register where introduced_in = '20261103040000') = 4, 'component register');
  perform fx.ok(not has_function_privilege('anon', 'public.admin_pipeline_yield(jsonb)', 'execute'), 'anon cannot read the yield');
  perform fx.ok(not has_function_privilege('authenticated', 'security.integration_yield_checks_v1()', 'execute'), 'clients cannot run the checks');
end $t$;

-- 1. clean: every check runs and finds nothing ----------------------------------------------------------------------------------------------
select fx.yreset();
do $t$ declare r jsonb;
begin
  -- healthy calls, a few errors below the share, an idle lane with no work waiting, complete lists, a provider with few failing pages
  for i in 1..20 loop perform fx.call(i, 'read', 200, '{"ok": true, "done": 3}'); end loop;
  perform fx.call(21, 'read', 500, 'boom');
  for i in 1..8 loop insert into pipeline.mode_outcome_ledger(mode, items, ok) values ('find_site', 0, 0); end loop;
  for i in 1..8 loop insert into pipeline.mode_outcome_ledger(mode, items, ok) values ('read', 3, 3); end loop;
  insert into pipeline.provider_course_lists(provider_id, status, links_found, reason) values ('00000000-0000-0000-0000-0000000000a1', 'read', 25, 'Found by the course source finder (25 course addresses)');
  insert into pipeline.entry_matrix_runs(provider_id, state, error) values ('00000000-0000-0000-0000-0000000000a1', 'failed', 'held_unparsed: not a country table');
  insert into pipeline.coverage_course_pages(course_id, provider_id, read_status, read_attempts) select gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', 'fetch_failed', 3 from generate_series(1, 9);
  insert into pipeline.scholarship_discovery_providers(provider_id, status, attempts) values ('00000000-0000-0000-0000-0000000000a1', 'failed', 1);
  insert into pipeline.enrichment_flags(entity, entity_key, provider_id, reason_code, tries) values ('provider', 'x', '00000000-0000-0000-0000-0000000000a1', 'site_unreachable', 1);
  r := security.integration_yield_checks_v1();
  perform fx.ok(r->'errors' = '{}'::jsonb and jsonb_array_length(r->'ran') = 5, 'every check ran without error');
  perform fx.ok(cardinality(fx.fps()) = 0, 'clean: no issue (errors under the share, idle lane, complete list, held_unparsed is not incomplete, few failing pages, one attempt)');
  perform fx.ok((select sum(calls) from pipeline.integration_yield_buckets where kind = 'edge') = 21 and (select sum(calls) from pipeline.integration_yield_buckets where kind = 'ledger') = 16, 'tallies filled');
  -- incremental: a second run adds nothing
  r := security.integration_yield_checks_v1();
  perform fx.ok((select sum(calls) from pipeline.integration_yield_buckets where kind = 'edge') = 21 and (select sum(calls) from pipeline.integration_yield_buckets where kind = 'ledger') = 16, 'incremental: rows past the watermark only, nothing counted twice');
end $t$;

-- 2. each invariant fires ---------------------------------------------------------------------------------------------------------------------
do $t$ declare r jsonb;
begin
  -- the live case: scholarship_discover answers 500 while its job succeeds; link_search answers 200 with "ok": false
  for i in 101..106 loop perform fx.call(i, 'scholarship_discover', case when i <= 104 then 500 else 200 end, case when i <= 104 then '{"error":"worker crashed"}' else '{"ok": true}' end); end loop;
  for i in 201..204 loop perform fx.call(i, 'link_search', 200, '{"ok": false, "error": "search provider refused"}'); end loop;
  -- zero yield: calls with items taken and none done; and an idle-looking lane whose work is waiting
  for i in 1..6 loop insert into pipeline.mode_outcome_ledger(mode, items, ok, failed) values ('fc_run', 2, 0, 2); end loop;
  insert into fx.waiting values ('find_site');
  -- pagination: 3,000 links read of 3,313 listed; an incomplete entry-matrix read
  insert into pipeline.provider_course_lists(provider_id, status, links_found, reason) values ('00000000-0000-0000-0000-0000000000a2', 'read', 3000, 'Found by the course source finder (3313 course addresses)');
  insert into pipeline.entry_matrix_runs(provider_id, state, error) values ('00000000-0000-0000-0000-0000000000a2', 'failed', 'held_incomplete: 2 of 31 published minimums');
  -- repeated failures: a provider with 10 failing pages; a discovery failed 3 times; a flag tried 3 times
  insert into pipeline.coverage_course_pages(course_id, provider_id, read_status, read_attempts) select gen_random_uuid(), '00000000-0000-0000-0000-0000000000a2', 'blocked', 4 from generate_series(1, 10);
  insert into pipeline.scholarship_discovery_providers(provider_id, status, attempts) values ('00000000-0000-0000-0000-0000000000a2', 'failed', 3);
  insert into pipeline.enrichment_flags(entity, entity_key, provider_id, reason_code, tries) values ('provider', 'y', '00000000-0000-0000-0000-0000000000a2', 'pages_refuse_reading', 3);
  r := security.integration_yield_checks_v1();
  perform fx.ok(r->'errors' = '{}'::jsonb, 'every check ran without error');
  perform fx.ok(fx.fps() = array['hidden_worker_error:coverage-sweep:link_search', 'hidden_worker_error:coverage-sweep:scholarship_discover', 'incomplete_pagination:course_lists',
    'incomplete_read:entry_matrix', 'provider_failed_attempts:course_pages', 'provider_failed_attempts:flag:pages_refuse_reading', 'provider_failed_attempts:scholarship_discovery',
    'zero_yield:fc_run', 'zero_yield:find_site'], 'each invariant fires once: ' || array_to_string(fx.fps(), ', '));
  perform fx.ok((fx.issue('hidden_worker_error:coverage-sweep:scholarship_discover')).failure like '4 of 6 answer(s) failed%', 'hidden error: 4 of 6 failed, with the sample');
  perform fx.ok((fx.issue('hidden_worker_error:coverage-sweep:link_search')).failure like '4 of 4 answer(s) failed%', '"ok": false under HTTP 200 counts as failed');
  perform fx.ok((fx.issue('zero_yield:fc_run')).severity = 'P1' and (fx.issue('zero_yield:find_site')).severity = 'P2', 'zero yield with failures is P1; with work waiting P2');
  perform fx.ok((fx.issue('provider_failed_attempts:course_pages')).provider_ids = array['00000000-0000-0000-0000-0000000000a2']::uuid[], 'the failing provider is named; the one with 9 pages is not');
  perform fx.ok((fx.issue('incomplete_pagination:course_lists')).failure like '1 course list(s) marked read with 313 listed%', '313 listed addresses not reached');
  -- repeated runs: no duplicates
  r := security.integration_yield_checks_v1();
  perform security.integration_validate_v1();
  r := security.integration_yield_checks_v1();
  perform fx.ok((select count(*) from pipeline.integration_issues) = 9, 'repeated runs (and the integration checks between them): no duplicate issues');
  perform fx.ok((fx.issue('hidden_worker_error:coverage-sweep:scholarship_discover')).retry_count = 2, 'retry count rises on each run');
  perform fx.ok((fx.issue('hidden_worker_error:coverage-sweep:scholarship_discover')).condition_cleared_at is null, 'the integration checks do not clear the yield issues');
end $t$;

-- 3. a condition that clears is marked cleared; it comes back as the same issue; after closure it reopens -------------------------------------
do $t$ declare v bigint;
begin
  update pipeline.provider_course_lists set links_found = 3313;
  perform security.integration_yield_checks_v1();
  perform fx.ok((fx.issue('incomplete_pagination:course_lists')).condition_cleared_at is not null and (fx.issue('incomplete_pagination:course_lists')).status <> 'closed', 'cleared, still open until verified');
  v := (fx.issue('incomplete_pagination:course_lists')).id;
  perform security.integration_issue_close_v1(v, 'controller', jsonb_build_object('outcome', 'passed', 'evidence', 'All 25 course lists now read to their listed count.', 'checked_at', now()));
  update pipeline.provider_course_lists set links_found = 3000;
  perform security.integration_yield_checks_v1();
  perform fx.ok((fx.issue('incomplete_pagination:course_lists')).id = v and (fx.issue('incomplete_pagination:course_lists')).status = 'reopened', 'back after closure: the same issue reopens as a regression');
end $t$;

-- 4. the hidden-error window: old failures leave it; tallies older than the keep time are removed ----------------------------------------------
select fx.yreset();
do $t$ begin
  for i in 301..305 loop perform fx.call(i, 'scholarship_discover', 503, 'unavailable', '5 hours'); end loop;
  perform security.integration_yield_checks_v1();
  perform fx.ok(cardinality(fx.fps()) = 0, 'failures older than the window do not open an issue');
  insert into pipeline.integration_yield_buckets(kind, key, bucket, calls) values ('edge', 'old:x', now() - interval '4 days', 1);
  perform security.integration_yield_checks_v1();
  perform fx.ok(not exists (select 1 from pipeline.integration_yield_buckets where key = 'old:x'), 'tallies older than the keep time removed');
end $t$;

-- 5. the yield view: every lane and stage; the screen is PIM Admin and above -----------------------------------------------------------------
do $t$ declare r jsonb; l jsonb;
begin
  insert into pipeline.mode_outcome_ledger(mode, status, items, ok, failed) values ('scholarship_discover', 500, 0, 0, 1), ('scholarship_read', 200, 2, 2, 0);
  insert into pipeline.scholarship_page_candidates(provider_id, url, found_at, read_status, read_at, admit_status, admitted_at) values
    ('00000000-0000-0000-0000-0000000000a1', 'https://a/1', now(), 'read', now(), 'admitted', now()),
    ('00000000-0000-0000-0000-0000000000a1', 'https://a/2', now(), 'read', now(), 'rejected', null);
  insert into scholarship.scholarships(provider_id, name, lifecycle_status, publication_status) values ('00000000-0000-0000-0000-0000000000a1', 's', 'active', 'published');
  insert into catalogue.course_links(course_id, link_type, url, is_primary, status) values ('00000000-0000-0000-0000-0000000000b1', 'official_course', 'https://a/c', true, 'active');
  insert into catalogue.courses(id, stable_key, provider_id, canonical_title) values ('00000000-0000-0000-0000-0000000000b1', 'c1', '00000000-0000-0000-0000-0000000000a1', 'C') on conflict do nothing;
  insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status, official_course_url)
  values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', 'P', 'C', 'c', to_tsvector('c'), 'published', 'https://a/c')
  on conflict (course_id) do update set official_course_url = excluded.official_course_url, publication_status = 'published';
  insert into pipeline.provider_description_reads(provider_id, state, source_url, evidence_id, source_captured_at, proposal, published_at) values
    ('00000000-0000-0000-0000-0000000000a1', 'admitted', 'https://a/about', gen_random_uuid(), now(), '{"text": "x"}', now());
  update catalogue.providers set description = 'An Australian university.' where id = '00000000-0000-0000-0000-0000000000a1';
  r := security.pipeline_yield_v1(24);
  perform fx.ok((select array_agg(x->>'lane' order by o) from jsonb_array_elements(r->'lanes') with ordinality t(x, o)) = array['scholarships', 'course_pages', 'aer', 'descriptions'], 'four lanes');
  for l in select * from jsonb_array_elements(r->'lanes') loop
    perform fx.ok((select array_agg(k order by k) from jsonb_object_keys(l->'stages') k) = array['accepted_or_held', 'consumer_read_back', 'extracted', 'invoked', 'pages_discovered', 'published', 'read_completely', 'source_accessed'],
                  (l->>'lane') || ': all eight stages');
  end loop;
  l := (select x from jsonb_array_elements(r->'lanes') x where x->>'lane' = 'scholarships');
  perform fx.ok((l->'stages'->'invoked'->>'calls')::int = 2 and (l->'stages'->'invoked'->>'failed_calls')::int = 1, 'scholarships: invoked 2, one failed (the 500 is not success)');
  perform fx.ok((l->'stages'->>'pages_discovered')::int = 2 and (l->'stages'->>'read_completely')::int = 2 and (l->'stages'->'accepted_or_held'->>'accepted')::int = 1
                and (l->'stages'->'accepted_or_held'->>'rejected')::int = 1 and (l->'stages'->>'published')::int = 1 and (l->'stages'->>'consumer_read_back')::int = 1, 'scholarships: each stage counted');
  l := (select x from jsonb_array_elements(r->'lanes') x where x->>'lane' = 'course_pages');
  perform fx.ok((l->'stages'->>'published')::int = 1 and (l->'stages'->>'consumer_read_back')::int = 1, 'course pages: published link read back from the search projection');
  l := (select x from jsonb_array_elements(r->'lanes') x where x->>'lane' = 'descriptions');
  perform fx.ok((l->'stages'->>'published')::int = 1 and (l->'stages'->>'consumer_read_back')::int = 1, 'descriptions: published and read back');
  update fx.caller set uid = gen_random_uuid(), rank = 4;
  perform fx.ok(fx.raises($q$select public.admin_pipeline_yield('{}')$q$) like 'PIM Admin role or above required', 'Pipeline Operator refused');
  update fx.caller set rank = 5;
  perform fx.ok(jsonb_array_length(public.admin_pipeline_yield('{"hours": 24}')->'lanes') = 4, 'PIM Admin reads the yield');
  update fx.caller set uid = null, rank = null;
end $t$;
