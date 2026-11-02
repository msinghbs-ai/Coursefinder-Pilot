-- Decision 5 E-7/E-8 fixtures, BEFORE the 20261102070000 migration: each defect reproduced on the live definitions (live-defs.json,
-- md5-checked by run.sh). Leaves a known spend today for the opening-row check after the migration.
set timezone = 'UTC';  -- as live (session time zone UTC)
create or replace function fx.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is distinct from true then raise exception 'FAIL: %', p_what; end if; end $f$;
create or replace function fx.reset() returns void language plpgsql as $f$
begin
  truncate pipeline.scholarship_ai_extractions, pipeline.scholarship_ai_reviews, pipeline.uni_adapter_drafts, pipeline.central_ai_queue, pipeline.coverage_ai_match,
           pipeline.field_enrich_items, pipeline.fee_reader_queue, pipeline.entry_matrix_runs, pipeline.layer3_openrouter_observations, pipeline.coverage_vendor_usage,
           pipeline.vendor_credit_observations, pipeline.layer2_provider_attempts, pipeline.firecrawl_budget_refusals, pipeline.firecrawl_refusals_by_provider,
           pipeline.enrich_plan_runs, fx.fired, pipeline.admin_control_events, catalogue.courses, catalogue.providers, cron.job_run_details, cron.job, pipeline.platform_alerts;
  update pipeline.platform_toolsets set enforcement = 'observe' where key = 'openrouter';
end $f$;
-- one provider and course for course-page matching
create or replace function fx.match_item(p_state text default 'ready') returns bigint language plpgsql as $f$
declare v_p uuid := gen_random_uuid(); v_c uuid := gen_random_uuid(); v bigint;
begin
  insert into catalogue.providers values (v_p, 'Uni', 'Uni'); insert into catalogue.courses values (v_c, v_p, 'Course', 'C1', null);
  insert into pipeline.coverage_ai_match(course_id, provider_id, state, candidates) values (v_c, v_p, p_state, '[{"url": "https://uni.example/c1", "title": "Course"}]') returning id into v;
  return v;
end $f$;

-- E-7 defects ---------------------------------------------------------------------------------------------------------------------------
do $t$
declare v jsonb;
begin
  perform fx.reset();
  update pipeline.platform_toolsets set enforcement = 'stop' where key = 'openrouter';
  insert into pipeline.layer3_openrouter_observations(kind, remaining_usd) values ('credits', 90);
  -- every lane under its guard, US$16 together: over the US$14 ceiling
  insert into pipeline.field_enrich_items(cost_usd) values (9); insert into pipeline.scholarship_ai_extractions(cost_usd) values (4);
  insert into pipeline.fee_reader_queue(cost_usd) values (3);
  perform fx.ok((select sum(spent) from security.ai_spend_today_v1()) = 16, 'before: US$16 spent today');
  perform fx.ok(security.ai_use_allowed_v1('enrich_fields') and security.ai_use_allowed_v1('fee_ai'), 'before: the ceiling is not enforced (lanes under their guards are allowed at US$16)');
  -- AI course-page matching over its guard is claimed anyway: the claim asks no one
  insert into pipeline.coverage_ai_match(cost_usd, state, decided_at) values (6, 'chosen', now());
  perform fx.ok(not security.ai_use_allowed_v1('course_match'), 'before: course_match is over its guard');
  perform fx.match_item();
  v := public.svc_coverage_ai_match_next(10);
  perform fx.ok(jsonb_array_length(v) = 1, 'before: the course_match claim ignores its guard and the ceiling');
  raise notice 'PASS before: ceiling not enforced; course_match claims past its guard';
end $t$;

do $t$
begin
  perform fx.reset();
  update pipeline.platform_toolsets set enforcement = 'stop' where key = 'openrouter';
  insert into pipeline.layer3_openrouter_observations(kind, remaining_usd) values ('credits', 5);  -- exactly the floor
  perform fx.ok(security.ai_use_allowed_v1('fee_ai'), 'before: at the floor is allowed (only below refuses)');
  raise notice 'PASS before: at the floor is allowed';
end $t$;

do $t$
begin
  perform fx.reset();
  -- a cost spent yesterday on an enrichment item is counted again today when the row is touched; a re-check's cost is not counted at all
  insert into pipeline.field_enrich_items(cost_usd, updated_at) values (2, now() - interval '1 day');
  update pipeline.field_enrich_items set state = 'settled', updated_at = now();
  insert into pipeline.scholarship_ai_reviews(recheck) values ('{"state": "done", "cost_usd": 0.75}');
  perform fx.ok((select spent from security.ai_spend_today_v1() where use = 'enrich_fields') = 2, 'before: yesterday''s US$2 counted today');
  perform fx.ok((select sum(spent) from security.ai_spend_today_v1()) = 2, 'before: the re-check''s US$0.75 is not counted');
  raise notice 'PASS before: accounting counts a past cost again and misses the re-check';
end $t$;

-- E-8 defects ---------------------------------------------------------------------------------------------------------------------------
do $t$
declare v_od uuid := gen_random_uuid(); v_p uuid := gen_random_uuid();
begin
  perform fx.reset();
  -- the vendor balance read just now: 1,500 left, under the 2,000 reserve
  insert into pipeline.vendor_credit_observations(provider_id, remaining_units) values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 1500);
  perform fx.ok(not (security.layer2_provider_budget_status('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 1)->>'allowed')::boolean, 'before: the monthly limit says no');
  perform fx.ok(security.fc_budget_left_v1('scrape') > 0, 'before: the daily check still offers credits');
  perform fx.ok(public.svc_fc_spend(1, 'scrape', v_p, 'https://uni.example/a'), 'before: a worker spend past the month is accepted');
  insert into pipeline.enrich_plan_runs(id, provider_id, mode, state) values (v_od, v_p, 'manual', 'running');
  perform fx.ok(public.svc_fc_spend(1, 'scrape', v_p, 'https://uni.example/b'), 'before: an on-demand spend past the month is accepted');
  raise notice 'PASS before: the month is not checked on the daily or on-demand path';
end $t$;

-- a known spend today for the opening rows (read by fixtures.sql after the migration)
do $t$
begin
  perform fx.reset();
  insert into pipeline.scholarship_ai_extractions(cost_usd) values (0.5); insert into pipeline.fee_reader_queue(cost_usd) values (0.25);
  insert into pipeline.coverage_ai_match(cost_usd, state, decided_at) values (0.125, 'chosen', now());
  create table fx.opening as select use, spent, calls from security.ai_spend_today_v1() where spent > 0;
  perform fx.ok((select count(*) from fx.opening) = 3, 'three lanes with spend before');
end $t$;
