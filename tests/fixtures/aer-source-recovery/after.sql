\set ON_ERROR_STOP on
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
do $$ declare t jsonb; n int; r record; begin
  -- the parked holds
  perform pg_temp.ok((select count(*) from security.aer_parked_items_v1()) = 5, 'parked holds: the 5 pending parked items; a retried transient hold, a deferred recovery and an already decided item are not parked');
  perform pg_temp.ok((select count(distinct failure_class) from security.aer_parked_items_v1()) = 4 and (select bool_and(reason is not null and next_action is not null) from security.aer_parked_items_v1()), 'parked holds: each carries the lane''s exact reason and next action');
  -- the capacity
  t := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok(not (t->>'back_pressure')::boolean and (t->>'layer4_waiting')::int = 12 and (t->>'parked_not_counted')::int = 5, 'capacity: 12 pending, 5 parked: 7 counted against the limit of 10, so reading is no longer stopped (raw count still shown)');
  perform pg_temp.ok((t->>'course_reads')::int = 3 and (t->>'layer4_max')::int = 10, 'capacity: the three courses with a confidently matched stored page are the ones read; the limit is the same 10');
  t := security.aer_schedule_tick_v1();
  select count(*) into n from pipeline.enrich_reads_log;
  perform pg_temp.ok(n = 3 and (t->>'course_reads')::int = 3, 'capacity: a real run asks for the three reads (one per course) and nothing else');
  perform pg_temp.ok((select (detail->>'parked_not_counted')::int = 5 and back_pressure = false from pipeline.aer_schedule_runs order by id desc limit 1), 'capacity: the run record carries parked_not_counted');
  -- the limit still holds: with only one parked, 11 counted against 10 stops the reading
  delete from pipeline.work_items where entity <> '40000000-0000-0000-0000-000000000001' and failure_class <> 'aer_reread_eligible' and failure_class <> 'transient';
  t := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok((t->>'back_pressure')::boolean and (t->>'course_reads')::int = 0 and (t->>'parked_not_counted')::int = 1, 'capacity: with 1 parked the other 11 still reach the limit and stop the reading (the limit is kept)');
end $$;
-- a recorded run while only one hold is parked (a separate transaction, so its time differs from the first run)
select pg_sleep(0.05);
select (security.aer_schedule_tick_v1()->>'back_pressure')::boolean as recorded_back_pressure;
do $$ declare t jsonb; n int; r record; begin
  -- with the fair count on, the count is the fair one (stub room 0), the parked count is not used
  insert into pipeline.work_items(lane, entity, work_kind, provider_id, stage, failure_class, unresolved_blocker)
    select 'aer_technical', ('40000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0')), 'l4_item', '10000000-0000-0000-0000-000000000001', 'parked', case when g <= 3 then 'duplicate' else 'aer_human_input' end, '{"action":"park","reason":"r","next_action":"a"}' from generate_series(2, 6) g;
  update pipeline.platform_toolset_settings set value = '1' where key = 'wc.aer_fair_on';
  t := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok((t->>'back_pressure')::boolean and (t->'fair')::boolean, 'fair mode: the fair count decides as before');
  update pipeline.platform_toolset_settings set value = '0' where key = 'wc.aer_fair_on';
  -- the routes
  for r in select * from security.aer_no_source_route_v1() order by provider_id loop null; end loop;
  perform pg_temp.ok((select count(*) from security.aer_no_source_route_v1()) = 8, 'routes: every eligible provider with no source has one route (the provider with a source has none)');
  perform pg_temp.ok((select route from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000001') = 'course_pages_waiting' and
                     (select courses_waiting from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000001') <= 3, 'routes: stored and confidently matched course pages -> course_pages_waiting');
  perform pg_temp.ok((select route from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000002') = 'source_page_stored' and
                     (select best_url from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000002') like '%entry-requirements-by-country' and
                     (select not parked from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000002'), 'routes: a stored page on the provider''s own host (www ignored) -> source_page_stored, not parked');
  perform pg_temp.ok((select route from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000003') = 'course_pages_unconfirmed' and
                     (select parked from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000003'), 'routes: pages matched by title only -> course_pages_unconfirmed, parked with the decision named');
  perform pg_temp.ok((select route from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000004') = 'nothing_stored' and
                     (select parked and next_action like 'Parked.%' from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000004'), 'routes: nothing stored -> nothing_stored, parked with its next action');
  perform pg_temp.ok((select route from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000005') = 'weak_page_only', 'routes: a general entry-requirements page under the suggestion score -> weak_page_only');
  perform pg_temp.ok((select count(*) from security.aer_no_source_route_v1() where route = 'source_page_host_shared') = 1 and
                     (select route from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000007') = 'nothing_stored', 'routes: a page on a website two providers use is held for identity; the provider with no page of its own is nothing_stored');
  perform pg_temp.ok((select route from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000009') = 'nothing_stored', 'routes: a page on another website is never used');
  update pipeline.platform_toolset_settings set value = '3' where key = 'central.min_suggest_score';
  perform pg_temp.ok((select route from security.aer_no_source_route_v1() where provider_id = '10000000-0000-0000-0000-000000000005') = 'weak_page_only', 'routes: the suggestion score is the setting (floor 3): 2.1 stays under it');
  update pipeline.platform_toolset_settings set value = '4' where key = 'central.min_suggest_score';
  -- the finding
  perform pg_temp.ok((select count(*) from security.aer_current_findings_v1() where root_cause = 'no_source') = 8, 'findings: still one no_source finding per provider with no source');
  perform pg_temp.ok((select evidence->>'route' from security.aer_current_findings_v1() where root_cause = 'no_source' and provider_id = '10000000-0000-0000-0000-000000000002') = 'source_page_stored'
                     and (select evidence ? 'country' and evidence ? 'next_action' and evidence ? 'reason' from security.aer_current_findings_v1() where root_cause = 'no_source' and provider_id = '10000000-0000-0000-0000-000000000002'), 'findings: the evidence names the route, reason and next action and keeps the country');
  perform pg_temp.ok((select fingerprint from security.aer_current_findings_v1() where root_cause = 'no_source' and provider_id = '10000000-0000-0000-0000-000000000004') = security.aer_fingerprint_v1('10000000-0000-0000-0000-000000000004', null, 'provider', null, null, 'no_source'), 'findings: fingerprints are made as before (provider, no source, no_source)');
end $$;
-- Data Delivery
insert into pipeline.aer_gap_findings(fingerprint, root_cause, provider_id, evidence) select fingerprint, root_cause, provider_id, evidence from security.aer_current_findings_v1() where root_cause = 'no_source';
insert into pipeline.aer_provider_coverage(provider_id, country, disposition, sources, sources_read, matrix_active, course_req_active, course_req_proposed) select e.provider_id, e.country, 'not_discovered', case when e.provider_id = '10000000-0000-0000-0000-000000000008' then 1 else 0 end, 0, 0, case when e.provider_id = '10000000-0000-0000-0000-000000000001' then 5 else 0 end, 0 from security.aer_eligible_v1() e;
do $$ declare a jsonb; before_c bigint; begin
  select (select count(*) from pipeline.aer_gap_findings) + (select count(*) from pipeline.work_items) + (select count(*) from pipeline.aer_schedule_runs) + (select count(*) from pipeline.enrich_reads_log) into before_c;
  a := security.data_delivery_aer_v1();
  perform pg_temp.ok((a->>'known')::boolean and (a->'coverage'->>'eligible')::int = 9 and (a->'coverage'->>'with_source')::int = 1 and (a->'coverage'->>'with_active_rows')::int = 1 and (a->'coverage'->>'active_course_rows')::int = 5, 'Data Delivery: eligible providers, providers with a source and with active rows, active rows');
  perform pg_temp.ok((select count(*) from jsonb_array_elements(a->'gaps') g where g->>'route' in ('source_page_stored', 'course_pages_waiting', 'nothing_stored', 'course_pages_unconfirmed', 'weak_page_only', 'source_page_host_shared')) = 6
                     and (select sum((g->>'providers')::int) from jsonb_array_elements(a->'gaps') g) = 8 and (select bool_and(g->>'next_action' is not null) from jsonb_array_elements(a->'gaps') g), 'Data Delivery: the remaining gaps by route add up to the eight providers with no source, each with its next action');
  perform pg_temp.ok((a->'parked'->>'items')::int = 6 and jsonb_array_length(a->'parked'->'by_rule') = 3, 'Data Delivery: parked holds by rule with the exact reason (' || (a->'parked'->>'items') || ' items now)');
  perform pg_temp.ok(jsonb_array_length(a->'jobs') = 4 and (select bool_and(case when (j->>'active')::boolean then j->>'next_run' is not null else j->>'next_run' is null end) from jsonb_array_elements(a->'jobs') j), 'Data Delivery: last and next run: each AER job, its schedule and its next run (none when paused)');
  perform pg_temp.ok((a->'sources'->'stored_find'->>'switch_on')::boolean is false and (a->'sources'->>'total')::int = 1, 'Data Delivery: sources recovered (stored-link step off, none attached) and sources by status');
  perform pg_temp.ok(exists (select 1 from jsonb_array_elements_text(a->'blockers') b where b like 'Layer 4 is full for entry requirements: 12 items waiting against the limit of 10%') and
                     exists (select 1 from jsonb_array_elements_text(a->'blockers') b where b like '1 providers have a stored entry page that waits for the switch%'), 'Data Delivery: the active blockers are named (Layer 4 full, stored-link switch off)');
  perform pg_temp.ok((select count(*) from pipeline.aer_gap_findings) + (select count(*) from pipeline.work_items) + (select count(*) from pipeline.aer_schedule_runs) + (select count(*) from pipeline.enrich_reads_log) = before_c, 'Data Delivery: reading it writes nothing');
  -- no run recorded yet: still a full answer
  delete from pipeline.aer_schedule_runs;
  a := security.data_delivery_aer_v1();
  perform pg_temp.ok((a->>'known')::boolean and a->'last_run' = '{}'::jsonb, 'Data Delivery: with no run on record the answer is still known, with no last run');
  alter table pipeline.aer_gap_findings rename to aer_gap_findings_x;
  a := security.data_delivery_aer_v1();
  alter table pipeline.aer_gap_findings_x rename to aer_gap_findings;
  perform pg_temp.ok(not (a->>'known')::boolean and a->>'reason' is not null, 'Data Delivery: a count that cannot be made returns known false with the error, never a zero');
end $$;
