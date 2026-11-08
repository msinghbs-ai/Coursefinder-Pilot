-- CF-247 Firecrawl priority floor: scenarios on the live definitions as edited by migration 20261108060000. Every check raises on failure (psql stops) and prints "PASS <name>".
-- Provider ids and urls are fixtures. svc_fc_spend is called as the postgres owner (the function's own rule for a non-service caller). Nothing fetches, searches or reads.
\set ON_ERROR_STOP on

-- S1 the setting is registered as a governed control (G2) ------------------------------------------------------------------------------------------
do $$ declare s pipeline.platform_toolset_settings%rowtype; begin
  select * into s from pipeline.platform_toolset_settings where toolset_key = 'firecrawl' and key = 'priority_floor_course_search';
  perform fx.ok('S1 the setting exists with default 1500', s.value = '1500'::jsonb);
  perform fx.ok('S1 label, help, kind, range, unit, used_by and reason are all given', s.label <> '' and s.help <> '' and s.kind = 'number' and s.min_value = 0 and s.max_value = 100000
                and s.unit = 'credits' and s.used_by like '%fc_budget_left_v1%' and s.used_by like '%svc_fc_spend%' and s.used_by like '%lane_paid_hold_v1%' and s.reason like '%8 Nov 2026%'
                and s.section = 'Daily budget');
  perform fx.ok('S1 the migration did not touch any other setting (11 before + 1 new)', (select count(*) from pipeline.platform_toolset_settings) = 11);
  perform fx.ok('S1 the daily shares, total and billing config are as live',
                (select string_agg(key || '=' || (value #>> '{}'), ',' order by key) from pipeline.platform_toolset_settings where key like 'daily_%') =
                'daily_budget_on=true,daily_budget_total=25000,daily_share_central=2500,daily_share_course_search=13000,daily_share_other=1000,daily_share_reads=5000,daily_share_scholarships=3500'
                and (select billing_config from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl') =
                    '{"monthly_vendor_units_limit": 500000, "stop_at_vendor_units_remaining": 0, "no_silent_paid_fallback": true}'::jsonb);
end $$;

-- S2 the audit event, once; the helpers are not open to anon / authenticated --------------------------------------------------------------------------
do $$ begin
  perform fx.ok('S2 one audit event (firecrawl / priority_floor) names the migration and the before md5s',
                (select count(*) from pipeline.admin_control_events where area = 'firecrawl' and action = 'priority_floor') = 1
                and (select detail->'before_md5'->>'security.fc_budget_left_v1' from pipeline.admin_control_events where action = 'priority_floor') = 'e979d2e3d7319d845a5149e40abe6987'
                and (select detail->>'migration' from pipeline.admin_control_events where action = 'priority_floor') = '20261108060000');
  perform fx.ok('S2 the new helpers are closed to anon and authenticated',
                not has_function_privilege('anon', 'security.fc_vendor_estimate_v1()', 'execute') and not has_function_privilege('authenticated', 'security.fc_priority_room_v1()', 'execute'));
end $$;

-- S3 the estimate is the one fc_month_refusal_v1 uses (balance, use since, attempts since, reserve, spend size) ------------------------------------------
do $$ declare b numeric; stop numeric; u numeric; n int; unit numeric; spend numeric; est numeric; r text; checked int := 0; i int; begin
  foreach unit in array array[1, 2] loop
    update pipeline.layer2_acquisition_providers set request_template = jsonb_build_object('fixed_credit_units', unit) where provider_key = 'firecrawl';
    foreach b in array array[0, 5, 962, 1500, 5000] loop foreach stop in array array[0, 2000] loop foreach u in array array[0, 7] loop foreach n in array array[0, 3] loop
      perform fx.reset(b, interval '1 minute', stop);
      if u > 0 then perform fx.use(u, 'scrape'); end if;
      for i in 1 .. n loop
        insert into pipeline.layer2_provider_attempts(job_id, profile_version_id, acquisition_provider_id, attempt_no, status, started_at)
        values (gen_random_uuid(), gen_random_uuid(), '6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', i, 'done', now());
      end loop;
      est := security.fc_vendor_estimate_v1();
      if est is distinct from greatest(b - u - n * unit, 0) then raise exception 'FAIL S3 estimate % for balance % use % attempts % unit %', est, b, u, n, unit; end if;
      foreach spend in array array[1, 2, 120] loop
        r := security.fc_month_refusal_v1(spend);
        if (r is null) is distinct from (est - spend >= stop) then raise exception 'FAIL S3 refusal % vs estimate % spend % stop %', r, est, spend, stop; end if;
        if r is not null and position('about ' || est::text || ' credits left on the plan' in r) = 0 then raise exception 'FAIL S3 the refusal text does not carry the estimate: % (estimate %)', r, est; end if;
        checked := checked + 1;
      end loop;
    end loop; end loop; end loop; end loop;
  end loop;
  update pipeline.layer2_acquisition_providers set request_template = '{"fixed_credit_units": 1}' where provider_key = 'firecrawl';
  perform fx.ok('S3 the helper and fc_month_refusal_v1 agree in ' || checked || ' combinations (balance, reserve, use since, attempts since, credit unit, spend)', checked = 2 * 5 * 2 * 2 * 2 * 3);
end $$;

-- S4 freshness: a balance read 119 minutes ago counts, one read 121 minutes ago does not; no observation at all is null -----------------------------------
do $$ begin
  perform fx.reset(2000, interval '119 minutes'); perform fx.ok('S4 a balance read 119 minutes ago is fresh', security.fc_vendor_estimate_v1() = 2000);
  perform fx.reset(2000, interval '121 minutes'); perform fx.ok('S4 a balance read 121 minutes ago is not (estimate null, room null)', security.fc_vendor_estimate_v1() is null and security.fc_priority_room_v1() is null);
  perform fx.reset(2000); delete from pipeline.vendor_credit_observations; perform fx.ok('S4 no observation: null', security.fc_vendor_estimate_v1() is null);
end $$;

-- S5 the measured live case: 962 credits left, floor 1500 ----------------------------------------------------------------------------------------------------
do $$ begin
  perform fx.reset(962);
  perform fx.ok('S5 estimate 962 and room -538', security.fc_vendor_estimate_v1() = 962 and security.fc_priority_room_v1() = -538);
  perform fx.ok('S5 course search has nothing left (budget 0), so the picker (floor(left / 2)) picks 0', security.fc_budget_left_v1('course_link_search') = 0 and floor(security.fc_budget_left_v1('course_link_search') / 2) = 0);
  perform fx.ok('S5 the lane is told why, in the Platform Admin''s words',
                security.lane_paid_hold_v1('course_link_search') = 'budget_held: Firecrawl balance kept for higher-priority work (priority floor 1500 credits)');
  perform fx.ok('S5 a 2-credit search is refused', public.svc_fc_spend(2, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/courses/a') = false);
  perform fx.ok('S5 the refusal is recorded as priority_floor (by group and by university), not share or day_total',
                fx.refusals('course_search', 'priority_floor') = 1 and fx.refusals('course_search', 'share') = 0 and fx.refusals('course_search', 'day_total') = 0
                and (select n from pipeline.firecrawl_refusals_by_provider where provider_id = 'aaaaaaaa-0000-0000-0000-000000000001' and grp = 'course_search' and reason = 'priority_floor') = 1);
  perform public.svc_fc_spend(2, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/courses/b');
  perform fx.ok('S5 the count goes up, and no credit was recorded', fx.refusals('course_search', 'priority_floor') = 2 and (select count(*) from pipeline.coverage_vendor_usage) = 0);
end $$;

-- S6 the same balance: every other group is untouched and svc_fc_spend still allows AER entry-page work (central_map) -------------------------------------
do $$ begin
  perform fx.reset(962);
  perform fx.ok('S6 shares left at 962 credits: central 2500, reads 5000, scholarships 3500, other 1000 (unchanged)',
                security.fc_budget_left_v1('central_map') = 2500 and security.fc_budget_left_v1('central_scrape') = 2500 and security.fc_budget_left_v1('provider_facts_scrape') = 2500
                and security.fc_budget_left_v1('scrape') = 5000 and security.fc_budget_left_v1('fc_read') = 5000 and security.fc_budget_left_v1('adapter_builder') = 5000
                and security.fc_budget_left_v1('sch_scrape') = 3500 and security.fc_budget_left_v1('sch_map') = 3500
                and security.fc_budget_left_v1('map') = 1000 and security.fc_budget_left_v1('search') = 1000 and security.fc_budget_left_v1('fc_search') = 1000);
  perform fx.ok('S6 none of them is held on the lane', security.lane_paid_hold_v1('central_map') is null and security.lane_paid_hold_v1('scrape') is null
                and security.lane_paid_hold_v1('sch_scrape') is null and security.lane_paid_hold_v1('map') is null);
  perform fx.ok('S6 course search is held at the same moment', security.fc_budget_left_v1('course_link_search') = 0);
  perform fx.ok('S6 a central_map spend (entry-requirement page finding) is allowed', public.svc_fc_spend(1, 'central_map', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/') = true);
  perform fx.ok('S6 so are central_scrape, scrape, a scholarship read and a site map',
                public.svc_fc_spend(1, 'central_scrape', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/entry') and public.svc_fc_spend(1, 'scrape', null, 'https://uni.example/x')
                and public.svc_fc_spend(1, 'sch_scrape', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/s') and public.svc_fc_spend(1, 'map', null, 'https://uni.example/'));
  perform fx.ok('S6 five credits recorded; no priority_floor refusal; course search still held',
                (select sum(units) from pipeline.coverage_vendor_usage) = 5 and fx.refusals('course_search', 'priority_floor') = 0 and security.fc_budget_left_v1('course_link_search') = 0);
end $$;

-- S7 edge: room of a few credits is used credit by credit, never below the floor ----------------------------------------------------------------------------
do $$ begin
  perform fx.reset(1503);
  perform fx.ok('S7 room 3: budget 3, lane not held, a batch of floor(3 / 2) = 1 search', security.fc_budget_left_v1('course_link_search') = 3 and security.lane_paid_hold_v1('course_link_search') is null
                and floor(security.fc_budget_left_v1('course_link_search') / 2) = 1);
  perform fx.ok('S7 the 2-credit search is allowed', public.svc_fc_spend(2, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/c/1'));
  perform fx.ok('S7 room is now 1: budget 1, a batch of 0', security.fc_priority_room_v1() = 1 and security.fc_budget_left_v1('course_link_search') = 1 and floor(security.fc_budget_left_v1('course_link_search') / 2) = 0);
  perform fx.ok('S7 another 2-credit search is refused as priority_floor (the estimate would fall to 1499)', public.svc_fc_spend(2, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/c/2') = false
                and fx.refusals('course_search', 'priority_floor') = 1);
  perform fx.ok('S7 a 1-credit spend that lands exactly on the floor is allowed', public.svc_fc_spend(1, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/c/3'));
  perform fx.ok('S7 at the floor: room 0, budget 0, lane held with the floor text', security.fc_priority_room_v1() = 0 and security.fc_budget_left_v1('course_link_search') = 0
                and security.lane_paid_hold_v1('course_link_search') like 'budget_held: Firecrawl balance kept for higher-priority work (priority floor 1500 credits)');
  perform fx.ok('S7 the estimate never went below the floor', security.fc_vendor_estimate_v1() = 1500);
end $$;

-- S8 automatic recovery: the next balance reading (after a top-up) releases course search with no other step -----------------------------------------------
do $$ declare v_before int; begin
  perform fx.reset(962);
  perform fx.ok('S8 held at 962', security.lane_paid_hold_v1('course_link_search') is not null and public.svc_fc_spend(2, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/r/1') = false);
  v_before := (select count(*) from pipeline.admin_control_events);
  -- the 15-minute balance reader records a new reading after the top-up: the only thing that happens
  insert into pipeline.vendor_credit_observations(provider_id, remaining_units, plan_units, period_end, observed_at)
  values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 6000, 5000, now() + interval '24 days', now() - interval '10 seconds');
  perform fx.ok('S8 released: room 4500, budget 4500 (the share is 13000), lane not held, the picker may take 2250 searches',
                security.fc_priority_room_v1() = 4500 and security.fc_budget_left_v1('course_link_search') = 4500 and security.lane_paid_hold_v1('course_link_search') is null
                and floor(security.fc_budget_left_v1('course_link_search') / 2) = 2250);
  perform fx.ok('S8 and the search is allowed again', public.svc_fc_spend(2, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/r/2') = true);
  perform fx.ok('S8 and the room is used credit for credit (4498 left)', security.fc_budget_left_v1('course_link_search') = 4498);
  perform fx.ok('S8 no setting, switch or event was changed to release it', (select count(*) from pipeline.admin_control_events) = v_before
                and (select value from pipeline.platform_toolset_settings where key = 'priority_floor_course_search') = '1500'::jsonb);
  -- and it holds again when the balance falls back (a balance read after heavy use)
  insert into pipeline.vendor_credit_observations(provider_id, remaining_units, plan_units, period_end, observed_at)
  values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 1200, 5000, now() + interval '24 days', now() - interval '5 seconds');
  perform fx.ok('S8 held again below the floor', security.fc_budget_left_v1('course_link_search') = 0);
end $$;

-- S9 the share still applies on top, and a share that is used is reported as share when the floor is not what holds ----------------------------------------
do $$ begin
  perform fx.reset(50000); perform fx.use(13000, 'course_link_search');
  perform fx.ok('S9 plenty of balance, share used up: budget 0, reason share', security.fc_budget_left_v1('course_link_search') = 0
                and public.svc_fc_spend(2, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/q/1') = false and fx.refusals('course_search', 'share') = 1 and fx.refusals('course_search', 'priority_floor') = 0);
  perform fx.ok('S9 the lane text for a used share is the earlier one', security.lane_paid_hold_v1('course_link_search') = 'budget_held: no room left in today''s Firecrawl share for course_search');
  perform fx.reset(50000); perform fx.use(12990, 'course_link_search');
  perform fx.ok('S9 share left 10 and room 35000: budget is the smaller (10)', security.fc_budget_left_v1('course_link_search') = 10);
  -- scholarship share used up at a low balance: still 'share' (the floor is course search only)
  perform fx.reset(5000); perform fx.use(3500, 'sch_scrape');  -- estimate 1500: at the floor, but the floor is for course search only
  perform fx.ok('S9 a used scholarship share with the estimate at the floor is "share"', public.svc_fc_spend(1, 'sch_scrape', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/s2') = false
                and fx.refusals('scholarships', 'share') = 1 and fx.refusals('scholarships', 'priority_floor') = 0);
  -- day_total comes first
  perform fx.reset(962); perform fx.setting('daily_budget_total', '0'::jsonb);
  perform fx.ok('S9 with the day total reached the reason stays day_total', public.svc_fc_spend(2, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/d') = false
                and fx.refusals('course_search', 'day_total') = 1 and fx.refusals('course_search', 'priority_floor') = 0);
  perform fx.setting('daily_budget_total', '25000'::jsonb);
end $$;

-- S10 switches that make the floor not apply: floor 0, setting missing, no fresh balance, daily budget off; earlier returns keep priority -------------------
do $$ begin
  perform fx.reset(962); perform fx.floor(0);
  perform fx.ok('S10 floor 0: room null, course search has its full share, not held, spend allowed, no refusal',
                security.fc_priority_room_v1() is null and security.fc_budget_left_v1('course_link_search') = 13000 and security.lane_paid_hold_v1('course_link_search') is null
                and public.svc_fc_spend(2, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/z/1') and fx.refusals('course_search', 'priority_floor') = 0);
  perform fx.floor(1500);
  delete from pipeline.platform_toolset_settings where key = 'priority_floor_course_search';
  perform fx.ok('S10 setting row missing: floor off', security.fc_priority_room_v1() is null and security.fc_budget_left_v1('course_link_search') = 12998);
  insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
  select 'firecrawl', 'priority_floor_course_search', label, help, kind, '1500'::jsonb, min_value, max_value, unit, sort, section, used_by, reason from pipeline.platform_toolset_settings where key = 'daily_share_other';
  perform fx.reset(962, interval '3 hours');
  perform fx.ok('S10 no fresh balance: unchanged (full share, not held, spend allowed)', security.fc_budget_left_v1('course_link_search') = 13000 and security.lane_paid_hold_v1('course_link_search') is null
                and public.svc_fc_spend(2, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/z/2'));
  perform fx.reset(962); perform fx.setting('daily_budget_on', 'false'::jsonb);
  perform fx.ok('S10 daily budget off (observe only): 1,000,000 as before, the floor does not apply', security.fc_budget_left_v1('course_link_search') = 1000000
                and public.svc_fc_spend(2, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000001', 'https://uni.example/z/3'));
  perform fx.setting('daily_budget_on', 'true'::jsonb);
  -- the monthly reserve is decided first, in every group, with its own text
  perform fx.reset(962, interval '1 minute', 2000);
  perform fx.ok('S10 the monthly reserve still comes first: 0 for every group, month text, month_limit', security.fc_budget_left_v1('course_link_search') = 0 and security.fc_budget_left_v1('central_map') = 0
                and security.lane_paid_hold_v1('course_link_search') like 'budget_held: Firecrawl monthly limit%' and public.svc_fc_spend(2, 'course_link_search', null, 'https://uni.example/m') = false
                and fx.refusals('course_search', 'month_limit') = 1 and fx.refusals('course_search', 'priority_floor') = 0);
end $$;

-- S11 a person's Run now (the on-demand allowance) is decided before the daily rules, as before: not held by the floor -------------------------------------
do $$ begin
  perform fx.reset(962);
  insert into pipeline.enrich_plan_runs(provider_id, mode, state, steps, requested_by, reason) values ('aaaaaaaa-0000-0000-0000-000000000002', 'manual', 'running', '[]', gen_random_uuid(), 'fixture');
  perform fx.ok('S11 on-demand spend is allowed from its own allowance (unchanged; the monthly limit still applies)',
                public.svc_fc_spend(2, 'course_link_search', 'aaaaaaaa-0000-0000-0000-000000000002', 'https://uni.example/od') = true);
  perform fx.ok('S11 it was recorded as on-demand and no priority_floor refusal was counted',
                (select on_demand_run from pipeline.coverage_vendor_usage order by id desc limit 1) is not null and fx.refusals('course_search', 'priority_floor') = 0);
end $$;

-- S12 the queue watch: a course-search queue held by the floor is a budget wait ("waiting"), not a code fault and not "out of toolset" ------------------------
do $$ begin
  perform fx.reset(962);
  perform fx.ok('S12 firecrawl:course_search is waiting while the floor holds it', security.queue_watch_tool_state_v1('firecrawl:course_search') = 'waiting');
  perform fx.ok('S12 the other Firecrawl tools of the queue watch are ok at the same balance', security.queue_watch_tool_state_v1('firecrawl:central') = 'ok' and security.queue_watch_tool_state_v1('firecrawl:reads') = 'ok'
                and security.queue_watch_tool_state_v1('firecrawl:scholarships') = 'ok' and security.queue_watch_tool_state_v1('firecrawl:other') = 'ok');
  insert into pipeline.vendor_credit_observations(provider_id, remaining_units, plan_units, period_end, observed_at)
  values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 6000, 5000, now() + interval '24 days', now() - interval '10 seconds');
  perform fx.ok('S12 and ok again after the balance recovers', security.queue_watch_tool_state_v1('firecrawl:course_search') = 'ok');
end $$;

-- S13 the oracle: against the live fc_budget_left_v1 (loaded as fx_live), for every purpose in every group ------------------------------------------------
do $$ declare b numeric; fl numeric; p text; grp text; v_old numeric; v_new numeric; v_want numeric; est numeric; sincu numeric; checked int := 0; held int := 0; same_cs int := 0; st int;
  purposes text[] := array['course_link_search', 'scrape', 'fc_read', 'fc_probe', 'site_hint', 'adapter_builder', 'list_scrape', 'fcx_course_list', 'central_map', 'central_scrape',
                           'provider_facts_scrape', 'provider_facts_search', 'sch_scrape', 'sch_map', 'sch_search', 'map', 'search', 'fc_search', 'companion_read', 'site_verify', 'unknown_purpose'];
begin
  foreach fl in array array[0, 1500, 100000] loop foreach b in array array[0, 8, 962, 1499, 1500, 1501, 1502, 1600, 6000, 100000] loop foreach st in array array[0, 1] loop
    perform fx.reset(b); perform fx.floor(fl);
    -- day use before the reading (counts in the shares, not in the estimate) and, in state 1, use after it
    perform fx.use(200, 'course_link_search', now() - interval '90 minutes'); perform fx.use(100, 'scrape', now() - interval '90 minutes'); perform fx.use(50, 'central_map', now() - interval '90 minutes');
    if st = 1 then perform fx.use(40, 'course_link_search'); perform fx.use(10, 'scrape'); end if;
    sincu := case when st = 1 then 50 else 0 end;
    est := greatest(b - sincu, 0);
    foreach p in array purposes loop
      grp := security.fc_purpose_group_v1(p);
      v_old := fx_live.fc_budget_left_v1(p); v_new := security.fc_budget_left_v1(p);
      -- the live answer, except for course search while the floor applies: the room above the floor when the live answer is above it (0 when under one credit of room)
      v_want := case when grp <> 'course_search' or fl <= 0 or v_old = 0 then v_old
                     when est - fl < 1 then 0 else least(v_old, est - fl) end;
      if v_new is distinct from v_want then raise exception 'FAIL S13 % balance % floor % state %: live % new % expected %', p, b, fl, st, v_old, v_new, v_want; end if;
      if grp <> 'course_search' and v_new is distinct from v_old then raise exception 'FAIL S13 group % changed', grp; end if;
      if grp = 'course_search' and v_new is distinct from v_old then held := held + 1; end if;
      if grp = 'course_search' and v_new = v_old then same_cs := same_cs + 1; end if;
      checked := checked + 1;
    end loop;
  end loop; end loop; end loop;
  perform fx.floor(1500);
  perform fx.ok('S13 ' || checked || ' answers agree with the live function except where the floor holds course search (' || held || ' held, ' || same_cs || ' same)', checked = 3 * 10 * 2 * 21 and held > 0 and same_cs > 0);
end $$;

-- S14 the purpose groups (read from the live function): what falls in every group ------------------------------------------------------------------------------
do $$ begin
  perform fx.ok('S14 course_link_search is the only purpose in the course_search group',
                (select string_agg(p, ',' order by p) from unnest(array['course_link_search', 'scrape', 'central_map', 'sch_map', 'map', 'search', 'companion_read', 'list_scrape', 'provider_facts_scrape', 'fcx_x']) p
                  where security.fc_purpose_group_v1(p) = 'course_search') = 'course_link_search');
  perform fx.ok('S14 the AER pages (central_map, central_scrape, provider_facts_*) are in central; companion_read, map, search, fc_search, site_verify, directory_scrape, enrich_address, test_* are in other',
                security.fc_purpose_group_v1('central_map') = 'central' and security.fc_purpose_group_v1('central_scrape') = 'central' and security.fc_purpose_group_v1('provider_facts_scrape') = 'central'
                and security.fc_purpose_group_v1('companion_read') = 'other' and security.fc_purpose_group_v1('map') = 'other' and security.fc_purpose_group_v1('search') = 'other'
                and security.fc_purpose_group_v1('fc_search') = 'other' and security.fc_purpose_group_v1('site_verify') = 'other'
                and security.fc_purpose_group_v1('directory_scrape') = 'other' and security.fc_purpose_group_v1('enrich_address') = 'other' and security.fc_purpose_group_v1('test_map') = 'other');
end $$;
