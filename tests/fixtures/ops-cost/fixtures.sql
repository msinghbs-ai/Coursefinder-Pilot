-- Workstream F cost and yield: every case on isolated fixtures after the migration (applied twice). Thresholds are lowered by setting so
-- small fixtures trip the breakers; every number the functions read is a setting.
select fx.reset();
select fx.set('ops_cost.trip_min_events', 1); select fx.set('ops_cost.trip_min_share', 1); select fx.set('ops_cost.ineligible_min_credits', 50);

-- settings ship as stated --------------------------------------------------------------------------------------------------------------------
select fx.ok((select count(*) from pipeline.platform_toolset_settings where key like 'ops_cost.%' and label <> '' and unit is not null and used_by is not null and min_value is not null and max_value is not null) = 22,
  'S1 22 cost and yield settings, each with a label, a range, a unit and a used_by line');
select fx.ok((select bool_and((value #>> '{}')::numeric = 0) from pipeline.platform_toolset_settings where key like 'ops_cost.enforce_%') and
             (select count(*) from pipeline.platform_toolset_settings where key like 'ops_cost.enforce_%') = 4, 'S2 the four enforcement switches ship off');
select fx.ok(security.pipeline_num_v1('ops_cost.measure_on', 0) = 1, 'S3 measuring ships on');
select fx.ok(security.pipeline_num_v1('ops_cost.fc_usd_per_credit', -1) = 0, 'S4 Firecrawl is not priced until the Platform Admin sets a price');

-- the six waste checks --------------------------------------------------------------------------------------------------------------------
-- W1 repeated AI read of identical evidence: a course field answered from page content h1, then read again from the same content
insert into pipeline.evidence_artifacts(id, source_url, content_hash, captured_at) values ('10000000-0000-0000-0000-000000000001', 'https://p1.example/c1', 'h1', now() - interval '20 days'),
  ('10000000-0000-0000-0000-000000000002', 'https://p1.example/c1', 'h1', now() - interval '2 days');
insert into pipeline.field_enrich_items(provider_id, course_id, field, state, source, evidence_id, cost_usd, updated_at) values
  (fx.p(1), fx.c(1), 'duration', 'skipped', 'ai_stored', '10000000-0000-0000-0000-000000000001', 0.002, now() - interval '20 days'),
  (fx.p(1), fx.c(1), 'duration', 'skipped', 'ai_stored', '10000000-0000-0000-0000-000000000002', 0.003, now() - interval '2 hours'),
  (fx.p(1), fx.c(2), 'duration', 'filled', 'ai_stored', '10000000-0000-0000-0000-000000000001', 0.002, now() - interval '3 hours');
-- W5 a low-confidence loop: course 3 english read three times by AI with no value
insert into pipeline.evidence_artifacts(id, source_url, content_hash) values ('10000000-0000-0000-0000-000000000003', 'https://p1.example/c3', 'h3a'),
  ('10000000-0000-0000-0000-000000000004', 'https://p1.example/c3', 'h3b'), ('10000000-0000-0000-0000-000000000005', 'https://p1.example/c3', 'h3c');
insert into pipeline.field_enrich_items(provider_id, course_id, field, state, source, evidence_id, cost_usd, updated_at) values
  (fx.p(1), fx.c(3), 'english', 'skipped', 'ai_stored', '10000000-0000-0000-0000-000000000003', 0.004, now() - interval '9 days'),
  (fx.p(1), fx.c(3), 'english', 'review', 'ai_stored', '10000000-0000-0000-0000-000000000004', 0.004, now() - interval '5 days'),
  (fx.p(1), fx.c(3), 'english', 'failed', 'ai_stored', '10000000-0000-0000-0000-000000000005', 0.004, now() - interval '1 hour');
-- W1 scholarship side: the same content, model, prompt, run kind and step read twice
insert into pipeline.scholarship_ai_queue(id, provider_id, state, step) overriding system value values (1, fx.p(1), 'done', 1), (2, fx.p(1), 'done', 1);
insert into pipeline.scholarship_ai_extractions(queue_id, model_code, prompt_version, run_kind, provider_id, url, content_hash, cost_usd, at) values
  (1, 'm', 3, 'admit', fx.p(1), 'https://p1.example/sch', 'sh1', 0.001, now() - interval '3 days'), (2, 'm', 3, 'admit', fx.p(1), 'https://p1.example/sch', 'sh1', 0.001, now() - interval '30 minutes');
-- W2 repeated searches: the same query twice within a day; a different query once
insert into pipeline.coverage_vendor_usage(units, purpose, provider_id, url, at) values
  (2, 'course_link_search', fx.p(1), '"Bachelor of Arts" site:p1.example', now() - interval '5 hours'),
  (2, 'course_link_search', fx.p(1), '"Bachelor of Arts" site:p1.example', now() - interval '4 hours'),
  (2, 'course_link_search', fx.p(1), '"Master of Arts" site:p1.example', now() - interval '4 hours');
-- W3 a paid read of a page stored 3 hours earlier, and one of a page never stored
insert into pipeline.evidence_artifacts(source_url, content_hash, captured_at) values ('https://p1.example/stored', 'hs', now() - interval '3 hours');
insert into pipeline.coverage_vendor_usage(units, purpose, provider_id, url, at) values (1, 'scrape', fx.p(1), 'https://p1.example/stored', now() - interval '1 hour'),
  (1, 'scrape', fx.p(1), 'https://p1.example/new', now() - interval '1 hour');
-- W4 AI course-page matching past the cap (attempt 5), and a normal attempt
insert into pipeline.coverage_ai_match(course_id, provider_id, attempt, state, cost_usd, created_at) values (fx.c(4), fx.p(1), 5, 'none', 0.0002, now() - interval '2 hours'),
  (fx.c(5), fx.p(1), 1, 'chosen', 0.0002, now() - interval '2 hours');
-- W6 ineligible providers: P2 (search-stopped) 60 credits of fc_search, P3 (scholarship-ineligible) 4 credits of sch_scrape, P4 (skip-listed) 2 credits
insert into pipeline.coverage_vendor_usage(units, purpose, provider_id, url, at) select 2, 'fc_search', fx.p(2), 'q' || g, now() - interval '2 hours' from generate_series(1, 30) g;
insert into pipeline.coverage_vendor_usage(units, purpose, provider_id, url, at) select 1, 'sch_scrape', fx.p(3), 'https://p3.example/s' || g, now() - interval '2 hours' from generate_series(1, 4) g;
insert into pipeline.coverage_vendor_usage(units, purpose, provider_id, url, at) values (2, 'map', fx.p(4), 'https://p4.example', now() - interval '2 hours');

do $$ declare m jsonb := security.ops_cost_waste_v1(24)->'checks'; begin
  perform fx.ok((m#>>'{cost_repeat_ai_read,events}')::int = 2 and (m#>>'{cost_repeat_ai_read,detail,enrich_fields}')::int = 1 and (m#>>'{cost_repeat_ai_read,detail,scholarship_ai}')::int = 1,
    'W1 repeated AI reads of identical evidence: the enrich read of unchanged content already answered and the scholarship re-read count; a different course on the same page does not');
  perform fx.ok(round((m#>>'{cost_repeat_ai_read,ai_usd}')::numeric, 4) = 0.004, 'W1 its AI spend is the repeat reads'' cost');
  perform fx.ok((m#>>'{cost_repeat_search,events}')::int = 1 and (m#>>'{cost_repeat_search,credits}')::numeric = 2, 'W2 the identical query within a day is one repeat of 2 credits; the other query is not');
  perform fx.ok((m#>>'{cost_paid_stored_page,events}')::int = 1 and (m#>>'{cost_paid_stored_page,base_events}')::int = 6, 'W3 one of six paid reads bought a page stored 3 hours earlier');
  perform fx.ok((m#>>'{cost_unbounded_retry,events}')::int = 1 and (m#>>'{cost_unbounded_retry,detail,cap}')::int = 3, 'W4 the match attempt past waste.retry_max_attempts counts');
  perform fx.ok((m#>>'{cost_low_conf_loop,detail,course_fields}')::int = 1 and (m#>>'{cost_low_conf_loop,events}')::int = 1, 'W5 the course field read three times with no value is one loop (its read in the window counted)');
  perform fx.ok((m#>>'{cost_ineligible_scan,detail,providers}')::int = 3 and (m#>>'{cost_ineligible_scan,credits}')::numeric = 66
                and (m#>'{cost_ineligible_scan,detail,heavy_providers}') = jsonb_build_array(fx.p(2)::text),
    'W6 credits on the search-stopped, scholarship-ineligible and skip-listed providers count; only P2 (60 credits) is over the breaker''s minimum');
  perform fx.ok(jsonb_array_length(m#>'{cost_low_conf_loop,samples}') = 1 and m#>>'{cost_low_conf_loop,samples,0,field}' = 'english', 'W7 each measure carries samples');
end $$;
select fx.set('ops_cost.loop_min_reads', 4);
select fx.ok((security.ops_cost_waste_v1(24)#>>'{checks,cost_low_conf_loop,events}')::int = 0, 'W8 the loop size is a setting: at 4 reads the course field is not yet a loop');
select fx.set('ops_cost.loop_min_reads', 3);

-- the hourly guard inside the existing waste-guard job ---------------------------------------------------------------------------------------
do $$ declare g jsonb := security.waste_guard_v1(); begin
  perform fx.ok(g ? 'idle' and g ? 'frozen' and g ? 'flags' and (g#>>'{cost,measured}')::boolean, 'G1 waste_guard_v1 keeps its three checks and adds the cost checks');
  perform fx.ok((select count(*) from pipeline.ops_cost_waste_measures) = 6, 'G1 six measures recorded');
  perform fx.ok((select count(*) from pipeline.ops_cost_breakers where scope_kind = 'global' and state = 'tripped') = 6, 'G2 with the lowered thresholds all six breakers trip');
  perform fx.ok(exists (select 1 from pipeline.ops_cost_breakers where code = 'cost_ineligible_scan' and scope_kind = 'provider' and scope_key = fx.p(2)::text and state = 'tripped')
                and not exists (select 1 from pipeline.ops_cost_breakers where scope_kind = 'provider' and scope_key = fx.p(3)::text), 'G2 the provider breaker trips for P2 only');
  perform fx.ok((select count(*) from pipeline.integration_issues where fingerprint like 'cost:cost_%') = 6, 'G3 one integration issue per check, by fingerprint');
  perform fx.ok((select diagnosis->>'root_cause' from pipeline.integration_issues where fingerprint = 'cost:cost_repeat_search') = 'cost_repeat_search'
                and (select correlation_key from pipeline.integration_issues where fingerprint = 'cost:cost_repeat_search') = 'cost:cost_repeat_search',
    'G3 each issue carries the deterministic diagnosis and correlation key (workstream A''s columns)');
  perform fx.ok((select count(*) from pipeline.enrichment_flags) = 0, 'G4 enforcement off: nothing is held');
end $$;
select security.waste_guard_v1();
select fx.ok((select count(*) from pipeline.integration_issues where fingerprint like 'cost:%') = 6 and (select max(observed) from pipeline.integration_issues) = 2,
  'G5 an unchanged problem re-observes its issue; no duplicate');
update pipeline.integration_issues set diagnosis = '{"root_cause": "set by the controller"}' where fingerprint = 'cost:cost_repeat_search';
select security.waste_guard_v1();
select fx.ok((select diagnosis->>'root_cause' from pipeline.integration_issues where fingerprint = 'cost:cost_repeat_search') = 'set by the controller', 'G6 a diagnosis already recorded is not overwritten');

-- the Firecrawl breakers in svc_fc_spend: off, then each switched on -----------------------------------------------------------------------
select fx.ok(fx.spend('course_link_search', fx.p(1), '"Bachelor of Arts" site:p1.example', 2), 'B1 switches off: a repeated search is paid for as before (breaker tripped, switch off)');
select fx.ok(fx.spend('scrape', fx.p(1), 'https://p1.example/stored'), 'B1 switches off: a stored page is bought as before');
select fx.ok(fx.spend('fc_search', fx.p(2), 'q-new'), 'B1 switches off: the ineligible provider is not refused');
select fx.ok((select count(*) from pipeline.firecrawl_budget_refusals) = 0, 'B1 no refusal recorded');
select fx.set('ops_cost.enforce_repeat_search', 1);
select fx.ok(not fx.spend('course_link_search', fx.p(1), '"Bachelor of Arts" site:p1.example', 2), 'B2 repeated search refused');
select fx.ok((select reason from pipeline.firecrawl_budget_refusals) = 'repeat_search' and (select reason from pipeline.firecrawl_refusals_by_provider) = 'repeat_search',
  'B2 recorded with the other refusals, per day and per provider');
select fx.ok(fx.spend('course_link_search', fx.p(1), '"Bachelor of Science" site:p1.example', 2), 'B2 a new query is paid for');
select fx.set('ops_cost.repeat_search_hours', 1);
select fx.ok(fx.spend('course_link_search', fx.p(1), '"Master of Arts" site:p1.example', 2), 'B2 a query last paid 4 hours ago is outside a 1-hour window (setting)');
select fx.set('ops_cost.repeat_search_hours', 24);
select fx.set('ops_cost.enforce_stored_page', 1);
select fx.ok(not fx.spend('scrape', fx.p(1), 'https://p1.example/stored'), 'B3 a page stored 3 hours ago is not bought again');
select fx.ok(fx.spend('scrape', fx.p(1), 'https://p1.example/never-stored'), 'B3 a page never stored is bought');
insert into pipeline.scholarship_pages(url, requested_at) values ('https://p1.example/stored', now());
select fx.ok(fx.spend('sch_scrape', fx.p(1), 'https://p1.example/stored'), 'B3 a page a person asked to be read again is never held');
delete from pipeline.scholarship_pages;
insert into pipeline.enrich_plan_runs(provider_id, mode, state) values (fx.p(1), 'manual', 'running');
select fx.ok(fx.spend('scrape', fx.p(1), 'https://p1.example/stored'), 'B3 an on-demand run a person started is decided before the breakers and not held');
delete from pipeline.enrich_plan_runs;
select fx.set('ops_cost.enforce_ineligible', 1);
select fx.ok(not fx.spend('fc_search', fx.p(2), 'q-other'), 'B4 the tripped ineligible provider is refused');
select fx.ok(fx.spend('fc_search', fx.p(1), 'q-other'), 'B4 an ordinary provider is not');
insert into fx.knobs values ('month_limit', null), ('month_refusal', 'month limit reached');
select fx.ok(not fx.spend('course_link_search', fx.p(1), '"Bachelor of Arts" site:p1.example', 2), 'B5 the month limit still decides first');
select fx.ok((select n from pipeline.firecrawl_budget_refusals where reason = 'month_limit') = 1, 'B5 refused as month_limit, not as a breaker');
delete from fx.knobs;
update pipeline.ops_cost_breakers set state = 'clear' where code = 'cost_repeat_search';
select fx.ok(fx.spend('course_link_search', fx.p(1), '"Bachelor of Arts" site:p1.example', 2), 'B6 a switch on does nothing while its breaker is clear (a circuit breaker, not a rule)');
select fx.set('ops_cost.enforce_repeat_search', 0); select fx.set('ops_cost.enforce_stored_page', 0); select fx.set('ops_cost.enforce_ineligible', 0);

-- the loop hold through the existing enrich_no_value hold ---------------------------------------------------------------------------------
select fx.ok(not security.enrich_item_held_v1(fx.c(3), 'english'), 'H1 the looping course field is not held before');
select fx.set('ops_cost.enforce_ai_loop_hold', 1);
select fx.ok((security.waste_guard_v1()#>>'{cost,held}')::int = 1, 'H2 switch on, breaker tripped: one course field held');
select fx.ok((select state || ':' || source || ':' || input_mark from pipeline.enrichment_flags where entity_key = fx.c(3)::text and field = 'english' and reason_code = 'enrich_no_value')
             = 'counting:ops-cost-guard:10000000-0000-0000-0000-000000000005', 'H2 a soft enrich_no_value flag marked with the last evidence read');
select fx.ok(security.enrich_item_held_v1(fx.c(3), 'english'), 'H3 the existing hold now skips it');
select fx.ok(not security.enrich_item_held_v1(fx.c(1), 'duration'), 'H3 a course field read twice is not held');
select fx.ok((security.waste_guard_v1()#>>'{cost,held}')::int = 0, 'H4 a held course field is not held again');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_at, evidence_id) values (fx.c(3), fx.p(1), 'https://p1.example/c3', 'bound', now(), gen_random_uuid());
select fx.ok(not security.enrich_item_held_v1(fx.c(3), 'english'), 'H5 a new page read lifts the hold (the flag unit''s own rule)');
select fx.set('ops_cost.hold_per_run', 0);
delete from pipeline.coverage_course_pages; delete from pipeline.enrichment_flags;
select fx.ok((security.waste_guard_v1()#>>'{cost,held}')::int = 0, 'H6 the per-run limit is a setting (0 holds nothing)');
select fx.set('ops_cost.hold_per_run', 500); select fx.set('ops_cost.enforce_ai_loop_hold', 0);

-- the registry (workstream A's contract) and the breaker remedy --------------------------------------------------------------------------------
select fx.ok((select count(*) from pipeline.ops_root_causes where code like 'cost\_%') = 8, 'R1 eight root causes registered');
select fx.ok((select authority from pipeline.ops_remedies where code = 'cost_breaker') = 'auto' and (select action_fn::text from pipeline.ops_remedies where code = 'cost_breaker') = 'security.ops_cost_remedy_breaker_v1(bigint)'
             and (select verify_fn::text from pipeline.ops_remedies where code = 'cost_breaker') = 'security.ops_cost_remedy_verify_v1(bigint)', 'R1 cost_breaker is auto with its action and verify functions');
select fx.ok((select authority from pipeline.ops_remedies where code = 'cost_result_reuse') = 'release' and (select authority from pipeline.ops_remedies where code = 'cost_budget_decision') = 'admin'
             and (select action_fn from pipeline.ops_remedies where code = 'cost_budget_decision') is null, 'R1 the shared fix is a release and the budget is the Platform Admin''s');
select fx.ok((select bool_and(exists (select 1 from pipeline.ops_root_causes c where c.code = t)) from pipeline.ops_remedies r, unnest(r.treats) t where r.code like 'cost\_%'), 'R1 every remedy treats registered root causes');
update pipeline.ops_cost_breakers set state = 'clear' where code = 'cost_paid_stored_page';
do $$ declare v_id bigint := (select id from pipeline.integration_issues where fingerprint = 'cost:cost_paid_stored_page'); a jsonb; begin
  a := security.ops_cost_remedy_breaker_v1(v_id);
  perform fx.ok((a->>'ok')::boolean and not (a->>'changed')::boolean and a#>>'{evidence,switch}' = 'ops_cost.enforce_stored_page',
    'R2 with its switch off the remedy trips the breaker but reports no change (the controller does not count it a repair)');
  update pipeline.ops_cost_breakers set state = 'clear' where code = 'cost_paid_stored_page';
  perform fx.set('ops_cost.enforce_stored_page', 1);
  a := security.ops_cost_remedy_breaker_v1(v_id);
  perform fx.ok((a->>'changed')::boolean and (select state from pipeline.ops_cost_breakers where code = 'cost_paid_stored_page' and scope_kind = 'global') = 'tripped', 'R3 with its switch on it trips and reports a change');
  perform fx.set('ops_cost.enforce_stored_page', 0);
  perform fx.ok(not (security.ops_cost_remedy_verify_v1(v_id)->>'passed')::boolean, 'R4 verify fails while the waste is still measured');
  insert into pipeline.ops_remedy_runs(issue_id, remedy_code, started_at) values (v_id, 'cost_breaker', now());
  perform fx.ok((security.ops_cost_remedy_verify_v1(v_id)->>'passed')::boolean, 'R5 verify passes when nothing was wasted since the remedy started');
end $$;
insert into pipeline.integration_issues(fingerprint) values ('health:budgets:firecrawl');
select fx.ok(not (security.ops_cost_remedy_breaker_v1((select id from pipeline.integration_issues where fingerprint = 'health:budgets:firecrawl'))->>'ok')::boolean, 'R6 the breaker remedy refuses an issue that is not a cost check');

-- clearing: the waste stops, the breakers clear and the issues are marked cleared ---------------------------------------------------------------
select fx.set('ops_cost.trip_min_events', 100000);
select security.waste_guard_v1();
select fx.ok((select count(*) from pipeline.ops_cost_breakers where scope_kind = 'global' and state = 'tripped') = 1, 'C1 global breakers clear below the thresholds (ineligible stays: P2 is still over its minimum)');
select fx.ok((select count(*) from pipeline.integration_issues where fingerprint like 'cost:%' and condition_cleared_at is not null) = 5, 'C1 their issues are marked cleared');
select fx.set('ops_cost.ineligible_min_credits', 1000);
select security.waste_guard_v1();
select fx.ok(not exists (select 1 from pipeline.ops_cost_breakers where state = 'tripped'), 'C2 provider breakers clear too');
select fx.set('ops_cost.trip_min_events', 1); select fx.set('ops_cost.ineligible_min_credits', 50);

-- switched off, and errors contained -----------------------------------------------------------------------------------------------------
select fx.set('ops_cost.measure_on', 0);
create temp table o1 as select count(*) n from pipeline.ops_cost_waste_measures;
select fx.ok((security.waste_guard_v1()#>>'{cost,measured}')::boolean is false and (select count(*) from pipeline.ops_cost_waste_measures) = (select n from o1), 'O1 measure off: nothing recorded');
select fx.set('ops_cost.measure_on', 1);
alter table pipeline.coverage_ai_match rename to coverage_ai_match_x;
do $$ declare g jsonb := security.waste_guard_v1(); begin
  perform fx.ok(g ? 'idle' and g#>>'{cost,error}' is not null and not (g#>>'{cost,measured}')::boolean, 'O2 a failing cost check never fails the waste guard');
end $$;
alter table pipeline.coverage_ai_match_x rename to coverage_ai_match;
insert into pipeline.ops_cost_waste_measures(measured_at, window_hours, check_code) values (now() - interval '200 days', 24, 'old');
select security.waste_guard_v1();
select fx.ok(not exists (select 1 from pipeline.ops_cost_waste_measures where check_code = 'old'), 'O3 measures older than ops_cost.measure_keep_days are removed by the job');

-- the value of a candidate plan step (for workstream D) ------------------------------------------------------------------------------------
select fx.reset();
-- fields: 4 values on stored pages not yet read, 2 needing a page, 1 not on the page; history 30 settled, 12 filled (40%)
insert into pipeline.course_attribute_coverage(course_id, provider_id, attribute, state) select fx.c(g), fx.p(1), 'duration', 'page_found' from generate_series(1, 4) g;
insert into pipeline.course_attribute_coverage(course_id, provider_id, attribute, state) select fx.c(g), fx.p(1), 'duration', 'site_known' from generate_series(5, 6) g;
insert into pipeline.course_attribute_coverage(course_id, provider_id, attribute, state) values (fx.c(7), fx.p(1), 'duration', 'not_on_page'), (fx.c(8), fx.p(1), 'english', 'page_found');
insert into pipeline.field_enrich_items(provider_id, course_id, field, state, cost_usd, updated_at)
  select fx.p(1), null, 'duration', case when g <= 12 then 'filled' else 'skipped' end, 0.001, now() - interval '2 days' from generate_series(1, 30) g;
insert into pipeline.ai_spend_ledger(lane, source, cost_usd, calls, at) values ('enrich_fields', 'field_enrich_items', 0.5, 250, now() - interval '1 day'),
  ('enrich_fields', 'opening', 9, 0, now() - interval '1 day');
do $$ declare v jsonb := security.ops_step_value_v1(fx.p(1), 'fields', '{"fields": ["duration"]}'); begin
  perform fx.ok((v->>'expected_eligible')::int = 6 and (v->>'evidence_available')::int = 4, 'V1 fields: 6 eligible (4 on stored pages, 2 needing a page); not-on-page and other fields excluded');
  perform fx.ok((v#>>'{expected_recovery,rate}')::numeric = 0.4 and v#>>'{expected_recovery,basis}' = 'provider' and (v#>>'{expected_recovery,records}')::numeric = 2.4,
    'V1 expected recovery from the provider''s measured yield (12 of 30): 2.4 values');
  perform fx.ok((v#>>'{estimated_cost,ai_usd_per_call}')::numeric = 0.002 and (v#>>'{estimated_cost,ai_usd}')::numeric = 0.012 and (v#>>'{estimated_cost,firecrawl_credits}')::numeric = 2,
    'V1 cost: US$0.002 a call from the ledger (opening rows left out) for 6 calls; 2 credits for the 2 pages to read');
  perform fx.ok((v->>'value_per_dollar')::numeric = 200 and (v->>'value_per_credit')::numeric = 1.2 and v->>'likelihood' = 'medium' and v->>'recommend' = 'run',
    'V1 value per dollar (credits unpriced), per credit, likelihood medium, recommended');
end $$;
select fx.set('ops_cost.fc_usd_per_credit', 0.01);
select fx.ok((security.ops_step_value_v1(fx.p(1), 'fields', '{"fields": ["duration"]}')#>>'{estimated_cost,usd_total}')::numeric = 0.032, 'V2 a price per credit puts credits into US$ (setting)');
select fx.set('ops_cost.fc_usd_per_credit', 0);
select fx.set('ops_cost.min_sample', 50);
select fx.ok(security.ops_step_value_v1(fx.p(1), 'fields', '{"fields": ["duration"]}')#>>'{expected_recovery,basis}' = 'platform', 'V3 below the minimum sample the platform-wide yield is used (setting)');
select fx.set('ops_cost.min_sample', 20);
-- pages: 10 active courses, 2 bound, 1 search found; proofs held for 1; history 25 searches 5 found, 2 verified
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status) values (fx.c(1), fx.p(1), 'u1', 'bound'), (fx.c(2), fx.p(1), 'u2', 'bound');
insert into pipeline.course_link_search(course_id, provider_id, state, done_at) values (fx.c(3), fx.p(1), 'found', now() - interval '1 day');
insert into pipeline.course_link_search(course_id, provider_id, state, done_at) select gen_random_uuid(), fx.p(1), case when g <= 2 then 'verified' when g <= 4 then 'found' else 'none' end, now() - interval '3 days' from generate_series(1, 24) g;
insert into pipeline.course_page_proofs(course_id, page_key, proven) values (fx.c(4), 'k', true);
do $$ declare v jsonb := security.ops_step_value_v1(fx.p(1), 'pages', '{}'); begin
  perform fx.ok((v->>'expected_eligible')::int = 7 and (v->>'evidence_available')::int = 1, 'V4 pages: 7 courses without a page or a search result; 1 already has a proven stored page');
  perform fx.ok((v#>>'{expected_recovery,rate}')::numeric = 0.2 and (v#>>'{expected_recovery,verified_rate}')::numeric = 0.08 and (v#>>'{estimated_cost,firecrawl_credits}')::numeric = 12,
    'V4 found 5 of 25, verified 2 of 25; 6 searches at 2 credits (the proven page needs none)');
end $$;
-- in progress, retry history, skip
insert into pipeline.enrich_plan_runs(provider_id, state, steps, actual, created_at) values
  (fx.p(1), 'done', '[{"step": "pages", "status": "failed", "note": "too few pages", "est_usd": 0.01}]', '{"usd": 0.05, "credits": 40}', now() - interval '5 days'),
  (fx.p(1), 'running', '[{"step": "pages", "status": "running"}]', null, now());
do $$ declare v jsonb := security.ops_step_value_v1(fx.p(1), 'pages', '{}'); begin
  perform fx.ok((v#>>'{retry,failed}')::int = 1 and v#>>'{retry,last_failure}' = 'too few pages' and (v#>>'{retry,spent_credits}')::numeric = 40, 'V5 the previous failure, its reason and its spend');
  perform fx.ok((v#>>'{in_progress,plan_step_running}')::boolean and v->>'recommend' = 'skip' and v->>'skip_reason' = 'the same step is already running', 'V5 work in progress: skip');
end $$;
select fx.ok(security.ops_step_value_v1(fx.p(2), 'fields', '{}')->>'skip_reason' = 'no eligible records', 'V6 no eligible records: skip');
-- scholarships: 3 candidates waiting (1 stored), history 10 read 2 admitted
insert into pipeline.scholarship_page_candidates(provider_id, admit_status, storage_path) values (fx.p(1), null, 's'), (fx.p(1), null, null), (fx.p(1), null, null), (fx.p(1), 'rejected', 's');
insert into pipeline.scholarship_page_candidates(provider_id, admit_status, admitted_at, read_at) select fx.p(1), case when g <= 2 then 'admitted' else 'rejected' end,
  case when g <= 2 then now() end, now() - interval '1 day' from generate_series(1, 20) g;
select fx.ok((security.ops_step_value_v1(fx.p(1), 'scholarships', '{}')->>'expected_eligible')::int = 3
             and (security.ops_step_value_v1(fx.p(1), 'scholarships', '{}')#>>'{expected_recovery,rate}')::numeric = 0.1, 'V7 scholarships: 3 waiting, measured admission 2 of 20');
do $$ begin
  perform security.ops_step_value_v1(fx.p(1), 'bogus', '{}');
  raise exception 'FAILED: V8';
exception when sqlstate '22023' then perform fx.ok(true, 'V8 an unknown step is refused');
end $$;

-- the efficiency report (§16) ---------------------------------------------------------------------------------------------------------------
insert into pipeline.field_enrich_items(provider_id, course_id, field, state, source, cost_usd, updated_at) values (fx.p(1), fx.c(9), 'level', 'filled', 'ai_stored', 0.01, now() - interval '1 hour'),
  (fx.p(1), fx.c(10), 'level', 'filled', 'scraper', 0.01, now() - interval '1 hour');
insert into pipeline.ai_spend_ledger(lane, source, cost_usd, calls, at) values ('enrich_fields', 'field_enrich_items', 0.6, 300, now() - interval '1 hour');
insert into pipeline.coverage_vendor_usage(units, purpose, provider_id, url, at) values (2, 'course_link_search', fx.p(1), 'q', now() - interval '1 hour'), (1, 'scrape', fx.p(1), 'u', now() - interval '1 hour');
insert into pipeline.course_link_search(course_id, provider_id, state, done_at) values (gen_random_uuid(), fx.p(1), 'verified', now() - interval '1 hour');
do $$ declare r jsonb := security.ops_cost_report_v1(6); begin
  perform fx.ok(r ? 'paid_operations' and r ? 'evidence_cache_reuse' and r ? 'avoided_duplicate_reads' and r ? 'useful_yield_per_execution' and r ? 'consumption'
                and r ? 'cost_per_verified_improvement' and r ? 'waste_latest' and r ? 'breakers', 'P1 the report has the six §16 efficiency parts plus waste and breakers');
  perform fx.ok((r#>>'{paid_operations,ai_by_lane,enrich_fields,usd}')::numeric = 0.6 and (r#>>'{paid_operations,firecrawl_by_purpose,course_link_search,credits}')::numeric = 2,
    'P2 paid operations: AI by lane (opening rows left out), Firecrawl by purpose');
  perform fx.ok((r#>>'{cost_per_verified_improvement,by_lane,enrich_fields,improvements}')::int = 2 and (r#>>'{cost_per_verified_improvement,by_lane,enrich_fields,ai_usd_per_improvement}')::numeric = 0.3,
    'P3 cost per verified improvement: US$0.60 for 2 values filled');
  perform fx.ok((r#>>'{cost_per_verified_improvement,by_lane,course_link_search,credits_per_improvement}')::numeric = 2, 'P3 2 credits per page found by search');
  perform fx.ok((r#>>'{evidence_cache_reuse,from_stored_evidence}')::int = 1 and (r#>>'{evidence_cache_reuse,new_reads}')::int = 1 and (r#>>'{evidence_cache_reuse,share_pct}')::numeric = 50,
    'P4 evidence reuse: one value from a stored page, one from a new read');
end $$;
select fx.ok((select provolatile from pg_proc where oid = 'security.ops_cost_report_v1(int)'::regprocedure) = 's' and (select provolatile from pg_proc where oid = 'security.ops_step_value_v1(uuid,text,jsonb)'::regprocedure) = 's'
             and (select provolatile from pg_proc where oid = 'security.ops_cost_waste_v1(int,timestamptz)'::regprocedure) = 's', 'P5 the report, the step value and the waste checks are read-only (stable)');
