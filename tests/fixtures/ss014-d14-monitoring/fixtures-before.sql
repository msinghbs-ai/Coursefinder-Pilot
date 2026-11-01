-- Guards: SS-014 D14 and monitoring accuracy (Platform Admin 2 Nov 2026 07:41): the seeds, and each defect reproduced on the live
-- definitions BEFORE the 20261102040000 migration (run.sh runs this between the rebuild and the migration). Every block raises on a failed
-- check; each passing block prints "PASS <name>". No live data: providers, courses and calls are made up for the cases.
\set ON_ERROR_STOP 1
set client_min_messages = notice;

create function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is distinct from true then raise exception 'FAIL: %', p_what; end if; end $f$;

-- ------------------------------------------------------------------ seeds: course pages to read
-- V1 and V2 are published providers; H1 is hidden (unpublished), like the four providers behind the 03:00 false critical.
insert into catalogue.providers(id, stable_key) values ('10000000-0000-4000-8000-000000000001', 'v1'), ('10000000-0000-4000-8000-000000000002', 'v2'),
  ('10000000-0000-4000-8000-0000000000a1', 'h1');
insert into fx.hidden values ('10000000-0000-4000-8000-0000000000a1');
create function pg_temp.page(p_tag text, p_provider uuid, p_status text, p_next interval, p_lease interval, p_attempts int, p_read_at interval default null, p_read_status text default null)
returns void language sql as $f$
  insert into catalogue.courses(id, provider_id, canonical_title, course_code) values (md5(p_tag)::uuid, p_provider, 'Course ' || p_tag, upper(left(md5(p_tag), 6)));
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, next_read_at, leased_until, read_attempts, read_at, read_status, bound_at)
  values (md5(p_tag)::uuid, p_provider, 'https://example/' || p_tag, p_status, now() + p_next, now() + p_lease, p_attempts, now() + p_read_at, p_read_status, now() - interval '30 minutes');
$f$;
select pg_temp.page('v1-due-' || i, '10000000-0000-4000-8000-000000000001', 'bound', interval '-1 hour', null, 0) from generate_series(1, 25) i;          -- 25 due (more than one call's 20 per provider)
select pg_temp.page('v1-amb-' || i, '10000000-0000-4000-8000-000000000001', 'ambiguous', null, null, 0) from generate_series(1, 2) i;                   -- 2 due, never scheduled
select pg_temp.page('v1-leased-' || i, '10000000-0000-4000-8000-000000000001', 'bound', interval '-2 hours', interval '5 minutes', 1) from generate_series(1, 3) i;  -- being read now
select pg_temp.page('v1-spent-' || i, '10000000-0000-4000-8000-000000000001', 'bound', interval '-3 hours', null, 3, interval '-5 hours', 'read') from generate_series(1, 2) i;  -- attempts used
select pg_temp.page('v1-later-' || i, '10000000-0000-4000-8000-000000000001', 'bound', interval '2 hours', null, 0) from generate_series(1, 2) i;          -- not due yet
select pg_temp.page('v1-mismatch', '10000000-0000-4000-8000-000000000001', 'mismatch', interval '-1 hour', null, 0);                                      -- not a page to read
select pg_temp.page('v2-due-' || i, '10000000-0000-4000-8000-000000000002', 'bound', interval '-30 minutes', null, 0) from generate_series(1, 4) i;         -- 4 due
select pg_temp.page('h1-due-' || i, '10000000-0000-4000-8000-0000000000a1', 'bound', interval '-15 hours', null, 0, null, 'needs_render') from generate_series(1, 10) i;  -- hidden provider
create table fx.read_expect as select 31 eligible, 44 old_count;  -- 25 + 2 + 4 the reader takes; the old counts add 3 leased and 10 hidden

-- ------------------------------------------------------------------ seeds: course page searches
-- S1 a target university; S2 hidden; S3 not a Firecrawl target; S4 searches a directory site; S5 on search.skip_providers; S6 not a focus
-- provider; S7 lists too few course pages; S8 its search stopped; S9 a bulk onboarding; S10 its recipe off; S11 its site not checked yet.
insert into catalogue.providers(id, stable_key) select ('20000000-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid, case when i = 5 then 'skip-me' else 's' || i end from generate_series(1, 11) i;
insert into fx.hidden values ('20000000-0000-4000-8000-000000000002');
insert into fx.provider(provider_id, focus, few, unchecked, stopped) select ('20000000-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid, i <> 6, i = 7, i = 11, i = 8 from generate_series(1, 11) i;
insert into pipeline.firecrawl_target_cache select ('20000000-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid, i <> 3 from generate_series(1, 11) i;
insert into pipeline.course_link_recipes(provider_id, active, search_domain) select ('20000000-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid, i <> 10,
  case when i = 4 then 'directory.example' else 's' || i || '.example' end from generate_series(1, 11) i;
insert into pipeline.provider_onboarding(provider_id, source, created_at) values ('20000000-0000-4000-8000-000000000009', 'backfill', now() - interval '2 days');
create function pg_temp.search(p_tag text, p_n int, p_state text default 'queued', p_requested boolean default false) returns void language sql as $f$
  insert into catalogue.courses(id, provider_id, canonical_title, course_code)
  values (md5(p_tag)::uuid, ('20000000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0'))::uuid, 'Course ' || p_tag, upper(left(md5(p_tag), 6)));
  insert into pipeline.course_link_search(course_id, provider_id, state, requested_at, sent_at, done_at)
  values (md5(p_tag)::uuid, ('20000000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0'))::uuid, p_state, case when p_requested then now() - interval '1 hour' end,
          case when p_state <> 'queued' then (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') + interval '1 second' end,
          case when p_state = 'done' then now() - interval '3 hours' end);
$f$;
select pg_temp.search('s1-q-' || i, 1) from generate_series(1, 6) i;
select pg_temp.search('s1-stop', 1); insert into fx.course(course_id, stop_reason) values (md5('s1-stop')::uuid, 'six searches found nothing');
select pg_temp.search('s1-list', 1); insert into fx.course(course_id, site_list_done) values (md5('s1-list')::uuid, false);
select pg_temp.search('s1-asked', 1, 'queued', true);
select pg_temp.search('s1-done-' || i, 1, 'done') from generate_series(1, 5) i;  -- 5 picked today (UTC day), finished 3 hours ago
select pg_temp.search('s' || p || '-q-' || i, p) from generate_series(2, 5) p, generate_series(1, 2) i;
select pg_temp.search('s2-q-3', 2);
select pg_temp.search('s6-q-' || i, 6) from generate_series(1, 2) i; select pg_temp.search('s6-asked', 6, 'queued', true);
select pg_temp.search('s7-q-' || i, 7) from generate_series(1, 2) i; select pg_temp.search('s7-asked', 7, 'queued', true);
select pg_temp.search('s8-q-' || i, 8) from generate_series(1, 2) i; select pg_temp.search('s8-person', 8); insert into fx.course(course_id, person_task) values (md5('s8-person')::uuid, false);
select pg_temp.search('s9-asked', 9, 'queued', true); select pg_temp.search('s9-q', 9);
select pg_temp.search('s10-q-' || i, 10) from generate_series(1, 2) i;
select pg_temp.search('s11-q', 11); select pg_temp.search('s11-asked', 11, 'queued', true);
-- a hard flag on one queued course: the old count left it out, though the picker's own gate decides
insert into pipeline.enrichment_flags(entity, entity_key, reason_code, kind, state) values ('course', md5('s1-q-6')::uuid::text, 'page_not_found', 'hard', 'raised');
-- the picker takes: S1 6 queued + 1 asked; S6, S7 and S11 their asked one; S9 both; S8 none (stopped, no person task) = 12
create table fx.search_expect as select 12 eligible, 32 old_count;  -- the old count: 33 queued less the hard-flagged course

-- ------------------------------------------------------------------ calls to the worker (edge_request_log and pg_net answers)
create sequence fx.req;
-- one call p_age_s seconds ago; p_items null = no answer yet; p_status other than 200 = a failed answer
create function fx.call(p_mode text, p_age_s int, p_items int, p_status int default 200) returns void language plpgsql as $f$
declare v_id bigint := nextval('fx.req');
begin
  insert into pipeline.edge_request_log(function_name, mode, request_id, created_at) values ('coverage-sweep', p_mode, v_id, now() - make_interval(secs => p_age_s));
  if p_items is not null then
    insert into net._http_response(id, status_code, content, created) values (v_id, p_status, jsonb_build_object('mode', p_mode, 'items', p_items)::text, now() - make_interval(secs => greatest(p_age_s - 4, 0)));
  end if;
end $f$;
create function fx.reset() returns void language sql as $f$
  truncate pipeline.edge_request_log, net._http_response, pipeline.enrichment_flag_events;
  delete from pipeline.enrichment_flags where entity = 'job';
  update cron.job set active = true;
$f$;

-- ------------------------------------------------------------------ BEFORE: the defects, on the live definitions
-- D14: a job that runs every minute, checked at the second it starts: the newest call has no answer yet, so the guard sees 29 of 30
do $t$ declare v jsonb; begin
  perform fx.reset();
  perform fx.call('ai_match', 0, null);                                   -- this minute's call, still under way
  perform fx.call('ai_match', 60 * i, 0) from generate_series(1, 40) i;   -- 40 answered calls in a row that found nothing
  v := security.flag_jobs_v1();
  perform pg_temp.ok(v = '[]'::jsonb and (select active from cron.job where jobname = 'coverage-ai-match'), 'before: the live guard does not pause (it sees 29 of 30)');
  -- the same calls with this minute's answer in: the live guard pauses, so the fixture models the guard correctly
  perform fx.reset();
  perform fx.call('ai_match', 60 * i, 0) from generate_series(0, 40) i;
  v := security.flag_jobs_v1();
  perform pg_temp.ok(v = '[{"paused": "coverage-ai-match"}]'::jsonb, 'before: with every call answered the live guard pauses');
  raise notice 'PASS before: D14 race reproduced (29 of 30, never paused)';
end $t$;

-- the health check's reading rule and the watchdog count hidden-provider and leased pages; the stall is aged from a hidden page
do $t$ declare v jsonb; begin
  v := security.platform_health_check_v1(true) -> 0;
  perform pg_temp.ok((v->>'waiting')::int = (select old_count from fx.read_expect), 'before: the health rule counts 44 (hidden and leased included), got ' || (v->>'waiting'));
  perform pg_temp.ok((v->>'since')::timestamptz = (select max(read_at) from pipeline.coverage_course_pages), 'before: the stall runs from the last read (5 hours), as hidden pages became due earlier');
  perform security.queue_watch_run_v1(false);
  perform pg_temp.ok((select pending from pipeline.queue_watch_state where key = 'course_page_read') = (select old_count from fx.read_expect), 'before: the watchdog counts 44');
  perform pg_temp.ok((select pending from pipeline.queue_watch_state where key = 'course_page_search') = (select old_count from fx.search_expect), 'before: the watchdog counts 32 searches');
  raise notice 'PASS before: waiting counts include pages and searches the readers skip';
end $t$;

-- the day's cap reached: the watchdog calls the search queue stuck and raises a health issue
do $t$ begin
  update pipeline.platform_toolset_settings set value = '5' where key = 'search.daily_picked_cap';
  perform pg_temp.ok(public.svc_course_link_search_next(200) = '[]'::jsonb, 'before: at the cap the picker picks nothing');
  perform security.queue_watch_run_v1(false);
  perform pg_temp.ok((select state from pipeline.queue_watch_state where key = 'course_page_search') = 'stuck', 'before: the cap pause is reported as stuck');
  perform pg_temp.ok(exists (select 1 from pipeline.platform_issues where check_key = 'queue_watch:course_page_search' and resolved_at is null), 'before: a health issue is open for it');
  perform pg_temp.ok(exists (select 1 from pipeline.queue_watch_alerts where key = 'course_page_search' and state = 'stuck'), 'before: a stuck alert was raised');
  raise notice 'PASS before: a configured cap pause is reported as stuck';
end $t$;
truncate pipeline.queue_watch_alerts;
update pipeline.platform_toolset_settings set value = '200' where key = 'search.daily_picked_cap';
