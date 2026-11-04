-- CF-247 recovery-knowledge fixtures (migration 20261104600000). The closed loop runs through the real operations controller (job ops-controller,
-- security.ops_controller_tick_v1) and the learning step of job first-run-verify; a failed assertion raises and stops run.sh. Time between scheduled
-- runs is simulated by moving next_action_at into the past. Issues, work items and runs are synthetic.
\set ON_ERROR_STOP on
create or replace function pg_temp.ok(p_cond boolean, p_what text) returns void language plpgsql as $$
begin if p_cond is not true then raise exception 'FAILED: %', p_what; end if; raise notice 'ok: %', p_what; end $$;
create or replace function pg_temp.due(p_fp text) returns void language sql as $$
  update pipeline.integration_issues set next_action_at = now() - interval '1 minute' where fingerprint = p_fp;
  update pipeline.ops_remedy_runs set finished_at = finished_at - interval '1 hour' where result = 'acted' $$;
-- an earlier issue with its own controller run, to give a pattern a real history
create or replace function pg_temp.history(p_fp text, p_rc text, p_remedy text, p_result text, p_n int) returns void language plpgsql as $$
declare v_id bigint; i int;
begin
  insert into pipeline.integration_issues(fingerprint, title, layer, failure, expected, detection_source, severity, workstream, status, diagnosis)
  values (p_fp, p_fp, 'Platform', 'history', 'x', 'fixture', 'P2', 'A7', case when p_fp ~ ':(earlier|history)$' then 'closed' else 'triaged' end,
          jsonb_build_object('root_cause', p_rc, 'at', now() - interval '1 day'))
  on conflict (fingerprint) do update set diagnosis = excluded.diagnosis returning id into v_id;
  for i in 1 .. p_n loop
    insert into pipeline.ops_remedy_runs(issue_id, remedy_code, started_at, finished_at, result, evidence, after)
    values (v_id, p_remedy, now() - make_interval(hours => 30 - i), now() - make_interval(hours => 30 - i), p_result,
            jsonb_build_object('diagnosis', jsonb_build_object('root_cause', p_rc)), jsonb_build_object('verify', jsonb_build_object('condition_cleared', p_result = 'verified')));
  end loop;
end $$;

-- the seeds: real outcomes only, with who achieved them ------------------------------------------------------------------------------------------
select pg_temp.ok((select performed_by from pipeline.ops_remedy_knowledge where code = 'sch_classify_duplicate_key') = 'claude_engineering'
                  and (select performed_by from pipeline.ops_remedy_knowledge where code = 'course_link_approved_rules') = 'platform_admin'
                  and (select verified from pipeline.ops_remedy_knowledge where code = 'course_link_approved_rules') = 338,
                  'seeds: the classifier fix is Claude engineering; the Course Link rules are Platform Admin authority (338 decided)');
select pg_temp.ok(not auto_eligible and applied = 100 and verified = 10 and failed = 90, 'seeds: AER corrected re-reads of the same copy: 10 of 100, not automatic')
  from pipeline.ops_remedy_knowledge where code = 'aer_corrected_reread_same_copy';
select pg_temp.ok(count(*) = 1, 'seeds: the §7 baseline is taken at release') from pipeline.ops_learning_readings where kind = 'baseline';

-- §6 AER: technically held items, a verified remedy chosen by the controller, executed, verified, the items advance ----------------------------------
select pg_temp.history('work_blocked:aer_technical:technical_hold:earlier', 'work_technical_hold', 'work_retry_technical', 'verified', 1);
select security.ops_learning_tick_v1();
select pg_temp.ok(verified = 1 and auto_eligible, 'AER: an earlier verified outcome makes work_retry_technical a verified pattern for work_technical_hold')
  from pipeline.ops_remedy_knowledge where code = 'work_retry_technical:work_technical_hold';
insert into pipeline.work_items(lane, entity, work_kind, stage, failure_class, field) select 'aer_technical', 'item-' || g, 'l4_item', 'parked', 'technical_hold', 'entry_matrix_first_run' from generate_series(1, 3) g;
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'work_blocked:aer_technical:technical_hold', 'title', 'Work continuity: AER items held for a technical reason (3)',
  'failure', '3 item(s) of lane aer_technical are blocked by technical_hold', 'expected', 'they recover', 'severity', 'P2', 'validation_layer', 'V4'), 'work-continuity');
select security.ops_controller_tick_v1();
select pg_temp.ok(r.result = 'acted' and (r.evidence->'plan'->>'proposed') = 'work_retry_technical' and (r.evidence->'authorise'->>'permitted')::boolean,
                  'AER: the controller recognised work_technical_hold and chose the verified remedy itself; authorised and executed')
  from pipeline.ops_remedy_runs r join pipeline.integration_issues i on i.id = r.issue_id where i.fingerprint = 'work_blocked:aer_technical:technical_hold';
-- the scheduled AER reader takes the released items (aer-scheduled-read)
update pipeline.work_items set stage = 'done', recovered_at = now(), outcome = 'succeeded' where lane = 'aer_technical' and stage = 'eligible';
select pg_temp.due('work_blocked:aer_technical:technical_hold');
select security.ops_controller_tick_v1();
select security.ops_learning_tick_v1();
select pg_temp.ok(i.status = 'closed' and r.result = 'verified' and o.success and o.performed_by = 'platform' and k.verified = 2,
                  'AER: verified on a later run, the issue closed by the controller, the outcome kept (platform), the pattern now 2 verified')
  from pipeline.integration_issues i join pipeline.ops_remedy_runs r on r.issue_id = i.id join pipeline.ops_remedy_outcomes o on o.remedy_run_id = r.id
  join pipeline.ops_remedy_knowledge k on k.code = o.knowledge_code where i.fingerprint = 'work_blocked:aer_technical:technical_hold';
select pg_temp.ok(count(*) = 3, 'AER: the three items advanced to the next stage (read and done)') from pipeline.work_items where lane = 'aer_technical' and stage = 'done';
-- AER: the same stored copy is not read again; a changed copy is
select security.ops_learning_record_v1('{"code": "aer_corrected_reread_same_copy", "entity": "course-1", "evidence_signature": "copy:a0ffab81|reader:v1|rows:30", "success": false}');
select pg_temp.ok(not (security.ops_learning_retry_check_v1('aer_corrected_reread_same_copy', 'course-1', 'copy:a0ffab81|reader:v1|rows:30')->>'allowed')::boolean,
                  'AER: a re-read of the same copy with the same reader and settings is refused (it cannot work)');
select pg_temp.ok((security.ops_learning_retry_check_v1('aer_corrected_reread_same_copy', 'course-1', 'copy:77e0c1d2|reader:v1|rows:30')->>'allowed')::boolean,
                  'AER: when the copy changes, reconsideration is allowed automatically');
select pg_temp.ok(not (security.ops_learning_retry_check_v1('aer_reread_row_limit', 'course-2', 'copy:x|rows:30')->>'allowed')::boolean
                  and security.ops_learning_retry_check_v1('aer_reread_row_limit', 'course-2', 'copy:x|rows:30')->>'reason' like 'needs admin authority%',
                  'AER: a row-limit hold is never re-read; it waits for the row-boundary authority');

-- §6 Course Link: the same remedy works on one fingerprint and is stopped on another where it never works --------------------------------------------
-- success: approvals not yet on the website (projection lag); the recheck verified before and verifies again
select pg_temp.history('l4_not_published:official_course_url:earlier', 'layer4_approval_not_published', 'layer4_admission_recheck', 'verified', 1);
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'l4_not_published:official_course_url:projection_lag', 'title', 'Course Link approvals not yet on the website (12)',
  'failure', '12 approvals admitted but not in the projection', 'expected', 'published', 'severity', 'P2', 'validation_layer', 'V4'), 'layer4-readiness');
insert into fx.verify_pass select 'layer4_admission_recheck:' || id, true from pipeline.integration_issues where fingerprint = 'l4_not_published:official_course_url:projection_lag';
select security.ops_controller_tick_v1();
select pg_temp.due('l4_not_published:official_course_url:projection_lag');
select security.ops_controller_tick_v1();
select security.ops_learning_tick_v1();
select pg_temp.ok(i.status = 'closed' and exists (select 1 from pipeline.ops_remedy_outcomes o join pipeline.ops_remedy_runs r on r.id = o.remedy_run_id where r.issue_id = i.id and o.success),
                  'Course Link: the controller reused the verified recheck for a projection lag; verified, closed, outcome kept')
  from pipeline.integration_issues i where i.fingerprint = 'l4_not_published:official_course_url:projection_lag';
-- refusal: approvals refused by a manual lock; the recheck verified nothing three times on this fingerprint
select pg_temp.history('l4_not_admitted:official_course_url:manual_lock_kept', 'layer4_approval_not_admitted', 'layer4_admission_recheck', 'verify_failed', 3);
select security.ops_learning_tick_v1();
select pg_temp.ok(count(*) = 1, 'Course Link: three failures in a row on one fingerprint open a block for it') from pipeline.ops_remedy_blocks
 where fingerprint = 'l4_not_admitted:official_course_url:manual_lock_kept' and lifted_at is null;
-- the issue comes back with its attempts reset (as after a reopening); the controller plans the same recheck
update pipeline.integration_issues set remedy_code = null, remedy_attempts = 0, next_action_at = now() - interval '1 minute', diagnosis = null,
       ops_plan = jsonb_build_object('proposed', 'layer4_admission_recheck') where fingerprint = 'l4_not_admitted:official_course_url:manual_lock_kept';
create temp table runs0 as select count(*) n from pipeline.ops_remedy_runs r join pipeline.integration_issues i on i.id = r.issue_id where i.fingerprint = 'l4_not_admitted:official_course_url:manual_lock_kept';
select security.ops_learning_tick_v1();
select security.ops_controller_tick_v1();
select pg_temp.ok((select count(*) from pipeline.ops_remedy_runs r join pipeline.integration_issues i on i.id = r.issue_id where i.fingerprint = 'l4_not_admitted:official_course_url:manual_lock_kept') = (select n from runs0)
                  and i.ops_state in ('needs_release', 'needs_decision') and i.blocker->>'reason' like 'attempts used up%'
                  and exists (select 1 from pipeline.integration_issue_events e where e.issue_id = i.id and e.note like 'Recovery knowledge: layer4_admission_recheck is not run again on this fingerprint%'),
                  'Course Link: the controller does not repeat the ineffective recheck; the issue is routed with the evidence')
  from pipeline.integration_issues i where i.fingerprint = 'l4_not_admitted:official_course_url:manual_lock_kept';
select pg_temp.ok(prevented >= 1, 'Course Link: the prevented repeat is counted') from pipeline.ops_remedy_blocks where fingerprint = 'l4_not_admitted:official_course_url:manual_lock_kept';
-- when the evidence changes (a fix is deployed), the block lifts and the remedy may be tried again
update pipeline.integration_issues set fix_migration = '20261104999999', deployed_version = 'v2.15.999' where fingerprint = 'l4_not_admitted:official_course_url:manual_lock_kept';
select security.ops_learning_tick_v1();
select pg_temp.ok(lifted_at is not null and lift_reason like 'evidence changed:%', 'Course Link: a deployed fix changes the evidence and lifts the block')
  from pipeline.ops_remedy_blocks where fingerprint = 'l4_not_admitted:official_course_url:manual_lock_kept';

-- a remedy that never works anywhere loses automatic eligibility; the Authorise step refuses it (fees, IQ-00111's history) -------------------------------
select pg_temp.history('fee:ai_reader_credit_point_unit:history', 'fee_reader_units_misread', 'fee_integrity_recheck', 'verify_failed', 6);
select security.ops_learning_tick_v1();
select pg_temp.ok(not auto_eligible and eligibility_reason like '0 of its last 6 outcomes verified%', 'fees: 0 of 6 verified: the remedy loses automatic eligibility')
  from pipeline.ops_remedy_knowledge where code = 'fee_integrity_recheck:fee_reader_units_misread';
select pg_temp.ok(count(*) = 1 and min(assignee) = 'engineering', 'fees: the ineffective remedy is raised once, owned by engineering') from pipeline.integration_issues where fingerprint = 'remedy_ineffective:fee_integrity_recheck';
select pg_temp.ok(not (security.ops_authorise_v1('fee_integrity_recheck')->>'permitted')::boolean
                  and security.ops_authorise_v1('fee_integrity_recheck')->>'reason' like 'lost automatic eligibility (recovery knowledge)%', 'fees: Authorise refuses it');
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'fee:ai_reader_units:new', 'title', 'AI fee divided by units again', 'failure', 'f', 'expected', 'x', 'severity', 'P1', 'validation_layer', 'V4'), 'fee-guard');
select security.ops_controller_tick_v1();
select pg_temp.ok(r.result = 'refused_authority' and i.ops_state = 'needs_release', 'fees: a new occurrence is not remedied automatically: the run is refused and the issue routed to a release')
  from pipeline.ops_remedy_runs r join pipeline.integration_issues i on i.id = r.issue_id where i.fingerprint = 'fee:ai_reader_units:new';
do $$ begin
  begin perform security.ops_learning_eligibility_set_v1('fee_integrity_recheck:fee_reader_units_misread', true, 'short', 'x'); raise exception 'restored without authority';
  exception when sqlstate '22023' then null; end;
end $$;
select pg_temp.ok(true, 'fees: eligibility is restored only with an evidence-based reason and a named authority');

-- §6 scholarships: a known code defect recurs: owned engineering work, never repeated automatically; an unauthorised recovery is parked ----------------
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'job_failed:scholarship-coverage-classify', 'title', 'Scheduled job "scholarship-coverage-classify" failed',
  'failure', 'failed', 'expected', 'runs succeed', 'severity', 'P1', 'validation_layer', 'V4',
  'evidence', jsonb_build_object('detail', jsonb_build_object('job', 'scholarship-coverage-classify', 'last_error', 'ERROR:  ON CONFLICT DO UPDATE command cannot affect row a second time'))), 'integration-validate');
select security.first_run_verify_tick_v1();
select pg_temp.ok(assignee = 'engineering' and remediation_status = 'engineering_open', 'scholarships: the recurring classifier defect becomes owned engineering work (the known pattern is Claude engineering)')
  from pipeline.integration_issues where fingerprint = 'job_failed:scholarship-coverage-classify';
select pg_temp.ok(not (security.ops_learning_retry_check_v1('sch_classify_duplicate_key', 'job:scholarship-coverage-classify', 'c072494c')->>'allowed')::boolean,
                  'scholarships: the code fix is never retried as an automatic remedy');

-- §1 and §7 ---------------------------------------------------------------------------------------------------------------------------------------------
select pg_temp.ok(jsonb_array_length(security.autonomy_audit_v1(24)->'categories') = 7, 'section 1: seven categories');
select pg_temp.ok((select count(*) from jsonb_array_elements(security.ops_learning_report_v1()->'table')) = 7
                  and (select x->>'verified_outcome' from jsonb_array_elements(security.ops_learning_report_v1()->'table') x where x->>'metric' = 'repeated_ineffective_prevented') = 'improved',
                  'section 7: seven metrics with baseline and current; prevented repeats improved on the baseline');
select pg_temp.ok(security.self_sustainability_v1(24) ?& array['autonomy', 'recovery_learning'], 'section 7: in the ops_report_v1 self_sustainability section');
