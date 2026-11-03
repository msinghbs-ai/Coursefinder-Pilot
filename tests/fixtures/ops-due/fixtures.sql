-- After 20261104130000: the same position (due a fraction of a second after the run's start, within its minute) is verified and closed.
\set ON_ERROR_STOP 1
select pg_sleep(61 - extract(second from clock_timestamp())) where extract(second from clock_timestamp()) > 50;
update pipeline.integration_issues set next_action_at = clock_timestamp() + interval '2 seconds' where fingerprint = 'job_failed:coverage-admit';
select fx.only(array['job_failed:coverage-admit']); select security.ops_controller_tick_v1();
select fx.ok((fx.issue('job_failed:coverage-admit')).status = 'closed' and (fx.issue('job_failed:coverage-admit')).verified_by = 'ops-controller'
  and (fx.issue('job_failed:coverage-admit')).verification_evidence->>'evidence' like '%nothing observed since the close%'
  and (select result from pipeline.ops_remedy_runs where remedy_code = 'reclose_stale_reopen') = 'verified',
  'D1 IQ-00067 sequence: due within the run''s minute, verified and closed again with its evidence');
-- a verification due in a later minute waits, and the run says so
select security.integration_issue_upsert_v1('{"fingerprint": "health:queue_watch:fx_due", "title": "fx: stuck", "failure": "stuck", "expected": "moves", "validation_layer": "V4", "severity": "P2"}');
update pipeline.integration_issues set condition_cleared_at = now() - interval '8 hours', last_observed_at = now() - interval '9 hours' where fingerprint = 'health:queue_watch:fx_due';
select fx.only(array['health:queue_watch:fx_due']); select security.ops_controller_tick_v1();
update pipeline.ops_remedy_runs set finished_at = finished_at - interval '1 minute' where remedy_code = 'confirm_condition_cleared';
update pipeline.integration_issues set next_action_at = date_trunc('minute', now()) + interval '1 minute' where fingerprint = 'health:queue_watch:fx_due';
select fx.only(array['health:queue_watch:fx_due']);
select fx.ok((security.ops_controller_tick_v1()->>'not_due')::int = 1 and (fx.issue('health:queue_watch:fx_due')).status <> 'closed',
  'D2 due in a later minute: not verified, and counted as not_due in the run summary');
-- the action and its verification are still never in the same run
update pipeline.integration_issues set next_action_at = now() - interval '1 minute' where fingerprint = 'health:queue_watch:fx_due';
update pipeline.ops_remedy_runs set finished_at = clock_timestamp() + interval '10 seconds' where remedy_code = 'confirm_condition_cleared';
select fx.only(array['health:queue_watch:fx_due']); select security.ops_controller_tick_v1();
select fx.ok((select result from pipeline.ops_remedy_runs where remedy_code = 'confirm_condition_cleared') = 'acted', 'D3 an action finished after the run started is never verified in that run');
