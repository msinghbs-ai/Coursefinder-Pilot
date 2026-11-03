-- IQ-00064 reproduced (on the live v2.15.423 definitions, and after the migration with tasks.lane_hold_on off: the same outcomes).
-- 1 the idle guard pauses the course page search lane after 30 empty calls although a running plan task has courses queued for it
select fx.reset();
select fx.task(4, 2, interval '50 minutes', fx.day_budget()) \gset t_
select security.flag_jobs_v1();
select fx.ok(fx.lane_active() = false, 'before: the idle guard paused the lane while a running task had 2 courses queued for it');
select fx.ok(exists (select 1 from pipeline.enrichment_flags where reason_code = 'idle_paused' and state = 'raised'), 'before: idle_paused flag raised');
-- 2 the watcher finishes the stalled task done with the gate as its note; the plan step and the plan finish done
select fx.task(4, 2, interval '50 minutes', fx.idle_paused()) \gset u_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'u_task')).state = 'done', 'before: the task ended done with 2 of 4 courses unsearched');
select fx.ok((fx.job(:'u_task')).result->>'note' like 'Blocked: The course page search lane is paused by the idle guard%', 'before: its note is the idle guard gate');
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'u_task')->>'status' = 'done', 'before: the plan step is done');
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.run_state(:'u_task') = 'done', 'before: the plan finished done');
-- 3 a plan step running past plans.step_max_hours times out while its task is still open
select fx.task(4, 2, interval '10 minutes', fx.day_budget(), interval '30 hours') \gset w_
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'w_task')->>'status' = 'timed_out', 'before: a step older than plans.step_max_hours times out with its task still running');
