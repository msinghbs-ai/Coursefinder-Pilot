-- Guards: Platform Admin decision 5 Nov 2026 19:14 §8 (bounded performance): every Automation Progress read at production volume and beyond.
-- Production on 5 Nov 2026 19:20 AEDT: 1,612 decision rows (growing about 4,800 a day), 10,270 intake states, 124,226 pg_cron run rows, 300
-- integration issues. This copy holds 30 days of hourly 200-row runs (144,000 decision rows over 50 providers), 12,000 intake states, 130,000 pg_cron
-- rows (most of other jobs) and 300 issues, then times each view as the authenticated Operations reader. Run on a copy (benchmark.sh).
\set ON_ERROR_STOP on
set client_min_messages = warning;
set session_replication_role = replica;  -- bulk load only: the classes are written directly, as the trigger would
insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, run_at, outcome, reason, failure_class, deterministic, page_quote, next_revisit_at, publication_state, calendar_set, reader)
select md5('bi' || (g % 12000))::uuid, md5('bc' || (g % 6000))::uuid, case when g % 50 < 14 then (select fx.id('p:' || k) from fx.provider_keys order by courses desc offset (g % 14) limit 1) else md5('bp' || (g % 50))::uuid end,
       date_trunc('hour', now()) - make_interval(hours => g / 200) + interval '26 minutes' - interval '1 hour',
       case when g % 40 = 0 then 'filled' else 'skipped' end, case when g % 40 = 0 then null else 'page not proved to be the course''s own (E16 refuse)' end,
       case when g % 40 = 0 then null when g % 3 = 0 then 'course_identity_unresolved' else 'no_matching_commencement_period' end, g % 3 <> 0, 'Intakes: February',
       case when g % 3 = 0 then now() + interval '7 days' end, case when g % 40 = 0 then 'published' end, 'set:' || (g % 50), 'calendar-v2.1'
  from generate_series(1, 144000) g;
insert into pipeline.course_intake_dates(intake_id, course_id, provider_id, outcome, reason, applied_at, failure_class, deterministic, next_revisit_at, next_action)
select md5('bi' || g)::uuid, md5('bc' || (g % 6000))::uuid, md5('bp' || (g % 50))::uuid, 'skipped', 'page not proved to be the course''s own (E16 refuse)', now() - make_interval(mins => g),
       'course_identity_unresolved', false, now() + make_interval(hours => g % 300), 'course_identity_unresolved'
  from generate_series(1, 12000) g;
insert into cron.job_run_details(jobid, status, start_time, end_time)
select case when g % 720 = 0 then (select jobid from cron.job where jobname = 'intake-dates-apply') else 1000 + g % 150 end, 'succeeded',
       now() - make_interval(secs => (130000 - g) * 6), now() - make_interval(secs => (130000 - g) * 6 - 2) from generate_series(1, 130000) g;
insert into pipeline.integration_issues(fingerprint, title, layer, failure, expected, detection_source, severity, workstream, course_ids)
select 'bench:' || g, 'bench', 'Platform', 'bench', 'bench', 'bench', 'P2', 'A8', array[md5('bc' || g)::uuid] from generate_series(1, 300) g;
set session_replication_role = origin;
analyze;
create temp table bench(view text, ms numeric);
do $$
declare t timestamptz; v text; a jsonb;
begin
  foreach v in array array['status', 'latest', '24h', '7d', '30d', 'runs30d', 'failures', 'observations'] loop
    a := case when v in ('latest', '24h', '7d', '30d') then jsonb_build_object('window', v) when v = 'runs30d' then '{"window":"30d"}' else '{}' end;
    t := clock_timestamp();
    perform fx.v(3, case when v in ('latest', '24h', '7d', '30d') then 'window' when v = 'runs30d' then 'runs' else v end, a);
    insert into bench values (v, round(extract(epoch from clock_timestamp() - t) * 1000, 1));
  end loop;
  t := clock_timestamp(); perform security.progress_read_v1(); insert into bench values ('observer (progress_read_v1, all chains)', round(extract(epoch from clock_timestamp() - t) * 1000, 1));
end $$;
select 'BENCH ' || view || ' ' || ms || ' ms' from bench order by view;
-- bounded: every read under 3 s at this volume (the bridge's own statement time-out is 20 s)
select case when max(ms) < 3000 then 'PASS benchmark: every view under 3 s at 144,000 decision rows (slowest ' || max(ms) || ' ms)' else 'FAIL benchmark slowest ' || max(ms) || ' ms' end from bench;
