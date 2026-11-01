-- Guards: SS-014 D14 and monitoring accuracy (Platform Admin 2 Nov 2026 07:41): the fixed behaviour AFTER the 20261102040000 migration,
-- on the seeds of fixtures-before.sql (see run.sh). Every block raises on a failed check; each passing block prints "PASS <name>".
\set ON_ERROR_STOP 1
set client_min_messages = notice;

create function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is distinct from true then raise exception 'FAIL: %', p_what; end if; end $f$;
create function pg_temp.flag() returns pipeline.enrichment_flags language sql as $f$
  select * from pipeline.enrichment_flags where entity = 'job' and entity_key = 'coverage-ai-match' and reason_code = 'idle_paused' $f$;
create function pg_temp.active() returns boolean language sql as $f$ select active from cron.job where jobname = 'coverage-ai-match' $f$;

-- ------------------------------------------------------------------ D14: the idle guard
-- the setting: registered for Settings > Pipeline settings (G2), 120 s by default (the worker call time-out)
do $t$ begin
  perform pg_temp.ok((select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'flag.answer_wait_seconds' and label is not null
                      and unit = 'seconds' and min_value = 10 and max_value = 600 and section = 'Flags' and used_by = 'security.flag_jobs_v1') = '120'::jsonb, 'setting flag.answer_wait_seconds');
  raise notice 'PASS setting registered';
end $t$;

-- the race of the 2 Nov evidence: checked at the second the job starts, with this minute's call still under way. It now pauses.
do $t$ declare v jsonb; f pipeline.enrichment_flags; begin
  perform fx.reset();
  perform fx.call('ai_match', 0, null);
  perform fx.call('ai_match', 60 * i, 0) from generate_series(1, 40) i;
  v := security.flag_jobs_v1();
  f := pg_temp.flag();
  perform pg_temp.ok(v = '[{"paused": "coverage-ai-match"}]'::jsonb and not pg_temp.active(), 'the race: paused');
  perform pg_temp.ok(f.state = 'raised' and (f.evidence->>'runs')::int = 30 and (f.evidence->>'with_work')::int = 0, 'the flag says 30 runs, none with work');
  perform pg_temp.ok((f.evidence->>'to')::timestamptz <= now() - interval '120 seconds', 'the newest counted run is at least 120 s old');
  perform pg_temp.ok(f.next_check_at <= now() + interval '15 minutes', 'the trial is within tick.backoff_max_minutes');
  raise notice 'PASS D14 race: pauses with the call under way';
end $t$;

-- the pause comes after exactly N empty answered runs (N = flag.empty_calls_to_pause), never on runs too young to have answered
do $t$ declare v jsonb; begin
  -- 29 answered empties old enough, plus two young ones: not yet
  perform fx.reset();
  perform fx.call('ai_match', 0, 0); perform fx.call('ai_match', 60, 0);
  perform fx.call('ai_match', 60 * i, 0) from generate_series(2, 30) i;
  perform pg_temp.ok(security.flag_jobs_v1() = '[]'::jsonb and pg_temp.active(), '29 counted empty runs: no pause');
  -- the 30th: paused
  perform fx.call('ai_match', 60 * 31, 0);
  perform pg_temp.ok(security.flag_jobs_v1() = '[{"paused": "coverage-ai-match"}]'::jsonb, '30 counted empty runs: paused');
  -- N follows the setting
  perform fx.reset();
  update pipeline.platform_toolset_settings set value = '10' where key = 'flag.empty_calls_to_pause';
  perform fx.call('ai_match', 60 * i, 0) from generate_series(2, 11) i;
  perform pg_temp.ok(security.flag_jobs_v1() = '[{"paused": "coverage-ai-match"}]'::jsonb, 'N = 10 from the setting');
  update pipeline.platform_toolset_settings set value = '30' where key = 'flag.empty_calls_to_pause';
  -- the window follows its setting: at 30 s the two calls of the last minute count, so 30 calls from 30 s are enough
  perform fx.reset();
  update pipeline.platform_toolset_settings set value = '30' where key = 'flag.answer_wait_seconds';
  perform fx.call('ai_match', 30 + 60 * i, 0) from generate_series(0, 29) i;
  perform pg_temp.ok(security.flag_jobs_v1() = '[{"paused": "coverage-ai-match"}]'::jsonb, 'the answer window follows flag.answer_wait_seconds');
  update pipeline.platform_toolset_settings set value = '120' where key = 'flag.answer_wait_seconds';
  raise notice 'PASS pause after N empty answered runs';
end $t$;

-- no pause when work was found, when a counted run has no answer (timed out) or a failed answer, or for a never-paused mode
do $t$ begin
  perform fx.reset();
  perform fx.call('ai_match', 60 * i, case when i = 17 then 3 else 0 end) from generate_series(2, 40) i;
  perform pg_temp.ok(security.flag_jobs_v1() = '[]'::jsonb and pg_temp.active(), 'one run with work among the last 30: no pause');
  perform fx.reset();
  perform fx.call('ai_match', 60 * i, case when i = 9 then null else 0 end) from generate_series(2, 31) i;
  perform pg_temp.ok(security.flag_jobs_v1() = '[]'::jsonb, 'a counted run with no answer (time-out): not proved empty, no pause');
  perform fx.reset();
  perform fx.call('ai_match', 60 * i, 0, case when i = 9 then 500 else 200 end) from generate_series(2, 31) i;
  perform pg_temp.ok(security.flag_jobs_v1() = '[]'::jsonb, 'a counted run that failed (500): no pause');
  perform fx.reset();
  perform fx.call('openrouter_balance', 60 * i, 0) from generate_series(2, 60) i;
  perform pg_temp.ok(security.flag_jobs_v1() = '[]'::jsonb and (select active from cron.job where jobname = 'openrouter-balance'), 'flag.never_pause_modes: never paused');
  raise notice 'PASS no pause with work, an unanswered or failed run, or a never-paused mode';
end $t$;

-- no permanent pause: the existing re-arm switches the job on when work waits, and at the capped trial time; the guard then waits for 30
-- new empty runs (counted from the release) before it pauses again
do $t$ declare v jsonb; f pipeline.enrichment_flags; begin
  perform fx.reset();
  perform fx.call('ai_match', 60 * i, 0) from generate_series(2, 40) i;
  perform security.flag_jobs_v1();
  perform pg_temp.ok(not pg_temp.active(), 'paused');
  -- nothing waiting, trial not due: stays paused
  perform pg_temp.ok(security.flag_jobs_v1() = '[]'::jsonb and not pg_temp.active(), 'no work and no trial due: stays paused');
  -- work appears (a ready AI match for a published provider): switched on at the next check
  insert into pipeline.coverage_ai_match(provider_id, course_id, state) values ('10000000-0000-4000-8000-000000000001', md5('v1-due-1')::uuid, 'ready');
  v := security.flag_jobs_v1(); f := pg_temp.flag();
  perform pg_temp.ok(v = '[{"trial": "coverage-ai-match"}]'::jsonb and pg_temp.active() and f.state = 'released' and f.released_by = 'flag-recheck', 'work waiting: switched on by the re-arm');
  perform pg_temp.ok(exists (select 1 from pipeline.enrichment_flag_events e where e.flag_id = f.id and e.action = 'released')
                     and exists (select 1 from pipeline.enrichment_flag_events e where e.flag_id = f.id and e.action = 'requeued'), 'release and requeue are recorded');
  -- the 39 empty runs before the release do not count again: not re-paused
  perform pg_temp.ok(security.flag_jobs_v1() = '[]'::jsonb and pg_temp.active(), 'runs before the release are not counted again');
  delete from pipeline.coverage_ai_match;
  raise notice 'PASS no permanent pause (re-arm on waiting work)';
end $t$;
-- the trial at its time, with no work: the job is switched on, and paused again only after 30 fresh empty runs
do $t$ declare f pipeline.enrichment_flags; begin
  perform fx.reset();
  perform fx.call('ai_match', 3600 + 60 * i, 0) from generate_series(2, 40) i;
  perform security.flag_jobs_v1();
  update pipeline.enrichment_flags set next_check_at = now() - interval '1 minute' where entity_key = 'coverage-ai-match';
  perform pg_temp.ok(security.flag_jobs_v1() = '[{"trial": "coverage-ai-match"}]'::jsonb and pg_temp.active(), 'trial due: switched on');
  update pipeline.enrichment_flags set released_at = now() - interval '45 minutes' where entity_key = 'coverage-ai-match';  -- the trial began 45 minutes ago
  perform fx.call('ai_match', 60 * i, 0) from generate_series(0, 31) i;  -- 32 calls since; the two of the last 2 minutes are not counted, 30 are
  perform pg_temp.ok(security.flag_jobs_v1() = '[{"paused": "coverage-ai-match"}]'::jsonb, 'after the trial, 30 fresh empty runs old enough: paused again');
  f := pg_temp.flag();
  perform pg_temp.ok(f.checks = 1 and f.state = 'raised', 're-raised with the check count carried (back-off step)');
  perform pg_temp.ok(exists (select 1 from pipeline.enrichment_flag_events e where e.flag_id = f.id and e.action = 're_raised'), 'the second pause is recorded as re_raised');
  raise notice 'PASS no permanent pause (capped trial) and the back-off steps on';
end $t$;

-- no duplicate processing and no paid AI reads: the guard reads the call log and the answers only; it claims, leases, re-queues or calls
-- nothing on the AI queue, and a running call keeps its lease
do $t$ declare v_before text; v_calls bigint; begin
  perform fx.reset();
  insert into pipeline.coverage_ai_match(provider_id, course_id, state, leased_until) values
    ('10000000-0000-4000-8000-000000000001', md5('v1-due-2')::uuid, 'leased', now() + interval '4 minutes'),   -- taken by the call under way
    ('10000000-0000-4000-8000-0000000000a1', md5('h1-due-1')::uuid, 'ready', null);                            -- hidden provider: not work
  v_before := (select string_agg(row(q.*)::text, '|' order by id) from pipeline.coverage_ai_match q);
  perform fx.call('ai_match', 0, null);
  perform fx.call('ai_match', 60 * i, 0) from generate_series(1, 40) i;
  v_calls := (select count(*) from pipeline.edge_request_log);
  perform security.flag_jobs_v1();
  perform pg_temp.ok(not pg_temp.active(), 'paused with a call under way');
  perform pg_temp.ok((select string_agg(row(q.*)::text, '|' order by id) from pipeline.coverage_ai_match q) = v_before, 'the AI queue is untouched (the lease of the call under way is kept)');
  perform pg_temp.ok((select count(*) from pipeline.edge_request_log) = v_calls, 'the guard makes no call (no AI read)');
  -- while paused, nothing is waiting (the hidden item is not work; the leased one is taken): it stays paused, no call is made
  perform pg_temp.ok(security.flag_jobs_v1() = '[]'::jsonb and not pg_temp.active() and (select count(*) from pipeline.edge_request_log) = v_calls, 'paused, not woken by a hidden or leased item');
  -- the lease runs out without an answer: the item is waiting again and the job is switched on to take it once
  update pipeline.coverage_ai_match set leased_until = now() - interval '1 second' where state = 'leased';
  perform pg_temp.ok(security.flag_jobs_v1() = '[{"trial": "coverage-ai-match"}]'::jsonb, 'an expired lease is work: switched on');
  delete from pipeline.coverage_ai_match;
  raise notice 'PASS no duplicate processing, no AI read by the guard';
end $t$;

-- Health and scheduled-job reporting: a run cancelled as the guard pauses its job is "paused", not "failed" (SS-004); a time-out stays failed
do $t$ declare v_at timestamptz; begin
  perform fx.reset();
  perform fx.call('ai_match', 60 * i, 0) from generate_series(2, 40) i;
  perform security.flag_jobs_v1();
  v_at := (select max(e.at) from pipeline.enrichment_flag_events e where e.action in ('raised', 're_raised'));
  perform pg_temp.ok(security.cron_run_outcome_v1('coverage-ai-match', 'failed', 'job canceled', v_at + interval '2 seconds') = 'paused', 'a run cancelled by the pause is paused');
  perform pg_temp.ok(security.cron_run_outcome_v1('coverage-ai-match', 'failed', 'ERROR:  canceling statement due to statement timeout', v_at + interval '2 seconds') = 'failed', 'a time-out is still a failure');
  perform pg_temp.ok(security.cron_run_outcome_v1('coverage-ai-match', 'failed', 'job canceled', v_at + interval '10 minutes') = 'failed', 'a cancel not at a pause is still a failure');
  -- the watchdog shows the guard's pause as the waste guard's, not a person's
  perform fx.reset();
  raise notice 'PASS reporting: paused runs are paused, failures stay failures';
end $t$;

-- ------------------------------------------------------------------ course page reading: counts equal the reader's selection
do $t$ declare v jsonb; v_e int; v_since timestamptz; begin
  create temp table e_read as select * from security.coverage_read_eligible_v1();
  v_e := (select count(*) from e_read);
  perform pg_temp.ok(v_e = (select eligible from fx.read_expect), 'eligible pages: 31, got ' || v_e);
  perform pg_temp.ok(not exists (select 1 from e_read where provider_id = '10000000-0000-4000-8000-0000000000a1'), 'no hidden-provider page');
  -- the health check's rule
  v := security.platform_health_check_v1(true) -> 0;
  perform pg_temp.ok((v->>'waiting')::int = v_e, 'health check waiting = eligible');
  v_since := greatest((select max(read_at) from pipeline.coverage_course_pages), (select min(due_at) from e_read));
  perform pg_temp.ok((v->>'since')::timestamptz = v_since and v_since > now() - interval '2 hours', 'the stall runs from the oldest page the reader can take (1 hour), not a hidden one');
  -- the watchdog
  perform security.queue_watch_run_v1(false);
  perform pg_temp.ok((select pending from pipeline.queue_watch_state where key = 'course_page_read') = v_e, 'watchdog waiting = eligible');
  raise notice 'PASS read counts: health = watchdog = eligible (31)';
end $t$;
-- the reader, called until it takes nothing, takes exactly those pages
do $t$ declare v jsonb; v_taken uuid[] := '{}'; v_calls int := 0; begin
  loop
    v := public.svc_coverage_read_next(200); v_calls := v_calls + 1;
    exit when jsonb_array_length(v) = 0 or v_calls > 10;
    v_taken := v_taken || array(select (x->>'course_id')::uuid from jsonb_array_elements(v) x);
  end loop;
  perform pg_temp.ok(cardinality(v_taken) = (select count(*) from e_read) and cardinality(v_taken) = (select count(distinct t) from unnest(v_taken) t), 'the reader took each eligible page once');
  perform pg_temp.ok((select array_agg(course_id order by course_id) from e_read) = (select array_agg(t order by t) from unnest(v_taken) t), 'the reader took exactly the eligible pages');
  perform pg_temp.ok(v_calls = 3, 'in two calls (20 per provider per call) and an empty third');
  -- everything left is skipped by the reader: hidden, leased (now all taken), spent, not due, mismatch. Nothing waits, so nothing stalls
  perform pg_temp.ok((select count(*) from security.coverage_read_eligible_v1()) = 0 and (security.platform_health_check_v1(true) -> 0 ->> 'waiting')::int = 0, 'after the reader: 0 waiting');
  perform security.queue_watch_run_v1(false);
  perform pg_temp.ok((select pending from pipeline.queue_watch_state where key = 'course_page_read') = 0
                     and (select state from pipeline.queue_watch_state where key = 'course_page_read') <> 'stuck'
                     and not exists (select 1 from pipeline.platform_issues where check_key = 'queue_watch:course_page_read' and resolved_at is null), 'watchdog: not stuck, issue closed (10 hidden pages left)');
  raise notice 'PASS read: the reader takes exactly what is counted; hidden pages alone are not a stall';
end $t$;

-- ------------------------------------------------------------------ course page search: counts equal the picker's selection; the cap
do $t$ declare v_e int; v_r text; begin
  create temp table e_search as select * from security.course_link_search_eligible_v1();
  v_e := (select count(*) from e_search);
  perform pg_temp.ok(v_e = (select eligible from fx.search_expect), 'eligible searches: 12, got ' || v_e);
  -- under the cap: no cap reason, the watchdog counts the same 12
  perform pg_temp.ok(security.course_link_search_cap_reason_v1() is null, 'room left: no cap reason');
  perform security.queue_watch_run_v1(false);
  perform pg_temp.ok((select pending from pipeline.queue_watch_state where key = 'course_page_search') = v_e, 'watchdog waiting = eligible');
  perform pg_temp.ok((select state from pipeline.queue_watch_state where key = 'course_page_search') <> 'capped', 'not capped while there is room');
  -- the day's cap reached (5 picked today, cap 5), no person's task waiting: "Paused: daily cap", no alert, no health issue
  update pipeline.platform_toolset_settings set value = '5' where key = 'search.daily_picked_cap';
  v_r := security.course_link_search_cap_reason_v1();
  perform pg_temp.ok(v_r like 'Paused: daily cap. 5 of 5 courses picked today (setting search.daily_picked_cap, counted per UTC day); picking resumes at %', 'cap reason: ' || coalesce(v_r, 'null'));
  perform pg_temp.ok(public.svc_course_link_search_next(200) = '[]'::jsonb, 'the picker agrees: nothing picked at the cap');
  perform security.queue_watch_run_v1(false);
  perform pg_temp.ok((select state from pipeline.queue_watch_state where key = 'course_page_search') = 'capped'
                     and (select reason from pipeline.queue_watch_state where key = 'course_page_search') = v_r
                     and (select pending from pipeline.queue_watch_state where key = 'course_page_search') = v_e, 'watchdog: capped, with the reason and the 12 waiting');
  perform pg_temp.ok(not exists (select 1 from pipeline.queue_watch_alerts where key = 'course_page_search' and state = 'capped'), 'no alert for a cap pause');
  perform pg_temp.ok(not exists (select 1 from pipeline.platform_issues where check_key = 'queue_watch:course_page_search' and resolved_at is null), 'the stuck issue is closed');
  perform pg_temp.ok((select (detail->>'paused_daily_cap')::int from pipeline.platform_health_checks where key = 'queue_watch') = 1
                     and (select (detail->>'stuck')::int from pipeline.platform_health_checks where key = 'queue_watch') = 0, 'health detail: 1 paused by its daily cap, 0 stuck');
  perform pg_temp.ok(exists (select 1 from pipeline.queue_watch_events where key = 'course_page_search' and to_state = 'capped'), 'the change of state is recorded');
  -- over the cap the picker still takes a person's running task: then it is not a pause, and that is what the picker takes
  update fx.course set person_task = true where course_id = md5('s8-person')::uuid;
  perform pg_temp.ok(security.course_link_search_cap_reason_v1() is null, 'a person''s task waiting: not paused');
  perform pg_temp.ok((select array_agg((x->>'course_id')::uuid) from jsonb_array_elements(public.svc_course_link_search_next(200)) x) = array[md5('s8-person')::uuid], 'the picker takes only the person''s task');
  perform pg_temp.ok(security.course_link_search_cap_reason_v1() is not null, 'that task taken: paused again');
  update fx.course set person_task = false where course_id = md5('s8-person')::uuid;
  update pipeline.platform_toolset_settings set value = '100000' where key = 'search.daily_picked_cap';
  raise notice 'PASS search counts and the daily cap reported as a pause';
end $t$;
-- the picker, called until it takes nothing, takes exactly the counted searches (the person's task above was the only extra one)
do $t$ declare v jsonb; v_taken uuid[] := '{}'; v_calls int := 0; begin
  loop
    v := public.svc_course_link_search_next(200); v_calls := v_calls + 1;
    exit when jsonb_array_length(v) = 0 or v_calls > 10;
    v_taken := v_taken || array(select (x->>'course_id')::uuid from jsonb_array_elements(v) x);
  end loop;
  perform pg_temp.ok((select array_agg(course_id order by course_id) from e_search where course_id <> md5('s8-person')::uuid)
                     = (select array_agg(t order by t) from unnest(v_taken) t), 'the picker took exactly the eligible searches');
  perform pg_temp.ok((select count(*) from security.course_link_search_eligible_v1()) = 0, 'nothing eligible left');
  perform security.queue_watch_run_v1(false);
  perform pg_temp.ok((select pending from pipeline.queue_watch_state where key = 'course_page_search') = 0, 'watchdog: 0 waiting (20 skipped searches left queued)');
  perform pg_temp.ok((select count(*) from pipeline.course_link_search where state = 'queued') = 20, '20 searches the picker skips are still queued');
  raise notice 'PASS search: the picker takes exactly what is counted';
end $t$;
