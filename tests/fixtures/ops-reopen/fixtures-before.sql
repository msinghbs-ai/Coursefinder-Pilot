-- The IQ-00067 sequence of 3 Nov 2026 on the live definitions (before 20261104100000): failures to 16:33, closed with verified evidence at 16:44,
-- every run after succeeded, the health issue still open on its 24-hour count; integration-validate reopens it at 16:51 and the controller
-- blocks it as needs_release. Times are relative to now: close = now - 60 minutes.
\set ON_ERROR_STOP 1
select fx.run('coverage-admit', 'failed', E'ERROR:  this course''s page was set by hand on the course record\nCONTEXT:  PL/pgSQL function layer4_course_link_apply_impl(uuid,uuid,jsonb,text) line 17 at RAISE', now() - make_interval(mins => 71 + 10 * g)) from generate_series(0, 17) g;
select fx.run('coverage-admit', 'succeeded', '1 row', now() - make_interval(mins => 61 - 10 * g)) from generate_series(0, 5) g;
select security.integration_issue_upsert_v1('{"fingerprint": "job_failed:coverage-admit", "title": "Scheduled job \"coverage-admit\" failed", "failure": "failed", "expected": "runs succeed", "validation_layer": "V4", "severity": "P1", "source": "platform-health"}');
select security.integration_issue_close_v1((fx.issue('job_failed:coverage-admit')).id, 'Integration Controller (Claude)', '{"outcome": "passed", "evidence": "v2.15.428 deployed; every coverage-admit run since 16:43 succeeded", "reference": "IQ-00067"}');
update pipeline.integration_issues set closed_at = now() - interval '60 minutes' where fingerprint = 'job_failed:coverage-admit';
update pipeline.integration_issue_events set at = now() - interval '60 minutes' where kind = 'closed' and issue_id = (fx.issue('job_failed:coverage-admit')).id;
insert into pipeline.platform_issues(check_key, severity, area, title, detail, first_seen, last_seen)
values ('cron:failed:coverage-admit', 'critical', 'scheduled jobs', 'Scheduled job "coverage-admit" failed 0 of 6 run(s) in the last hour; 17 failure(s) in the last 24 hours', '{}', now() - interval '4 hours', now() - interval '5 minutes');
select security.integration_validate_v1();
select fx.ok((fx.issue('job_failed:coverage-admit')).status = 'reopened' and (fx.issue('job_failed:coverage-admit')).regression_count = 1,
  'before: the live definitions reopen IQ-00067 as a regression on failures from before its close (as at 16:51)');
select fx.only(array['job_failed:coverage-admit']); select security.ops_controller_tick_v1();
select fx.ok((fx.issue('job_failed:coverage-admit')).ops_state = 'needs_release' and (fx.issue('job_failed:coverage-admit')).diagnosis->>'root_cause' = 'regression_after_close',
  'before: the controller reads it as recurred and blocks it as needs_release (fix_in_release)');
-- 18:15 the Integration Controller closes it again; the health issue is still open; 18:21 integration-validate reopens it again (regression 2)
select security.integration_issue_close_v1((fx.issue('job_failed:coverage-admit')).id, 'Integration Controller (Claude)', '{"outcome": "passed", "evidence": "re-closed: every coverage-admit run since 16:43 succeeded", "reference": "IQ-00067"}');
update pipeline.integration_issues set closed_at = now() - interval '9 minutes' where fingerprint = 'job_failed:coverage-admit';
update pipeline.integration_issue_events set at = now() - interval '9 minutes' where kind = 'closed' and issue_id = (fx.issue('job_failed:coverage-admit')).id and at > now() - interval '1 minute';
select fx.run('coverage-admit', 'succeeded', '1 row', now() - interval '3 minutes');
select security.integration_validate_v1();
select fx.ok((fx.issue('job_failed:coverage-admit')).status = 'reopened' and (fx.issue('job_failed:coverage-admit')).regression_count = 2
  and (fx.issue('job_failed:coverage-admit')).next_action_at > now() + interval '5 hours', 'before: reopened again (as at 18:21), its next look hours away');
