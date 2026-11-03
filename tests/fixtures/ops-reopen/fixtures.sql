-- CF-247 P0 workstream A follow-ups (20261104100000) on isolated fixtures, after fixtures-before.sql (the IQ-00067 false reopening reproduced on
-- the live definitions). Every case raises an exception when it fails.
\set ON_ERROR_STOP 1

-- R1 reconciliation: the reopening had no evidence after the close; the controller records it, verifies on a later run, closes again with evidence
select fx.only(array['job_failed:coverage-admit']); select security.ops_controller_tick_v1();
select fx.ok((fx.issue('job_failed:coverage-admit')).diagnosis->>'root_cause' = 'reopened_on_stale_evidence' and (fx.issue('job_failed:coverage-admit')).ops_state = 'verifying'
  and (fx.issue('job_failed:coverage-admit')).blocker is null and (fx.issue('job_failed:coverage-admit')).status <> 'closed',
  'R1 IQ-00067: looked at on the next run although its next look was hours away; reopened on evidence from before the close; remedy reclose_stale_reopen acted; not closed in the same run');
select fx.ok((select (evidence->'action'->'evidence'->>'runs_after_close')::int = 1 and (evidence->'action'->'evidence'->>'failed_after_close')::int = 0
  from pipeline.ops_remedy_runs where remedy_code = 'reclose_stale_reopen'), 'R1 its evidence: 1 run after the close (18:15), none failed');
select fx.age(31); select fx.only(array['job_failed:coverage-admit']); select security.ops_controller_tick_v1();
select fx.ok((fx.issue('job_failed:coverage-admit')).status = 'closed' and (fx.issue('job_failed:coverage-admit')).verified_by = 'ops-controller'
  and (fx.issue('job_failed:coverage-admit')).verification_evidence->>'evidence' like '%on evidence observed before the close%nothing observed since the close: 1 run(s) of coverage-admit since, 0 failed%',
  'R1 closed again through integration_issue_close_v1 with the evidence, on a later run');

-- R2 the health issue is still open on its 24-hour count: integration-validate leaves the closed issue closed
create temp table r2 as select regression_count n, (select count(*) from pipeline.integration_issue_events e where e.issue_id = i.id) ev from pipeline.integration_issues i where fingerprint = 'job_failed:coverage-admit';
select security.integration_validate_v1();
select fx.ok((fx.issue('job_failed:coverage-admit')).status = 'closed' and (fx.issue('job_failed:coverage-admit')).regression_count = (select n from r2)
  and (select count(*) from pipeline.integration_issue_events e where e.issue_id = (fx.issue('job_failed:coverage-admit')).id) = (select ev from r2),
  'R2 the open 24-hour health count no longer reopens it; nothing is changed or recorded');
select fx.ok((security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'job_failed:coverage-admit', 'title', 'x', 'failure', 'x', 'expected', 'x', 'severity', 'P1',
  'observed_at', now() - interval '2 hours')))->>'action' = 'closed_evidence_before_close', 'R2 evidence observed before the close: action closed_evidence_before_close');

-- R3 a real recurrence: a failed run after the close reopens it, with the evidence time; the controller reads it as recurred
select fx.run('coverage-admit', 'failed', 'ERROR:  something new', clock_timestamp());
update pipeline.integration_validate_state set watermark_id = (select max(runid) - 1 from cron.job_run_details) where check_key = 'job_failed';
select security.integration_validate_v1();
select fx.ok((fx.issue('job_failed:coverage-admit')).status = 'reopened' and (fx.issue('job_failed:coverage-admit')).regression_count = (select n + 1 from r2)
  and (select (e.detail->>'observed_at')::timestamptz > (e.detail->>'closed_at')::timestamptz from pipeline.integration_issue_events e
        where e.issue_id = (fx.issue('job_failed:coverage-admit')).id and e.kind = 'reopened_regression' order by e.id desc limit 1),
  'R3 a failed run after the close reopens it; the history line records observed_at after closed_at');
update pipeline.integration_issues set next_action_at = null where fingerprint = 'job_failed:coverage-admit';
select fx.only(array['job_failed:coverage-admit']); select security.ops_controller_tick_v1();
select fx.ok((fx.issue('job_failed:coverage-admit')).diagnosis->>'root_cause' = 'regression_after_close' and (fx.issue('job_failed:coverage-admit')).ops_state = 'needs_release',
  'R3 a real recurrence is a regression after close (needs a release), not a stale reopening');

-- R4 a caller without an evidence time reopens a closed issue as before (current-state detectors)
select security.integration_issue_upsert_v1('{"fingerprint": "fx:state_check", "title": "x", "failure": "x", "expected": "x", "severity": "P2"}');
select security.integration_issue_close_v1((fx.issue('fx:state_check')).id, 'fx', '{"outcome": "passed", "evidence": "the condition was gone for a day", "checked_at": "2026-11-03T00:00:00Z"}');
select security.integration_issue_upsert_v1('{"fingerprint": "fx:state_check", "title": "x", "failure": "seen again", "expected": "x", "severity": "P2"}');
select fx.ok((fx.issue('fx:state_check')).status = 'reopened', 'R4 no observed_at: the evidence is now, after the close: reopened as before');
select fx.ok((security.ops_recurrence_v1((fx.issue('fx:state_check')).id))->>'recurred' = 'true', 'R4 and the controller counts it as recurred');

-- R5 a health check that is a current state reopens on a sighting after the close (its last_seen)
select security.integration_issue_upsert_v1('{"fingerprint": "health:fx_state", "title": "x", "failure": "x", "expected": "x", "severity": "P2", "validation_layer": "V4"}');
select security.integration_issue_close_v1((fx.issue('health:fx_state')).id, 'fx', '{"outcome": "passed", "evidence": "the condition was gone for a day", "checked_at": "2026-11-03T00:00:00Z"}');
update pipeline.integration_issues set closed_at = now() - interval '1 hour' where fingerprint = 'health:fx_state';
insert into pipeline.platform_issues(check_key, severity, area, title, detail, first_seen, last_seen) values ('fx_state', 'warning', 'platform', 'fx state', '{}', now() - interval '3 hours', now() - interval '2 hours');
select security.integration_validate_v1();
select fx.ok((fx.issue('health:fx_state')).status = 'closed', 'R5 a health issue last seen before the close does not reopen it');
update pipeline.platform_issues set last_seen = now() where check_key = 'fx_state';
select security.integration_validate_v1();
select fx.ok((fx.issue('health:fx_state')).status = 'reopened', 'R5 seen after the close: reopened');

-- R6 a closed issue keeps no open controller state
select security.integration_issue_upsert_v1('{"fingerprint": "fx:closed_blocked", "title": "x", "failure": "x", "expected": "x", "severity": "P2"}');
update pipeline.integration_issues set ops_state = 'needs_release', blocker = '{"kind": "release"}', next_action_at = now() + interval '1 hour' where fingerprint = 'fx:closed_blocked';
select security.integration_issue_close_v1((fx.issue('fx:closed_blocked')).id, 'Integration Controller (Claude)', '{"outcome": "passed", "evidence": "re-closed with evidence by the Integration Controller", "checked_at": "2026-11-03T07:15:00Z"}');
select fx.only(array['fx:closed_blocked']); select security.ops_controller_tick_v1();
select fx.ok((fx.issue('fx:closed_blocked')).ops_state = 'verified' and (fx.issue('fx:closed_blocked')).blocker is null and (fx.issue('fx:closed_blocked')).next_action_at is null
  and exists (select 1 from pipeline.integration_issue_events e where e.issue_id = (fx.issue('fx:closed_blocked')).id and e.note like '%the controller''s open record (needs_release) is cleared'),
  'R6 closed elsewhere with needs_release: reconciled to verified, blocker cleared, with a history line');

-- A AI-assisted diagnosis: spend inside the ceiling; guards; the contract
insert into pipeline.ops_ai_diagnosis_requests(issue_id, context) values ((fx.issue('fx:state_check')).id, '{"title": "The \"lane\" stopped", "failure": "it said \"no work\" twice"}');
update pipeline.ops_ai_diagnosis_requests set cost_usd = 0.002 where issue_id = (fx.issue('fx:state_check')).id;
select fx.ok((select count(*) = 1 and sum(cost_usd) = 0.002 from pipeline.ai_spend_ledger where lane = 'ops_diagnose'), 'A1 the lane''s cost is captured in the AI spend ledger (lane ops_diagnose)');
update pipeline.ops_ai_diagnosis_requests set cost_usd = null, state = 'queued';
update pipeline.platform_toolset_settings set value = '1' where key = 'ops.ai_diagnosis_on';
select fx.ok((public.svc_ops_diagnosis_next(5))->>'held' like 'the ops_diagnose lane is not counted in the daily AI ceiling yet%', 'A2 held while security.ai_spend_today_v1 does not count the lane');
insert into fx.lanes values ('ops_diagnose', 9);
insert into pipeline.ai_spend_ledger(lane, source, cost_usd) values ('enrich_fields', 'fx', 20);
select fx.ok((public.svc_ops_diagnosis_next(5))->>'held' like 'daily AI ceiling reached%', 'A3 held at the daily AI ceiling');
delete from pipeline.ai_spend_ledger where source = 'fx' and lane = 'enrich_fields';
insert into pipeline.ai_spend_ledger(lane, source, cost_usd) values ('ops_diagnose', 'fx', 0.6);
select fx.ok((public.svc_ops_diagnosis_next(5))->>'held' = 'ops.ai_diagnosis_usd_per_day reached', 'A4 held at the lane''s own daily cap');
delete from pipeline.ai_spend_ledger where source = 'fx' and lane = 'ops_diagnose';
insert into pipeline.layer3_openrouter_observations(kind, remaining_usd) values ('credits', 3);
select fx.ok((public.svc_ops_diagnosis_next(5))->>'held' like 'credit floor%', 'A5 held at the OpenRouter credit floor (the existing guard)');
insert into pipeline.layer3_openrouter_observations(kind, remaining_usd) values ('credits', 50);
create temp table a6 as select public.svc_ops_diagnosis_next(5) r;
select fx.ok((select r->>'contract' = 'ops-diagnose-v1' and jsonb_array_length(r->'items') = 1 and r->'items'->0 ?& array['id', 'model', 'lease_until', 'contract', 'context', 'instructions', 'response_schema']
  and r->'items'->0->'response_schema'->'properties'->'root_cause'->'enum' ? 'reopened_on_stale_evidence' and r->'items'->0->>'model' = 'openai/gpt-4.1-mini' from a6),
  'A6 an item carries the contract version, pinned model, lease, context, instructions and the answer schema (root causes as its enum)');
select fx.ok((public.svc_ops_diagnosis_record((select id from pipeline.ops_ai_diagnosis_requests limit 1), '{"root_cause": "stalled_work", "confidence": 0.8, "evidence": ["it said \"no work\" twice"]}', 0.001))->>'state' = 'answered',
  'A7 a quote containing quotation marks matches the context text (not its JSON escaping)');
insert into pipeline.ops_ai_diagnosis_requests(issue_id, context, state, leased_until) values ((fx.issue('fx:state_check')).id, '{"title": "second"}', 'leased', now() + interval '5 minutes');
select fx.ok((public.svc_ops_diagnosis_record((select max(id) from pipeline.ops_ai_diagnosis_requests), '{"error": "upstream 502"}', 0.0005))->>'reason' = 'worker error', 'A8 a worker error is accepted');
select fx.ok((select state = 'refused' and note like 'worker error: upstream 502%' from pipeline.ops_ai_diagnosis_requests where id = (select max(id) from pipeline.ops_ai_diagnosis_requests))
  and (select sum(cost_usd) from pipeline.ai_spend_ledger where lane = 'ops_diagnose') = 0.0035, 'A8 recorded as refused with its cost in the ledger (0.002 + 0.001 + 0.0005); not retried');
update pipeline.platform_toolset_settings set value = '0' where key = 'ops.ai_diagnosis_on';
select fx.ok((public.svc_ops_diagnosis_next(5))->>'held' = 'ops.ai_diagnosis_on is 0', 'A9 off: nothing handed out');
