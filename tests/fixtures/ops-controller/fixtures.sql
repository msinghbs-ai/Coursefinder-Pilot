-- CF-247 P0 workstream A: the controller (part 2 of 20261104010000) on isolated fixtures. Every case raises an exception when it fails.
-- Time is moved on with fx.age(minutes): every stored time the controller compares is moved back, as if that many minutes had passed.
\set ON_ERROR_STOP 1
create or replace function fx.age(p_min int) returns void language plpgsql as $f$
declare d interval := make_interval(mins => p_min);
begin
  update pipeline.ops_remedy_runs set started_at = started_at - d, finished_at = finished_at - d;
  update pipeline.integration_issues set next_action_at = next_action_at - d, condition_cleared_at = condition_cleared_at - d, last_observed_at = last_observed_at - d,
         detected_at = detected_at - d, closed_at = closed_at - d;
  update pipeline.ops_checkpoints set at = at - d;
  update cron.job_run_details set start_time = start_time - d, end_time = end_time - d;
  update pipeline.component_register set registered_at = registered_at - d;
end $f$;
create or replace function fx.issue(p_fp text) returns pipeline.integration_issues language sql as $f$ select * from pipeline.integration_issues where fingerprint = p_fp $f$;
create or replace function fx.tick() returns jsonb language sql as $f$ select security.ops_controller_tick_v1() $f$;
-- quieten the rest of the queue between cases: only the issues a case creates are due
create or replace function fx.only(p_fps text[]) returns void language sql as $f$
  update pipeline.integration_issues set next_action_at = now() + interval '30 days' where not (fingerprint = any (p_fps)) and status <> 'closed';
$f$;
-- the functions the subject finder may name (as live)
create function security.course_page_check_v1() returns void language sql as $f$ select $f$;
create function security.layer4_course_link_apply_impl() returns void language sql as $f$ select $f$;
create function security.coverage_admission_gated_v1() returns void language sql as $f$ select $f$;
insert into cron.job(jobname, schedule, command, active) values
  ('coverage-admit', '3-59/10 * * * *', $c$select security.coverage_admission_gated_v1('coverage-admit', security.pipeline_num_v1('batch.coverage_admit', 500)::int)$c$, true),
  ('search-refresh-requested', '6-59/10 * * * *', 'select security.search_refresh_requested_v1()', true),
  ('fx-capacity', '* * * * *', 'select 1', true);

-- S0 the shipped state
select fx.ok((select active from cron.job where jobname = 'ops-controller') and (select command from cron.job where jobname = 'ops-controller') = 'select security.ops_controller_tick_v1()'
  and exists (select 1 from pipeline.automation_catalogue where jobname = 'ops-controller'), 'S0 job ops-controller ships on, catalogued, its command has no number');
select fx.ok((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where key = 'ops.controller_on') = 1
  and (select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where key = 'ops.ai_diagnosis_on') = 0
  and (select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where key = 'ops.checkpoint_on') = 1, 'S0 controller on, checkpoint on, AI-assisted diagnosis off');
select fx.ok((select count(*) from pipeline.ops_remedies where authority = 'auto') = 3 and (select count(*) from pipeline.ops_root_causes) = 23
  and (select count(*) from pipeline.ops_authority_matrix where executes) = 1, 'S0 23 root causes, 3 auto remedies, only auto executes in the matrix');
select fx.ok(not exists (select 1 from pipeline.platform_toolset_settings s where s.key like 'ops.%' and (s.label is null or s.used_by is null or (s.kind = 'number' and (s.min_value is null or s.max_value is null or s.unit is null)))),
  'S0 every ops setting has a label, a range, a unit and used_by (G2)');

-- T1 a condition cleared for longer than ops.stale_clear_hours: acted on one run, verified and closed only on a later run
select security.integration_issue_upsert_v1('{"fingerprint": "health:queue_watch:fx_lane", "title": "Fx lane: stuck", "failure": "stuck", "expected": "moves", "validation_layer": "V4", "severity": "P2", "source": "queue-watch"}');
update pipeline.integration_issues set condition_cleared_at = now() - interval '7 hours', last_observed_at = now() - interval '7 hours 30 minutes' where fingerprint = 'health:queue_watch:fx_lane';
select fx.only(array['health:queue_watch:fx_lane']);
select fx.tick();
select fx.ok((fx.issue('health:queue_watch:fx_lane')).diagnosis->>'root_cause' = 'condition_cleared_stale' and (fx.issue('health:queue_watch:fx_lane')).status = 'triaged'
  and (fx.issue('health:queue_watch:fx_lane')).ops_state = 'verifying', 'T1 diagnosed condition_cleared_stale; status detected -> triaged; verifying');
select fx.ok((select count(*) = 1 and bool_and(result = 'acted') and bool_and(before is not null) and bool_and(evidence ? 'authorise' and (evidence->'authorise'->>'permitted')::boolean)
  from pipeline.ops_remedy_runs where issue_id = (fx.issue('health:queue_watch:fx_lane')).id), 'T1 one run acted, with its before measure and the Authorise step recorded');
select fx.tick();
select fx.ok((fx.issue('health:queue_watch:fx_lane')).status <> 'closed', 'T2 never verified in the same run as the action, nor before its cool-down');
select fx.age(31);
select fx.tick();
select fx.ok((fx.issue('health:queue_watch:fx_lane')).status = 'closed' and (fx.issue('health:queue_watch:fx_lane')).verified_by = 'ops-controller'
  and (fx.issue('health:queue_watch:fx_lane')).verification_evidence->>'reference' like 'pipeline.ops_remedy_runs#%'
  and (select result = 'verified' and after ? 'verify' and evidence ? 'learn' from pipeline.ops_remedy_runs where issue_id = (fx.issue('health:queue_watch:fx_lane')).id),
  'T1 verified on a later run and closed through integration_issue_close_v1 with its evidence and run reference; Learn recorded');
select fx.ok(security.ops_issue_end_state_v1((fx.issue('health:queue_watch:fx_lane')).id) = 'verified_resolved', 'T1 end state verified_resolved');

-- T3 cleared, but not yet long enough: routed by its own cause and looked at again when it would be stale
select security.integration_issue_upsert_v1('{"fingerprint": "draft_stuck:fx", "title": "Fx drafts stuck", "failure": "stuck", "expected": "moves", "validation_layer": "V4", "severity": "P2", "root_cause_class": "queue_or_lease"}');
update pipeline.integration_issues set condition_cleared_at = now() - interval '2 hours', last_observed_at = now() - interval '2 hours 30 minutes' where fingerprint = 'draft_stuck:fx';
select fx.only(array['draft_stuck:fx']); select fx.tick();
select fx.ok((fx.issue('draft_stuck:fx')).diagnosis->>'root_cause' = 'stalled_work' and (fx.issue('draft_stuck:fx')).ops_state = 'needs_release'
  and (fx.issue('draft_stuck:fx')).next_action_at between now() + interval '3 hours 50 minutes' and now() + interval '4 hours 10 minutes',
  'T3 cleared 2 h: stalled_work, needs a release for now, looked at again when it has been clear 6 h');
select fx.age(250); select fx.only(array['draft_stuck:fx']); select fx.tick();
select fx.ok((fx.issue('draft_stuck:fx')).diagnosis->>'root_cause' = 'condition_cleared_stale' and (fx.issue('draft_stuck:fx')).ops_state = 'verifying' and (fx.issue('draft_stuck:fx')).blocker is null,
  'T3 once clear long enough the blocked issue moves to the stale-close remedy');

-- T4 shared cause: the second issue of a job is superseded into the first, evidence carried over; it closes when the owner is verified
select security.integration_issue_upsert_v1('{"fingerprint": "job_failed:search-refresh-requested", "title": "search-refresh-requested failed", "failure": "canceling statement due to statement timeout in course_page_check_v1", "expected": "runs succeed", "validation_layer": "V4", "severity": "P1", "source": "platform-health"}');
select security.integration_issue_upsert_v1('{"fingerprint": "job:search-refresh-requested:statement_timeout_course_page_check", "title": "hidden time-out", "failure": "120 s time-out inside course_page_check_v1", "expected": "no time-out", "severity": "P2", "evidence": {"function": "security.course_page_check_v1"}}');
select fx.only(array['job_failed:search-refresh-requested', 'job:search-refresh-requested:statement_timeout_course_page_check']);
select fx.tick();
select fx.ok((fx.issue('job:search-refresh-requested:statement_timeout_course_page_check')).correlation_key = 'job:search-refresh-requested'
  and (fx.issue('job_failed:search-refresh-requested')).correlation_key = 'job:search-refresh-requested', 'T4 both correlate on job:search-refresh-requested');
select fx.ok((fx.issue('job:search-refresh-requested:statement_timeout_course_page_check')).superseded_by = (fx.issue('job_failed:search-refresh-requested')).id
  and (fx.issue('job_failed:search-refresh-requested')).supersedes @> array[(fx.issue('job:search-refresh-requested:statement_timeout_course_page_check')).id]
  and (fx.issue('job_failed:search-refresh-requested')).evidence->'superseded' ? (fx.issue('job:search-refresh-requested:statement_timeout_course_page_check')).issue_ref
  and (fx.issue('job:search-refresh-requested:statement_timeout_course_page_check')).ops_state = 'superseded',
  'T4 superseded into the owner both ways with the evidence carried over (traceability kept)');
select fx.ok((fx.issue('job_failed:search-refresh-requested')).diagnosis->>'root_cause' = 'timeout_under_load' and (fx.issue('job_failed:search-refresh-requested')).remedy_code = 'record_capacity_profile',
  'T4 the owner is diagnosed time-outs under load and gets the capacity remedy; the superseded issue gets none of its own');
select security.integration_issue_close_v1((fx.issue('job_failed:search-refresh-requested')).id, 'fx', '{"outcome": "passed", "evidence": "the job ran clean for a day after the fix", "checked_at": "2026-11-04T00:00:00Z"}');
select fx.age(31); select fx.tick();
select fx.ok((fx.issue('job:search-refresh-requested:statement_timeout_course_page_check')).status = 'closed'
  and (fx.issue('job:search-refresh-requested:statement_timeout_course_page_check')).verification_evidence->>'evidence' like '%Resolved by the shared correction verified on IQ-%',
  'T4 the superseded issue closes with its owner''s verified evidence');

-- T10 one remedy per shared cause per run: two issues of one worker mode, both clear long enough, act on consecutive runs
select security.integration_issue_upsert_v1('{"fingerprint": "zero_yield:fx_mode", "title": "fx mode zero yield", "failure": "0 items done", "expected": "x", "validation_layer": "V4", "severity": "P2"}');
select security.integration_issue_upsert_v1('{"fingerprint": "health:queue_watch:fx_mode", "title": "fx mode: stuck", "failure": "stuck", "expected": "x", "validation_layer": "V4", "severity": "P2"}');
update pipeline.integration_issues set condition_cleared_at = now() - interval '8 hours', last_observed_at = now() - interval '9 hours' where fingerprint in ('zero_yield:fx_mode', 'health:queue_watch:fx_mode');
select fx.only(array['zero_yield:fx_mode', 'health:queue_watch:fx_mode']); select fx.tick();
select fx.ok((fx.issue('zero_yield:fx_mode')).correlation_key = 'mode:fx_mode' and (fx.issue('health:queue_watch:fx_mode')).correlation_key = 'mode:fx_mode'
  and (select count(*) from pipeline.ops_remedy_runs u join pipeline.integration_issues i on i.id = u.issue_id where i.correlation_key = 'mode:fx_mode') = 1,
  'T10 one remedy per shared cause per run: the second issue of mode:fx_mode waits');
select fx.only(array['zero_yield:fx_mode', 'health:queue_watch:fx_mode']); select fx.tick();
select fx.ok((select count(*) from pipeline.ops_remedy_runs u join pipeline.integration_issues i on i.id = u.issue_id where i.correlation_key = 'mode:fx_mode') = 2,
  'T10 and acts on the next run');

-- T5 IQ-00067 replay: coverage-admit fails every run since 13:53 with the manual-lock refusal; Release A applied at 13:39 (problem created by a previous release)
insert into pipeline.component_register(kind, name, layer, purpose, introduced_in, registered_at) values ('table', 'fx.release_a', 'Platform', 'fx', '20261103200000', now() - interval '125 minutes');
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from cron.job where jobname = 'coverage-admit'), 'succeeded', '1 row', now() - make_interval(mins => 120 + 10 * g), now() - make_interval(mins => 120 + 10 * g) + interval '30 seconds' from generate_series(1, 6) g;
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from cron.job where jobname = 'coverage-admit'), 'failed',
       E'ERROR:  this course''s page was set by hand on the course record: change it there (course detail, official page), or keep the page we hold\nCONTEXT:  PL/pgSQL function layer4_course_link_apply_impl(uuid,uuid,jsonb,text) line 17 at RAISE',
       now() - make_interval(mins => 110 - 10 * g), now() - make_interval(mins => 110 - 10 * g) + interval '30 seconds' from generate_series(0, 11) g;
select security.integration_issue_upsert_v1('{"fingerprint": "job_failed:coverage-admit", "title": "Scheduled job \"coverage-admit\" failed 3 of 6 run(s) in the last hour", "failure": "failed 3 of 6", "expected": "runs succeed", "validation_layer": "V4", "severity": "P1", "source": "platform-health", "evidence": {"detail": {"job": "coverage-admit", "last_error": "ERROR: this course''s page was set by hand on the course record"}}}');
select fx.only(array['job_failed:coverage-admit']); select fx.tick();
select fx.ok((fx.issue('job_failed:coverage-admit')).diagnosis->>'root_cause' = 'regression_after_release'
  and (fx.issue('job_failed:coverage-admit')).diagnosis->'contributing' ?& array['manual_lock_unguarded_in_batch', 'permanent_job_error', 'retry_loop_no_new_evidence'],
  'T5 IQ-00067: a regression after release 20261103200000, with the unguarded manual-lock refusal, a permanent error and a retry loop contributing');
select fx.ok(exists (select 1 from jsonb_array_elements((fx.issue('job_failed:coverage-admit')).diagnosis->'evidence') e where e->'release'->>'release' = '20261103200000' and (e->'release'->>'minutes_after')::int = 15)
  and exists (select 1 from jsonb_array_elements((fx.issue('job_failed:coverage-admit')).diagnosis->'evidence') e where (e->'job_runs'->>'streak')::int = 12 and (e->'job_runs'->>'streak_messages')::int = 1),
  'T5 evidence: the release and its timing (failures 15 minutes after it), 12 failed runs in a row with one error, read from the live runs not the stale issue text');
select fx.ok((fx.issue('job_failed:coverage-admit')).ops_state = 'needs_release' and (fx.issue('job_failed:coverage-admit')).blocker->>'kind' = 'release'
  and not exists (select 1 from pipeline.ops_remedy_runs where issue_id = (fx.issue('job_failed:coverage-admit')).id), 'T5 blocked as needs_release with its evidence; nothing executed');

-- T6 time-outs on part of the runs: capacity, recorded and checked again; checks used up -> needs a release; never loops
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from cron.job where jobname = 'fx-capacity'), case when g in (3, 7) then 'failed' else 'succeeded' end,
       case when g in (3, 7) then 'ERROR:  canceling statement due to statement timeout' else '1 row' end, now() - make_interval(mins => g), now() - make_interval(mins => g) from generate_series(1, 12) g;
select security.integration_issue_upsert_v1('{"fingerprint": "job_failed:fx-capacity", "title": "fx-capacity failed", "failure": "statement timeout", "expected": "runs succeed", "validation_layer": "V4", "severity": "P2"}');
update pipeline.platform_toolset_settings set value = '2' where key = 'ops.capacity_max_checks';
select fx.only(array['job_failed:fx-capacity']); select fx.tick();
select fx.ok((fx.issue('job_failed:fx-capacity')).diagnosis->>'root_cause' = 'timeout_under_load' and (fx.issue('job_failed:fx-capacity')).remedy_code = 'record_capacity_profile'
  and (select evidence->'action'->'evidence'->>'transient_share' from pipeline.ops_remedy_runs where issue_id = (fx.issue('job_failed:fx-capacity')).id) = 'true',
  'T6 a time-out on 2 of 12 runs is load: the capacity profile is recorded (no setting changed)');
do $d$ begin for k in 1 .. 6 loop perform fx.age(121); perform security.integration_issue_upsert_v1('{"fingerprint": "job_failed:fx-capacity", "title": "fx", "failure": "statement timeout", "expected": "x", "validation_layer": "V4", "severity": "P2"}');
  perform fx.only(array['job_failed:fx-capacity']); perform fx.tick(); end loop; end $d$;
select fx.ok((select count(*) from pipeline.ops_remedy_runs where issue_id = (fx.issue('job_failed:fx-capacity')).id) = 2 and (fx.issue('job_failed:fx-capacity')).ops_state = 'needs_release'
  and (fx.issue('job_failed:fx-capacity')).blocker->>'reason' like 'attempts used up%', 'T8 attempts used up after 2 checks: needs a release; 6 more runs execute nothing (no loop)');

-- T7 a decision: blocked once with the decision required; later runs add no history (no loop)
select security.integration_issue_upsert_v1('{"fingerprint": "seed:fx_restore_rehearsal", "title": "No restore rehearsal", "failure": "the rehearsal (about US$3) is not approved", "expected": "a rehearsal", "severity": "P1", "root_cause_class": "human_decision"}');
select fx.only(array['seed:fx_restore_rehearsal']); select fx.tick();
select fx.ok((fx.issue('seed:fx_restore_rehearsal')).ops_state = 'needs_decision' and (fx.issue('seed:fx_restore_rehearsal')).blocker->>'required' like 'Platform Admin decision:%'
  and (fx.issue('seed:fx_restore_rehearsal')).blocker->>'issue_statement' like '%not approved%' and security.ops_issue_end_state_v1((fx.issue('seed:fx_restore_rehearsal')).id) = 'blocked',
  'T7 needs_decision with the decision required and the evidence: an end state (blocked)');
create temp table fx_ev as select count(*) n from pipeline.integration_issue_events where issue_id = (fx.issue('seed:fx_restore_rehearsal')).id;
do $d$ begin for k in 1 .. 3 loop perform fx.age(400); perform fx.only(array['seed:fx_restore_rehearsal']); perform fx.tick(); end loop; end $d$;
select fx.ok((select count(*) from pipeline.integration_issue_events where issue_id = (fx.issue('seed:fx_restore_rehearsal')).id) = (select n from fx_ev),
  'T7 three more looks add no history and execute nothing');

-- T9 recurrence after a controller close reopens the same issue as a regression, and it is diagnosed as one
select security.integration_issue_upsert_v1('{"fingerprint": "health:queue_watch:fx_lane", "title": "Fx lane: stuck", "failure": "stuck again", "expected": "moves", "validation_layer": "V4", "severity": "P2"}');
select fx.only(array['health:queue_watch:fx_lane']); select fx.tick();
select fx.ok((fx.issue('health:queue_watch:fx_lane')).status = 'triaged' and (fx.issue('health:queue_watch:fx_lane')).regression_count = 1
  and (fx.issue('health:queue_watch:fx_lane')).diagnosis->>'root_cause' = 'regression_after_close' and (fx.issue('health:queue_watch:fx_lane')).ops_state = 'needs_release',
  'T9 reopened as a regression (regression_count 1) with its history; diagnosed regression_after_close; needs a release');

-- T13 an issue recorded by hand that no check observes gets no check-verified remedy: blocked at once, nothing executed
select security.integration_issue_upsert_v1('{"fingerprint": "seed:fx_timeouts", "title": "07:00 admission time-outs: root cause not verified", "failure": "time-outs at 07:00", "expected": "x", "severity": "P1"}');
select fx.only(array['seed:fx_timeouts']); select fx.tick();
select fx.ok((fx.issue('seed:fx_timeouts')).diagnosis->>'root_cause' = 'timeout_under_load' and (fx.issue('seed:fx_timeouts')).ops_state = 'needs_release'
  and not exists (select 1 from pipeline.ops_remedy_runs where issue_id = (fx.issue('seed:fx_timeouts')).id), 'T13 a hand-recorded time-out issue is blocked as needs_release, no remedy run');

-- T11 tasks that keep ending without data movement open one issue per kind
insert into pipeline.admin_jobs(kind, state, outcome, finished_at) select 'fx_scan', 'done', 'succeeded_no_movement', now() - make_interval(mins => g) from generate_series(1, 3) g;
select fx.only(array['no_movement:fx_scan']); select fx.tick();
select fx.ok((fx.issue('no_movement:fx_scan')).id is not null and (fx.issue('no_movement:fx_scan')).diagnosis->>'root_cause' = 'done_without_movement',
  'T11 three tasks succeeded_no_movement open no_movement:fx_scan, diagnosed done_without_movement');

-- T12 Authorise: a switched-off remedy is not run; the refusal is recorded on the run and the issue routed
select security.integration_issue_upsert_v1('{"fingerprint": "health:queue_watch:fx_off", "title": "Fx off: stuck", "failure": "stuck", "expected": "moves", "validation_layer": "V4", "severity": "P2"}');
update pipeline.integration_issues set condition_cleared_at = now() - interval '8 hours', last_observed_at = now() - interval '9 hours' where fingerprint = 'health:queue_watch:fx_off';
update pipeline.ops_remedies set active = false where code = 'confirm_condition_cleared';
select fx.only(array['health:queue_watch:fx_off']); select fx.tick();
select fx.ok(not exists (select 1 from pipeline.ops_remedy_runs where issue_id = (fx.issue('health:queue_watch:fx_off')).id) and (fx.issue('health:queue_watch:fx_off')).ops_state is not null
  and (fx.issue('health:queue_watch:fx_off')).status <> 'closed', 'T12 an inactive remedy is never planned or executed');
update pipeline.ops_remedies set active = true where code = 'confirm_condition_cleared';
update pipeline.ops_authority_matrix set executes = false where authority = 'auto';
update pipeline.integration_issues set next_action_at = null where fingerprint = 'health:queue_watch:fx_off'; select fx.only(array['health:queue_watch:fx_off']); select fx.tick();
select fx.ok((select result = 'refused_authority' and evidence->'authorise'->>'reason' like 'authority auto does not execute%' from pipeline.ops_remedy_runs where issue_id = (fx.issue('health:queue_watch:fx_off')).id),
  'T12 the matrix says no: the run records refused_authority with the reason; nothing executed');
update pipeline.ops_authority_matrix set executes = true where authority = 'auto';

-- G guardrails in data: a registered auto remedy that tries each protected write is refused by the triggers, recorded as refused_guard
create table fx.attack(n int primary key, sql text);
insert into fx.attack values
 (1, $q$update pipeline.ops_remedies set active = false where code = 'fix_in_release'$q$),
 (2, $q$update pipeline.platform_toolset_settings set max_value = 999 where key = 'ops.max_attempts'$q$),
 (3, $q$update pipeline.platform_toolset_settings set value = '1000' where key = 'budgets.ai_daily_ceiling_usd'$q$),
 (4, $q$update pipeline.platform_toolset_settings set value = '99' where key = 'ops.max_attempts'$q$),
 (5, $q$update pipeline.layer4_review_items set status = 'approved' where status = 'pending'$q$),
 (6, $q$insert into pipeline.layer4_decisions(action, reason) values ('approve', 'remedy')$q$),
 (7, $q$delete from pipeline.manual_locks$q$),
 (8, $q$update pipeline.layer2_acquisition_providers set billing_config = '{"limit_units": 9999999}'$q$),
 (9, $q$update pipeline.integration_issues set status = 'closed' where fingerprint = 'seed:fx_restore_rehearsal'$q$),
 (10, $q$update pipeline.ops_authority_matrix set executes = true where authority = 'admin'$q$),
 (11, $q$update pipeline.ops_remedy_runs set result = 'verified'$q$),
 (12, $q$update pipeline.integration_issues set remedy_attempts = 0 where fingerprint = 'job_failed:fx-capacity'$q$),
 (13, $q$insert into pipeline.layer4_auto_admissions(review_item_id) values (null)$q$),
 (14, $q$update pipeline.platform_toolset_settings set value = '0' where toolset_key = 'firecrawl' and key = 'daily_budget_on'$q$),
 (15, $q$insert into pipeline.ops_root_causes(code, class, title) values ('fx_evil', 'rule', 'evil')$q$);
create table fx.state(n int); insert into fx.state values (0);
create function fx.act_attack(p_issue bigint) returns jsonb language plpgsql security definer as $f$
declare v text; begin select a.sql into v from fx.attack a where a.n = (select n from fx.state); execute v; return jsonb_build_object('ok', true, 'changed', true, 'evidence', '{}'::jsonb); end $f$;
create function fx.verify_never(p_issue bigint) returns jsonb language sql as $f$ select jsonb_build_object('passed', false, 'measure', '{}'::jsonb, 'evidence', 'fx') $f$;
select security.ops_root_cause_register_v1('fx_attack_cause', '{"class": "transient", "title": "Fixture attack cause", "detect": {"priority": 1, "confidence": 1, "all": [{"fingerprint_like": ["fx_attack%"]}]}}');
select security.ops_remedy_register_v1('fx_attack', '{"title": "Fixture attack remedy", "treats": ["fx_attack_cause"], "authority": "auto", "action_fn": "fx.act_attack(bigint)", "verify_fn": "fx.verify_never(bigint)", "max_attempts_key": "ops.max_attempts"}');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status) values ('course', gen_random_uuid(), 'official_course_url', 'pending');
insert into pipeline.manual_locks(entity, entity_id, field) values ('course', gen_random_uuid(), 'official_url');
insert into pipeline.layer2_acquisition_providers(provider_key, billing_config) values ('firecrawl', '{"limit_units": 500000}');
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value, min_value, max_value, unit) values ('pipeline', 'fx.batch', 'number', '10', 1, 50, 'items') on conflict do nothing;
create temp table fx_before as select
  (select md5(string_agg(m::text, '|' order by m.code)) from pipeline.ops_remedies m) remedies,
  (select md5(string_agg(s.toolset_key || s.key || s.value::text || coalesce(s.min_value::text, '') || coalesce(s.max_value::text, ''), '|' order by s.toolset_key, s.key)) from pipeline.platform_toolset_settings s) settings,
  (select count(*) from pipeline.layer4_review_items where status = 'approved') approved, (select count(*) from pipeline.layer4_decisions) decisions,
  (select count(*) from pipeline.manual_locks) locks, (select md5(string_agg(billing_config::text, '|')) from pipeline.layer2_acquisition_providers) billing,
  (select md5(string_agg(a::text, '|' order by a.authority)) from pipeline.ops_authority_matrix a) matrix, (select count(*) from pipeline.layer4_auto_admissions) admissions,
  (select count(*) from pipeline.ops_root_causes) causes;
do $d$
declare k int; v_id bigint; v_r record;
begin
  for k in 1 .. 15 loop
    update fx.state set n = k;
    perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'fx_attack' || k || ':x', 'title', 'attack ' || k, 'failure', 'x', 'expected', 'x', 'severity', 'P2'));
    perform fx.only(array['fx_attack' || k || ':x']);
    perform fx.tick();
    select u.result, u.evidence->'action'->>'error' err into v_r from pipeline.ops_remedy_runs u join pipeline.integration_issues i on i.id = u.issue_id where i.fingerprint = 'fx_attack' || k || ':x';
    if v_r.result is distinct from 'refused_guard' then raise exception 'FAILED: G% attack % was not refused by the guard (result %, %)', k, (select sql from fx.attack where n = k), v_r.result, v_r.err; end if;
  end loop;
  raise notice 'ok: G1-G15 every protected write by a remedy is refused in data and recorded as refused_guard';
end $d$;
select fx.ok((select remedies from fx_before) = (select md5(string_agg(m::text, '|' order by m.code)) from pipeline.ops_remedies m), 'G1 the remedy register is unchanged');
select fx.ok((select settings from fx_before) = (select md5(string_agg(s.toolset_key || s.key || s.value::text || coalesce(s.min_value::text, '') || coalesce(s.max_value::text, ''), '|' order by s.toolset_key, s.key)) from pipeline.platform_toolset_settings s),
  'G2-G4, G14 settings ranges, budgets, out-of-range values and service toolsets are unchanged');
select fx.ok((select approved from fx_before) = (select count(*) from pipeline.layer4_review_items where status = 'approved') and (select decisions from fx_before) = (select count(*) from pipeline.layer4_decisions)
  and (select admissions from fx_before) = (select count(*) from pipeline.layer4_auto_admissions), 'G5, G6, G13 no Layer 4 admission, decision or automatic admission');
select fx.ok((select locks from fx_before) = (select count(*) from pipeline.manual_locks), 'G7 manual locks are unchanged');
select fx.ok((select billing from fx_before) = (select md5(string_agg(billing_config::text, '|')) from pipeline.layer2_acquisition_providers), 'G8 paid-service limits are unchanged');
select fx.ok((fx.issue('seed:fx_restore_rehearsal')).status <> 'closed' and (fx.issue('job_failed:fx-capacity')).remedy_attempts = 2, 'G9, G12 a remedy cannot close an issue or reset the controller''s record');
select fx.ok((select matrix from fx_before) = (select md5(string_agg(a::text, '|' order by a.authority)) from pipeline.ops_authority_matrix a)
  and (select causes from fx_before) = (select count(*) from pipeline.ops_root_causes), 'G10, G15 the authority matrix and the root-cause register are unchanged');
-- positive control: within its range a remedy may tune an ordinary pipeline setting
update fx.attack set sql = $q$update pipeline.platform_toolset_settings set value = '20' where key = 'fx.batch'$q$ where n = 1; update fx.state set n = 1;
select security.integration_issue_upsert_v1('{"fingerprint": "fx_attackok:x", "title": "tune within range", "failure": "x", "expected": "x", "severity": "P2"}');
select fx.only(array['fx_attackok:x']); select fx.tick();
select fx.ok((select (value #>> '{}')::int from pipeline.platform_toolset_settings where key = 'fx.batch') = 20
  and (select result from pipeline.ops_remedy_runs u join pipeline.integration_issues i on i.id = u.issue_id where i.fingerprint = 'fx_attackok:x') = 'acted',
  'G0 positive control: an ordinary setting changed within its range is allowed (reversible optimisation)');

-- R report and checkpoint rows
select fx.ok(not exists (select 1 from jsonb_each(security.ops_report_v1(24)) e where jsonb_typeof(e.value) = 'object' and e.value ? 'error'), 'R the report reads every section without error');
select fx.ok((select r ?& array['platform_health', 'data_improvement', 'autonomy', 'efficiency', 'governance', 'reconciliation', 'groups'] from security.ops_report_v1(24) r)
  and (select r->'autonomy'->'scorecard' ?& array['autonomous_resolution_pct', 'autonomous_resolution_basis', 'detection_to_diagnosis_minutes_median', 'diagnosis_to_resolution_minutes_median', 'recurrence'] from security.ops_report_v1(24) r),
  'R the mandate §16 sections and the §17 scorecard metrics are present');
select fx.ok((select count(*) from pipeline.ops_checkpoints where kind = 'hourly' and at > now() - interval '1 hour') = 1, 'R one hourly checkpoint row, not one per run');

-- A AI-assisted diagnosis: off queues nothing; on queues a low-confidence diagnosis once; the recorder checks quotes
select security.integration_issue_upsert_v1('{"fingerprint": "fx_unknown:1", "title": "Something odd", "failure": "an odd thing happened in the lane", "expected": "x", "severity": "P2"}');
select fx.only(array['fx_unknown:1']); select fx.tick();
select fx.ok((fx.issue('fx_unknown:1')).diagnosis->>'root_cause' = 'unclassified' and not exists (select 1 from pipeline.ops_ai_diagnosis_requests), 'A off: an unclassified issue queues nothing');
select fx.ok((public.svc_ops_diagnosis_next(5))->>'held' = 'ops.ai_diagnosis_on is 0', 'A off: the picker hands out nothing');
update pipeline.platform_toolset_settings set value = '1' where key = 'ops.ai_diagnosis_on';
update pipeline.integration_issues set next_action_at = null where fingerprint = 'fx_unknown:1'; select fx.only(array['fx_unknown:1']); select fx.tick();
select fx.ok((select count(*) from pipeline.ops_ai_diagnosis_requests) = 1, 'A on: one request queued');
select fx.ok(jsonb_array_length((public.svc_ops_diagnosis_next(5))->'items') = 1, 'A the picker hands out the request');
select fx.ok((select model = 'openai/gpt-4.1-mini' and state = 'leased' from pipeline.ops_ai_diagnosis_requests), 'A leased with the pinned model');
select fx.ok((public.svc_ops_diagnosis_record((select id from pipeline.ops_ai_diagnosis_requests), '{"root_cause": "stalled_work", "confidence": 0.9, "evidence": ["a quote the context does not contain"]}'))->>'state' = 'refused',
  'A an answer quoting text that is not in the context is refused');
update pipeline.ops_ai_diagnosis_requests set state = 'leased', leased_until = now() + interval '5 minutes';
select fx.ok((public.svc_ops_diagnosis_record((select id from pipeline.ops_ai_diagnosis_requests), '{"root_cause": "stalled_work", "confidence": 0.9, "evidence": ["an odd thing happened in the lane"]}'))->>'applied' = 'true'
  and (fx.issue('fx_unknown:1')).diagnosis->>'method' = 'ai_assisted', 'A a quoted answer above the minimum becomes the diagnosis (method ai_assisted)');
update pipeline.platform_toolset_settings set value = '0' where key = 'ops.ai_diagnosis_on';

-- O off: nothing runs
update pipeline.platform_toolset_settings set value = '0' where key = 'ops.controller_on';
select fx.ok((fx.tick())->>'off' = 'true', 'O with ops.controller_on 0 the controller does nothing');
update pipeline.platform_toolset_settings set value = '1' where key = 'ops.controller_on';
