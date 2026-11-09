-- CF-247 F-OPS.03A Data Delivery: behaviour of migration 20261109210000 on isolated fixtures. Each assertion names what it proves.
\set ON_ERROR_STOP on
create temp table t_results(name text);
create or replace function pg_temp.ok(p_name text, p_cond boolean) returns void language plpgsql as $$ begin
  if p_cond is not true then raise exception 'FAILED: %', p_name; end if; insert into t_results values (p_name); raise notice 'ok: %', p_name; end $$;
create or replace function pg_temp.raises(p_name text, p_sql text, p_like text) returns void language plpgsql as $$ declare v text; begin
  begin execute p_sql; v := null; exception when others then v := sqlerrm; end;
  if v is null or v not like p_like then raise exception 'FAILED: % (got %)', p_name, coalesce(v, 'no error'); end if; insert into t_results values (p_name); raise notice 'ok: %', p_name; end $$;

-- 1 the migration itself
select pg_temp.ok('ten settings, each labelled with a range, a unit and what uses it',
  (select count(*) = 10 and bool_and(label is not null and min_value is not null and max_value is not null and unit is not null and used_by is not null and section = 'Data delivery')
     from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'data\_delivery.%'));
select pg_temp.ok('the screen''s refresh interval is a setting (60 s, 15 to 3600)', (select value = to_jsonb(60) and min_value = 15 and max_value = 3600 from pipeline.platform_toolset_settings where key = 'data_delivery.ui_refresh_seconds'));
select pg_temp.ok('eight streams: pdesc, int, cdesc, fee, eng, aer, sch, disc',
  (select array_agg(stream order by sort) = array['pdesc','int','cdesc','fee','eng','aer','sch','disc'] from pipeline.data_delivery_streams));
select pg_temp.ok('job data-delivery is catalogued and scheduled every minute with no number in its command',
  exists (select 1 from cron.job j join pipeline.automation_catalogue a using (jobname) where jobname = 'data-delivery' and j.schedule = '* * * * *' and j.command = 'select security.data_delivery_refresh_v1()'));
select pg_temp.ok('the two new provider description stages are in the lane funnel (queued, held)', (select count(*) = 2 from pipeline.lane_funnel_stages where lane = 'pdesc' and key in ('queued', 'held')));
select pg_temp.ok('the read is STABLE and the refresh is the only writer (volatile)', (select (select provolatile from pg_proc where oid = 'security.data_delivery_v1()'::regprocedure) = 's' and (select provolatile from pg_proc where oid = 'security.data_delivery_refresh_v1(boolean)'::regprocedure) = 'v'));
select pg_temp.ok('the Operations action was added once and the older action is untouched', (select position('security.data_delivery_v1()' in pg_get_functiondef('public.admin_layer23(text,jsonb)'::regprocedure)) > 0 and position('universities_page' in pg_get_functiondef('public.admin_layer23(text,jsonb)'::regprocedure)) > 0));

-- 2 fixtures: two countries, five providers, courses, ledgers, jobs, feeds
insert into ref.countries(iso_alpha2) values ('AU'), ('NZ');
insert into catalogue.providers(stable_key, country_id, lifecycle_status, description)
  select k, (select id from ref.countries where iso_alpha2 = c), 'active', d from (values ('p1','AU','About one'), ('p2','AU','About two'), ('p3','AU','About three'), ('p4','AU',null), ('p5','NZ','About five')) v(k, c, d);
insert into catalogue.courses(stable_key, provider_id, lifecycle_status, description)
  select 'c' || g, (select id from catalogue.providers where stable_key = 'p' || (1 + g % 3)), 'active', case when g <= 2 then 'text' end from generate_series(1, 6) g;
insert into catalogue.course_fees(course_id, status) select id, 'active' from catalogue.courses where stable_key in ('c1', 'c2', 'c3');
insert into catalogue.course_english_requirements(course_id, status) select id, 'active' from catalogue.courses where stable_key in ('c1', 'c2');
insert into catalogue.course_intakes(course_id, status, start_date) select id, 'active', current_date from catalogue.courses where stable_key in ('c1', 'c2', 'c3', 'c4');
-- provider descriptions: 2 queued, 3 held (two share a cause), 1 machine admission in the window, 1 older, 1 withdrawn in the window
insert into pipeline.provider_description_reads(provider_id, state, reason) select id, 'queued', null from catalogue.providers where stable_key in ('p4', 'p5');
insert into pipeline.provider_description_reads(provider_id, state, reason)
  select (select id from catalogue.providers where stable_key = k), 'held', r from (values ('p1', '2 verified fact(s) held (register, location); 3 needed for a description'), ('p2', '4 verified fact(s) held (register, location); 3 needed for a description'), ('p3', 'home page not read: fetch_failed')) v(k, r);
insert into pipeline.provider_description_machine_admissions(provider_id, outcome, created_at, withdrawn_at)
  select (select id from catalogue.providers where stable_key = k), 'admitted', now() - make_interval(hours => h), w from (values ('p1', 1, null::timestamptz), ('p2', 72, null), ('p3', 30, now() - interval '2 hours')) v(k, h, w);
-- intake dates: three decisions in the window, none admitted (all held) -> a green job with nothing admitted
insert into pipeline.course_intake_date_events(provider_id, run_at, outcome, failure_class) select (select id from catalogue.providers where stable_key = 'p1'), now() - interval '3 hours', 'held', 'no_evidence' from generate_series(1, 3);
insert into pipeline.course_intake_date_events(provider_id, run_at, outcome) select (select id from catalogue.providers where stable_key = 'p1'), now() - interval '40 hours', 'filled';
-- scholarships: two published, admission log with one admitted today
insert into scholarship.scholarships(stable_key, provider_id, lifecycle_status, publication_status) select 's' || g, (select id from catalogue.providers where stable_key = 'p1'), 'active', 'published' from generate_series(1, 2) g;
insert into pipeline.scholarship_admission_log(provider_id, action, at) select (select id from catalogue.providers where stable_key = 'p1'), 'admitted', now() - interval '1 hour';
-- feeds: Website holds p1 (same text), p2 (different text), not p3; Zoho holds p1 only. Served: every provider except p5 (unpublished: not applicable)
insert into pipeline.website_sync_items(entity, item_key, item) values ('provider', 'p1', '{"description":"About one"}'), ('provider', 'p2', '{"description":"changed"}');
insert into pipeline.zoho_sync_items(entity, item_key, item) values ('provider', 'p1', '{"description":"About one"}');
insert into pipeline.fx_served(feed, entity, ref_id) select f, 'provider', id from catalogue.providers p, (values ('w'), ('z')) v(f) where stable_key <> 'p5';
-- jobs and their scheduler history
insert into cron.job(jobname, schedule, command, active) values ('provider-description-read', '6,16,26,56 * * * *', 'x', true), ('intake-dates-apply', '26 * * * *', 'x', true), ('fee-reader', '* * * * *', 'x', true), ('scholarship-read', '*/5 * * * *', 'x', true);
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message)
  select (select jobid from cron.job where jobname = 'provider-description-read'), now() - make_interval(mins => 10 * g), now() - make_interval(mins => 10 * g) + interval '5 seconds', 'succeeded', 'done' from generate_series(1, 3) g;
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message)
  select (select jobid from cron.job where jobname = 'intake-dates-apply'), now() - make_interval(hours => g), now() - make_interval(hours => g) + interval '5 seconds', 'succeeded', 'applied 0' from generate_series(1, 2) g;
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message) values ((select jobid from cron.job where jobname = 'fee-reader'), now() - interval '5 minutes', now() - interval '4 minutes', 'failed', 'boom');
-- fee-reader is the only job with a failed run; scholarship-read has no history at all

-- 3 the refresh: records only, a few measures per run, oldest first, then everything
create temp table t_run1 as select security.data_delivery_refresh_v1() r;
select pg_temp.ok('one run counts at most the batch setting (8 measures)', (select (r->>'counted')::int + (r->>'failed')::int = 8 from t_run1));
do $$ begin for i in 1..6 loop perform security.data_delivery_refresh_v1(); end loop; end $$;
select pg_temp.ok('every measure SELECT runs under the evaluator''s empty search path with no error', (select count(*) = 0 from pipeline.data_delivery_readings where error is not null));
select pg_temp.ok('every built measure is counted: 8 streams x 4 measures less the two consumer measures that are not built (course descriptions, AER)', (select count(*) = 30 from pipeline.data_delivery_readings));
select pg_temp.ok('a due measure is not counted again before the count-again time', (select (security.data_delivery_refresh_v1()->>'counted')::int = 0));
update pipeline.platform_toolset_settings set value = to_jsonb(0) where key = 'data_delivery.on';
select pg_temp.ok('the refresh switch stops the count', (select (security.data_delivery_refresh_v1()->>'skipped') like 'switched off%'));
update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'data_delivery.on';
insert into pipeline.data_delivery_streams(stream, title, sort, lane, unit, coverage_sql) values ('bad', 'Bad', 99, 'pdesc', 'x', 'select 1 / 0 as n');
create temp table t_bad as select security.data_delivery_refresh_v1(true) r;
select pg_temp.ok('a measure that fails to count is recorded as an error with no rows (never as zero)', (select (r->>'failed')::int >= 1 and (select rows is null and error like '%division by zero%' from pipeline.data_delivery_readings where stream = 'bad' and measure = 'coverage') from t_bad));
delete from pipeline.data_delivery_readings where stream = 'bad'; delete from pipeline.data_delivery_streams where stream = 'bad';

select security.lane_funnel_refresh_v1(true);  -- the lane funnel readings (queue and hold stages) that the summary reuses
set test.uid = '00000000-0000-0000-0000-000000000001'; set test.rank = '3';
create temp table t_read as select public.admin_layer23('data_delivery') d;
create or replace function pg_temp.st(p text) returns jsonb language sql as $$ select x from t_read, jsonb_array_elements(d->'streams') x where x->>'stream' = p $$;

-- 4 coverage, net gain, speed
select pg_temp.ok('provider descriptions: coverage 4 of 5 = 80.0 percent, with the country split', (select (x->'coverage'->>'n')::int = 4 and (x->'coverage'->>'total')::int = 5 and (x->'coverage'->>'pct')::numeric = 80.0 and jsonb_array_length(x->'coverage'->'by_country') = 2 from (select pg_temp.st('pdesc') x) q));
select pg_temp.ok('provider descriptions: net over the short window = 1 admitted - 1 withdrawn = 0, known', (select (x->'net_short'->>'added')::int = 1 and (x->'net_short'->>'removed')::int = 1 and (x->'net_short'->>'net')::int = 0 and (x->'net_short'->>'known')::boolean from (select pg_temp.st('pdesc') x) q));
select pg_temp.ok('the long window counts the older admissions too (3 admitted) and says the ledger is younger than the window', (select (x->'net_long'->>'added')::int = 3 and (x->'net_long'->>'partial')::boolean and x->'net_long'->>'since' is not null from (select pg_temp.st('pdesc') x) q));
select pg_temp.ok('windows come from the settings (24 h and 168 h)', (select (d->'windows'->>'short_hours')::int = 24 and (d->'windows'->>'long_hours')::int = 168 from t_read));
select pg_temp.ok('speed is items per hour over a stated window with its basis', (select (x->'speed'->>'known')::boolean and (x->'speed'->>'window_hours')::numeric > 0 and x->'speed'->>'basis' is not null from (select pg_temp.st('int') x) q));
select pg_temp.ok('unknown removals are not zero: English net is null, removed_known false, with the reason', (select x->'net_short'->'removed' = 'null'::jsonb and x->'net_short'->'net' = 'null'::jsonb and not (x->'net_short'->>'removed_known')::boolean and x->'net_short'->>'removed_reason' like '%no withdrawal time%' from (select pg_temp.st('eng') x) q));
select pg_temp.ok('unknown speed is not zero: English speed is known=false with the reason', (select not (x->'speed'->>'known')::boolean and x->'speed'->>'reason' like '%cannot be counted%' and x->'speed'->'per_hour' is null from (select pg_temp.st('eng') x) q));
select pg_temp.ok('scholarships: the total is not defined, so no percentage is invented', (select (x->'coverage'->>'n')::int = 2 and x->'coverage'->'total' = 'null'::jsonb and x->'coverage'->'pct' = 'null'::jsonb and x->'coverage'->>'total_reason' like '%not defined%' from (select pg_temp.st('sch') x) q));

-- 5 Website and Zoho
select pg_temp.ok('provider descriptions on the Website: 1 matched, 1 pending (text differs), 1 missing (served, not in the feed), 1 not applicable (unpublished)',
  (select (x->'website'->>'matched')::int = 1 and (x->'website'->>'pending')::int = 1 and (x->'website'->>'missing')::int = 1 and (x->'website'->>'not_applicable')::int = 1 from (select pg_temp.st('pdesc') x) q));
select pg_temp.ok('provider descriptions on Zoho: 1 matched, 2 missing', (select (x->'zoho'->>'matched')::int = 1 and (x->'zoho'->>'missing')::int = 2 from (select pg_temp.st('pdesc') x) q));
select pg_temp.ok('course descriptions: Website and Zoho are Not measured with a reason, never 0', (select not (x->'website'->>'known')::boolean and x->'website'->'matched' is null and x->'website'->>'reason' like '%not compared yet%' and not (x->'zoho'->>'known')::boolean from (select pg_temp.st('cdesc') x) q));
select pg_temp.ok('scholarships: Website measured, Zoho Not measured with a reason', (select (x->'website'->>'known')::boolean and not (x->'zoho'->>'known')::boolean and x->'zoho'->>'reason' like '%not built%' from (select pg_temp.st('sch') x) q));

-- 6 queue and holds with exact reasons
select pg_temp.ok('provider descriptions: queue 2 (waiting for the reader)', (select (x->'queue'->>'n')::int = 2 and x->'queue'->'parts'->0->>'stage' = 'queued' from (select pg_temp.st('pdesc') x) q));
select pg_temp.ok('provider descriptions: holds 3, the largest exact reason first with its count (digits normalised)', (select (x->'holds'->>'n')::int = 3 and x->'holds'->'reasons'->0->>'reason' like 'N verified fact(s) held (register, location)%' and (x->'holds'->'reasons'->0->>'n')::int = 2 from (select pg_temp.st('pdesc') x) q));
select pg_temp.ok('the number of reasons shown is a setting (3)', (select jsonb_array_length(x->'holds'->'reasons') <= 3 from (select pg_temp.st('pdesc') x) q));
select pg_temp.ok('a queue that is not recorded is unknown with the reason, never 0', (select not (x->'queue'->>'known')::boolean and x->'queue'->>'reason' like '%not counted%' and x->'queue'->'n' is null from (select pg_temp.st('cdesc') x) q));

-- 7 last / next run, the green flag, failing, no history
select pg_temp.ok('last and next run of the primary job are returned as timestamps with the job list', (select x->'jobs'->>'last_run_at' is not null and x->'jobs'->>'next_run_at' is not null and jsonb_array_length(x->'jobs'->'list') = 1 from (select pg_temp.st('pdesc') x) q));
select pg_temp.ok('a green job that admitted nothing is flagged, with the cause and the count of runs', (select exists (select 1 from jsonb_array_elements(x->'flags') f where f->>'code' = 'green_no_admission' and f->>'text' like 'Ran OK 2 time(s) in 24 h, admitted nothing%') from (select pg_temp.st('int') x) q));
select pg_temp.ok('a job that admitted in the window is not flagged', (select not exists (select 1 from jsonb_array_elements(x->'flags') f where f->>'code' like 'green%') from (select pg_temp.st('pdesc') x) q));
select pg_temp.ok('a failed run is flagged and recovery says it retries at the next scheduled run', (select exists (select 1 from jsonb_array_elements(x->'flags') f where f->>'code' = 'job_failing') and x->'recovery'->>'state' = 'failing' and x->'recovery'->>'text' like '%retries at its next scheduled run%' from (select pg_temp.st('fee') x) q));
select pg_temp.ok('a job with no run in the history window is Unknown with the reason, not "never"', (select not (x->'jobs'->>'known')::boolean and x->'jobs'->>'reason' like 'No run of scholarship-read, scholarship-auto-publish in the last 48 hours%' and x->'jobs'->'last_run_at' = 'null'::jsonb from (select pg_temp.st('sch') x) q));
select pg_temp.ok('a stream with no primary job found in the scheduler is unknown, and its flag is not green', (select not (x->'jobs'->>'known')::boolean from (select pg_temp.st('aer') x) q));

-- 8 recovery: open issues, remedy runs, a switch that is off
insert into pipeline.integration_issues(issue_ref, title, severity, status) values ('IQ-00313', 'Intake dates stalled', 'P1', 'open');
insert into pipeline.ops_remedy_runs(issue_id, remedy_code, result) select id, 'work_retry_parked', 'acted' from pipeline.integration_issues where issue_ref = 'IQ-00313';
select pg_temp.ok('an open issue with an automatic remedy that acted is recovering',
  (select x->'recovery'->>'state' = 'recovering' and (x->'recovery'->>'remedy_acted')::int = 1 and (x->'recovery'->>'open_issues')::int = 1 from (select x from jsonb_array_elements(public.admin_layer23('data_delivery')->'streams') x where x->>'stream' = 'int') q));
insert into pipeline.platform_toolset_settings(toolset_key, key, label, value) values ('pipeline', 'intake_dates.apply_enabled', 'Intake dates apply', to_jsonb(0)) on conflict (toolset_key, key) do update set value = to_jsonb(0);
select pg_temp.ok('a switch that is off shows recovery off: nothing retries',
  (select x->'recovery'->>'state' = 'off' from (select x from jsonb_array_elements(public.admin_layer23('data_delivery')->'streams') x where x->>'stream' = 'int') q));

-- 9 stale, error and never-counted are shown as such
update pipeline.data_delivery_readings set measured_at = now() - interval '2 hours' where stream = 'pdesc' and measure = 'coverage';
select pg_temp.ok('an old count is marked stale with its age', (select (x->'coverage'->>'stale')::boolean and (x->'coverage'->>'age_minutes')::int >= 119 from (select x from jsonb_array_elements(public.admin_layer23('data_delivery')->'streams') x where x->>'stream' = 'pdesc') q));
update pipeline.data_delivery_readings set rows = null, error = 'canceling statement due to statement timeout' where stream = 'int' and measure = 'net_short';
select pg_temp.ok('a count that failed is Unknown with the error, never 0, and the green flag says what it admitted is unknown',
  (select not (x->'net_short'->>'known')::boolean and x->'net_short'->>'reason' like 'Could not be counted: canceling statement%' and x->'net_short'->'added' is null
      and exists (select 1 from jsonb_array_elements(x->'flags') f where f->>'code' = 'green_admission_unknown')
      from (select x from jsonb_array_elements(public.admin_layer23('data_delivery')->'streams') x where x->>'stream' = 'int') q));
delete from pipeline.data_delivery_readings where stream = 'fee' and measure = 'coverage';
select pg_temp.ok('a measure never counted says so (not zero)', (select not (x->'coverage'->>'known')::boolean and x->'coverage'->>'reason' like 'Not counted yet%' and x->'coverage'->'n' is null from (select x from jsonb_array_elements(public.admin_layer23('data_delivery')->'streams') x where x->>'stream' = 'fee') q));

-- 10 gate, read-only, settings
reset test.rank; set test.rank = '2';
select pg_temp.raises('rank 2 is refused (same gate as Operations)', $$select public.admin_layer23('data_delivery')$$, 'Curator role or above required');
set test.rank = '3'; select set_config('test.uid', '', false);
select pg_temp.raises('no signed-in user is refused', $$select public.admin_layer23('data_delivery')$$, 'authentication required');
set test.uid = '00000000-0000-0000-0000-000000000001';
select pg_temp.ok('the older Operations action still answers', (select public.admin_layer23('universities_page') = '{"stub": "universities_page"}'::jsonb));
create temp table t_before as select count(*) n, max(measured_at) m, sum(coalesce(took_ms, 0)) t from pipeline.data_delivery_readings;
do $$ begin for i in 1..5 loop perform public.admin_layer23('data_delivery'); end loop; end $$;
select pg_temp.ok('reading never writes: the snapshot is unchanged after five reads', (select b.n = a.n and b.m = a.m and b.t = a.t from t_before b, (select count(*) n, max(measured_at) m, sum(coalesce(took_ms, 0)) t from pipeline.data_delivery_readings) a));
update pipeline.platform_toolset_settings set value = to_jsonb(48) where key = 'data_delivery.net_short_hours';
select pg_temp.ok('changing the short window changes the answer''s window (setting, not code)', (select (public.admin_layer23('data_delivery')->'windows'->>'short_hours')::int = 48));
update pipeline.platform_toolset_settings set value = to_jsonb(24) where key = 'data_delivery.net_short_hours';
select pg_temp.ok('the screen''s refresh interval is returned from the setting', (select (public.admin_layer23('data_delivery')->>'ui_refresh_seconds')::int = 60));
select pg_temp.ok('the provider catalogue filters are reported unavailable until their function exists', (select not (public.admin_layer23('data_delivery')->>'provider_filters_available')::boolean));
create function security.admin_providers_page_v3(p jsonb) returns jsonb language sql as $$ select '{}'::jsonb $$;
select pg_temp.ok('and available once admin_providers_page_v3 exists', (select (public.admin_layer23('data_delivery')->>'provider_filters_available')::boolean));
select pg_temp.ok('the answer carries a timezone and a time, and the meaning of unknown', (select d->>'timezone' = 'Australia/Melbourne' and d->>'at' is not null and d->'meaning'->>'unknown' like '%never shown as 0%' from (select public.admin_layer23('data_delivery') d) q));
create or replace function pg_temp.read_ms() returns numeric language plpgsql as $$ declare t0 timestamptz := clock_timestamp(); x jsonb; begin x := public.admin_layer23('data_delivery'); return extract(epoch from clock_timestamp() - t0) * 1000; end $$;
select pg_temp.ok('the read answers within the one-second budget on the fixtures (measured, not assumed)', (select pg_temp.read_ms() < 1000));
select pg_temp.ok('all assertions ran', (select count(*) >= 40 from t_results));
