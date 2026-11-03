-- Every case, with the shipped switches (and each remedy switch turned on where its case says so).
-- O: outcomes at every ended path; R: reconciliation of history; W: held tasks; T: the plan tick; A: the automatic planner (IQ-00064);
-- E: repeated empty cycles; H: self-healing remedies; P: paid answers kept and replayed; G: registration through workstream A's contract.
do $$
declare v_p uuid; v_j uuid; v_j2 uuid; v_r uuid; v jsonb; h text; hj text; v_i bigint; v_i2 bigint; v_i3 bigint;
begin
  -- O1-O9 every ended path records an explicit outcome through security.admin_job_close_v1, from real data movement
  perform fx.reset3();
  v_j := fx.task3('enrich_fields', 'done', '{"cost_usd": 0.01}'); perform fx.items(v_j, 2, 8); perform security.admin_job_close_v1(v_j);
  perform fx.ok(fx.outcome(v_j) = 'succeeded_with_result' and (select (outcome_detail->'movement'->>'filled')::int from pipeline.admin_jobs where id = v_j) = 2,
                'O1 Fill missing fields done with 2 items filled: succeeded_with_result, measured from field_enrich_items');
  v_j := fx.task3('enrich_fields', 'done', '{"cost_usd": 0}'); perform fx.items(v_j, 0, 10); perform security.admin_job_close_v1(v_j);
  perform fx.ok(fx.outcome(v_j) = 'succeeded_no_movement', 'O2 done with every item skipped: succeeded_no_movement');
  v_j := fx.task3('course_page_find', 'done', '{"done": 62, "total": 173, "found": 8, "not_found": 54}'); perform security.admin_job_close_v1(v_j);
  perform fx.ok(fx.outcome(v_j) = 'failed_retryable' and (select (outcome_detail->>'unprocessed')::int from pipeline.admin_jobs where id = v_j) = 111
                and (select (outcome_detail->'movement'->>'pages_found')::int from pipeline.admin_jobs where id = v_j) = 8,
                'O3 IQ-00064 shape (done 62 of 173): failed_retryable, 111 unprocessed, the 8 pages it found kept in the detail');
  v_j := fx.task3('scholarship_provider_scan', 'cancelled', '{"done": 0, "total": 0, "end_state": "not_needed", "note": "Not needed: not eligible"}'); perform security.admin_job_close_v1(v_j);
  perform fx.ok(fx.outcome(v_j) = 'not_needed' and (select state from pipeline.admin_jobs where id = v_j) = 'cancelled',
                'O4 the not-needed path: outcome not_needed is the truth; state stays cancelled for compatibility');
  v_j := fx.task3('enrich_fields', 'failed', '{}', gen_random_uuid(), null, 'canceling statement due to statement timeout'); perform security.admin_job_close_v1(v_j);
  perform fx.ok(fx.outcome(v_j) = 'failed_retryable', 'O5 failed on a statement time-out: failed_retryable');
  v_j := fx.task3('course_page_find', 'failed', '{}', gen_random_uuid(), null, 'no website is recorded for this provider yet'); perform security.admin_job_close_v1(v_j);
  perform fx.ok(fx.outcome(v_j) = 'failed_remediation', 'O6 failed on a data or rule cause: failed_remediation');
  v_j := fx.task3('course_page_find', 'failed', '{"done": 2, "total": 10, "end_state": "failed", "blocked": {"code": "daily_cap"}}'); perform security.admin_job_close_v1(v_j);
  perform fx.ok(fx.outcome(v_j) = 'blocked_policy', 'O7 held too long by the day cap: blocked_policy');
  v_j := fx.task3('course_page_find', 'failed', '{"done": 2, "total": 10, "end_state": "failed"}'); perform security.admin_job_close_v1(v_j);
  perform fx.ok(fx.outcome(v_j) = 'failed_retryable', 'O8 held too long waiting its turn: failed_retryable');
  v_j := fx.task3('enrich_fields', 'cancelled', '{}'); perform fx.items(v_j, 0, 3); perform security.admin_job_close_v1(v_j);
  perform fx.ok(fx.outcome(v_j) = 'not_needed' and (select (outcome_detail->>'cancelled_by_person')::boolean from pipeline.admin_jobs where id = v_j),
                'O9 a person''s cancel with nothing moved: not_needed, marked cancelled by a person');
  perform fx.ok((select count(*) from pipeline.jobs) = 9, 'O9 every close still mirrors the task into pipeline.jobs as before');
  perform fx.ok(position('perform security.admin_job_close_v1(v_j.id);' in pg_get_functiondef('security.admin_jobs_tick_v1(integer)'::regprocedure)) > 0
                and (length(pg_get_functiondef('security.admin_jobs_tick_v1(integer)'::regprocedure)) - length(replace(pg_get_functiondef('security.admin_jobs_tick_v1(integer)'::regprocedure), 'perform security.admin_job_close_v1(v_j.id);', '')))
                    / length('perform security.admin_job_close_v1(v_j.id);') = 3, 'O10 the runner''s three ended paths (cancelled, failed, finished) each call the close');
  -- outcome recording never fails the close
  alter table pipeline.admin_jobs rename column outcome to outcome_x;
  v_j := fx.task3('enrich_fields', 'done', '{}'); perform security.admin_job_close_v1(v_j);
  alter table pipeline.admin_jobs rename column outcome_x to outcome;
  perform fx.ok((select count(*) from pipeline.jobs where payload->>'admin_job_id' = v_j::text) = 1, 'O11 a failure to record the outcome never fails the close');

  -- R1-R4 history: the 17 empty 12:41 plans report no movement; only the outcome columns are written
  perform fx.reset3();
  for i in 1 .. 17 loop
    v_p := fx.provider(false, null);
    v_j := fx.task3('scholarship_provider_scan', 'done', '{"done": 0, "total": 0, "new_scholarships": 0, "became": 0, "links_changed": 0}', v_p);
    perform fx.plan(v_p, 'done', jsonb_build_array(jsonb_build_object('step', 'scholarships', 'status', 'done', 'ref', jsonb_build_object('kind', 'job', 'id', v_j))));
  end loop;
  v_p := fx.provider(false, null);
  v_j := fx.task3('enrich_fields', 'done', '{}', v_p); perform fx.items(v_j, 3, 1);
  v_j2 := fx.task3('course_page_find', 'done', '{"done": 62, "total": 173, "found": 8}', v_p);
  v_r := fx.plan(v_p, 'done', jsonb_build_array(jsonb_build_object('step', 'pages', 'status', 'failed', 'ref', jsonb_build_object('kind', 'job', 'id', v_j2)),
                                               jsonb_build_object('step', 'fields', 'status', 'done', 'ref', jsonb_build_object('kind', 'job', 'id', v_j))));
  h := fx.plan_hist(v_r); hj := fx.job_hist(v_j2);
  perform fx.ok((security.plan_outcomes_v1()->>'moved')::int = 18, 'R1 before reconciliation the report still counts the 17 empty plans as moved');
  perform fx.set('ops.outcome_reconcile_batch', '10');
  v := security.ops_outcome_reconcile_v1();
  perform fx.ok((v->>'tasks')::int = 10 and (v->>'plans')::int = 10 and (v->>'plans_left')::int = 8, 'R2 the reconciliation is bounded by ops.outcome_reconcile_batch');
  perform security.ops_outcome_reconcile_v1(); perform security.ops_outcome_reconcile_v1();
  perform fx.ok((select count(*) from pipeline.enrich_plan_runs where outcome = 'succeeded_no_movement') = 17 and fx.plan_outcome(v_r) = 'succeeded_with_result',
                'R3 the 17 empty plans reconcile to succeeded_no_movement; the plan whose fields step filled 3 values to succeeded_with_result');
  v := security.plan_outcomes_v1();
  perform fx.ok((v->>'moved')::int = 1 and (v->>'no_movement')::int = 17 and (v->'by_outcome'->>'succeeded_no_movement')::int = 17,
                'R3 the plan outcome report now reads 1 moved and 17 with no movement');
  perform fx.ok(fx.plan_hist(v_r) = h and fx.job_hist(v_j2) = hj and (select outcome_detail->>'basis' from pipeline.enrich_plan_runs where id = v_r) = 'reconciled',
                'R4 state, steps, actual and results are untouched: only the outcome columns, basis reconciled');
  perform fx.set('ops.outcome_reconcile_batch', '500');

  -- W1-W2 a held task carries its provisional outcome; it is cleared when the task moves again
  perform fx.reset3();
  v_j := fx.task(10, 2, interval '5 minutes', fx.day_budget());
  perform security.admin_job_watch_v1(v_j);
  perform fx.ok(fx.outcome(v_j) = 'blocked_policy' and (select (outcome_detail->>'provisional')::boolean from pipeline.admin_jobs where id = v_j),
                'W1 a Find course pages task held by the day budget: provisional blocked_policy');
  update pipeline.course_link_search set state = 'none' where state = 'queued' and course_id in (select course_id from pipeline.course_link_search where state = 'queued' limit 3);
  delete from fx.block;
  perform security.admin_job_watch_v1(v_j);
  perform fx.ok(fx.outcome(v_j) = 'blocked_policy' and (select (outcome_detail->>'provisional')::boolean from pipeline.admin_jobs where id = v_j)
                and (select state from pipeline.admin_jobs where id = v_j) = 'running', 'W2 it moves again: the outcome stays marked provisional until the task ends');
  update pipeline.admin_jobs set state = 'done', finished_at = now(), result = result || '{"found": 3}' where id = v_j;
  perform security.admin_job_close_v1(v_j);
  perform fx.ok(fx.outcome(v_j) = 'failed_retryable' and not coalesce((select (outcome_detail->>'provisional')::boolean from pipeline.admin_jobs where id = v_j), false),
                'W3 at close the final outcome replaces it (done with work unfinished: failed_retryable)');

  -- T1-T2 a finished plan records its outcome; actual.outcome comes from movement
  perform fx.reset3();
  v_p := fx.provider(false, null);
  v_j := fx.task3('scholarship_provider_scan', 'done', '{"done": 0, "total": 0}', v_p);
  v_r := fx.plan(v_p, 'running', jsonb_build_array(jsonb_build_object('step', 'scholarships', 'status', 'running', 'ref', jsonb_build_object('kind', 'job', 'id', v_j))));
  perform security.enrich_plan_tick_v1(v_r); perform security.enrich_plan_tick_v1(v_r);
  perform fx.ok((select state from pipeline.enrich_plan_runs where id = v_r) = 'done' and (select actual->>'outcome' from pipeline.enrich_plan_runs where id = v_r) = 'no_movement'
                and fx.plan_outcome(v_r) = 'succeeded_no_movement' and (select outcome_detail->>'basis' from pipeline.enrich_plan_runs where id = v_r) = 'at_close',
                'T1 a plan whose scan found nothing finishes no_movement (was moved), outcome succeeded_no_movement at close');
  v_p := fx.provider(false, null);
  v_j := fx.task3('enrich_fields', 'done', '{}', v_p); perform fx.items(v_j, 1, 0);
  v_r := fx.plan(v_p, 'running', jsonb_build_array(jsonb_build_object('step', 'fields', 'status', 'running', 'ref', jsonb_build_object('kind', 'job', 'id', v_j))));
  perform security.enrich_plan_tick_v1(v_r); perform security.enrich_plan_tick_v1(v_r);
  perform fx.ok((select actual->>'outcome' from pipeline.enrich_plan_runs where id = v_r) = 'moved' and fx.plan_outcome(v_r) = 'succeeded_with_result', 'T2 a plan that filled a value: moved, succeeded_with_result');

  -- T3-T7 dependency sequencing: a step whose input is still being produced waits as deferred_dependency
  perform fx.reset3();
  v_p := fx.provider(false, null);
  insert into pipeline.course_link_search(course_id, provider_id, state, requested_at) select gen_random_uuid(), v_p, 'queued', now() - interval '4 hours' from generate_series(1, 3);
  insert into fx.block values (1, '{"code": "daily_cap", "words": "Today''s course search cap (200 courses) is reached; searching resumes at 00:00 UTC"}');
  v_r := fx.plan(v_p, 'running', '[{"step": "pages", "group": "none", "status": "pending"}]');
  perform security.enrich_plan_tick_v1(v_r);
  v := (select steps->0 from pipeline.enrich_plan_runs where id = v_r);
  perform fx.ok(v->>'status' = 'waiting' and v->'deferred'->>'code' = 'lane_backlog' and v->'deferred'->>'outcome' = 'deferred_dependency' and (v->'deferred'->>'queued')::int = 3
                and v->>'note' like 'Deferred: 3 course search(es)%cap (200 courses)%'
                and not (v ? 'waiting_since') and not exists (select 1 from fx.started where run = v_r),
                'T3 IQ-00064: Find course pages waits while 3 of the provider''s searches are queued (deferred_dependency, the hold named); no task, nothing queued again');
  perform fx.ok(exists (select 1 from security.ops_lifecycle_detect_v1() d where d.root_cause = 'step_input_pending'), 'T3 detected as step_input_pending');
  perform security.enrich_plan_tick_v1(v_r);
  perform fx.ok((select steps->0->'deferred'->>'since' from pipeline.enrich_plan_runs where id = v_r) = v->'deferred'->>'since', 'T4 the wait keeps its first deferral time');
  update pipeline.course_link_search set state = 'none' where provider_id = v_p;
  perform security.enrich_plan_tick_v1(v_r);
  perform fx.ok(exists (select 1 from fx.started where run = v_r and step = 'pages') and not ((select steps->0 from pipeline.enrich_plan_runs where id = v_r) ? 'deferred'),
                'T5 once they are searched, the step starts');
  insert into pipeline.course_link_search(course_id, provider_id, state) select gen_random_uuid(), v_p, 'queued' from generate_series(1, 2);
  v_r := fx.plan(fx.provider(false, null), 'running', '[{"step": "pages", "group": "none", "status": "waiting"}]');
  update pipeline.course_link_search set provider_id = (select provider_id from pipeline.enrich_plan_runs where id = v_r) where state = 'queued';
  update pipeline.enrich_plan_runs set steps = jsonb_set(steps, '{0,deferred}', jsonb_build_object('code', 'lane_backlog', 'since', now() - interval '49 hours')) where id = v_r;
  perform security.enrich_plan_tick_v1(v_r);
  perform fx.ok(exists (select 1 from fx.started where run = v_r), 'T6 after plans.step_wait_hours the step goes ahead as before');
  v_p := fx.provider(false, null);
  insert into pipeline.course_link_search(course_id, provider_id, state) select gen_random_uuid(), v_p, 'queued' from generate_series(1, 2);
  v_r := fx.plan(v_p, 'running', '[{"step": "pages", "group": "none", "status": "pending"}]', interval '1 hour', 'manual');
  perform security.enrich_plan_tick_v1(v_r);
  perform fx.ok(exists (select 1 from fx.started where run = v_r), 'T7 a person''s Run now plan is not deferred');
  -- fields waits for the plan's pages step only with plans.step_dependency_on
  v_p := fx.provider(false, null);
  v_r := fx.plan(v_p, 'running', '[{"step": "pages", "group": "none", "status": "running", "ref": {"kind": "none"}, "started_at": "2099-01-01"}, {"step": "fields", "group": "none", "status": "pending"}]');
  perform security.enrich_plan_tick_v1(v_r);
  perform fx.ok(exists (select 1 from fx.started where run = v_r and step = 'fields'), 'T8 off (ships off): Fill missing fields runs beside Find course pages as before');
  perform fx.set('plans.step_dependency_on', '1');
  v_r := fx.plan(fx.provider(false, null), 'running', '[{"step": "pages", "group": "none", "status": "running", "ref": {"kind": "none"}, "started_at": "2099-01-01"}, {"step": "fields", "group": "none", "status": "pending"}]');
  perform security.enrich_plan_tick_v1(v_r);
  perform fx.ok(not exists (select 1 from fx.started where run = v_r) and (select steps->1->'deferred'->>'code' from pipeline.enrich_plan_runs where id = v_r) = 'step_dependency',
                'T9 on: Fill missing fields waits for the plan''s Find course pages step (deferred_dependency)');
  perform fx.set('plans.step_dependency_on', '0');

  -- A1-A6 IQ-00064 and the planner record
  perform fx.reset3();
  v_p := fx.iq64();
  v := security.enrich_plan_auto_v1();
  perform fx.ok((v->>'started')::int = 1 and v->>'outcome' = 'created', 'A1 IQ-00064: 6.5 hours after the step failed (past plans.retry_after_hours 6) the retry re-plan fires');
  v := (select to_jsonb(r) from pipeline.enrich_plan_runs r where provider_id = v_p and state = 'queued');
  perform fx.ok(v->'estimate'->'replan_why' = '["retry"]' and jsonb_array_length(v->'steps') = 1 and v->'steps'->0->>'step' = 'pages' and v->>'reason' like '%steps that can run again: pages%',
                'A1 its only step is Find course pages, the reason recorded');
  perform fx.ok((select outcome from pipeline.enrich_plan_auto_runs order by id desc limit 1) = 'created', 'A2 the run is recorded (created)');
  v := security.enrich_plan_auto_v1();
  perform fx.ok(v->>'outcome' = 'nothing_eligible' and (select reason from pipeline.enrich_plan_auto_runs order by id desc limit 1) like 'no university was due%',
                'A3 the next run creates nothing and says why (nothing_eligible)');
  perform fx.reset3();
  v_p := fx.iq64(interval '2 hours');
  v := security.enrich_plan_auto_v1();
  perform fx.ok((v->>'started')::int = 0, 'A4 not before the step''s own wait (plans.retry_after_hours)');
  perform fx.reset3();
  v_p := fx.iq64();
  update pipeline.platform_toolset_settings set value = '0' where key = 'plans.replan_per_hour';
  v := security.enrich_plan_auto_v1();
  perform fx.ok((v->>'started')::int = 0, 'A5 plans.replan_per_hour 0 (off) still holds it');
  update pipeline.platform_toolset_settings set value = '5' where key = 'plans.replan_per_hour';
  -- evidence re-plans keep plans.replan_min_days
  perform fx.reset3();
  v_p := fx.provider(false, null);
  insert into fx.priority(provider_id, missing) values (v_p, 500);
  insert into fx.fields values (v_p, '{"official_url": {"missing": 10}}');
  perform fx.plan(v_p, 'done', '[{"step": "pages", "status": "done"}]', interval '7 hours', 'auto', '{"missing": 500, "fingerprint": "x"}');
  insert into pipeline.coverage_course_pages(provider_id, course_id, evidence_id, read_status, read_at) values (v_p, gen_random_uuid(), gen_random_uuid(), 'read', now());
  v := security.enrich_plan_auto_v1();
  perform fx.ok((v->>'started')::int = 0, 'A6 a re-plan on new evidence still waits plans.replan_min_days (unchanged)');

  -- E1-E4 repeated empty cycles
  perform fx.reset3();
  v_p := fx.provider(false, null);
  insert into fx.fields values (v_p, '{"official_url": {"missing": 10}}');
  for i in 1 .. 3 loop
    v_j := fx.task3('course_page_find', 'done', '{"done": 10, "total": 10, "found": 0}', v_p);
    perform fx.plan(v_p, 'done', jsonb_build_array(jsonb_build_object('step', 'pages', 'status', 'done', 'ref', jsonb_build_object('kind', 'job', 'id', v_j))), make_interval(hours => 10 * i), 'auto', '{"missing": 10}');
  end loop;
  v := security.enrich_plan_v1(v_p);
  perform fx.ok(jsonb_array_length(v->'steps') = 0 and exists (select 1 from jsonb_array_elements(v->'not_proposed') x where x->>'code' = 'repeated_empty' and x->>'step' = 'pages') and v->'empty_cycles' is not null and (v->>'est_credits')::numeric = 0,
                'E1 the scheduled planner is not offered a university whose last 3 plans moved nothing (repeated_empty, with the reason)');
  insert into fx.uid values (1, gen_random_uuid());
  v := security.enrich_plan_v1(v_p);
  perform fx.ok(jsonb_array_length(v->'steps') = 1 and v->'empty_cycles' is not null, 'E2 a person still sees the steps, with the notice');
  delete from fx.uid;
  insert into pipeline.coverage_course_pages(provider_id, course_id, evidence_id, read_status, read_at) values (v_p, gen_random_uuid(), gen_random_uuid(), 'read', now());
  perform fx.ok(jsonb_array_length(security.enrich_plan_v1(v_p)->'steps') = 1, 'E3 new verified evidence: proposed again');
  delete from pipeline.coverage_course_pages;
  update fx.fields set f = '{"official_url": {"missing": 20}}' where provider_id = v_p;
  perform fx.ok(jsonb_array_length(security.enrich_plan_v1(v_p)->'steps') = 1, 'E3 missing values grew by plans.replan_min_new_gaps: proposed again');
  update fx.fields set f = '{"official_url": {"missing": 10}}' where provider_id = v_p;
  update pipeline.enrich_plan_runs set outcome = 'succeeded_with_result' where id = (select id from pipeline.enrich_plan_runs where provider_id = v_p order by created_at desc limit 1);
  perform fx.ok(jsonb_array_length(security.enrich_plan_v1(v_p)->'steps') = 1, 'E4 one of the last 3 moved data: proposed');
  perform fx.set('plans.empty_cycles_max', '0');
  update pipeline.enrich_plan_runs set outcome = null where provider_id = v_p;
  perform fx.ok(jsonb_array_length(security.enrich_plan_v1(v_p)->'steps') = 1, 'E4 plans.empty_cycles_max 0: off');
  perform fx.set('plans.empty_cycles_max', '3');

  -- H1-H8 self-healing remedies: detected always, acting only with their switch on, recorded as remedy runs
  perform fx.reset3();
  insert into pipeline.field_enrich_items(job_id, state, attempts, leased_until, field, updated_at) values
    (null, 'leased', 3, now() - interval '2 hours', 'duration', now()), (null, 'ai', 3, null, 'campus', now()), (null, 'leased', 1, now() - interval '2 hours', 'campus', now());
  perform fx.ok(security.ops_d_detect_count_v1('lease_orphaned') = 2, 'H1 two items at the attempt cap are orphaned (the one at attempt 1 the reader picks again)');
  perform security.ops_job_lifecycle_v1();
  perform fx.ok((select count(*) from pipeline.field_enrich_items where state = 'failed') = 0, 'H1 switch off: detected only');
  perform fx.set('ops.lease_orphan_close_on', '1');
  v := security.ops_lease_orphan_close_v1(null);
  perform fx.ok((v->>'changed')::int = 2 and (security.ops_lease_orphan_verify_v1(null)->>'passed')::boolean
                and (select count(*) from pipeline.admin_control_events where area = 'ops' and action = 'self_heal' and target = 'lease_orphan_close') = 1
                and (select reason from pipeline.field_enrich_items where state = 'failed' limit 1) like '%orphaned at the attempt cap%',
                'H2 on: closed as failed with the reason, verified, what it changed recorded');
  perform fx.set('ops.lease_orphan_close_on', '0');
  -- task precedence left by ended tasks
  v_j := fx.task3('course_page_find', 'running', '{}');
  v_p := gen_random_uuid();
  update pipeline.admin_jobs set args = args || jsonb_build_object('course_ids', jsonb_build_array(v_p)) where id = v_j;
  insert into pipeline.course_link_search(course_id, provider_id, state, requested_at) values (v_p, null, 'queued', now()), (gen_random_uuid(), null, 'queued', now()), (gen_random_uuid(), null, 'queued', now());
  perform fx.ok(security.ops_d_detect_count_v1('lane_work_orphaned') = 2, 'H3 two queued searches keep the precedence of an ended task');
  perform fx.set('ops.lane_orphan_release_on', '1');
  perform security.ops_job_lifecycle_v1();
  perform fx.ok((select count(*) from pipeline.course_link_search where requested_at is not null) = 1 and (select requested_at from pipeline.course_link_search where course_id = v_p) is not null
                and (select count(*) from pipeline.course_link_search where state = 'queued') = 3, 'H4 on: released to their normal turn, the open task''s course untouched, nothing leaves the queue');
  perform fx.set('ops.lane_orphan_release_on', '0');
  -- interrupted tasks
  update pipeline.admin_jobs set updated_at = now() - interval '1 hour' where id = v_j;
  perform fx.ok(security.ops_d_detect_count_v1('job_interrupted') = 1 and not (security.ops_job_interrupted_verify_v1(null)->>'passed')::boolean, 'H5 a running task untouched for an hour is interrupted');
  -- duplicate tasks
  v_p := gen_random_uuid();
  v_j := fx.task3('course_page_find', 'running', '{}', v_p, null, null, interval '3 hours');
  v_j2 := fx.task3('course_page_find', 'running', '{}', v_p, gen_random_uuid(), null, interval '1 hour');
  perform fx.ok(exists (select 1 from security.ops_lifecycle_detect_v1() where root_cause = 'task_duplicate'), 'H6 two open Find course pages tasks for one provider are detected');
  perform fx.set('ops.task_dedupe_on', '1');
  perform security.ops_job_lifecycle_v1();
  perform fx.ok((select cancel_requested from pipeline.admin_jobs where id = v_j2) and not (select cancel_requested from pipeline.admin_jobs where id = v_j),
                'H6 on: the newer plan task is asked to stop; the person''s task is not');
  perform fx.set('ops.task_dedupe_on', '0');
  -- excessive paid retries
  v_j := fx.task3('enrich_fields', 'running', '{}');
  insert into pipeline.field_enrich_items(job_id, state, attempts, cost_usd, field, updated_at) select v_j, 'filled', 3, 0.5, 'duration', now() from generate_series(1, 3);
  perform fx.ok(exists (select 1 from security.ops_lifecycle_detect_v1() where root_cause = 'retry_cost_excess' and correlation_key = 'admin_jobs:' || v_j), 'H7 a task whose items read again cost US$1.50 (over 1) is detected');
  perform fx.set('ops.retry_cost_pause_on', '1');
  perform security.ops_job_lifecycle_v1();
  perform fx.ok((select pause_requested from pipeline.admin_jobs where id = v_j) and (security.ops_retry_cost_verify_v1(null)->>'passed')::boolean, 'H8 on: asked to pause, with the reason');
  perform fx.set('ops.retry_cost_pause_on', '0');

  -- P1-P6 a paid answer whose record failed is recorded again from the kept copy, never read again
  perform fx.reset3();
  v_r := gen_random_uuid();
  insert into pipeline.field_enrich_items(job_id, state, attempts, leased_until, field, evidence_id, storage_path, updated_at) values
    (null, 'leased', 1, now() + interval '4 minutes', 'duration', v_r, 'layer2/AU/x.md.gz', now()) returning id into v_i;
  insert into pipeline.field_enrich_items(job_id, state, attempts, leased_until, field, evidence_id, updated_at) values (null, 'leased', 1, now() + interval '4 minutes', 'campus', v_r, now()) returning id into v_i2;
  insert into pipeline.field_enrich_items(job_id, state, attempts, leased_until, field, evidence_id, updated_at) values (null, 'leased', 1, now() + interval '4 minutes', 'delivery', v_r, now()) returning id into v_i3;
  v := public.svc_enrich_ai_stash_v1(jsonb_build_array(jsonb_build_object('item_id', v_i, 'value', jsonb_build_object('text', '3 years'), 'quote', '3 years full-time', 'cost', 0.002),
                                                       jsonb_build_object('item_id', v_i2, 'value', null, 'reason', 'the page does not state it', 'cost', 0.002),
                                                       jsonb_build_object('item_id', v_i3, 'retry', true, 'reason', 'time budget')));
  perform fx.ok((v->>'kept')::int = 2 and (select evidence_id from pipeline.enrich_ai_answers where item_id = v_i) = v_r,
                'P1 the answers are kept per item and attempt with their evidence (a "retry" answer is not kept)');
  perform fx.ok((public.svc_enrich_ai_stash_v1(jsonb_build_array(jsonb_build_object('item_id', v_i, 'value', null)))->>'kept')::int = 0, 'P1 kept once per attempt');
  insert into fx.record_fails values (1, true);
  begin perform public.svc_enrich_ai_record(jsonb_build_array(jsonb_build_object('item_id', v_i))); exception when others then null; end;
  update pipeline.enrich_ai_answers set received_at = now() - interval '5 minutes';
  perform fx.ok(security.ops_d_detect_count_v1('answer_not_persisted') = 2, 'P2 the record failed: two paid answers not recorded are detected');
  perform security.ops_job_lifecycle_v1();
  perform fx.ok((select count(*) from pipeline.enrich_ai_answers where state = 'received') = 2 and (select count(*) from fx.recorded) = 0, 'P2 switch off: kept, not replayed');
  perform fx.set('ops.answer_replay_on', '1');
  v := security.ops_answer_replay_v1(null);
  perform fx.ok((v->>'changed')::int = 0 and (select count(*) from pipeline.enrich_ai_answers where state = 'received' and (detail->>'tries')::int = 1) = 2
                and (select detail->>'error' from pipeline.enrich_ai_answers limit 1) like '%statement timeout%', 'P3 the recording fails again: kept with the error, to be tried again (only the recording)');
  delete from fx.record_fails;
  v := security.ops_answer_replay_v1(null);
  perform fx.ok((v->>'changed')::int = 2 and (select state from pipeline.field_enrich_items where id = v_i) = 'filled' and (select state from pipeline.field_enrich_items where id = v_i2) = 'skipped'
                and (select count(*) from fx.recorded) = 2 and (select attempts from pipeline.field_enrich_items where id = v_i) = 1
                and (select count(*) from pipeline.enrich_ai_answers where state = 'replayed' and detail->>'item_state' in ('filled', 'skipped')) = 2,
                'P4 replayed: only the recording, from the kept answers (no new lease or attempt), final state checked (filled, skipped)');
  -- an item leased again (a new paid read under way) or whose evidence changed is superseded, never replayed
  insert into pipeline.field_enrich_items(job_id, state, attempts, field, evidence_id, updated_at) values (null, 'leased', 1, 'level', v_r, now()) returning id into v_i;
  perform public.svc_enrich_ai_stash_v1(jsonb_build_array(jsonb_build_object('item_id', v_i, 'value', null)));
  update pipeline.field_enrich_items set attempts = 2 where id = v_i;
  update pipeline.enrich_ai_answers set received_at = now() - interval '5 minutes' where item_id = v_i;
  perform security.ops_answer_replay_v1(null);
  perform fx.ok((select state from pipeline.enrich_ai_answers where item_id = v_i) = 'superseded' and (select count(*) from fx.recorded) = 2, 'P5 leased again: superseded, not replayed');
  insert into pipeline.field_enrich_items(job_id, state, attempts, field, evidence_id, updated_at) values (null, 'leased', 1, 'level', v_r, now()) returning id into v_i;
  perform public.svc_enrich_ai_stash_v1(jsonb_build_array(jsonb_build_object('item_id', v_i, 'value', null)));
  update pipeline.field_enrich_items set state = 'filled' where id = v_i;
  perform security.ops_answer_replay_v1(null);
  perform fx.ok((select state from pipeline.enrich_ai_answers where item_id = v_i) = 'recorded', 'P6 settled by the normal path: recorded');
  -- a recording that keeps failing is tried ops.heal_max_attempts times, then left to the reader as failed
  insert into fx.record_fails values (1, true);
  insert into pipeline.field_enrich_items(job_id, state, attempts, field, evidence_id, updated_at) values (null, 'leased', 1, 'level', v_r, now()) returning id into v_i;
  perform public.svc_enrich_ai_stash_v1(jsonb_build_array(jsonb_build_object('item_id', v_i, 'value', null)));
  update pipeline.enrich_ai_answers set received_at = now() - interval '5 minutes' where item_id = v_i;
  for i in 1 .. 4 loop perform security.ops_answer_replay_v1(null); end loop;
  perform fx.ok((select state from pipeline.enrich_ai_answers where item_id = v_i) = 'failed' and (select (detail->>'tries')::int from pipeline.enrich_ai_answers where item_id = v_i) = 3,
                'P7 still failing after ops.heal_max_attempts (3) tries: failed, the item left to the reader');
  delete from fx.record_fails;
  perform fx.set('ops.answer_replay_on', '0');

  -- G1-G3 registration through workstream A's contract; the job
  perform fx.ok((select count(*) from pipeline.ops_root_causes where code in ('false_completion', 'lease_orphaned', 'lane_work_orphaned', 'job_interrupted', 'task_duplicate',
                 'plan_repeated_empty', 'retry_cost_excess', 'answer_not_persisted', 'step_input_pending')) = 9, 'G1 nine root causes registered');
  perform fx.ok((select count(*) from pipeline.ops_remedies) = 9 and (select count(*) from pipeline.ops_remedies where authority = 'auto' and action_fn is not null) = 6
                and (select authority from pipeline.ops_remedies where code = 'job_interrupted_check') = 'admin'
                and (select count(*) from pipeline.ops_remedies where authority = 'release') = 2, 'G2 nine remedies: six with an action, one for a person, two built in by this release');
  perform fx.ok((select command from cron.job where jobname = 'ops-job-lifecycle') = 'select security.ops_job_lifecycle_v1()'
                and exists (select 1 from pipeline.automation_catalogue where jobname = 'ops-job-lifecycle'), 'G3 the job is scheduled and catalogued');
end $$;
