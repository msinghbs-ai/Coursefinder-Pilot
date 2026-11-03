-- CF-247 P0 workstream A: dry run of the controller on the live integration queue (snapshot read 3 Nov 2026 15:56 AEDT, each row checked against
-- its live md5 by dryrun.sh) and the live scheduler job map (16:07 AEDT, md5 checked). Scratch PostgreSQL only. It loads the
-- 68 issues as they were, the 157 jobs with the functions and worker modes their commands name, the runs of coverage-admit observed live
-- (succeeded every 10 minutes to 13:43, failed every run from 13:53 with the manual-lock refusal) and of search-refresh-requested (no failure
-- in the 6 hours read), and the release clock (each migration's apply time, from pipeline.component_register). It then runs the controller three
-- times, 31 minutes apart, and prints issue -> end state -> evidence for the 48-issue cohort. Nothing here touches production.
\set ON_ERROR_STOP 1
create temp table snap(j jsonb);
\copy snap(j) from 'tests/fixtures/ops-controller/live/issues-20261103-1556.jsonl' with (format csv, quote e'\x01', delimiter e'\x02')
create temp table jobs(line text);
\copy jobs(line) from 'tests/fixtures/ops-controller/live/cron-jobs-20261103-1607.txt'

-- the functions the issue texts and the job commands name (they exist live)
do $d$ declare f text; begin
  for f in select distinct x from (
      select unnest(string_to_array(split_part(line, '|', 3), ',')) x from jobs
      union select unnest(array['course_page_check_v1', 'svc_enrich_ai_record', 'svc_provider_description_next', 'layer4_course_link_apply_impl', 'course_url_fill_v1',
                                'coverage_apply_course_v1', 'flag_jobs_v1', 'layer4_tuition_apply_impl', 'svc_coverage_tuition_handoff_record'])) y where x <> '' loop
    if not exists (select 1 from pg_proc where proname = f) then execute format('create function security.%I() returns void language sql as $f$ select $f$', f); end if;
  end loop;
end $d$;
truncate cron.job cascade;
insert into cron.job(jobname, schedule, command, active)
select split_part(line, '|', 1), '* * * * *',
       'select ' || coalesce((select string_agg('security.' || x || '()', ', ') from unnest(string_to_array(nullif(split_part(line, '|', 3), ''), ',')) x), '1')
         || coalesce(' -- ''' || nullif(split_part(line, '|', 4), '') || '''', ''),
       split_part(line, '|', 2)::boolean
  from jobs;
select setval('cron.job_jobid_seq', (select max(jobid) from cron.job));

-- the issues as they were at 15:56 AEDT
insert into pipeline.integration_issues(id, fingerprint, title, layer, subsystem, failure, expected, detection_source, validation_layer, evidence, root_cause_class, severity, workstream,
       status, retry_count, regression_count, detected_at, last_observed_at, condition_cleared_at, closed_at, verification_outcome)
select (j->>'id')::bigint, j->>'fp', j->>'title', 'Platform', nullif(j->>'sub', ''), j->>'fail', 'not stated', j->>'src', j->>'vl',
       case when j->>'msg' <> '' then jsonb_build_object('message', j->>'msg') else '{}'::jsonb end, j->>'rcc', j->>'sev', 'A10', j->>'st',
       (j->>'rc')::int, (j->>'reg')::int, (j->>'det' || '+00')::timestamptz, (j->>'obs' || '+00')::timestamptz, (j->>'clr' || '+00')::timestamptz, (j->>'cls' || '+00')::timestamptz,
       case when j->>'st' = 'closed' then 'passed' end
  from snap;
select setval('pipeline.integration_issues_id_seq', (select max(id) from pipeline.integration_issues));

-- the job runs observed live (UTC): coverage-admit succeeded to 02:43 and failed every run from 02:53; search-refresh-requested no failure
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from cron.job where jobname = 'coverage-admit'), 'succeeded', '1 row', t, t + interval '30 seconds'
  from generate_series('2026-11-02 23:53:00+00'::timestamptz, '2026-11-03 02:43:00+00', interval '10 minutes') t;
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from cron.job where jobname = 'coverage-admit'), 'failed',
       E'ERROR:  this course''s page was set by hand on the course record: change it there (course detail, official page), or keep the page we hold\nCONTEXT:  PL/pgSQL function layer4_course_link_apply_impl(uuid,uuid,jsonb,text) line 17 at RAISE',
       t, t + interval '30 seconds' from generate_series('2026-11-03 02:53:00+00'::timestamptz, '2026-11-03 04:43:00+00', interval '10 minutes') t;
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from cron.job where jobname = 'search-refresh-requested'), 'succeeded', '1 row', t, t + interval '20 seconds'
  from generate_series('2026-11-02 22:56:00+00'::timestamptz, '2026-11-03 04:46:00+00', interval '10 minutes') t;
-- the release clock (first component registered by each migration, read live 15:55 AEDT)
insert into pipeline.component_register(kind, name, layer, purpose, introduced_in, registered_at) values
 ('table', 'dry.20261103230000', 'Platform', 'release clock', '20261103230000', '2026-11-03 03:35:32+00'),
 ('table', 'dry.20261103210000', 'Platform', 'release clock', '20261103210000', '2026-11-03 03:07:15+00'),
 ('table', 'dry.20261103200000', 'Platform', 'release clock', '20261103200000', '2026-11-03 02:39:02+00'),
 ('table', 'dry.20261103190000', 'Platform', 'release clock', '20261103190000', '2026-11-03 02:38:56+00'),
 ('table', 'dry.20261103160000', 'Platform', 'release clock', '20261103160000', '2026-11-03 01:30:30+00'),
 ('table', 'dry.20261103150000', 'Platform', 'release clock', '20261103150000', '2026-11-03 00:39:51+00'),
 ('table', 'dry.20261103140000', 'Platform', 'release clock', '20261103140000', '2026-11-03 00:17:04+00')
on conflict do nothing;
-- the migration's cohort insert, as it runs against the live queue (the migration ran before the issues were loaded here)
insert into pipeline.ops_baseline_cohort(issue_id, cohort, status_at_baseline, captured_at)
select i.id, 'p0-2026-11-03-detected-48', 'detected', '2026-11-03 04:41:00+00'::timestamptz from pipeline.integration_issues i
 where i.id = any (array[3, 4, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 24, 25, 29, 30, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 45, 46, 47, 49,
                         50, 51, 52, 54, 56, 57, 58, 59, 61, 65, 67, 68, 69]::bigint[]) on conflict do nothing;
create or replace function pg_temp.age(p_min int) returns void language plpgsql as $f$
declare d interval := make_interval(mins => p_min);
begin
  update pipeline.ops_remedy_runs set started_at = started_at - d, finished_at = finished_at - d;
  update pipeline.integration_issues set next_action_at = next_action_at - d;
  update pipeline.ops_checkpoints set at = at - d;
end $f$;

\echo run 1
select security.ops_controller_tick_v1() - 'ms';
select pg_temp.age(31);
\echo run 2 (31 minutes later)
select security.ops_controller_tick_v1() - 'ms';
select pg_temp.age(31);
\echo run 3 (62 minutes later)
select security.ops_controller_tick_v1() - 'ms';

\echo cohort by end state after three runs (one hour, as the snapshot stood)
select security.ops_reconciliation_v1('p0-2026-11-03-detected-48')->'by_end_state';
\echo PROJECTION (not live): the conditions already clear stay clear and nothing recurs for 7 more hours; two more runs
update pipeline.integration_issues set condition_cleared_at = condition_cleared_at - interval '7 hours', last_observed_at = last_observed_at - interval '7 hours'
 where status <> 'closed' and condition_cleared_at is not null and last_observed_at <= condition_cleared_at;
select pg_temp.age(420);
select security.ops_controller_tick_v1() - 'ms';
select pg_temp.age(31);
select security.ops_controller_tick_v1() - 'ms';

\echo correlated groups with more than one open issue
select g->>'key' key, g->>'strength' strength, g->>'owner' owner, g->>'open' open, g->'issues' issues from jsonb_array_elements(security.ops_correlation_groups_v1()) g where (g->>'open')::int > 1;
\echo cohort by end state
select security.ops_reconciliation_v1('p0-2026-11-03-detected-48')->'by_end_state';
\echo cohort: issue -> end state -> evidence
\pset format unaligned
\pset fieldsep ' | '
select x->>'issue' issue, x->>'end_state' end_state, x->>'root_cause' root_cause, x->>'confidence' conf, coalesce(x->>'superseded_by', '') superseded_by,
       coalesce(x->'blocked'->>'kind', '') blocked, left(coalesce(x->'blocked'->>'required', x->>'verification', ''), 110) evidence
  from jsonb_array_elements(security.ops_reconciliation_v1('p0-2026-11-03-detected-48')->'issues') x;
\echo IQ-00067 diagnosis
select jsonb_pretty(diagnosis - 'subject' - 'group') from pipeline.integration_issues where id = 67;
\echo all open issues by root cause
select diagnosis->>'root_cause' rc, count(*) from pipeline.integration_issues where status <> 'closed' group by 1 order by 2 desc;
