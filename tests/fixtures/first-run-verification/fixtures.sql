-- CF-247 first-run verification fixtures (migration 20261104460000). Each case replays a production failure of 3-4 Nov 2026 on the fixture database
-- and asserts the outcome; a failed assertion raises and stops run.sh. Times are relative to now(); runs, issues and rows are synthetic.
\set ON_ERROR_STOP on
create or replace function pg_temp.ok(p_cond boolean, p_what text) returns void language plpgsql as $$
begin if p_cond is not true then raise exception 'FAILED: %', p_what; end if; raise notice 'ok: %', p_what; end $$;

-- the schedule: the expected first run is the job's next scheduled minute (pg_cron runs in UTC)
select pg_temp.ok(security.cron_next_run_v1('29 * * * *', '2026-11-03 19:03:51+00') = '2026-11-03 19:29:00+00', 'expected first run of v2.15.460 classify (29 * * * *) after the 06:03 AEDT merge: 06:29 AEDT');
select pg_temp.ok(security.cron_next_run_v1('4-59/10 * * * *', '2026-11-03 12:00:30+00') = '2026-11-03 12:04:00+00', 'ranges with steps (4-59/10)');
select pg_temp.ok(security.cron_next_run_v1('2,32 * * * *', '2026-11-03 12:02:00+00') = '2026-11-03 12:32:00+00', 'lists (2,32), strictly after');
select pg_temp.ok(security.cron_next_run_v1('23 18 * * *', '2026-11-04 19:00:00+00') = '2026-11-05 18:23:00+00', 'daily job: next day');
select pg_temp.ok(security.cron_next_run_v1('23 16 * * 0', '2026-11-07 00:00:00+00') = '2026-11-08 16:23:00+00', 'weekly job (Sunday)');
select pg_temp.ok(security.cron_next_run_v1('23 16 * * 7', '2026-11-07 00:00:00+00') = '2026-11-08 16:23:00+00', 'day of week 7 is Sunday');
select pg_temp.ok(security.cron_next_run_v1('30 seconds', now()) is null, 'a schedule in seconds has no minute to expect');
select pg_temp.ok(security.cron_next_run_v1('0 0 1 1 *', '2026-11-04 00:00:00+00') is null, 'no run inside frv.next_run_search_hours: null, not a guess');

-- jobs and the run history as live (ids synthetic)
insert into cron.job(jobname, schedule, command, active) values
 ('scholarship-coverage-classify', '29 * * * *', 'select security.scholarship_coverage_classify_v1()', true),
 ('course-relink', '4-59/10 * * * *', 'select security.course_relink_tick_v1(security.pipeline_num_v1(''batch.course_relink'', 200)::int)', true),
 ('aer-scheduled-read', '13 * * * *', 'select security.aer_schedule_tick_v1()', true),
 ('work-continuity', '8,18,28,58 * * * *', 'select security.work_continuity_tick_v1()', true),
 ('scholarship-read', '*/5 * * * *', 'select 1', true),
 ('never-fires', '* * * * *', 'select security.never_fires_v1()', true),
 ('built-but-off', '* * * * *', 'select security.built_but_off_v1()', false),
 ('coverage-discover', '* * * * *', 'select 1', false), ('coverage-discover-2', '* * * * *', 'select 1', false)
on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command, active = excluded.active;
create temp table j as select jobname, jobid from cron.job;
-- older history: runs before every deployment below
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from j where jobname = 'course-relink'), 'succeeded', '1 row', now() - make_interval(hours => 10) + make_interval(mins => g), now() - make_interval(hours => 10) + make_interval(mins => g)
  from generate_series(1, 30) g;

-- settings, Layer 4 work and jobs are only read: snapshot them
create temp table snap as select
  (select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings) settings,
  (select md5(string_agg(jobname || schedule || command || active::text, '|' order by jobname)) from cron.job) jobs,
  (select count(*) from pipeline.layer4_review_items) l4;

-- case 1: v2.15.460 scholarship-coverage-classify, first run failed (ON CONFLICT twice); IQ-00239 raised by the controller's validator --------------
insert into pipeline.integration_deploy_checks(release, checked_at, since, ok, result) values ('v2.15.460', now() - interval '150 minutes', now() - interval '150 minutes', true, '{}');
select pg_temp.ok((security.release_first_run_register_v1('v2.15.460', '[]', '{"security.scholarship_coverage_classify_v1(uuid[])": "a268ce816990d71ef545dbdc0ae28a5e"}',
                   now() - interval '150 minutes')->>'jobs')::int = 1, 'v2.15.460 registers the job whose command calls the changed function');
select pg_temp.ok(status = 'awaiting_first_run' and transition_key = 'sch_classification' and expected_first_run > deployed_at and expected_first_run <= deployed_at + interval '1 hour',
                  'awaiting its first run, expected within the hour, output counted on sch_classification')
  from pipeline.release_job_verifications where release = 'v2.15.460';
select pg_temp.ok(operational_status = 'awaiting_first_run', 'the deploy check says deployed, operationally unverified') from pipeline.integration_deploy_checks where release = 'v2.15.460';
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
values ((select jobid from j where jobname = 'scholarship-coverage-classify'), 'failed',
        E'ERROR:  ON CONFLICT DO UPDATE command cannot affect row a second time\nHINT:  Ensure that no rows proposed for insertion within the same command have duplicate constrained values.',
        (select expected_first_run from pipeline.release_job_verifications where release = 'v2.15.460'), (select expected_first_run + interval '20 seconds' from pipeline.release_job_verifications where release = 'v2.15.460'));
-- the controller's validator had raised IQ-00239 from the health issue (as live: evidence.detail.last_error)
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'job_failed:scholarship-coverage-classify',
  'title', 'Scheduled job "scholarship-coverage-classify" failed 1 of 1 run(s) in the last hour; the last run failed', 'layer', 'Scheduling', 'subsystem', 'scheduled jobs',
  'failure', 'Scheduled job "scholarship-coverage-classify" failed 1 of 1 run(s) in the last hour; the last run failed', 'expected', 'runs succeed', 'validation_layer', 'V4', 'severity', 'P1',
  'evidence', jsonb_build_object('platform_issue', 'cron:failed:scholarship-coverage-classify', 'detail', jsonb_build_object('job', 'scholarship-coverage-classify',
    'last_error', E'ERROR:  ON CONFLICT DO UPDATE command cannot affect row a second time\nHINT:  Ensure', 'last_three_failed', true)), 'status', 'triaged'), 'integration-validate');
select security.first_run_verify_tick_v1();
select pg_temp.ok(v.status = 'failed_first_run' and v.first_run_status = 'failed' and v.first_runid is not null and v.status_reason like '%cannot affect row a second time%',
                  'case 1: failed_first_run with the run id and the error text')
  from pipeline.release_job_verifications v where v.release = 'v2.15.460';
select pg_temp.ok(i.fingerprint = 'job_failed:scholarship-coverage-classify' and i.evidence->'first_run'->>'runid' is not null,
                  'case 1: the failure updates the job''s own issue (IQ-00239''s fingerprint) with the run id')
  from pipeline.release_job_verifications v join pipeline.integration_issues i on i.id = v.issue_id where v.release = 'v2.15.460';
select pg_temp.ok(operational_status = 'failed_first_run', 'case 1: the release is failed_first_run on its deploy check') from pipeline.integration_deploy_checks where release = 'v2.15.460';
select pg_temp.ok(assignee = 'engineering' and status = 'assigned' and remediation_owner = 'engineering' and remediation_status = 'engineering_open' and root_cause_class = 'code_defect'
                  and remediation_checkpoint_at > now() and remediation_checkpoint_at <= now() + interval '4 hours' and remediation_evidence->>'error_class' = 'sql_cardinality'
                  and remediation_evidence->>'job' = 'scholarship-coverage-classify',
                  'case 1: the SQL defect is owned engineering work: assignee, assigned, code_defect, error class, job and a 4-hour checkpoint')
  from pipeline.integration_issues where fingerprint = 'job_failed:scholarship-coverage-classify';

-- case 2: IQ-00241 raised by hand for the same fault, its fix deployed; the two are linked (one canonical) -----------------------------------------
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'sch_coverage_classify_on_conflict_v2.15.460',
  'title', 'v2.15.460: scholarship-coverage-classify fails (ON CONFLICT DO UPDATE affects a row twice); coverage tables empty', 'layer', 'Layer 2', 'subsystem', 'scholarship coverage',
  'failure', 'First run 06:29 AEDT 4 Nov failed: ON CONFLICT DO UPDATE command cannot affect row a second time; pipeline.scholarship_coverage_items and scholarship_coverage_providers empty',
  'expected', 'classification runs', 'severity', 'P1', 'root_cause_class', 'code_defect', 'status', 'in_progress',
  'evidence', jsonb_build_object('job', 'scholarship-coverage-classify', 'release', 'v2.15.460', 'migration', '20261104390000')), 'Integration Controller');
select security.integration_issue_transition_v1(id, 'code_ready', 'Integration Controller'), security.integration_issue_transition_v1(id, 'integration_testing', 'Integration Controller'),
       security.integration_issue_transition_v1(id, 'deployed', 'Integration Controller')
  from pipeline.integration_issues where fingerprint = 'sch_coverage_classify_on_conflict_v2.15.460';
select security.first_run_verify_tick_v1();
select pg_temp.ok(a.superseded_by = b.id and a.ops_state = 'superseded' and b.id = any (b.supersedes) is false and a.id = any (b.supersedes) and b.evidence->'superseded' ? a.issue_ref,
                  'case 2: IQ-00239 (assigned) is linked into IQ-00241 (deployed, furthest along): superseded, listed, evidence carried over')
  from pipeline.integration_issues a, pipeline.integration_issues b
 where a.fingerprint = 'job_failed:scholarship-coverage-classify' and b.fingerprint = 'sch_coverage_classify_on_conflict_v2.15.460';
select pg_temp.ok(count(*) = 1, 'case 2: a supersede_into_owner run is recorded, so the controller closes the duplicate with its canonical issue')
  from pipeline.ops_remedy_runs r join pipeline.integration_issues a on a.id = r.issue_id
 where a.fingerprint = 'job_failed:scholarship-coverage-classify' and r.remedy_code = 'supersede_into_owner' and r.result = 'acted';
select pg_temp.ok(count(*) = 2, 'case 2: both histories record the link') from pipeline.integration_issue_events e
 where e.actor = 'first-run-verify' and (e.note like 'Same failure as IQ-%' or e.note like 'Canonical issue for IQ-%');
select pg_temp.ok(b.status = 'deployed' and b.remediation_status = 'awaiting_first_run' and b.assignee = 'engineering' and b.remediation_evidence->>'job' = 'scholarship-coverage-classify',
                  'case 2: the canonical issue, fix deployed, is owned engineering work awaiting its first run')
  from pipeline.integration_issues b where b.fingerprint = 'sch_coverage_classify_on_conflict_v2.15.460';
select security.first_run_verify_tick_v1();
select pg_temp.ok(count(*) = 1, 'case 2: idempotent: a second check links nothing again') from pipeline.ops_remedy_runs r where r.remedy_code = 'supersede_into_owner';
select pg_temp.ok(count(*) = 1, 'case 2: no duplicate issue was created for the job') from pipeline.integration_issues where fingerprint like 'job_failed:scholarship-coverage-classify%';

-- case 3: v2.15.461 (the fix) first run succeeds, creates cases and queues recovery: operationally verified; issues marked verified, left open ---------
select security.release_first_run_register_v1('v2.15.461', '[{"job": "scholarship-coverage-classify"}]', '{}', now() - interval '50 minutes');
select pg_temp.ok(remediation_status = 'fix_released' and remediation_evidence->>'fix_release' = 'v2.15.461', 'case 3: registering the fix release marks the open remediation fix_released')
  from pipeline.integration_issues where fingerprint = 'job_failed:scholarship-coverage-classify';
insert into pipeline.scholarship_page_candidates(provider_id, url, found_at) select gen_random_uuid(), 'https://example.edu/s' || g, now() - interval '3 days' from generate_series(1, 5) g;
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
values ((select jobid from j where jobname = 'scholarship-coverage-classify'), 'succeeded', '1 row', now() - interval '30 minutes', now() - interval '29 minutes');
insert into pipeline.scholarship_coverage_items(provider_id, item_key, state, classified_at)
select gen_random_uuid(), 'k' || g, case when g % 3 = 0 then 'traversal_incomplete' when g % 3 = 1 then 'published_verified' else 'rejected_correctly' end, now() - interval '29 minutes'
  from generate_series(1, 30) g;
select security.first_run_verify_tick_v1();
select pg_temp.ok(v.status = 'operationally_verified' and v.actual_output = 30 and v.downstream_eligible = 10 and v.verified_at is not null,
                  'case 3: v2.15.461 operationally verified: 30 cases created, 10 recoverable cases eligible downstream')
  from pipeline.release_job_verifications v where v.release = 'v2.15.461';
select pg_temp.ok(count(*) filter (where remediation_status = 'verified') = 2 and count(*) filter (where status = 'closed') = 0,
                  'case 3: both issues marked verified with the evidence; closing stays with the controller (recovery.close_on_verified_on 0)')
  from pipeline.integration_issues where fingerprint in ('job_failed:scholarship-coverage-classify', 'sch_coverage_classify_on_conflict_v2.15.460');

-- case 4: v2.15.443 course relink: the fix was deployed, its first scheduled runs still time out: the issue returns to in_progress -------------------
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'job_failed:course-relink', 'title', 'Scheduled job "course-relink" failed 2 of 6 run(s) in the last hour',
  'failure', 'failed', 'expected', 'runs succeed', 'severity', 'P1', 'validation_layer', 'V4', 'status', 'in_progress',
  'evidence', jsonb_build_object('detail', jsonb_build_object('job', 'course-relink', 'last_error', 'ERROR:  canceling statement due to statement timeout'), 'failed_runs', 2)), 'integration-validate');
select security.integration_issue_transition_v1(id, 'code_ready', 'IC'), security.integration_issue_transition_v1(id, 'integration_testing', 'IC'), security.integration_issue_transition_v1(id, 'deployed', 'IC')
  from pipeline.integration_issues where fingerprint = 'job_failed:course-relink';
select security.release_first_run_register_v1('v2.15.443', '[]', '{"security.course_relink_tick_v1(integer)": "656d308b"}', now() - interval '25 minutes');
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from j where jobname = 'course-relink'), 'failed', E'ERROR:  canceling statement due to statement timeout\nCONTEXT:  SQL function "course_relink_slugs_v1" statement 1',
       expected_first_run, expected_first_run + interval '60 seconds' from pipeline.release_job_verifications where release = 'v2.15.443';
select security.first_run_verify_tick_v1();
select pg_temp.ok(v.status = 'failed_first_run' and i.status = 'in_progress' and i.verification_outcome = 'failed' and i.remediation_status = 'returned'
                  and exists (select 1 from pipeline.integration_issue_events e where e.issue_id = i.id and e.from_status = 'deployed' and e.to_status = 'in_progress' and e.note like '%failed again%'),
                  'case 4: a deployed fix whose first run fails goes back to in_progress with the new evidence (remediation returned)')
  from pipeline.release_job_verifications v join pipeline.integration_issues i on i.fingerprint = 'job_failed:course-relink' where v.release = 'v2.15.443';

-- case 5: activation: a job that never fires, and a job built but left off ----------------------------------------------------------------------------
select security.release_first_run_register_v1('vX.never', '["never-fires"]', '{}', now() - interval '2 hours');
select security.release_first_run_register_v1('vX.off', '["built-but-off"]', '{}', now() - interval '30 hours');
select security.release_first_run_register_v1('vX.missing', '["no-such-job"]', '{}', now() - interval '1 hour');
select security.first_run_verify_tick_v1();
select pg_temp.ok(status = 'failed_first_run' and first_run_status = 'did_not_run' and status_reason like 'no run started by%', 'case 5: an active job with no run past its expected time and grace: did_not_run')
  from pipeline.release_job_verifications where release = 'vX.never';
select pg_temp.ok(count(*) = 1, 'case 5: did_not_run raises first_run:<job> (not a job failure fingerprint)') from pipeline.integration_issues where fingerprint = 'first_run:never-fires';
select pg_temp.ok(v.status = 'awaiting_first_run' and v.status_reason = 'job inactive: awaiting activation' and v.active_at_deploy is false and i.fingerprint = 'first_run:built-but-off'
                  and i.severity = 'P2' and i.assignee = 'engineering',
                  'case 5: built but off: stays awaiting activation; past frv.verify_deadline_hours it is raised with an owner (no indefinite built-but-off)')
  from pipeline.release_job_verifications v join pipeline.integration_issues i on i.id = v.issue_id where v.release = 'vX.off';
select pg_temp.ok(status = 'failed_first_run' and status_reason like 'not scheduled%', 'case 5: a release naming a job that is not scheduled is failed at once')
  from pipeline.release_job_verifications where release = 'vX.missing';

-- case 6: zero output needs a reason: AER cap (held), no eligible work (verified), technical zero (failed) -------------------------------------------
insert into pipeline.entry_matrix_sources(provider_id, url, status, read_at, created_at) values (gen_random_uuid(), 'https://uni.example/aer', 'read', now() - interval '2 days', now() - interval '2 days');
insert into pipeline.aer_schedule_runs(ran_at, course_reads, layer4_waiting, back_pressure, room, refusal)
values (now() - interval '20 minutes', 0, 605, true, 0, 'the daily cap is reached');
select security.release_first_run_register_v1('vX.aer', '["aer-scheduled-read", "work-continuity", {"job": "scholarship-read", "transition": "sch_reading"}]', '{}', now() - interval '70 minutes');
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select (select jobid from j where jobname = v.jobname), 'succeeded', '1 row', v.expected_first_run, v.expected_first_run + interval '5 seconds'
  from pipeline.release_job_verifications v where v.release = 'vX.aer';
insert into pipeline.scholarship_page_candidates(provider_id, url, found_at) values (gen_random_uuid(), 'https://example.edu/unread', now() - interval '3 days');
select security.first_run_verify_tick_v1();
select pg_temp.ok(status = 'awaiting_first_run' and zero_reason = 'cap_reached' and status_reason like '%held: cap_reached%',
                  'case 6: AER reading succeeded with 0 rows behind a valid cap (605 of 600): held, not verified, not failed')
  from pipeline.release_job_verifications where release = 'vX.aer' and jobname = 'aer-scheduled-read';
select pg_temp.ok(status = 'operationally_verified' and zero_reason = 'no_eligible_work', 'case 6: no eligible work is a justified zero')
  from pipeline.release_job_verifications where release = 'vX.aer' and jobname = 'work-continuity';
select pg_temp.ok(status = 'failed_first_run' and zero_reason = 'technical_failure' and status_reason like '%created nothing with eligible work%',
                  'case 6: a successful run that created nothing with eligible work is not operational success')
  from pipeline.release_job_verifications where release = 'vX.aer' and jobname = 'scholarship-read';

-- case 7: the progress contract: stalls, blocks and isolation --------------------------------------------------------------------------------------
select security.progress_read_v1();
select pg_temp.ok(stalled and zero_reason = 'technical_failure' and issue_id is not null, 'case 7: reading with eligible pages and no read for progress.stall_hours is stalled and raised')
  from pipeline.progress_transitions where key = 'sch_reading';
select pg_temp.ok(count(*) = 1 and min(severity) = 'P2', 'case 7: one stall issue by fingerprint stall:sch_reading') from pipeline.integration_issues where fingerprint = 'stall:sch_reading';
select pg_temp.ok(not stalled and zero_reason = 'cap_reached', 'case 7: AER extraction at its cap is held, not stalled') from pipeline.progress_transitions where key = 'aer_extraction';
insert into pipeline.aer_gap_findings(provider_id, root_cause, state, next_action) select gen_random_uuid(), 'no_source', 'open', 'source discovery' from generate_series(1, 4);
select security.progress_read_v1();
select pg_temp.ok(zero_reason = 'blocked_authority' and zero_detail like 'producing job(s) paused%' and input_eligible = 4 and not stalled,
                  'case 7: AER source discovery with course page discovery paused: blocked by authority, 4 providers waiting, not reported as success')
  from pipeline.progress_transitions where key = 'aer_source_discovery';
select pg_temp.ok(zero_reason = 'blocked_authority' and zero_detail like 'switched off:%', 'case 7: scholarship source recovery with every family switched off: blocked by authority')
  from pipeline.progress_transitions t where key = 'sch_source_recovery' and input_eligible > 0;
select pg_temp.ok(output_created = 30 and zero_reason is null and downstream_queued = 10 and last_advanced_at is not null, 'case 7: classification advanced: 30 created, 10 downstream')
  from pipeline.progress_transitions where key = 'sch_classification';
alter table pipeline.aer_schedule_runs rename column back_pressure to back_pressure_x;
select pg_temp.ok((security.progress_read_v1()->>'errors')::int = 1, 'case 7: one transition that cannot be read is recorded; the others still read');
select pg_temp.ok(measure_error is not null, 'case 7: the read error is kept on its transition') from pipeline.progress_transitions where key = 'aer_extraction';
select pg_temp.ok(measure_error is null, 'case 7: the next transition read normally') from pipeline.progress_transitions where key = 'aer_completeness';
alter table pipeline.aer_schedule_runs rename column back_pressure_x to back_pressure;
select pg_temp.ok(count(distinct transition_key) = 16, 'case 7: every transition has readings in the history') from pipeline.progress_observations;

-- case 8: routing rules: a time-out needs repeats; a checkpoint passed without change is recorded once and moved ---------------------------------------
select security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'job_failed:once-slow', 'title', 'Scheduled job "once-slow" failed 1 of 6 run(s)', 'failure', 'failed',
  'expected', 'x', 'severity', 'P2', 'evidence', jsonb_build_object('detail', jsonb_build_object('job', 'once-slow', 'last_error', 'ERROR:  canceling statement due to statement timeout'))), 'integration-validate');
select security.recovery_route_engineering_v1();
select pg_temp.ok(remediation_owner is null and assignee is null, 'case 8: one time-out is not yet a defect (ops.permanent_after_runs)') from pipeline.integration_issues where fingerprint = 'job_failed:once-slow';
update pipeline.integration_issues set remediation_checkpoint_at = now() - interval '1 minute' where fingerprint = 'sch_coverage_classify_on_conflict_v2.15.460';
select security.recovery_route_engineering_v1();
select pg_temp.ok(i.remediation_checkpoint_at > now() and exists (select 1 from pipeline.integration_issue_events e where e.issue_id = i.id and e.note like 'Engineering checkpoint passed with no change%'),
                  'case 8: a checkpoint passed with no change is recorded and the next one set')
  from pipeline.integration_issues i where i.fingerprint = 'sch_coverage_classify_on_conflict_v2.15.460';
update pipeline.platform_toolset_settings set value = to_jsonb(0) where key in ('recovery.link_on', 'recovery.route_on', 'frv.on', 'progress.on');
select pg_temp.ok(security.first_run_verify_tick_v1() = '{"link": {"off": true}, "route": {"off": true}, "progress": {"off": true}}'::jsonb, 'case 8: every part has its own switch');
update pipeline.platform_toolset_settings set value = to_jsonb(1) where key in ('recovery.link_on', 'recovery.route_on', 'frv.on', 'progress.on');

-- case 9: the controller now routes a job's SQL defect to a release, not a decision -----------------------------------------------------------------
select pg_temp.ok(security.ops_diagnose_v1(i.id, jsonb_build_object('job_failing', true, 'job', jsonb_build_object('last_failure_message', 'ERROR:  ON CONFLICT DO UPDATE command cannot affect row a second time')))->>'root_cause'
                  = 'first_run_sql_defect', 'case 9: a failing job with a SQL defect is diagnosed first_run_sql_defect (was unclassified -> needs_decision)')
  from pipeline.integration_issues i where i.fingerprint = 'job_failed:scholarship-coverage-classify';
select pg_temp.ok(security.ops_route_v1(i.id, jsonb_build_object('root_cause', 'first_run_sql_defect', 'evidence', '[]'::jsonb), 'no automatic remedy') = 'needs_release',
                  'case 9: and routed needs_release (engineering_remediation, authority release)')
  from pipeline.integration_issues i where i.fingerprint = 'job_failed:once-slow';

-- case 10: authority: nothing but records changed; the scorecard reads ------------------------------------------------------------------------------
select pg_temp.ok((select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings) = s.settings
                  and (select md5(string_agg(jobname || schedule || command || active::text, '|' order by jobname)) from cron.job) = s.jobs
                  and (select count(*) from pipeline.layer4_review_items) = s.l4, 'case 10: no setting, job or Layer 4 item changed by any check') from snap s;
select pg_temp.ok(jsonb_array_length(security.self_sustainability_v1(24)->'measures') = 10, 'case 10: the scorecard has the ten measures of §10');
select pg_temp.ok((select x->>'verdict' from jsonb_array_elements(security.self_sustainability_v1(24)->'measures') x where x->>'measure' = 'release_correctness') = 'not_met',
                  'case 10: release correctness is not met while a release failed its first run');
select pg_temp.ok((select x->>'verdict' from jsonb_array_elements(security.self_sustainability_v1(24)->'measures') x where x->>'measure' = 'unattended_operation') = 'not_met',
                  'case 10: unattended operation is not met with failures in the window');
