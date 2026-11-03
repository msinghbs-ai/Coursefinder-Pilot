-- IQ-00064 with tasks.lane_hold_on on (as shipped; fixtures-off.sql set it 0): every case.
update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key = 'tasks.lane_hold_on';

-- A. work waiting from a task (read-only)
select fx.reset();
select fx.task(4, 2, interval '50 minutes', fx.day_budget()) \gset a_
select fx.ok(security.lane_task_waiting_v1('link_search'), 'A1 lane_task_waiting_v1: a running Find course pages task with queued courses waits for link_search');
select fx.ok(not security.lane_task_waiting_v1('read'), 'A2 lane_task_waiting_v1: another mode answers false');
update pipeline.admin_jobs set state = 'paused' where id = :'a_task';
select fx.ok(not security.lane_task_waiting_v1('link_search'), 'A3 a paused task does not hold the lane awake');
update pipeline.admin_jobs set state = 'running' where id = :'a_task';

-- B. the idle guard
select security.flag_jobs_v1();
select fx.ok(fx.lane_active(), 'B1 the idle guard does not pause the lane while a running task has courses queued for it (30 empty calls)');
select fx.ok(not exists (select 1 from pipeline.enrichment_flags where reason_code = 'idle_paused'), 'B1 no idle_paused flag');
update pipeline.course_link_search set state = 'none' where state = 'queued';
select security.flag_jobs_v1();
select fx.ok(fx.lane_active() = false, 'B2 with no task work waiting, 30 empty calls still pause the lane (the guard is kept)');
update pipeline.course_link_search set state = 'queued' where course_id in (select course_id from pipeline.course_link_search limit 1);
update pipeline.enrichment_flags set next_check_at = now() + interval '1 hour';
select security.flag_jobs_v1();
select fx.ok(fx.lane_active(), 'B3 a paused lane is released as soon as a task has work waiting for it (before its recheck time)');
select fx.ok((select release_reason from pipeline.enrichment_flags where reason_code = 'idle_paused') = 'Trial run: switched on again to look for new work', 'B3 released by the recheck');

-- C. the watcher: held, never done, while courses are unsearched
select fx.reset();
select fx.task(4, 2, interval '50 minutes', fx.day_budget()) \gset c_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'c_task')).state = 'running', 'C1 a stalled task (50 minutes) with 2 of 4 courses unsearched stays running');
select fx.ok((fx.job(:'c_task')).result->'held'->>'code' = 'day_budget', 'C1 held by the Firecrawl day share (a budget hold is a hold)');
select fx.ok((fx.job(:'c_task')).result->>'note' like 'Held: Today''s Firecrawl share for course search is used. 2 of 4 course(s) still to search; it carries on by itself when the lane has room (gives up %',
             'C1 the note says why, what is left and when it gives up');
select fx.ok(((fx.job(:'c_task')).result->'held'->>'ends_at')::timestamptz between now() + interval '23 hours' and now() + interval '24 hours', 'C1 gives up tasks.lane_hold_max_hours after the last progress');
select fx.ok((fx.job(:'c_task')).result->>'unprocessed' = '2', 'C1 unprocessed scope recorded');
select security.admin_jobs_tick_v1(10);
select fx.ok((select count(*) from pipeline.admin_job_events where job_id = :'c_task' and note like 'Held:%') = 1, 'C2 one event when the hold starts, not one a minute');
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'c_task')->>'status' = 'running' and fx.run_state(:'c_task') = 'running', 'C3 the plan step and the plan stay running while the task is held');
-- the lane wakes: the rest are searched; the task finishes done with its normal note; the step and the plan complete
update pipeline.course_link_search set state = 'found' where state = 'queued';
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'c_task')).state = 'done' and (fx.job(:'c_task')).result->>'note' like '2 of 4 course page(s) found%', 'C4 the task continues when the lane wakes and finishes done when every course is searched');
select fx.ok((fx.job(:'c_task')).result->'held' is null, 'C4 no hold once finished');
select security.enrich_plan_tick_v1(null); select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'c_task')->>'status' = 'done' and fx.run_state(:'c_task') = 'done', 'C4 the plan step completes only now, then the plan');

-- D. the idle guard gate and searches waiting their turn are holds too; recent progress is not a hold
select fx.reset();
select fx.task(4, 2, interval '50 minutes', fx.idle_paused()) \gset d_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'d_task')).state = 'running' and (fx.job(:'d_task')).result->'held'->>'code' = 'lane_idle_paused', 'D1 the IQ-00064 case: held by the idle guard gate, not done');
select fx.task(4, 2, interval '50 minutes', null) \gset e_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'e_task')).state = 'running' and (fx.job(:'e_task')).result->'held'->>'code' = 'waiting_turn'
             and (fx.job(:'e_task')).result->>'note' like 'Held: 2 search(es) waiting their turn in the course page search lane.%', 'D2 no gate named: held, waiting their turn');
select fx.task(4, 2, interval '30 seconds', fx.day_budget()) \gset f_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'f_task')).state = 'running' and (fx.job(:'f_task')).result->'held' is null, 'D3 progress within tasks.stall_seconds: running, not shown held');
select fx.ok((fx.job(:'f_task')).result->>'note' like 'Blocked:%', 'D3 the gate is still shown as before');

-- E. bounded: nothing moved for tasks.lane_hold_max_hours ends the task failed with the reason; the step fails with it (retryable)
select fx.reset();
select fx.task(4, 2, interval '25 hours', fx.day_budget(), interval '26 hours') \gset g_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'g_task')).state = 'failed', 'E1 held past 24 hours: the task ends failed, not done');
select fx.ok((fx.job(:'g_task')).error like 'Held too long: 2 of 4 course(s) not processed; nothing moved for 24 hour(s) (Today''s Firecrawl share for course search is used). The plan''s retry can start it again',
             'E1 the error gives the reason and the courses not searched');
select fx.ok((fx.job(:'g_task')).finished_at is not null, 'E1 finished_at set');
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'g_task')->>'status' = 'failed' and fx.step(:'g_task')->>'note' like 'Held too long: 2 of 4%', 'E2 the plan step fails with the task''s reason');
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.run_state(:'g_task') = 'done', 'E2 the plan run then finishes (its failed step is what plans.replan_on_retry retries)');
update pipeline.platform_toolset_settings set value = '48' where toolset_key = 'pipeline' and key = 'tasks.lane_hold_max_hours';
select fx.task(4, 2, interval '25 hours', fx.day_budget(), interval '26 hours') \gset h_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'h_task')).state = 'running', 'E3 the bound is the setting (48 hours: still held at 25)');
update pipeline.platform_toolset_settings set value = '24' where toolset_key = 'pipeline' and key = 'tasks.lane_hold_max_hours';
select fx.task(4, 2, interval '25 hours', fx.no_site(), interval '26 hours') \gset i_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'i_task')).error like '%(No website is recorded to search)%', 'E4 a cause time does not clear is named, so plans.retry_waits_for_change keeps it from a timed retry');

-- F. the plan step: not timed out while its Find course pages task is open; others as before
select fx.reset();
select fx.task(4, 2, interval '10 minutes', fx.day_budget(), interval '30 hours') \gset j_
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'j_task')->>'status' = 'running', 'F1 a step past plans.step_max_hours is not timed out while its task (tasks.hold_kinds) is open');
select fx.task(4, 2, interval '10 minutes', fx.day_budget(), interval '30 hours') \gset k_
update pipeline.admin_jobs set kind = 'enrich_fields' where id = :'k_task';
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'k_task')->>'status' = 'timed_out', 'F2 a kind outside tasks.hold_kinds (enrich_fields) times out as before');

-- G. a task that ended done with courses unsearched (as the four on 3 Nov) is a failed step, with the reason
select fx.reset();
select fx.task(4, 2, interval '10 minutes') \gset l_
update pipeline.admin_jobs set state = 'done', finished_at = now(),
       result = '{"done": 2, "total": 4, "note": "Blocked: The course page search lane is paused by the idle guard until 12:45. It wakes by itself when work waits; nothing to do"}'
 where id = :'l_task';
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'l_task')->>'status' = 'failed', 'G1 done with 2 of 4 courses unsearched is not a done step');
select fx.ok(fx.step(:'l_task')->>'note' = 'ended done with 2 of 4 items unprocessed (IQ-00064): Blocked: The course page search lane is paused by the idle guard until 12:45. It wakes by itself when work waits; nothing to do',
             'G1 the step note says what was left and why');
select fx.task(4, 4, interval '10 minutes') \gset m_
update pipeline.admin_jobs set state = 'done', finished_at = now(), result = '{"done": 4, "total": 4, "note": "1 of 4 course page(s) found"}' where id = :'m_task';
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'m_task')->>'status' = 'done' and fx.step(:'m_task')->>'note' is null, 'G2 every course searched: done, as before');
select fx.task(4, 2, interval '10 minutes') \gset n_
update pipeline.admin_jobs set state = 'cancelled', finished_at = now(), result = '{"done": 2, "total": 4, "note": "cancelled by the operator"}' where id = :'n_task';
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'n_task')->>'status' = 'cancelled' and fx.step(:'n_task')->>'note' = 'cancelled by the operator', 'G3 a cancelled task: the step is cancelled with its reason');

-- H. the task runner: only end_state failed changes the finish
select fx.reset();
select fx.task(4, 4, interval '10 minutes') \gset o_
update pipeline.course_link_search set state = 'found';
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'o_task')).state = 'done' and (fx.job(:'o_task')).error is null, 'H1 a finished task without end_state is done, error untouched');

-- I. generalised (mandate 13:09 §3.4): scholarship scans and provider fill with work left are held too, with their phase as the reason
select fx.reset();
insert into catalogue.providers(id, website) values ('00000000-0000-0000-0000-0000000000a1', 'https://a.example');
insert into catalogue.courses(provider_id) values ('00000000-0000-0000-0000-0000000000a1');
insert into pipeline.admin_jobs(id, kind, lane, state, args, cursor, created_at, started_at) values
  ('00000000-0000-0000-0000-0000000000f1', 'provider_fill', 'providers:provider_fill:a1', 'running', '{"provider_id": "00000000-0000-0000-0000-0000000000a1"}',
   jsonb_build_object('last_done', 1, 'last_change_at', now() - interval '40 minutes'), now() - interval '1 hour', now() - interval '1 hour');
insert into scholarship.scholarships(id, provider_id, created_at) values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', now() - interval '2 days');
insert into pipeline.scholarship_pages(scholarship_id, requested_at) values ('00000000-0000-0000-0000-0000000000b1', now() - interval '50 minutes');
insert into pipeline.admin_jobs(id, kind, lane, state, args, cursor, created_at, started_at) values
  ('00000000-0000-0000-0000-0000000000f2', 'scholarship_provider_scan', 'providers:sch:a1', 'running', '{"providers": ["00000000-0000-0000-0000-0000000000a1"]}',
   jsonb_build_object('last_done', 0, 'last_change_at', now() - interval '40 minutes'), now() - interval '1 hour', now() - interval '1 hour');
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job('00000000-0000-0000-0000-0000000000f1')).state = 'running' and (fx.job('00000000-0000-0000-0000-0000000000f1')).result->'held'->>'reason' = '2 item(s) waiting their turn (reading contacts)',
             'I1 provider fill with 1 of 3 parts done, stalled 40 minutes: held (was: done by the 30-minute rule), its phase the reason');
select fx.ok((fx.job('00000000-0000-0000-0000-0000000000f1')).result->'held'->'checkpoint' @> '{"done": 1, "total": 3, "phase": "reading contacts"}', 'I1 the checkpoint is kept');
select fx.ok((fx.job('00000000-0000-0000-0000-0000000000f2')).state = 'running' and (fx.job('00000000-0000-0000-0000-0000000000f2')).result->>'unprocessed' = '1'
             and (fx.job('00000000-0000-0000-0000-0000000000f2')).result->>'note' like 'Held: 1 item(s) waiting their turn (reading scholarship pages). 1 of 1 item(s) still to process;%',
             'I2 a scholarship scan with a page unread, stalled 40 minutes: held, not done');
update pipeline.platform_toolset_settings set value = '["course_page_find"]' where toolset_key = 'pipeline' and key = 'tasks.hold_kinds';
update pipeline.admin_jobs set result = null where id = '00000000-0000-0000-0000-0000000000f1';
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job('00000000-0000-0000-0000-0000000000f1')).state = 'done', 'I3 the kinds are a setting: a kind left out of tasks.hold_kinds ends as before');
update pipeline.platform_toolset_settings set value = '["course_page_find", "scholarship_provider_scan", "provider_fill"]' where toolset_key = 'pipeline' and key = 'tasks.hold_kinds';

-- J. the step shows its task's hold (remaining, checkpoint, reason) and, once ended, its restart eligibility
select fx.reset();
select fx.task(4, 2, interval '50 minutes', fx.day_budget()) \gset p_
select security.admin_jobs_tick_v1(10);
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'p_task')->'held'->>'code' = 'day_budget' and fx.step(:'p_task')->>'remaining' = '2' and fx.step(:'p_task')->>'note' like 'Held: %'
             and fx.step(:'p_task')->'held'->'checkpoint'->>'done' = '2', 'J1 the running step carries the hold: reason, remaining items, checkpoint (Enrichment plan screen)');
update pipeline.course_link_search set state = 'found' where state = 'queued' and course_id in (select course_id from pipeline.course_link_search limit 1);
update pipeline.admin_jobs set cursor = jsonb_build_object('last_done', 2, 'last_change_at', now()) where id = :'p_task';
select security.admin_jobs_tick_v1(10);
select security.enrich_plan_tick_v1(null);
select fx.ok(not (fx.step(:'p_task') ? 'held') and fx.step(:'p_task')->>'note' is null, 'J2 progress: the step no longer shows a hold');
update pipeline.admin_jobs set state = 'failed', error = 'Held too long: 1 of 4 course(s) not processed', result = result || '{"done": 3, "total": 4}' where id = :'p_task';
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'p_task')->>'status' = 'failed' and (fx.step(:'p_task')->'restart'->>'retry_on')::boolean and not (fx.step(:'p_task')->'restart'->>'waits_for_change')::boolean
             and (fx.step(:'p_task')->'restart'->>'after')::timestamptz between now() + interval '5 hours' and now() + interval '7 hours' and fx.step(:'p_task')->>'remaining' = '1',
             'J3 an ended step keeps its remaining items and when the governed re-plan may retry it');
select fx.task(4, 2, interval '10 minutes') \gset q_
update pipeline.admin_jobs set state = 'failed', error = 'Held too long: (No website is recorded to search)', result = '{"done": 2, "total": 4}' where id = :'q_task';
select security.enrich_plan_tick_v1(null);
select fx.ok((fx.step(:'q_task')->'restart'->>'waits_for_change')::boolean, 'J4 a cause time does not clear: the restart waits for a change');

-- K. monitoring: one issue while a plan step or task ended done with work unfinished; cleared when none remains
select fx.reset();
select fx.task(4, 2, interval '10 minutes') \gset r_
update pipeline.admin_jobs set state = 'done', finished_at = now(), result = '{"done": 2, "total": 4, "note": "x"}' where id = :'r_task';
update pipeline.enrich_plan_runs set steps = jsonb_set(steps, '{0,status}', '"done"') where id = ((fx.job(:'r_task')).args->>'plan_run')::uuid;
select fx.ok((select count(*) from security.plan_unfinished_done_v1() where kind = 'step') = 1, 'K1 a done step whose task left 2 of 4 is listed');
select security.integration_yield_checks_v1();
select fx.ok((select count(*) from pipeline.integration_issues where fingerprint = 'plan_unfinished_done:plans' and severity = 'P1' and condition_cleared_at is null) = 1, 'K1 one issue raised');
select security.integration_yield_checks_v1();
select fx.ok((select observed from pipeline.integration_issues where fingerprint = 'plan_unfinished_done:plans') = 2 and (select count(*) from pipeline.integration_issues where fingerprint like 'plan_unfinished_done%') = 1,
             'K2 observed again, still one issue (fingerprinted)');
update pipeline.enrich_plan_runs set steps = jsonb_set(steps, '{0,status}', '"failed"') where id = ((fx.job(:'r_task')).args->>'plan_run')::uuid;
select fx.ok((select count(*) from security.plan_unfinished_done_v1()) = 1 and (select kind from security.plan_unfinished_done_v1()) = 'task', 'K3 the task itself (finished after the reconciliation) is still listed');
update pipeline.admin_jobs set finished_at = (select created_at - interval '1 minute' from pipeline.admin_control_events where action = 'iq64_plan_step_reconcile') where id = :'r_task';
select fx.ok((select count(*) from security.plan_unfinished_done_v1()) = 0, 'K4 a task that ended before the reconciliation is not listed (the earlier ones were reconciled)');
select security.integration_yield_checks_v1();
select fx.ok((select condition_cleared_at from pipeline.integration_issues where fingerprint = 'plan_unfinished_done:plans') is not null, 'K5 none remains: the issue is marked cleared');
