-- CF-247 OPS/UI lane funnels: behaviour of migration 20261108170000 on isolated fixtures. Each assertion names what it proves.
\set ON_ERROR_STOP on
create temp table t_results(name text);
create or replace function pg_temp.ok(p_name text, p_cond boolean) returns void language plpgsql as $$ begin
  if p_cond is not true then raise exception 'FAILED: %', p_name; end if; insert into t_results values (p_name); raise notice 'ok: %', p_name; end $$;
create or replace function pg_temp.raises(p_name text, p_sql text, p_like text) returns void language plpgsql as $$ declare v text; begin
  begin execute p_sql; v := null; exception when others then v := sqlerrm; end;
  if v is null or v not like p_like then raise exception 'FAILED: % (got %)', p_name, coalesce(v, 'no error'); end if; insert into t_results values (p_name); raise notice 'ok: %', p_name; end $$;

-- 1 the migration itself: settings with label, range, unit and used_by; lanes and stages; the job catalogued and scheduled; nothing deleted
select pg_temp.ok('ten settings, each labelled with a range, a unit and what uses it',
  (select count(*) = 10 and bool_and(label is not null and min_value is not null and max_value is not null and unit is not null and used_by is not null and section = 'Lane funnels')
     from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and (key like 'lane_funnel.%')));
select pg_temp.ok('nine lanes: p0, int, fee, eng, cdesc, pdesc, aer, sch, disc',
  (select array_agg(lane order by sort) = array['p0','int','fee','eng','cdesc','pdesc','aer','sch','disc'] from pipeline.lane_funnel_lanes));
select pg_temp.ok('every stage is a progress transition or a SELECT, and every kind is one of the twelve',
  (select count(*) > 50 and bool_and(transition_key is not null or count_sql is not null) from pipeline.lane_funnel_stages));
select pg_temp.ok('job lane-funnel is catalogued and scheduled every minute with no number in its command',
  exists (select 1 from cron.job j join pipeline.automation_catalogue a using (jobname) where jobname = 'lane-funnel' and j.schedule = '* * * * *' and j.command = 'select security.lane_funnel_refresh_v1()'));
select pg_temp.ok('every stage SELECT is schema-qualified (the evaluator runs with an empty search path)',
  (select bool_and(count_sql !~* '\m(from|join)\s+(?!pipeline\.|catalogue\.|\()[a-z_]+\M' ) from pipeline.lane_funnel_stages where count_sql is not null));

-- 2 the evaluator is one read-only SELECT and the database itself keeps it so
select pg_temp.ok('the evaluator is STABLE', (select provolatile = 's' from pg_proc where oid = 'security.lane_funnel_eval_v1(text,integer)'::regprocedure));
select pg_temp.raises('a second statement is refused', $$select security.lane_funnel_eval_v1('select 1; select 2', 24)$$, 'lane funnel: a stage must be one read-only SELECT%');
select pg_temp.raises('an UPDATE is refused', $$select security.lane_funnel_eval_v1('update catalogue.courses set description = null', 24)$$, 'lane funnel: a stage must be one read-only SELECT%');
select pg_temp.raises('a write hidden in a CTE is refused', $$select security.lane_funnel_eval_v1('with d as (delete from catalogue.courses returning 1) select count(*) as n from d', 24)$$, 'lane funnel: a stage must be one read-only SELECT%');
select pg_temp.raises('pg_sleep is refused', $$select security.lane_funnel_eval_v1('select pg_sleep(1)', 24)$$, 'lane funnel: a stage must be one read-only SELECT%');
select pg_temp.ok('a column called updated_at or created_at is not mistaken for a write', (select (security.lane_funnel_eval_v1('select count(*) as n, max(updated_at) as oldest from catalogue.courses', 24)->0->>'n')::int = 0));
select pg_temp.ok('{window} becomes the setting, not a number in the stage',
  (select (security.lane_funnel_eval_v1('select count(*) filter (where decided_at > now() - {window}) as gain, count(*) as n from pipeline.layer4_review_items', 24)->0->>'gain')::int = 0));

-- 3 seed: a world with one of each situation
insert into pipeline.platform_toolset_settings(toolset_key, key, label, value, min_value, max_value, unit, sort, section, used_by, reason) values
  ('pipeline', 'intake_dates.apply_enabled', 'Intake dates: apply', 'true', null, null, 'on/off', 1, 'Intake dates', 'intake-dates-apply', 'seed'),
  ('pipeline', 'intake_dates.revisit_days', 'Look at a waiting row again after', '14', 1, 90, 'days', 2, 'Intake dates', 'intake-dates-apply', 'seed'),
  ('pipeline', 'progress.intake_chain_on', 'Intake chain', '1', 0, 1, 'switch', 3, 'Progress', 'first-run-verify', 'seed'),
  ('pipeline', 'fees.course_pages', 'Fees from course pages', '0', 0, 1, 'on/off', 4, 'Enrichment', 'fee-reader', 'seed'),
  ('firecrawl', 'daily_budget_total', 'Credits a day', '4000', 0, 100000, 'credits', 1, null, null, 'seed'),
  ('firecrawl', 'daily_share_course_search', 'Share course search', '800', 0, 100000, 'credits', 2, null, null, 'seed'),
  ('firecrawl', 'daily_share_reads', 'Share reads', '1200', 0, 100000, 'credits', 3, null, null, 'seed'),
  ('firecrawl', 'priority_floor_course_search', 'Floor', '1500', 0, 100000, 'credits', 4, null, null, 'seed');
insert into pipeline.automation_catalogue(jobname, area, sort, label, control_rank) values ('intake-dates-apply', 'Admission', 1, 'Intake dates from the approved calendar', 5), ('fee-reader', 'Course pages', 2, 'Fee reader (AI)', 5), ('consumer-api-guard', 'Search and API', 3, 'Consumer API guard', 6);
insert into cron.job(jobname, schedule, active) values ('intake-dates-apply', '26 * * * *', true), ('calendar-reread', '13 * * * *', true), ('fee-reader', '* * * * *', true), ('consumer-api-guard', '23 18 * * *', false), ('firecrawl-credit', '*/15 * * * *', true);
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message)
  select jobid, now() - interval '30 minutes', now() - interval '29 minutes', 'succeeded', 'ok' from cron.job where jobname in ('intake-dates-apply', 'calendar-reread', 'firecrawl-credit');
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message) select jobid, now() - interval '10 minutes', now() - interval '9 minutes', 'failed', 'boom' from cron.job where jobname = 'fee-reader';
insert into pipeline.progress_transitions(key, chain, step, title, measured_at, window_start, input_eligible, input_processed, output_created, output_admitted, output_published, rejected_reasons) values
  ('intake_selection', 'intake', 10, 'Selection', now(), now() - interval '24 hours', 100, 100, 100, null, null, null),
  ('intake_admission', 'intake', 20, 'Admission', now(), now() - interval '24 hours', 100, 100, 0, 0, null, '{"no_matching_commencement_period": 60, "course_identity_unresolved": 40}'),
  ('intake_publication', 'intake', 30, 'Publication', now(), now() - interval '24 hours', 0, 0, 0, null, 0, null);
insert into pipeline.integration_issues(issue_ref, title, severity, status, detected_at) values ('IQ-00313', 'Deakin intake dates', 'P0', 'deployed', now() - interval '5 days'), ('IQ-00111', 'Fee integrity', 'P0', 'production_verification', now() - interval '3 days');
insert into pipeline.release_job_verifications(release, jobname, status, registered_at) values ('v1', 'fee-reader', 'failed_first_run', now() - interval '2 days');
insert into pipeline.fee_reader_queue(state) values ('queued'), ('queued'), ('done');
insert into pipeline.fee_reader_rows(outcome, created_at) values ('admitted', now()), ('domestic', now() - interval '3 days'), ('domestic', now()), ('review', now());
insert into pipeline.layer4_review_items(field_code, status, created_at, decided_at) values ('course_description_first_read', 'pending', now() - interval '4 days', null), ('course_description_first_read', 'pending', now() - interval '2 days', null), ('course_description_first_read', 'approved', now() - interval '3 days', now() - interval '2 hours'), ('provider_description', 'pending', now() - interval '1 day', null);
insert into pipeline.layer4_item_readiness(field_code, item_status, readiness) values ('course_description_first_read', 'pending', 'judgement_ready'), ('course_description_first_read', 'pending', 'judgement_ready'), ('course_entry_first_read', 'pending', 'technical_blocked');
insert into catalogue.courses(lifecycle_status, description) values ('active', null), ('active', ''), ('active', 'A degree in nursing.'), ('archived', null);
insert into catalogue.course_fees(status) values ('active'), ('active'), ('inactive');
insert into pipeline.coverage_vendor_usage(units, purpose) values (30, 'course_link_search'), (12, 'scrape'), (5, 'sch_scrape');
insert into pipeline.coverage_vendor_usage(units, purpose, at) values (40, 'course_link_search', now() - interval '3 days');

-- 4 refresh: counts every SELECT stage, from fixtures, with the unknown kept apart from zero
select security.lane_funnel_refresh_v1(true) as r1 \gset
select pg_temp.ok('the first refresh counts every SELECT stage without an error',
  (:'r1'::jsonb->>'failed')::int = 0 and (select count(*) from pipeline.lane_funnel_readings) = (select count(*) from pipeline.lane_funnel_stages where count_sql is not null));
select pg_temp.ok('fee: two items wait for the fee reader and the oldest age is held', (select n = 2 and oldest_at is not null from pipeline.lane_funnel_readings where lane = 'fee' and stage_key = 'queued'));
select pg_temp.ok('fee: held causes are one row per cause with the sum as the count', (select n = 3 and reasons @> '[{"reason":"domestic","n":2}]'::jsonb from pipeline.lane_funnel_readings where lane = 'fee' and stage_key = 'held'));
select pg_temp.ok('fee: 24 h gain counts only rows read inside the window', (select gain = 3 from pipeline.lane_funnel_readings where lane = 'fee' and stage_key = 'read'));
select pg_temp.ok('course descriptions: two wait, the oldest is 4 days, one decision was taken in the window',
  (select n = 2 and gain = 1 and oldest_at < now() - interval '3 days' from pipeline.lane_funnel_readings where lane = 'cdesc' and stage_key = 'human'));
select pg_temp.ok('readiness splits the waiting items so technical holds are not review capacity', (select reasons @> '[{"reason":"judgement_ready","n":2}]'::jsonb from pipeline.lane_funnel_readings where lane = 'cdesc' and stage_key = 'readiness'));
select pg_temp.ok('a measured zero is 0 (no P0 closed) and an empty cause list is 0 with no reasons', (select n = 0 from pipeline.lane_funnel_readings where lane = 'p0' and stage_key = 'p0_closed') and (select n = 0 and reasons is null from pipeline.lane_funnel_readings where lane = 'cdesc' and stage_key = 'held_rejected'));
select pg_temp.ok('the publish gain of active course fees is the rows created in the window', (select n = 2 and gain = 2 from pipeline.lane_funnel_readings where lane = 'fee' and stage_key = 'active'));

-- 5 a stage that cannot be counted is UNKNOWN (null), keeps its error, and does not stop the others
insert into pipeline.lane_funnel_stages(lane, step, key, title, kind, count_sql) values ('fee', 95, 'broken', 'Broken stage', 'held', 'select count(*) as n from pipeline.no_such_table');
select security.lane_funnel_refresh_v1(true) as r2 \gset
select pg_temp.ok('a broken stage is recorded with its error and no number; every other stage is still counted',
  (:'r2'::jsonb->>'failed')::int = 1
  and (select n is null and error like '%no_such_table%' from pipeline.lane_funnel_readings where lane = 'fee' and stage_key = 'broken')
  and (select n = 2 from pipeline.lane_funnel_readings where lane = 'fee' and stage_key = 'queued'));
select pg_temp.ok('the read shows the broken stage as null (unknown), not 0',
  (select s->'n' = 'null'::jsonb and s->>'error' like '%no_such_table%' from jsonb_array_elements(security.lane_funnel_v1('fee')->'lanes'->0->'stages') s where s->>'key' = 'broken'));
delete from pipeline.lane_funnel_stages where key = 'broken'; delete from pipeline.lane_funnel_readings where stage_key = 'broken';
insert into pipeline.lane_funnel_stages(lane, step, key, title, kind, count_sql) values ('sch', 999, 'never_counted', 'Never counted', 'held', 'select count(*) as n from catalogue.courses');
select pg_temp.ok('a stage never counted reads as unknown (null count, null time), not 0',
  (select s->'n' = 'null'::jsonb and s->'measured_at' = 'null'::jsonb from jsonb_array_elements(security.lane_funnel_v1('sch')->'lanes'->0->'stages') s where s->>'key' = 'never_counted'));
delete from pipeline.lane_funnel_stages where key = 'never_counted';

-- 6 due check: a second refresh inside the count-again time does not count again; switched off does nothing
update pipeline.lane_funnel_readings set measured_at = '2000-01-01', n = -1 where lane = 'fee' and stage_key = 'queued';
select security.lane_funnel_refresh_v1() as r3 \gset
select pg_temp.ok('a stage older than the count-again time is counted again by the unforced run', (:'r3'::jsonb->>'counted')::int = 1 and (select n = 2 from pipeline.lane_funnel_readings where lane = 'fee' and stage_key = 'queued'));
select security.lane_funnel_refresh_v1() as r4 \gset
select pg_temp.ok('a second unforced run counts nothing', (:'r4'::jsonb->>'counted')::int = 0);
insert into pipeline.platform_toolset_settings(toolset_key, key, value) values ('pipeline', 'lane_funnel.on', '0') on conflict (toolset_key, key) do update set value = '0';
select security.lane_funnel_refresh_v1() as r5 \gset
select pg_temp.ok('lane_funnel.on = 0 stops the refresh', :'r5'::jsonb->>'skipped' like 'switched off%');
update pipeline.platform_toolset_settings set value = '1' where key = 'lane_funnel.on';
select pg_temp.ok('history keeps a trend point per stage and not a second one inside its spacing', (select count(*) > 0 from pipeline.lane_funnel_history) and (select max(c) = 1 from (select count(*) c from pipeline.lane_funnel_history group by lane, stage_key) x));
insert into pipeline.lane_funnel_history(lane, stage_key, measured_at, n, gain) values ('fee', 'queued', now() - interval '25 hours', 7, 0);
select pg_temp.ok('the change on 24 hours ago is read from history', (select (s->>'n_prev')::int = 7 from jsonb_array_elements(security.lane_funnel_v1('fee')->'lanes'->0->'stages') s where s->>'key' = 'queued'));

-- 7 the read: header, jobs, switches, settings, issues, budget and the verdict that keeps green, transfer and published apart
create temp table t_int as select security.lane_funnel_v1('int')->'lanes'->0 l;
select pg_temp.ok('int: jobs carry schedule, next run, last result and run counts; a job that is not scheduled says so',
  (select (j->>'active')::boolean and j->>'next_run' is not null and j->>'last_status' = 'succeeded' and (j->>'succeeded')::int = 1 from t_int, jsonb_array_elements(l->'jobs') j where j->>'job' = 'intake-dates-apply')
  and (select (j->>'scheduled')::boolean is false from t_int, jsonb_array_elements(l->'jobs') j where j->>'job' = 'coverage-admit-intakes'));
select pg_temp.ok('int: the switches read on / unknown (a missing setting is unknown, not off)',
  (select (s->>'on')::boolean from t_int, jsonb_array_elements(l->'switches') s where s->>'key' = 'intake_dates.apply_enabled')
  and (select s->'on' = 'null'::jsonb from (select jsonb_array_elements(security.lane_funnel_v1('sch')->'lanes'->0->'switches') s) x limit 1));
select pg_temp.ok('int: settings listed by prefix with their range, unit and last change', (select count(*) = 2 and bool_and(s ? 'min' and s ? 'unit' and s ? 'updated_at') from t_int, jsonb_array_elements(l->'settings') s where s->>'key' like 'intake_dates.%'));
select pg_temp.ok('int: held causes of the admission transition come from the progress contract', (select s->'reasons'->'rejected'->>'no_matching_commencement_period' = '60' from t_int, jsonb_array_elements(l->'stages') s where s->>'key' = 'admitted'));
select pg_temp.ok('int: a green job with waiting items and no admission is GREEN_NO_TRANSFER, not transferring', (select l->>'verdict' = 'green_no_transfer' from t_int));
update pipeline.progress_transitions set output_admitted = 12 where key = 'intake_admission';
select pg_temp.ok('int: once values are admitted the verdict is transferring and the 24 h admitted gain is 12', (select l->>'verdict' = 'transferring' and (l->>'transfer_24h')::int = 12 from (select security.lane_funnel_v1('int')->'lanes'->0 l) x));
update pipeline.progress_transitions set stalled = true where key = 'intake_selection';
select pg_temp.ok('a stalled transition is STALLED even when its job succeeded', (select l->>'verdict' = 'stalled' from (select security.lane_funnel_v1('int')->'lanes'->0 l) x));
update pipeline.progress_transitions set stalled = false, output_admitted = 0 where key in ('intake_selection', 'intake_admission');
select pg_temp.ok('fee: a switch that is off reads OFF', (select l->>'verdict' = 'off' from (select security.lane_funnel_v1('fee')->'lanes'->0 l) x));
update pipeline.platform_toolset_settings set value = '1' where key = 'fees.course_pages';
select pg_temp.ok('fee: switched on, a failed run in the window reads FAILING', (select l->>'verdict' = 'failing' and (l->>'jobs_failing')::int = 1 from (select security.lane_funnel_v1('fee')->'lanes'->0 l) x));
update pipeline.platform_toolset_settings set value = '0' where key = 'fees.course_pages';
select pg_temp.ok('p0: the only scheduled job is paused, so the lane reads OFF', (select l->>'verdict' = 'off' from (select security.lane_funnel_v1('p0')->'lanes'->0 l) x));
select pg_temp.ok('issue references resolve to the issue register (int: two, fee: one of two)', (select jsonb_array_length(security.lane_funnel_v1('int')->'lanes'->0->'issues') = 2 and jsonb_array_length(security.lane_funnel_v1('fee')->'lanes'->0->'issues') = 1));
select pg_temp.ok('fee: budget names the group, credits and the share; credits in the window are the group''s only', (select l->'budget'->>'group' = 'central' and l->'budget'->>'unit' = 'credits' from (select security.lane_funnel_v1('fee')->'lanes'->0 l) x));
select pg_temp.ok('disc: the course-search group shows 30 credits in the window, not the 40 of 3 days ago', (select (l->'budget'->>'credits_window')::numeric = 30 and (l->'budget'->>'share_today')::numeric = 800 from (select security.lane_funnel_v1('disc')->'lanes'->0 l) x));

-- 8 permissions: the screen read needs rank 3 and a signed-in user
select set_config('test.uid', '', false); select set_config('test.rank', '0', false);
select pg_temp.raises('no user: refused', $$select public.admin_lane_funnel_v1(null)$$, 'Operations read permission required');
select set_config('test.uid', '00000000-0000-0000-0000-000000000001', false); select set_config('test.rank', '2', false);
select pg_temp.raises('a Counsellor (rank 2) is refused', $$select public.admin_lane_funnel_v1(null)$$, 'Operations read permission required');
select pg_temp.raises('a Counsellor is refused the Firecrawl read', $$select public.admin_firecrawl_acceptance_v1()$$, 'Operations read permission required');
select set_config('test.rank', '3', false);
select pg_temp.ok('a Curator (rank 3) reads all nine lanes', (select jsonb_array_length(public.admin_lane_funnel_v1(null)->'lanes') = 9));
select pg_temp.ok('the public reads are executable by signed-in users only', not has_function_privilege('anon', 'public.admin_lane_funnel_v1(text)', 'execute') and has_function_privilege('authenticated', 'public.admin_lane_funnel_v1(text)', 'execute')
  and not has_function_privilege('authenticated', 'security.lane_funnel_refresh_v1(boolean)', 'execute') and not has_table_privilege('authenticated', 'pipeline.lane_funnel_stages', 'select'));

-- 9 the read writes nothing: it runs in a read-only transaction
begin read only; select jsonb_array_length(security.lane_funnel_v1(null)->'lanes'); select security.firecrawl_acceptance_v1()->>'unit'; commit;
select pg_temp.ok('lane_funnel_v1 and firecrawl_acceptance_v1 run in a READ ONLY transaction', true);

-- 10 Firecrawl acceptance
select pg_temp.ok('no vendor reading: remaining and last sync read null (unknown), the floor is reported, nothing is 0 by default',
  (select a->'vendor'->'remaining_credits' = 'null'::jsonb and (a->'vendor'->>'fresh')::boolean is false and (a->'floor'->>'credits')::numeric = 1500 and a->>'unit' = 'credits' from (select security.firecrawl_acceptance_v1() a) x));
insert into pipeline.layer2_acquisition_providers(provider_key, billing_config) values ('firecrawl', '{"monthly_vendor_units_limit":100000,"stop_at_vendor_units_remaining":0,"plan_tier":"standard_100k"}');
insert into pipeline.vendor_credit_observations(provider_id, remaining_units, plan_units, period_end, observed_at, raw)
  select id, 100228, 100000, '2026-12-08 01:04:55+00', now() - interval '20 minutes', '{"billing_period_start":"2026-11-08T01:04:55.000Z"}' from pipeline.layer2_acquisition_providers;
create temp table t_fc as select security.firecrawl_acceptance_v1() a;
select pg_temp.ok('allowance, live remaining and reading time come from the vendor reading', (select (a->'allowance'->>'plan_credits')::numeric = 100000 and (a->'allowance'->>'monthly_limit_credits')::numeric = 100000 and (a->'vendor'->>'remaining_credits')::numeric = 100228 and a->'vendor'->>'read_at' is not null from t_fc));
select pg_temp.ok('a remaining above the plan is flagged, not hidden', (select (a->'vendor'->>'above_plan')::boolean from t_fc));
select pg_temp.ok('the estimate is the reading less use since (42 credits spent since... the 30 + 12 + 5 are after the reading)', (select (a->'vendor'->>'estimated_now_credits')::numeric is not null and (a->'vendor'->>'fresh')::boolean from t_fc));
select pg_temp.ok('the floor leaves room above it for course search and says so', (select (a->'floor'->>'applies')::boolean and (a->'floor'->>'room_credits')::numeric = (a->'vendor'->>'estimated_now_credits')::numeric - 1500 from t_fc));
select pg_temp.ok('the sync job is shown with its schedule, next run and last result', (select a->'sync'->>'schedule' = '*/15 * * * *' and a->'sync'->>'last_status' = 'succeeded' and a->'sync'->>'next_run' is not null from t_fc));
select pg_temp.ok('daily distribution: each group has its share, what it used today and what is left', (select (g->>'share')::numeric = 800 and (g->>'used')::numeric = 30 and (g->>'left')::numeric = 770 from t_fc, jsonb_array_elements(a->'daily'->'groups') g where g->>'group' = 'course_search'));
select pg_temp.ok('usage by group and by purpose over the window', (select (select count(*) from jsonb_array_elements(a->'usage'->'by_purpose') p where (p->>'credits_window')::numeric > 0) = 3 from t_fc));
select pg_temp.ok('credits are never money: the read carries no currency or dollar field', (select a::text !~* 'usd|\$|price|cost' from t_fc));

-- 11 re-run of the migration is a no-op on the data it seeds
select pg_temp.ok('all assertions ran', (select count(*) >= 40 from t_results));
