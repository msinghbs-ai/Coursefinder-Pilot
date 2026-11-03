-- The live sequence of 3 Nov 2026 on the v2.15.436 definitions: IQ-00067 (reopened at 18:21 on evidence from before its 18:15 close) is
-- diagnosed reopened_on_stale_evidence and remedy reclose_stale_reopen acts (19:24); the next run (19:54) starts a fraction of a second before
-- next_action_at (live: due 19:54:00.369, run started 19:54:00.312) and the verification is skipped without a trace.
\set ON_ERROR_STOP 1
-- 19:24
select fx.only(array['job_failed:coverage-admit']); select security.ops_controller_tick_v1();
select fx.ok((fx.issue('job_failed:coverage-admit')).diagnosis->>'root_cause' = 'reopened_on_stale_evidence' and (fx.issue('job_failed:coverage-admit')).ops_state = 'verifying'
  and (select result from pipeline.ops_remedy_runs where remedy_code = 'reclose_stale_reopen') = 'acted', 'before: 19:24 diagnosed reopened_on_stale_evidence; reclose_stale_reopen acted');
-- 30 minutes on: the action finished 30 minutes ago; the next run starts a fraction of a second before next_action_at, within the same minute
select pg_sleep(61 - extract(second from clock_timestamp())) where extract(second from clock_timestamp()) > 50;
select fx.age(30);
update pipeline.integration_issues set next_action_at = clock_timestamp() + interval '2 seconds' where fingerprint = 'job_failed:coverage-admit';
select fx.only(array['job_failed:coverage-admit']); select security.ops_controller_tick_v1();
select fx.ok((fx.issue('job_failed:coverage-admit')).status = 'triaged' and (select result from pipeline.ops_remedy_runs where remedy_code = 'reclose_stale_reopen') = 'acted'
  and security.ops_verify_stale_reopen_v1((fx.issue('job_failed:coverage-admit')).id)->>'passed' = 'true',
  'before: 19:54 the run starts just before next_action_at: no verification and no close, although the verification would pass (as live)');
