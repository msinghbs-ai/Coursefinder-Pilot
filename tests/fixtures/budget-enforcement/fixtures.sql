-- Decision 5 E-7/E-8/E-9 fixtures, AFTER the 20261102070000 migration (applied twice by run.sh). Isolated cases; each starts from fx.reset().
set timezone = 'UTC';  -- as live (session time zone UTC)
create or replace function fx.reset() returns void language plpgsql as $f$
begin
  truncate pipeline.scholarship_ai_extractions, pipeline.scholarship_ai_reviews, pipeline.uni_adapter_drafts, pipeline.central_ai_queue, pipeline.coverage_ai_match,
           pipeline.field_enrich_items, pipeline.fee_reader_queue, pipeline.entry_matrix_runs, pipeline.layer3_openrouter_observations, pipeline.coverage_vendor_usage,
           pipeline.vendor_credit_observations, pipeline.layer2_provider_attempts, pipeline.firecrawl_budget_refusals, pipeline.firecrawl_refusals_by_provider,
           pipeline.enrich_plan_runs, fx.fired, pipeline.admin_control_events, catalogue.courses, catalogue.providers, cron.job_run_details, cron.job, pipeline.platform_alerts,
           pipeline.ai_spend_ledger;
  update pipeline.platform_toolsets set enforcement = 'observe' where key = 'openrouter';
  update pipeline.platform_toolset_settings set value = '5' where toolset_key = 'openrouter' and key = 'credit_floor_usd';
end $f$;
create or replace function fx.stop(p_balance numeric default 90) returns void language sql as $f$
  update pipeline.platform_toolsets set enforcement = 'stop' where key = 'openrouter';
  insert into pipeline.layer3_openrouter_observations(kind, remaining_usd, observed_at) values ('credits', p_balance, now() - interval '1 minute');
$f$;
create or replace function fx.today(p_use text) returns numeric language sql as $f$ select spent from security.ai_spend_today_v1() where use = p_use $f$;
create or replace function fx.total() returns numeric language sql as $f$ select sum(spent) from security.ai_spend_today_v1() $f$;
-- whether an admin action raised (and its message)
create or replace function fx.raises(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return null; exception when others then return sqlerrm; end $f$;

-- 0. the migration kept every setting value and the opening rows are today's spend as counted before ---------------------------------------
do $t$
begin
  perform fx.ok((select enforcement from pipeline.platform_toolsets where key = 'openrouter') = 'observe', 'enforcement stays observe');
  perform fx.ok((select value from pipeline.platform_toolset_settings where toolset_key = 'openrouter' and key = 'credit_floor_usd') = '5', 'credit floor stays US$5');
  perform fx.ok((select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'budgets.ai_daily_ceiling_usd') = '14', 'ceiling stays US$14');
  perform fx.ok((select value from pipeline.platform_toolset_settings where toolset_key = 'firecrawl' and key = 'daily_budget_total') = '25000', 'daily total stays 25,000');
  perform fx.ok((select value from pipeline.platform_toolset_settings where toolset_key = 'firecrawl' and key = 'ondemand_credits_per_day') = '2000', 'on-demand stays 2,000');
  perform fx.ok((select count(*) from pipeline.platform_toolset_settings where key in ('alerts.watchdog_stale_minutes', 'alerts.watchdog_scan_runs')
                   and label is not null and min_value is not null and max_value is not null and unit is not null and used_by is not null) = 2, 'new settings complete (G2)');
  perform fx.ok((select used_by from pipeline.platform_toolset_settings where toolset_key = 'openrouter' and key = 'credit_floor_usd') = 'security.ai_use_refusal_v1 (every AI lane)', 'floor used_by corrected');
  perform fx.ok((select count(*) from pipeline.ai_spend_ledger where source = 'opening') = 3, 'one opening row per lane with spend (and only once: applied twice)');
  perform fx.ok(not exists (select 1 from fx.opening o where o.spent is distinct from fx.today(o.use)), 'spend today after = spend counted before, per lane');
  raise notice 'PASS no live value changed; opening rows equal the spend counted before, once';
end $t$;

-- E-7 ----------------------------------------------------------------------------------------------------------------------------------
do $t$
begin
  perform fx.reset(); perform fx.stop();
  insert into pipeline.field_enrich_items(cost_usd) values (9); insert into pipeline.scholarship_ai_extractions(cost_usd) values (3);
  perform fx.ok(fx.total() = 12, 'US$12 today');
  perform fx.ok(security.ai_use_allowed_v1('enrich_fields') and security.ai_use_allowed_v1('course_match') and security.ai_use_allowed_v1('adapter_builder'), 'under the ceiling: allowed');
  insert into pipeline.fee_reader_queue(cost_usd) values (2);   -- exactly US$14
  perform fx.ok(fx.total() = 14, 'US$14 today');
  perform fx.ok(not security.ai_use_allowed_v1(u), format('at the ceiling: %s refused', u))
    from unnest(array['scholarship_ai', 'adapter_builder', 'central_ai', 'course_match', 'enrich_fields', 'fee_ai', 'entry_matrix']) u;
  perform fx.ok(security.ai_use_refusal_v1('fee_ai') like 'daily ceiling: US$14% spent today (UTC) across all AI lanes, ceiling US$14 (budgets.ai_daily_ceiling_usd)', 'the reason names the ceiling');
  -- observe never refuses, whatever is spent
  update pipeline.platform_toolsets set enforcement = 'observe' where key = 'openrouter';
  perform fx.ok(security.ai_use_allowed_v1('fee_ai') and security.ai_use_refusal_v1('fee_ai') is null, 'observe: never refused');
  raise notice 'PASS ceiling: under allowed, at or over refused on every lane; observe never refuses';
end $t$;

do $t$
begin
  perform fx.reset(); perform fx.stop(5);   -- balance exactly the floor
  perform fx.ok(not security.ai_use_allowed_v1('fee_ai'), 'at the floor: refused');
  perform fx.ok(security.ai_use_refusal_v1('fee_ai') like 'credit floor: balance about US$5.00, at or below the floor of US$5 %', 'the reason names the floor');
  perform fx.reset(); perform fx.stop(5.01);
  perform fx.ok(security.ai_use_allowed_v1('fee_ai'), 'just above the floor: allowed');
  -- spend recorded since the balance was read brings it to the floor before the next reading
  insert into pipeline.central_ai_queue(cost_usd) values (0.01);
  perform fx.ok(not security.ai_use_allowed_v1('fee_ai'), 'balance less spend since the reading at the floor: refused');
  -- the proposed floor of US$10 (a setting change for the Platform Admin): refuses at 10
  perform fx.reset(); perform fx.stop(10);
  perform fx.ok(security.ai_use_allowed_v1('fee_ai'), 'US$10 balance, floor US$5: allowed');
  update pipeline.platform_toolset_settings set value = '10' where toolset_key = 'openrouter' and key = 'credit_floor_usd';
  perform fx.ok(not security.ai_use_allowed_v1('fee_ai'), 'US$10 balance, floor US$10 (proposed): refused');
  raise notice 'PASS floor: at the floor refused, above allowed, spend since the reading counted, the proposed US$10 refuses at 10';
end $t$;

do $t$
declare v jsonb; v_d uuid; v_err text;
begin
  -- the two lanes that asked no one: course-page matching and adapter proposals
  perform fx.reset(); perform fx.stop();
  insert into pipeline.coverage_ai_match(cost_usd, state, decided_at) values (5, 'chosen', now());   -- course_match at its US$5 guard
  perform fx.match_item();
  perform fx.ok(jsonb_array_length(public.svc_coverage_ai_match_next(10)) = 0, 'course_match over its guard: nothing claimed');
  perform fx.ok((select count(*) from pipeline.coverage_ai_match where state = 'leased') = 0, 'no lease taken');
  update pipeline.platform_toolsets set enforcement = 'observe' where key = 'openrouter';
  perform fx.ok(jsonb_array_length(public.svc_coverage_ai_match_next(10)) = 1, 'observe: claimed as before');
  -- adapter proposals over their guard
  perform fx.reset(); perform fx.stop();
  insert into pipeline.uni_adapter_drafts(provider_id, captures, cost_usd) values (gen_random_uuid(), '[{"url": "x"}]', 5) returning id into v_d;
  v_err := fx.raises(format($s$select public.admin_adapter_builder('propose', '{"draft_id": "%s"}')$s$, v_d));
  perform fx.ok(v_err like 'AI spending is stopped for now (lane guard: adapter_builder spent US$5% today (UTC), guard US$5 (openrouter.guard_adapter_builder)). Models & services › Toolsets & limits', 'adapter proposal over its guard: refused with the reason');
  perform fx.ok((select status from pipeline.uni_adapter_drafts where id = v_d) = 'capturing' and not exists (select 1 from fx.fired), 'nothing recorded, nothing sent');
  update pipeline.platform_toolset_settings set value = '6' where toolset_key = 'openrouter' and key = 'guard_adapter_builder';
  perform fx.ok(fx.raises(format($s$select public.admin_adapter_builder('propose', '{"draft_id": "%s"}')$s$, v_d)) is null, 'under its guard: proposed');
  perform fx.ok((select body->>'mode' from fx.fired) = 'adapter_propose', 'the proposal is sent');
  update pipeline.platform_toolset_settings set value = '5' where toolset_key = 'openrouter' and key = 'guard_adapter_builder';
  raise notice 'PASS unguarded lanes now guarded: course_match claims nothing, adapter proposals refused, both as before in observe or under the guard';
end $t$;

do $t$
declare v jsonb; i jsonb; v_st text;
begin
  -- in-flight work is not cut: what is claimed finishes and its cost counts; only new claims are refused
  perform fx.reset(); perform fx.stop();
  insert into pipeline.field_enrich_items(cost_usd) values (13.9);
  perform fx.match_item(); perform fx.match_item(); perform fx.match_item();
  v := public.svc_coverage_ai_match_next(2);
  perform fx.ok(jsonb_array_length(v) = 2, 'two claimed under the ceiling');
  for i in select * from jsonb_array_elements(v) loop
    v_st := public.svc_coverage_ai_match_record((i->>'id')::bigint, 'https://uni.example/c1', '{"choice": 1}', 'm', 0.06, null);
    perform fx.ok(v_st = 'chosen', 'a claimed match finishes after the ceiling is crossed');
  end loop;
  perform fx.ok(fx.total() = 14.02, 'both calls counted (US$13.90 + 0.06 + 0.06)');
  perform fx.ok(jsonb_array_length(public.svc_coverage_ai_match_next(2)) = 0, 'the third is not claimed: over the ceiling');
  perform fx.ok((select count(*) from pipeline.coverage_ai_match where state = 'ready') = 1, 'it waits, unchanged');
  raise notice 'PASS in-flight: claims finish and are counted; new claims refused';
end $t$;

do $t$
declare v jsonb; v_id bigint;
begin
  -- restart and retry: nothing is counted twice
  perform fx.reset(); perform fx.stop();
  v_id := fx.match_item();
  v := public.svc_coverage_ai_match_next(1);
  -- the worker restarts mid-call: the lease runs out and the item is claimed again
  update pipeline.coverage_ai_match set leased_until = now() - interval '1 second' where id = v_id;
  v := public.svc_coverage_ai_match_next(1);
  perform fx.ok(jsonb_array_length(v) = 1, 'the expired lease is claimed again');
  perform fx.ok(public.svc_coverage_ai_match_record(v_id, 'https://uni.example/c1', '{}', 'm', 0.04, null) = 'chosen', 'the second call records');
  -- the first call's late answer finds the item no longer leased: nothing is recorded or counted
  perform fx.ok(public.svc_coverage_ai_match_record(v_id, 'https://uni.example/c1', '{}', 'm', 0.04, null) = 'not_leased', 'the late answer is refused');
  perform fx.ok(fx.today('course_match') = 0.04 and (select count(*) from pipeline.ai_spend_ledger where lane = 'course_match') = 1, 'counted once');
  -- a time-budget release (no call made) records nothing
  v_id := fx.match_item(); v := public.svc_coverage_ai_match_next(1);
  perform fx.ok(public.svc_coverage_ai_match_record(v_id, null, null, 'm', 0, 'time budget') = 'released', 'released');
  perform fx.ok(fx.today('course_match') = 0.04, 'a release adds nothing');
  -- an accumulated cost: an item retried adds only the new call; touching the row adds nothing
  insert into pipeline.fee_reader_queue(cost_usd) values (0.1) returning id into v_id;
  update pipeline.fee_reader_queue set cost_usd = coalesce(cost_usd, 0) + 0.2, state = 'queued' where id = v_id;   -- the retry's call
  update pipeline.fee_reader_queue set state = 'done', finished_at = now() where id = v_id;                          -- finishing, no new cost
  update pipeline.fee_reader_queue set cost_usd = cost_usd where id = v_id;                                            -- the same cost written again
  perform fx.ok(fx.today('fee_ai') = 0.3, 'fee reader: 0.1 + 0.2, once each');
  raise notice 'PASS restart and retry: a late answer, a release and a re-written cost add nothing; each real call counts once';
end $t$;

do $t$
declare v_id bigint;
begin
  -- accounting: the day a cost was recorded, every lane, the re-check included
  perform fx.reset();
  insert into pipeline.field_enrich_items(cost_usd) values (2) returning id into v_id;
  update pipeline.ai_spend_ledger set at = now() - interval '1 day';                    -- recorded yesterday
  update pipeline.field_enrich_items set state = 'settled', updated_at = now() where id = v_id;   -- touched today
  perform fx.ok(fx.today('enrich_fields') = 0, 'yesterday''s cost is not counted today (it was before)');
  insert into pipeline.scholarship_ai_reviews(recheck) values ('{"state": "leased"}') returning id into v_id;
  update pipeline.scholarship_ai_reviews set recheck = '{"state": "done", "cost_usd": 0.75}' where id = v_id;
  update pipeline.scholarship_ai_reviews set recheck = recheck || '{"cost_usd": 1.0}' where id = v_id;   -- a second re-check adds 0.25
  perform fx.ok(fx.today('scholarship_ai') = 1.0, 'the re-check''s cost is counted in the scholarship lane (it was not before)');
  insert into pipeline.central_ai_queue(cost_usd) values (0.01); insert into pipeline.entry_matrix_runs(cost_usd) values (0.02);
  insert into pipeline.uni_adapter_drafts(cost_usd) values (0.03); insert into pipeline.scholarship_ai_extractions(cost_usd) values (0.04);
  insert into pipeline.field_enrich_items(cost_usd) values (0.06); insert into pipeline.fee_reader_queue(cost_usd) values (0.05);
  v_id := fx.match_item(); perform public.svc_coverage_ai_match_next(1);
  perform public.svc_coverage_ai_match_record(v_id, null, '{}', 'm', 0.07, null);
  perform fx.ok((select count(*) from security.ai_spend_today_v1() where spent > 0) = 7, 'every lane writes the ledger');
  perform fx.ok((select string_agg(use || '=' || spent, ' ' order by use) from security.ai_spend_today_v1())
                = 'adapter_builder=0.0300 central_ai=0.0100 course_match=0.0700 enrich_fields=0.0600 entry_matrix=0.0200 fee_ai=0.0500 scholarship_ai=1.0400', 'each lane''s spend');
  perform fx.ok((select count(*) from security.ai_spend_today_v1()) = 7, 'seven lanes listed, as before');
  raise notice 'PASS accounting: counted on the day recorded; the re-check counted; every lane';
end $t$;

-- E-8 ----------------------------------------------------------------------------------------------------------------------------------
do $t$
declare p text; v_p uuid := gen_random_uuid();
begin
  -- the month used up (vendor balance under the 2,000 reserve): refused on every path, recorded as month_limit, nothing spent
  perform fx.reset();
  insert into pipeline.vendor_credit_observations(provider_id, remaining_units) values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 2000);
  foreach p in array array['search', 'scrape', 'list_scrape', 'fc_read', 'sch_scrape', 'sch_map', 'central_map', 'site_verify', 'enrich_address', 'companion_read'] loop
    perform fx.ok(security.fc_budget_left_v1(p) = 0, format('%s: nothing left', p));
    perform fx.ok(not public.svc_fc_spend(1, p, v_p, 'https://uni.example/' || p), format('%s: spend refused', p));
  end loop;
  perform fx.ok((select sum(n) from pipeline.firecrawl_budget_refusals where reason = 'month_limit') = 10, 'every refusal recorded as month_limit');
  perform fx.ok(not exists (select 1 from pipeline.coverage_vendor_usage), 'nothing spent');
  perform fx.ok(security.fc_month_refusal_v1(1) like 'Firecrawl monthly limit: about 2000 credits left on the plan (vendor balance read %), 2000 kept in reserve', 'the reason');
  raise notice 'PASS month: every worker path refused at the limit (course search, reads, scholarships, central, site checks, other)';
end $t$;

do $t$
declare v_p uuid := gen_random_uuid(); v_err text; v_d uuid;
begin
  -- on demand: a manual enrichment plan run and the adapter builder's page captures
  perform fx.reset();
  insert into pipeline.vendor_credit_observations(provider_id, remaining_units) values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 2000);
  insert into pipeline.enrich_plan_runs(provider_id, mode, state) values (v_p, 'manual', 'running');
  perform fx.ok(not public.svc_fc_spend(1, 'scrape', v_p, 'https://uni.example/od'), 'on-demand: refused');
  perform fx.ok(exists (select 1 from pipeline.firecrawl_budget_refusals where reason = 'month_limit'), 'on-demand refusal recorded as month_limit');
  v_err := fx.raises(format($s$select public.admin_adapter_builder('start', '{"provider_id": "%s"}')$s$, v_p));
  perform fx.ok(v_err like 'Firecrawl monthly limit:%. Nothing was spent.', 'adapter capture (start): refused');
  perform fx.ok(not exists (select 1 from pipeline.uni_adapter_drafts) and not exists (select 1 from fx.fired), 'no draft, nothing sent');
  insert into pipeline.uni_adapter_drafts(provider_id) values (v_p) returning id into v_d;
  v_err := fx.raises(format($s$select public.admin_adapter_builder('add_sample', '{"draft_id": "%s", "sample": {"url": "https://uni.example/c2"}}')$s$, v_d));
  perform fx.ok(v_err like 'Firecrawl monthly limit:%', 'adapter capture (add sample): refused');
  perform fx.ok((select jsonb_array_length(samples) from pipeline.uni_adapter_drafts where id = v_d) = 0 and not exists (select 1 from fx.fired), 'the sample is not added, nothing sent');
  -- with credit left, on demand and captures run as before (the on-demand allowance still applies)
  update pipeline.vendor_credit_observations set remaining_units = 300000;
  perform fx.ok(public.svc_fc_spend(1, 'scrape', v_p, 'https://uni.example/od2'), 'on-demand under the limit: spent');
  perform fx.ok((select on_demand_run from pipeline.coverage_vendor_usage) is not null, 'from the on-demand allowance');
  perform fx.ok(fx.raises(format($s$select public.admin_adapter_builder('start', '{"provider_id": "%s"}')$s$, v_p)) is null, 'capture under the limit: started');
  raise notice 'PASS on demand: plan runs and adapter captures refused at the monthly limit, run as before under it';
end $t$;

do $t$
declare v_p uuid := gen_random_uuid();
begin
  -- the daily allowance is unchanged: with the month fine, the day's rules decide as before
  perform fx.reset();
  insert into pipeline.vendor_credit_observations(provider_id, remaining_units) values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 300000);
  perform fx.ok(security.fc_budget_left_v1('scrape') = 5000, 'reads share 5,000 left');
  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, at) values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 5000, 'scrape', greatest(now() - interval '1 minute', security.fc_day_start_v1()));
  perform fx.ok(not public.svc_fc_spend(1, 'scrape', v_p, 'https://uni.example/x'), 'reads share used: refused');
  perform fx.ok((select reason from pipeline.firecrawl_budget_refusals) = 'share', 'refused by the share, as before (not month_limit)');
  perform fx.ok(security.fc_budget_left_v1('search') = 13000, 'other shares untouched');
  raise notice 'PASS daily allowance unchanged: shares and totals decide as before while the month has credit';
end $t$;

do $t$
declare v_p uuid := gen_random_uuid(); v_m timestamptz := date_trunc('month', now());
begin
  -- month roll-over (no vendor balance in the last 2 hours: the counted month, UTC calendar month)
  perform fx.reset();
  insert into pipeline.vendor_credit_observations(provider_id, remaining_units, observed_at) values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 1, now() - interval '3 hours');
  insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, at) values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 499000, 'scrape', v_m - interval '1 second');
  perform fx.ok(security.fc_month_refusal_v1(1) is null, 'last month''s use (one second before the 1st, 00:00 UTC) does not count: allowed');
  perform fx.ok(public.svc_fc_spend(1, 'search', v_p, 'https://uni.example/new-month'), 'a spend in the new month is accepted');
  update pipeline.coverage_vendor_usage set at = v_m where units = 499000;   -- the same use on the 1st, 00:00 UTC
  perform fx.ok(security.fc_month_refusal_v1(1) like 'Firecrawl monthly limit: % credits left this month (UTC, counted; no vendor balance in the last 2 hours), 2000 kept in reserve', 'this month''s use counts: refused');
  perform fx.ok(not public.svc_fc_spend(1, 'search', v_p, 'https://uni.example/x'), 'refused');
  perform fx.ok((select (security.layer2_provider_budget_status('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 1)->>'period_start')::timestamptz) = v_m, 'period_start is the 1st, 00:00 UTC');
  raise notice 'PASS month roll-over: the counted month starts on the 1st at 00:00 UTC; a fresh vendor balance overrides it';
end $t$;

do $t$
declare v_case record; v_a boolean; v_b boolean; n int := 0;
begin
  -- the month rule here gives the same answer as security.layer2_provider_budget_status in every case (fresh and stale balance)
  for v_case in select * from (values (1999::numeric, 0, 0, 1), (2001, 0, 0, 1), (2001, 1, 0, 1), (5000, 2999, 0, 1), (5000, 2998, 1, 1), (300000, 0, 0, 5),
                                      (2004, 0, 0, 5), (2005, 0, 0, 5)) c(rem, used_since, attempts_since, units) loop
    foreach v_b in array array[true, false] loop   -- fresh vendor balance, or none in the last 2 hours
      perform fx.reset();
      insert into pipeline.vendor_credit_observations(provider_id, remaining_units, observed_at)
        values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', v_case.rem, now() - case when v_b then interval '10 minutes' else interval '3 hours' end);
      insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, at)
        select '6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 1, 'scrape', now() - interval '1 minute' from generate_series(1, v_case.used_since);
      insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, at)
        select '6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 498000 - v_case.rem, 'scrape', date_trunc('month', now()) where v_case.rem < 498000;
      insert into pipeline.layer2_provider_attempts(acquisition_provider_id, started_at) select '6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', now() - interval '1 minute' from generate_series(1, v_case.attempts_since);
      v_a := security.fc_month_refusal_v1(v_case.units) is null;
      perform fx.ok(v_a = (security.layer2_provider_budget_status('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', v_case.units)->>'allowed')::boolean,
                    format('same answer as layer2_provider_budget_status: %s', v_case));
      n := n + 1;
    end loop;
  end loop;
  perform fx.ok(n = 16, '16 cases');
  raise notice 'PASS the month rule equals layer2_provider_budget_status in 16 cases (fresh and stale vendor balance)';
end $t$;

-- E-9 ----------------------------------------------------------------------------------------------------------------------------------
create or replace function fx.jobs(p_health_age interval, p_alerts_age interval, p_health_status text default 'succeeded', p_alerts_active boolean default true) returns void language plpgsql as $f$
declare h bigint; a bigint; o bigint;
begin
  truncate cron.job_run_details, cron.job, pipeline.platform_alerts;
  insert into cron.job(jobname, schedule, command, active) values ('platform-health', '8-59/10 * * * *', 'select 1', true) returning jobid into h;
  insert into cron.job(jobname, schedule, command, active) values ('platform-alerts', '*/10 * * * *', 'select 1', p_alerts_active) returning jobid into a;
  insert into cron.job(jobname, schedule, command, active) values ('other', '* * * * *', 'select 1', true) returning jobid into o;
  insert into cron.job_run_details(jobid, status, start_time) values (h, p_health_status, now() - p_health_age), (a, 'succeeded', now() - p_alerts_age);
  insert into cron.job_run_details(jobid, status, start_time) select o, 'succeeded', now() - make_interval(secs => g) from generate_series(1, 50) g;  -- newer runs of other jobs
end $f$;

do $t$
declare w jsonb;
begin
  perform fx.reset(); perform fx.jobs('5 minutes', '7 minutes');
  w := security.platform_watchdog_v1();
  perform fx.ok((w->>'ok')::boolean and jsonb_array_length(w->'problems') = 0, 'healthy: ok');
  perform fx.jobs('45 minutes', '7 minutes'); w := security.platform_watchdog_v1();
  perform fx.ok(not (w->>'ok')::boolean and w->'problems'->>0 like 'platform-health: no run started in the last 30 minutes (last: %)', 'health stale: fails');
  perform fx.jobs('5 minutes', '7 minutes', 'failed'); w := security.platform_watchdog_v1();
  perform fx.ok(w->'problems'->>0 = 'platform-health: the last run failed', 'health failed: fails');
  perform fx.jobs('5 minutes', '7 minutes', 'succeeded', false); w := security.platform_watchdog_v1();
  perform fx.ok(w->'problems'->>0 = 'platform-alerts: the job is switched off', 'alerts job off: fails');
  perform fx.jobs('5 minutes', '7 minutes'); delete from cron.job where jobname = 'platform-alerts'; w := security.platform_watchdog_v1();
  perform fx.ok(w->'problems'->>0 = 'platform-alerts: the job is not scheduled', 'alerts job missing: fails');
  -- the alert-collecting step: an alert waiting over alerts.collect_within_minutes (120)
  perform fx.jobs('5 minutes', '7 minutes');
  insert into pipeline.platform_alerts(kind, severity, title, status, created_at) values ('issue', 'critical', 'x', 'pending', now() - interval '3 hours');
  w := security.platform_watchdog_v1();
  perform fx.ok(w->'problems'->>0 like 'alerts are not being collected: 1 waiting since % (longer than 120 minutes)', 'alerts not collected: fails');
  update pipeline.platform_alerts set created_at = now() - interval '30 minutes'; w := security.platform_watchdog_v1();
  perform fx.ok((w->>'ok')::boolean, 'an alert waiting 30 minutes: ok');
  update pipeline.platform_alerts set created_at = now() - interval '3 hours';
  update pipeline.platform_toolset_settings set value = 'false' where key = 'alerts.delivery_enabled'; w := security.platform_watchdog_v1();
  perform fx.ok((w->>'ok')::boolean, 'delivery switched off on purpose: not a failure');
  update pipeline.platform_toolset_settings set value = 'true' where key = 'alerts.delivery_enabled';
  -- the stale window is a setting
  insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'alerts.watchdog_stale_minutes', '60')
    on conflict (toolset_key, key) do update set value = excluded.value;
  delete from pipeline.platform_alerts; perform fx.jobs('45 minutes', '7 minutes');
  perform fx.ok((security.platform_watchdog_v1()->>'ok')::boolean, 'stale window 60: a 45-minute-old run is ok');
  update pipeline.platform_toolset_settings set value = '30' where key = 'alerts.watchdog_stale_minutes';
  -- a run beyond the scan window is not found (bounded read)
  update pipeline.platform_toolset_settings set value = '20' where key = 'alerts.watchdog_scan_runs';
  perform fx.jobs('5 minutes', '7 minutes');
  insert into cron.job_run_details(jobid, status, start_time) select (select jobid from cron.job where jobname = 'other'), 'succeeded', now() from generate_series(1, 25);
  w := security.platform_watchdog_v1();
  perform fx.ok(w->'problems'->>0 like 'platform-health: no run started in the last 30 minutes (last: none found)', 'the read stays within the newest runs');
  update pipeline.platform_toolset_settings set value = '20000' where key = 'alerts.watchdog_scan_runs';
  raise notice 'PASS watchdog: healthy ok; stale, failed, switched off or missing jobs and uncollected alerts fail; windows are settings';
end $t$;

-- read-only: the read-only role runs the watchdog in a read-only transaction, and nothing else
grant usage on schema security, pipeline, cron to supabase_read_only_user;
grant select on all tables in schema pipeline, cron to supabase_read_only_user;   -- as live: pg_read_all_data
begin;
set transaction read only;
set local role supabase_read_only_user;
do $t$ begin perform fx.ok(jsonb_typeof(security.platform_watchdog_v1()) = 'object', 'the read-only role runs it in a read-only transaction'); end $t$;
do $t$ declare v_err text;
begin
  begin perform security.ai_use_refusal_v1('fee_ai'); v_err := null; exception when others then v_err := sqlerrm; end;
  perform fx.ok(v_err like 'permission denied for function ai_use_refusal_v1', 'the read-only role runs nothing else (' || coalesce(v_err, 'allowed') || ')');
end $t$;
commit;
do $t$ begin raise notice 'PASS watchdog read-only: runs as the read-only role in a read-only transaction; nothing else is granted'; end $t$;
