-- Guards: CF-247 Operations load speed (Platform Admin P1, 10 Nov 2026): the scheduler history, intake events and control-log rows the before/after comparison reads (fixtures only).
-- jobs: the lane jobs below are scheduled; integration-validate is not scheduled at all; fee-period-settle is scheduled and paused with no run.
insert into cron.job(jobname, schedule, active) values
  ('consumer-api-guard', '* * * * *', true), ('first-run-verify', '* * * * *', true), ('intake-dates-apply', '26 * * * *', true), ('calendar-reread', '13 * * * *', true),
  ('process-results', '5 * * * *', true), ('fee-reader', '* * * * *', true), ('fee-period-settle', '7 3 * * *', false), ('central-ai', '*/5 * * * *', true), ('provider-facts', '*/15 * * * *', true),
  ('lane-funnel', '* * * * *', true)
on conflict (jobname) do nothing;
-- consumer-api-guard: every 30 minutes for 60 hours; one failed 3 hours ago, one failed 36 hours ago (inside the 48 hour history, outside the 24 hour window), the rest succeeded
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message)
  select j.jobid, now() - make_interval(mins => g * 30), now() - make_interval(mins => g * 30) + interval '3 seconds',
         case when g = 6 or g = 72 then 'failed' else 'succeeded' end, case when g = 6 then 'recent failure' when g = 72 then 'older failure' else 'ok' end
    from cron.job j cross join generate_series(1, 120) g where j.jobname = 'consumer-api-guard';
-- first-run-verify: succeeded runs, and one running now (2 minutes ago, no end)
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message)
  select j.jobid, now() - make_interval(mins => g * 10), now() - make_interval(mins => g * 10) + interval '1 second', 'succeeded', 'ok' from cron.job j cross join generate_series(1, 20) g where j.jobname = 'first-run-verify';
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message, job_pid) select j.jobid, now() - interval '2 minutes', null, 'running', null, 4242 from cron.job j where j.jobname = 'first-run-verify';
-- intake-dates-apply: only 40 hours ago (inside the history, outside the 24 hour window); calendar-reread: only 60 hours ago (outside the history; the recovery read keeps it)
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message) select jobid, now() - interval '40 hours', now() - interval '40 hours' + interval '5 seconds', 'succeeded', 'old but in history' from cron.job where jobname = 'intake-dates-apply';
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message) select jobid, now() - interval '60 hours', now() - interval '60 hours' + interval '5 seconds', 'failed', 'older than the history' from cron.job where jobname = 'calendar-reread';
-- fee-reader: a run that is starting, a long message on the latest run (cut at 240), a failure
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message) select jobid, now() - interval '9 minutes', now() - interval '8 minutes', 'failed', 'boom' from cron.job where jobname = 'fee-reader';
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message) select jobid, now() - interval '1 minute', null, 'starting', repeat('long message ', 40) from cron.job where jobname = 'fee-reader';
insert into cron.job_run_details(jobid, start_time, end_time, status, return_message) select jobid, now() - interval '30 minutes', now() - interval '29 minutes', 'succeeded', 'ok' from cron.job where jobname in ('process-results', 'central-ai', 'provider-facts');

-- repeats: eight intake rows decided twice, one of each kind of repeat (times chosen so each window holds only its own control-log row or setting change)
insert into pipeline.course_intake_date_events(intake_id, run_at, outcome, failure_class, deterministic, calendar_set, page_quote, rule, reader, periods, evidence_year, next_revisit_at)
select u.id, u.run_at, 'skipped', 'X', true, u.cs, u.q, 'r1', u.rd, '[]'::jsonb, 2026, u.rev from (values
  ('00000000-0000-0000-0000-000000000001'::uuid, now() - interval '4 hours',  'cs', 'q',  'rd1', null::timestamptz),   -- 1 earlier decision of the pair that is a confirmed repeat
  ('00000000-0000-0000-0000-000000000001'::uuid, now() - interval '2 hours',  'cs', 'q',  'rd1', null),
  ('00000000-0000-0000-0000-000000000002'::uuid, now() - interval '4 hours',  'cs', 'q',  'rd1', null),                -- 2 page wording differs: source update
  ('00000000-0000-0000-0000-000000000002'::uuid, now() - interval '2 hours',  'cs', 'q2', 'rd1', null),
  ('00000000-0000-0000-0000-000000000003'::uuid, now() - interval '4 hours',  'cs', 'q',  'rd1', null),                -- 3 reader differs: reader revision
  ('00000000-0000-0000-0000-000000000003'::uuid, now() - interval '2 hours',  'cs', 'q',  'rd2', null),
  ('00000000-0000-0000-0000-000000000004'::uuid, now() - interval '14 hours', 'cs', 'q',  'rd1', null),                -- 4 a control-log row between: setting change
  ('00000000-0000-0000-0000-000000000004'::uuid, now() - interval '12 hours', 'cs', 'q',  'rd1', null),
  ('00000000-0000-0000-0000-000000000005'::uuid, now() - interval '20 hours', 'cs', 'q',  'rd1', null),               -- 5 a setting's own changed time between: setting change
  ('00000000-0000-0000-0000-000000000005'::uuid, now() - interval '18 hours', 'cs', 'q',  'rd1', null),
  ('00000000-0000-0000-0000-000000000006'::uuid, now() - interval '25 hours', 'cs', 'q',  'rd1', null),               -- 6 a release that changed an intake function between: reader revision
  ('00000000-0000-0000-0000-000000000006'::uuid, now() - interval '23 hours', 'cs', 'q',  'rd1', null),
  ('00000000-0000-0000-0000-000000000007'::uuid, now() - interval '8 hours',  null, 'q',  'rd1', null),              -- 7 no calendar set on either decision: unverified
  ('00000000-0000-0000-0000-000000000007'::uuid, now() - interval '6 hours',  null, 'q',  'rd1', null),
  ('00000000-0000-0000-0000-000000000008'::uuid, now() - interval '9 hours',  'cs', 'q',  'rd1', now() - interval '8 hours'), -- 8 its own revisit time had passed: scheduled revisit
  ('00000000-0000-0000-0000-000000000008'::uuid, now() - interval '7 hours',  'cs', 'q',  'rd1', null)
) u(id, run_at, cs, q, rd, rev);
insert into pipeline.admin_control_events(area, action, target, created_at) values ('settings', 'setting', 'pipeline.intake_dates.apply_enabled', now() - interval '13 hours'), ('settings', 'setting', 'pipeline.unrelated.key', now() - interval '3 hours');
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, unit, sort, section, updated_at) values ('pipeline', 'run_now.fixture_marker', 'fixture', 'number', to_jsonb(1), 'x', 1, 'Fixture', now() - interval '19 hours')
  on conflict (toolset_key, key) do nothing;
insert into pipeline.integration_deploy_checks(since, result) values (now() - interval '24 hours', jsonb_build_object('functions', jsonb_build_array(jsonb_build_object('function', 'security.intake_dates_plan_v3')))),
  (now() - interval '10 hours', jsonb_build_object('functions', jsonb_build_array(jsonb_build_object('function', 'security.unrelated_fn')))), (now() - interval '5 minutes', jsonb_build_object('note', 'no functions recorded'));

-- recovery: the filled values and dates of the one fixture university, a calendar refresh request and the reader states
insert into pipeline.course_intake_date_events(provider_id, run_at, outcome, rule, after_value, before_value, start_precision, publication_state)
  values ('00000000-0000-0000-0000-0000000000a1', now() - interval '1 day', 'filled', 'approved-calendar', '{"year": 2027, "start_date": "2027-02-01", "application_deadline": "2026-12-01"}', '{"year": 2027}', 'day', 'published'),
         ('00000000-0000-0000-0000-0000000000a1', now() - interval '2 days', 'filled', 'approved-calendar', '{"year": 2027, "start_date": "2027-07-01"}', '{"year": 2027}', 'day', null);
insert into pipeline.course_intake_dates(provider_id, intake_id, failure_class, next_action, deterministic, reason, next_revisit_at, revisit_trigger, outcome, publication_state)
  values ('00000000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'stale_calendar_edition', 'wait', true, 'stale', now() + interval '3 days', 'calendar', 'skipped', null), ('00000000-0000-0000-0000-0000000000a1', gen_random_uuid(), null, 'complete', false, null, null, null, 'filled', 'published');
insert into pipeline.calendar_refresh_requests(provider_id, url, status, credit_estimate, credits_used, reason) values ('00000000-0000-0000-0000-0000000000a1', 'https://example.edu/cal', 'done', 3, 2, 'fixture');
insert into pipeline.calendar_reread_state(reader_version, state) values ('v1', 'done'), ('v1', 'queued'), (null, 'queued');
