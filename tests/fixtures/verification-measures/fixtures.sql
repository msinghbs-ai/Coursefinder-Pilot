-- CF-247 verification-measures fixtures (migration 20261104500000). Each case asserts an outcome; a failed assertion raises and stops run.sh.
-- Times are relative to now(); jobs, runs, issues and rows are synthetic.
\set ON_ERROR_STOP on
create or replace function pg_temp.ok(p_cond boolean, p_what text) returns void language plpgsql as $$
begin if p_cond is not true then raise exception 'FAILED: %', p_what; end if; raise notice 'ok: %', p_what; end $$;

insert into cron.job(jobname, schedule, command, active) values
 ('layer4-readiness', '22,52 * * * *', 'select security.layer4_readiness_tick_v1()', true),
 ('layer4-interventions', '14,44 * * * *', 'select security.layer4_interventions_tick_v1()', true),
 ('first-run-verify', '2,32 * * * *', 'select security.first_run_verify_tick_v1()', true)
on conflict (jobname) do update set active = true;
create temp table j as select jobname, jobid from cron.job;
create temp table snap as select (select md5(string_agg(jobname || schedule || command || active::text, '|' order by jobname)) from cron.job) jobs,
  (select count(*) from pipeline.layer4_review_items where status = 'pending') pending;

-- case 1 (§6): a release names the job's output contract --------------------------------------------------------------------------------------
select security.release_first_run_register_v1('vT.readiness-zero', '["layer4-readiness"]', '{}', now() - interval '70 minutes');
select pg_temp.ok(transition_key = 'l4_readiness' and status = 'awaiting_first_run', 'case 1: layer4-readiness is registered on its output contract (l4_readiness)')
  from pipeline.release_job_verifications where release = 'vT.readiness-zero';
select pg_temp.ok((select count(*) from pipeline.job_output_contracts) = 3 and (select outputs from pipeline.job_output_contracts where jobname = 'layer4-interventions')
                  = '{created,reused,resolved,returned_to_recovery,awaiting_human_input}', 'case 1: three contracts; interventions name the five outputs of §6');

-- case 2: readiness with nothing pending: a zero is justified (no eligible work) -------------------------------------------------------------
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from j where jobname = 'layer4-readiness'), 'succeeded', '1 row', expected_first_run, expected_first_run + interval '12 seconds'
  from pipeline.release_job_verifications where release = 'vT.readiness-zero';
update pipeline.layer4_review_items set status = 'decided' where status = 'pending';
select security.first_run_verify_jobs_v1();
select pg_temp.ok(status = 'operationally_verified' and zero_reason = 'no_eligible_work', 'case 2: readiness with no pending item: a justified zero, verified')
  from pipeline.release_job_verifications where release = 'vT.readiness-zero';

-- case 3: readiness that classifies: checked, newly classified, technical-blocked, judgement-ready, superseded ----------------------------------
select security.release_first_run_register_v1('vT.readiness', '["layer4-readiness"]', '{}', now() - interval '40 minutes');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, created_at)
select 'course', gen_random_uuid(), 'course_entry_first_read', 'pending', now() - interval '10 minutes' from generate_series(1, 5);
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from j where jobname = 'layer4-readiness'), 'succeeded', '1 row', expected_first_run, expected_first_run + interval '12 seconds'
  from pipeline.release_job_verifications where release = 'vT.readiness';
insert into pipeline.layer4_readiness_runs(at, ms, result) values (now() - interval '5 minutes', 12014, '{"classified": 5, "gates": 2}');
insert into pipeline.layer4_item_readiness(item_id, field_code, item_created_at, readiness, classified_at)
select i.id, i.field_code, i.created_at, case when row_number() over () <= 2 then 'technical_blocked' else 'judgement_ready' end, now() - interval '5 minutes'
  from pipeline.layer4_review_items i where i.status = 'pending';
insert into pipeline.layer4_supersessions(item_id, field_code, reason, at) values (gen_random_uuid(), 'course_entry_first_read', 'duplicate_pending', now() - interval '5 minutes');
select security.first_run_verify_jobs_v1();
select pg_temp.ok(v.status = 'operationally_verified' and v.actual_output = 5 and (v.output_measure->>'newly_classified')::int = 5
                  and (v.output_measure->>'technical_blocked')::int = 2 and (v.output_measure->>'judgement_ready')::int = 3 and (v.output_measure->>'superseded')::int = 1
                  and (v.output_measure->>'checked')::int = 5,
                  'case 3: readiness verified on its output: 5 checked and newly classified, 2 technical-blocked, 3 judgement-ready, 1 superseded')
  from pipeline.release_job_verifications v where v.release = 'vT.readiness';

-- case 4: interventions: an open item, nothing produced, both generation switches off: held by authority, not verified ----------------------------
insert into pipeline.layer4_interventions(lane, entity, missing_fact, status, created_at, last_seen_at, updated_at)
values ('aer_source', 'p1', 'official_source', 'awaiting_input', now() - interval '3 hours', now() - interval '3 hours', now() - interval '3 hours');
update pipeline.platform_toolset_settings set value = to_jsonb(0) where key in ('har.generate_aer_on', 'har.generate_sch_on');
select security.release_first_run_register_v1('vT.interventions', '["layer4-interventions"]', '{}', now() - interval '50 minutes');
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from j where jobname = 'layer4-interventions'), 'succeeded', '1 row', expected_first_run, expected_first_run + interval '3 seconds'
  from pipeline.release_job_verifications where release = 'vT.interventions';
select security.first_run_verify_jobs_v1();
select pg_temp.ok(status = 'awaiting_first_run' and zero_reason = 'blocked_authority' and status_reason like '%held: blocked_authority%',
                  'case 4: interventions produced nothing with generation switched off: held by authority (the contract''s switches), not verified')
  from pipeline.release_job_verifications where release = 'vT.interventions';

-- case 5: generation on, interventions created, reused, resolved, returned: verified with the five outputs ----------------------------------------
update pipeline.platform_toolset_settings set value = to_jsonb(1) where key in ('har.generate_aer_on', 'har.generate_sch_on');
insert into pipeline.layer4_interventions(lane, entity, missing_fact, status, created_at, last_seen_at, updated_at, verified_at) values
 ('sch_coverage', 'p2', 'official_source', 'awaiting_input', now() - interval '2 minutes', now() - interval '2 minutes', now() - interval '2 minutes', null),
 ('sch_coverage', 'p3', 'official_source', 'resolved', now() - interval '1 day', now() - interval '1 day', now() - interval '1 minute', now() - interval '1 minute'),
 ('aer_source', 'p4', 'official_source', 'returned_technical', now() - interval '1 day', now() - interval '1 day', now() - interval '1 minute', null);
update pipeline.layer4_interventions set last_seen_at = now() - interval '1 minute' where entity = 'p1';
select security.first_run_verify_jobs_v1();
select pg_temp.ok(v.status = 'operationally_verified' and (v.output_measure->>'interventions_created')::int = 1 and (v.output_measure->>'reused')::int = 1
                  and (v.output_measure->>'resolved')::int = 1 and (v.output_measure->>'returned_to_recovery')::int = 1 and (v.output_measure->>'awaiting_human_input')::int = 2
                  and v.actual_output = 4, 'case 5: interventions verified: 1 created, 1 reused, 1 resolved, 1 returned to recovery, 2 awaiting human input')
  from pipeline.release_job_verifications v where v.release = 'vT.interventions';

-- case 6: first-run-verify's own row: measured on its readings, settles once its own run has finished -----------------------------------------------
select security.release_first_run_register_v1('vT.frv', '["first-run-verify"]', '{}', now() - interval '45 minutes');
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from j where jobname = 'first-run-verify'), 'running', null, expected_first_run, null from pipeline.release_job_verifications where release = 'vT.frv';
select security.first_run_verify_jobs_v1();
select pg_temp.ok(status = 'awaiting_first_run' and first_runid is null and status_reason like 'first run in progress%', 'case 6: a check that meets its own running run waits for it')
  from pipeline.release_job_verifications where release = 'vT.frv';
update cron.job_run_details set status = 'succeeded', end_time = start_time + interval '20 seconds', return_message = '1 row'
 where jobid = (select jobid from j where jobname = 'first-run-verify') and status = 'running';
select security.progress_read_v1();
select security.first_run_verify_jobs_v1();
select pg_temp.ok(status = 'operationally_verified' and transition_key = 'first_run_verify' and actual_output = 16,
                  'case 6: the next check settles it: verified on the 16 transitions it read (not "no output measure")')
  from pipeline.release_job_verifications where release = 'vT.frv';

-- case 7 (§6): the classifier keeps its answer: duplicate cases and report errors; a ledger failure never fails the run --------------------------------
insert into pipeline.coverage_provider_reconciliation(provider_id, domain, disposition) values
 ('11111111-1111-1111-1111-111111111111', 'scholarship', 'no_evidence'), ('22222222-2222-2222-2222-222222222222', 'scholarship', 'gap'),
 ('33333333-3333-3333-3333-333333333333', 'scholarship', 'out_of_scope');
insert into fx.sch_items values
 ('11111111-1111-1111-1111-111111111111', 'list:4:https://u.example/apply', 'traversal_incomplete', 'listing read before fan-out', '{"listing": 4, "n": 1}', 'refresh_listing'),
 ('11111111-1111-1111-1111-111111111111', 'list:4:https://u.example/apply', 'traversal_incomplete', 'listing read before fan-out', '{"listing": 4, "n": 2}', 'refresh_listing'),
 ('22222222-2222-2222-2222-222222222222', 'cand:9', 'awaiting_layer4', 'held', '{}', null),
 ('22222222-2222-2222-2222-222222222222', 'cand:10', 'source_found_unread', 'unread', '{}', null);
insert into fx.report_fail values ('awaiting_layer4');
create temp table r1 as select security.scholarship_coverage_classify_v1() res;
select pg_temp.ok(c.manual is false and c.providers = 2 and c.duplicate_cases = 1 and c.report_errors = 1 and c.report_error_last like 'awaiting_layer4:%' and c.result = (select res from r1),
                  'case 7: the scheduled run''s answer is kept: 2 providers, 1 duplicate case folded, 1 report error with its text, the whole answer')
  from pipeline.scholarship_coverage_classify_runs c order by c.id desc limit 1;
select pg_temp.ok((select count(*) from pipeline.scholarship_coverage_items where provider_id = '11111111-1111-1111-1111-111111111111') = 1, 'case 7: the repeated address is one case');
alter table pipeline.scholarship_coverage_classify_runs rename column duplicate_cases to duplicate_cases_x;
select pg_temp.ok((security.scholarship_coverage_classify_v1(array['22222222-2222-2222-2222-222222222222']::uuid[])->>'ran')::boolean, 'case 7: a failed ledger write never fails the run');
alter table pipeline.scholarship_coverage_classify_runs rename column duplicate_cases_x to duplicate_cases;
select security.scholarship_coverage_classify_v1(array['22222222-2222-2222-2222-222222222222']::uuid[]);
select pg_temp.ok(manual and providers = 1, 'case 7: a manual run (providers given) is recorded as manual') from pipeline.scholarship_coverage_classify_runs order by id desc limit 1;

-- case 8 (§10): governed severity --------------------------------------------------------------------------------------------------------------
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'coverage:scholarship:tafe-sa', 'title', 'Scholarship coverage: TAFE SA zero', 'failure', 'zero scholarships',
  'expected', 'x', 'severity', 'P1', 'status', 'triaged'), 'coverage-reconcile');
create temp table iq as select id, fingerprint, status, (select count(*) from pipeline.integration_issue_events e where e.issue_id = i.id) events from pipeline.integration_issues i
 where fingerprint = 'coverage:scholarship:tafe-sa';
do $$ begin
  begin perform security.integration_issue_severity_v1((select id from iq), 'P2', 'policy', 'Platform Admin', '{"x": 1}'); raise exception 'short reason accepted';
  exception when sqlstate '22023' then null; end;
  begin perform security.integration_issue_severity_v1((select id from iq), 'P2', 'Refused by the pilot admission policy, not missing data (decision item 22)', '', '{"x": 1}'); raise exception 'no authority accepted';
  exception when sqlstate '22023' then null; end;
  begin perform security.integration_issue_severity_v1((select id from iq), 'P2', 'Refused by the pilot admission policy, not missing data (decision item 22)', 'Platform Admin', '{}'); raise exception 'no evidence accepted';
  exception when sqlstate '22023' then null; end;
end $$;
select pg_temp.ok(true, 'case 8: a change without an evidence-based reason, an authority or evidence is refused');
select security.integration_issue_severity_v1((select id from iq), 'P2', 'Refused by the pilot admission policy (TAFE outside the non-university pilot), not missing data',
  'Platform Admin, decision pack item 22 (4 Nov 2026)', '{"provider_type": "tafe_polytechnic", "policy": "scholarship.pilot_only", "refusals": 3}');
select pg_temp.ok(i.severity = 'P2' and i.fingerprint = q.fingerprint and i.status = q.status and i.severity_decided_by like 'Platform Admin%'
                  and i.severity_decision->>'from' = 'P1' and i.severity_decision->>'to' = 'P2' and i.severity_decision->>'direction' = 'lowered'
                  and jsonb_array_length(i.evidence->'severity_decisions') = 1
                  and (select count(*) from pipeline.integration_issue_events e where e.issue_id = i.id) = q.events + 1
                  and exists (select 1 from pipeline.integration_issue_events e where e.issue_id = i.id and e.kind = 'updated' and e.note like 'Severity P1 -> P2 (governed decision)%'
                              and e.detail->'severity_decision'->>'authority' like 'Platform Admin%'),
                  'case 8: lowered P1 -> P2 with reason, authority, evidence and one history event; same fingerprint, status and row')
  from pipeline.integration_issues i, iq q where i.id = q.id;
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'coverage:scholarship:tafe-sa', 'title', 'x', 'failure', 'zero scholarships', 'expected', 'x', 'severity', 'P1'), 'coverage-reconcile');
select pg_temp.ok(severity = 'P2', 'case 8: the detector''s next P1 observation does not undo the governed decision') from pipeline.integration_issues where fingerprint = 'coverage:scholarship:tafe-sa';
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'ungoverned:x', 'title', 'x', 'failure', 'f', 'expected', 'x', 'severity', 'P2'), 'test');
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'ungoverned:x', 'title', 'x', 'failure', 'f', 'expected', 'x', 'severity', 'P1'), 'test');
select pg_temp.ok(severity = 'P1', 'case 8: an issue without a governed decision still escalates as before') from pipeline.integration_issues where fingerprint = 'ungoverned:x';
select security.integration_issue_severity_v1((select id from iq), 'P1', 'New evidence: an eligible international scholarship on the provider''s own site was refused',
  'Integration Controller under decision item 22', '{"candidate": 8435}');
select pg_temp.ok(severity = 'P1' and severity_decision->>'direction' = 'raised' and jsonb_array_length(evidence->'severity_decisions') = 2
                  and exists (select 1 from pipeline.integration_issue_events e where e.issue_id = i.id and e.kind = 'escalated'), 'case 8: a governed raise is recorded the same way')
  from pipeline.integration_issues i where fingerprint = 'coverage:scholarship:tafe-sa';
update pipeline.integration_issues set status = 'closed', closed_at = now() where fingerprint = 'ungoverned:x';
do $$ begin
  begin perform security.integration_issue_severity_v1((select id from pipeline.integration_issues where fingerprint = 'ungoverned:x'), 'P2', 'Refused by the pilot admission policy, not missing data', 'Platform Admin', '{"x": 1}');
        raise exception 'closed issue changed';
  exception when sqlstate '22023' then null; end;
end $$;
select pg_temp.ok(true, 'case 8: a closed issue is not changed (never closed or recreated to downgrade)');

-- case 9 (§7): states with no recovery condition --------------------------------------------------------------------------------------------------
insert into pipeline.work_items(lane, entity, work_kind, stage) values ('ai_extraction', '*lane', 'reflect', 'eligible'), ('course_relink', 'c-1', 'relink', 'failed');
insert into pipeline.work_items(lane, entity, work_kind, stage, unresolved_blocker, escalation) values
 ('aer_technical', 'i-1', 'l4_item', 'parked', '{"class": "technical_hold"}', '{"as": "release", "issue_id": 203}'),
 ('aer_technical', 'i-2', 'l4_item', 'parked', '{"class": "technical_hold"}', null);
insert into pipeline.field_enrich_items(course_id, field, state, reason) values ('44444444-4444-4444-4444-444444444444', 'intakes', 'failed', 'no answer could be recorded after 3 tries');
create temp table gaps as select security.recovery_condition_gaps_v1(true) g;
select pg_temp.ok((g->'work_items_no_condition'->>'count')::int = 1 and g->'work_items_no_condition'->'examples'->0->>'entity' = 'c-1',
                  'case 9: a failed work item with no next time, blocker, escalation or review is reported (lane markers excluded)') from gaps;
select pg_temp.ok((g->'work_items_blocked_no_next_no_escalation'->>'count')::int = 1 and (g->'work_items_parked_escalated_no_next'->>'count')::int = 1,
                  'case 9: a blocked item with no escalation is a gap; one escalated to its issue is reported apart') from gaps;
select pg_temp.ok((g->'field_reads_failed_no_work_item'->>'count')::int = 1, 'case 9 (deep): a failed field read with no work item is reported') from gaps;
select pg_temp.ok(not (security.recovery_condition_gaps_v1(false) ? 'field_reads_failed_no_work_item'), 'case 9: the light read leaves the two large tables alone');

-- case 10 (§11): the table by pipeline, the scope, and the scorecard -----------------------------------------------------------------------------------
create temp table pt as select security.pipeline_progress_table_v1(24) t;
select pg_temp.ok(jsonb_array_length(t->'pipelines') = 2 and (select bool_and(x ?& array['eligible', 'processed', 'technically_recovered', 'review_ready', 'human_decided', 'admitted', 'published', 'blocked'])
                  from jsonb_array_elements(t->'pipelines') x), 'case 10: scholarships and AER, each with the eight §11 columns') from pt;
select pg_temp.ok((t->'scholarship_scope'->>'in_scope_providers')::int = 2 and (t->'scholarship_scope'->>'classified')::int = 2
                  and t->'scholarship_scope'->>'meaning' like '%755 on 4 Nov%', 'case 10: the scope is the coverage ledger without out-of-scope; the 755 meaning is stated') from pt;
select pg_temp.ok((select x->'technically_recovered'->>'value' from jsonb_array_elements(t->'pipelines') x where x->>'pipeline' = 'scholarships')::int = 1
                  and (select x->'review_ready'->>'value' from jsonb_array_elements(t->'pipelines') x where x->>'pipeline' = 'scholarships')::int >= 1,
                  'case 10: scholarship interventions count as technically recovered (resolved) and review-ready (awaiting input)') from pt;
select security.progress_read_v1();
select pg_temp.ok(input_eligible = 2, 'case 10: the progress reading''s scholarship eligible is now the in-scope ledger, not providers with candidates')
  from pipeline.progress_transitions where key = 'sch_classification';
select pg_temp.ok(security.self_sustainability_v1(24) ?& array['pipelines', 'scholarship_scope', 'recovery_gaps', 'measures'], 'case 10: the scorecard (ops_report_v1 section) carries the table and the gaps');

-- case 11: authority: no job changed, no Layer 4 item decided by the checks --------------------------------------------------------------------------
select pg_temp.ok((select md5(string_agg(jobname || schedule || command || active::text, '|' order by jobname)) from cron.job) = s.jobs, 'case 11: no job changed') from snap s;
