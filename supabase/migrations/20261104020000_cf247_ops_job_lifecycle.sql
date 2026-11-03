-- CF-247 Autonomous AI Operations, workstream D (P0 mandate 3 Nov 2026 15:37 §7; workstreams 15:40): pipeline self-healing and the job
-- lifecycle. Every task and plan ends with an explicit outcome from pipeline.ops_outcome_codes; past tasks and plans get a reconciled outcome
-- without their state or result being touched; stale and orphaned work, interrupted tasks, duplicate tasks, repeated empty cycles, costly
-- retries and answers paid for but not recorded are each detected, given a root cause and a remedy (workstream A's contract), and healed by a
-- scheduled job within bounded settings; a step whose input is still being produced waits as deferred_dependency; the retry re-plan
-- (plans.replan_on_retry) fires when the failed step's own wait has passed (IQ-00064), and every automatic planner run records why it
-- created what it did (Integration Controller 15:55).
-- Lands after workstream A (20261104010000: ops_root_causes, ops_remedies, ops_remedy_runs, ops_outcome_codes, admin_jobs.outcome and
-- outcome_detail, security.ops_root_cause_register_v1, security.ops_remedy_register_v1, security.job_outcome_set_v1).
-- Why (live, read-only, 3 Nov 2026 15:43-15:58 AEDT):
--   * No task has an outcome: admin_jobs holds 6,767 rows in done (6,758) or running (8); "done" is read as success whatever moved.
--   * The 17 automatic plans of 12:41 AEDT (one "Find and read scholarships" step each, task total 0, 0 new scholarships) have
--     actual.outcome null, and security.plan_run_outcome_v1 (used by security.plan_outcomes_v1 when actual.outcome is null) reports all 17
--     as "moved" because their step is "done". The 5 plans of 11:41 also compute "moved" from step status alone.
--   * IQ-00064: the 4 Find course pages steps of 11:41 (tasks 8c12b05c 62/173, 31c01095 28/100, 5b5f5d3f 40/92, fba22606 40/79) ended
--     failed with restart.after 18:35-18:40 AEDT, but security.enrich_plan_auto_v1 reads a university's retry inputs (lateral i,
--     security.enrich_plan_inputs_v1) only when its latest plan is older than plans.replan_min_days (2): the retry re-plan could not fire
--     before 5 Nov 11:41 AEDT. Their 274 unsearched courses are still queued in pipeline.course_link_search (since 11:45, requested_at set,
--     no open task), held by the course search day cap (200, resumes 00:00 UTC). A re-plan's Find course pages task
--     (security.provider_task_prepare_v1) queues every course of the provider without a read page again (attempts 0, queued_at now),
--     including the 128 searched "none" and 41 "found": duplicate paid searches. 1,273 queued courses keep task precedence (requested_at)
--     with no open task. The 15:41 planner run created 0 plans and left no record of why.
--   * Answers paid for but not recorded: 227 enrich_ai calls in 24 hours (05:27-14:31 AEDT, none since v2.15.426) ended
--     "svc_enrich_ai_record: canceling statement due to statement timeout"; the worker (coverage-sweep enrich_ai) keeps its answers only in
--     memory, so each lost call's up-to-30 answers were paid again when the 4-minute lease ran out (field_enrich_items attempts 2: 1,854,
--     attempts 3: 3,257 in 7 days). The answer is not retained today; it cannot be re-recorded.
--   * field_enrich_items: no item is leased now (0 expired, 0 at the attempt cap); 0 tasks untouched by the runner; 0 open duplicate plans
--     (unique index enrich_plan_runs_one_open) and 0 overlapping course_page_find, provider_fill or scholarship scan tasks in 14 days;
--     570 overlapping enrich_fields tasks of the same scope (12 scopes, 36 with a plan) in 14 days. The detectors stay registered so a
--     recurrence is found by the platform.
-- What:
--   1 Settings (G2), all in Settings › Pipeline settings, Platform upkeep.
--   2 New columns pipeline.enrich_plan_runs.outcome and outcome_detail (beside actual; history is not rewritten); new tables
--     pipeline.enrich_plan_auto_runs (one row per automatic planner run, with why it created what it did) and pipeline.enrich_ai_answers
--     (AI answers kept before they are recorded, so a failed record is replayed from them, never paid again).
--   3 Outcomes (ship ON, ops.outcome_on: they only record): security.job_movement_v1 (real data movement per task kind),
--     security.job_outcome_compute_v1 / job_outcome_record_v1, security.plan_outcome_compute_v1 / plan_outcome_record_v1, the reconciliation
--     security.ops_outcome_reconcile_v1 (past tasks and plans, newest first, ops.outcome_reconcile_batch per run; only the outcome columns).
--   4 md5-guarded edits: security.admin_job_close_v1 (every ended task records its outcome, whichever path ended it);
--     security.admin_job_watch_v1 (a held task carries its provisional outcome); security.enrich_plan_tick_v1 (a finished plan records its
--     outcome; actual.outcome from real movement; a step whose input is still being produced waits as deferred_dependency);
--     security.enrich_plan_v1 (repeated empty cycles: not proposed to the automatic planner); security.plan_outcomes_v1 (reads the
--     reconciled outcome); security.enrich_plan_auto_v1 (retry inputs read without waiting plans.replan_min_days; every run recorded).
--   5 Self-healing (job ops-job-lifecycle, every 2 minutes): detection security.ops_lifecycle_detect_v1 (read-only), remedies with action
--     and verify functions registered through workstream A's contract; each remedy that changes work ships OFF behind its own switch.
-- Ships ON (records outcomes, diagnoses, or only stops waste): ops.outcome_on, plans.empty_cycles_max 3, plans.lane_backlog_wait_on,
--   plans.retry_ignores_min_days (the retry re-plan already on since 11:42, #28709, now able to fire; its new Find course pages step waits
--   while the provider's searches are still queued, so no search is paid twice), the detection and the auto-run record.
-- Ships OFF (changes, removes or admits work): ops.lease_orphan_close_on, ops.lane_orphan_release_on, ops.task_dedupe_on,
--   ops.retry_cost_pause_on, ops.answer_replay_on, plans.step_dependency_on.
-- Budgets: no Firecrawl or AI value is raised; nothing reads a page or calls a model.
-- md5 (before = live v2.15.426, read 3 Nov 2026 15:43-15:58 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/ops-lifecycle/run.sh):
--   security.admin_job_close_v1(uuid)                      233236ffc66e438edb21c4f51a6c45a1 -> 1c33edb08b5ee5724a67a24ebc39913f
--   security.admin_job_watch_v1(uuid)                      995f26c437f0abfb3c666271cd622fec -> a7b17b399222f34c3b49460c73a7cef7
--   security.enrich_plan_tick_v1(uuid)                     77705c2b34e13801f4d7ccc5773bd4c1 -> 9b7c7c05491b95646b99fb7a855a9fa9
--   security.enrich_plan_v1(uuid)                          a63146c23989eb64ee2248e3f32eade6 -> 774c061974916b878f7762e55de07bb6
--   security.plan_outcomes_v1()                            0f127f0241764413fb87278f403a2e14 -> f63b93e1bc954221e3388625594c7d56
--   security.enrich_plan_auto_v1()                         14d4769267f827736a0d4e2f013c4dad -> 14fee957a992f39a68075da1a952271a
-- Not edited: security.admin_jobs_tick_v1 (every ended path already calls security.admin_job_close_v1), security.enrich_plan_inputs_v1,
--   security.provider_task_prepare_v1, public.svc_enrich_ai_next, public.svc_enrich_ai_record (Release B), the coverage-sweep worker.
-- Consumer API (G3): untouched (no website_*, zoho_*, api.* object, table or column is changed).
-- Data: nothing is corrected here; the reconciliation and the remedies are mechanisms the job runs.
-- Replaces: the plan outcome from step status alone (security.plan_run_outcome_v1 in security.enrich_plan_tick_v1 and
--   security.plan_outcomes_v1); the retry inputs gated by plans.replan_min_days in security.enrich_plan_auto_v1 (same functions,
--   md5-guarded edits)
-- Retires: nothing (security.plan_run_outcome_v1 stays the fallback while ops.outcome_on is 0)
-- Nothing is dropped or deleted.

do $g$
begin
  if to_regclass('pipeline.ops_remedies') is null or to_regclass('pipeline.ops_outcome_codes') is null
     or to_regprocedure('security.job_outcome_set_v1(uuid,text,jsonb)') is null
     or to_regprocedure('security.ops_remedy_register_v1(text,jsonb)') is null or to_regprocedure('security.ops_root_cause_register_v1(text,jsonb)') is null then
    raise exception 'workstream D (20261104020000) lands after workstream A (20261104010000): the ops contract is missing';
  end if;
end $g$;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 0. the definitions the new code calls are the ones it was written against (not changed here) ----------------------------------------------
do $g$
declare r record;
begin
  for r in select * from (values ('security.enrich_plan_inputs_v1(uuid)', 'a546c58cfc4897ef7cf1a19f2041a2ae'),
                                 ('security.plan_run_outcome_v1(jsonb)', 'fa05333f110034b24f2a799f275e3a7f')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. settings (G2) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'ops.outcome_on', 'Outcomes: record every task''s and plan''s outcome',
  '1: every task and enrichment plan that ends records its outcome (succeeded with a result, succeeded with no data movement, not needed, deferred for a dependency, blocked by policy, blocked by evidence, failed and retryable, failed and needing remediation), from the data it actually moved; a held task shows its provisional outcome; past tasks and plans are reconciled. 0: no outcome is recorded.',
  'number', '1'::jsonb, '0', '1', 'on (1) or off (0)', 800, 'Platform upkeep',
  'security.job_outcome_record_v1, security.plan_outcome_record_v1, security.enrich_plan_tick_v1, security.ops_outcome_reconcile_v1', 'CF-247 ops D, P0 mandate 3 Nov 2026 15:37 §7: on (records only)'),
 ('pipeline', 'ops.outcome_reconcile_batch', 'Outcomes: past tasks and plans reconciled per run',
  'Job ops-job-lifecycle gives this many past tasks and this many past plans without an outcome their reconciled outcome each run, newest first. Only the outcome columns are written.',
  'number', '500'::jsonb, '10', '5000', 'rows per run', 801, 'Platform upkeep', 'security.ops_outcome_reconcile_v1 (ops-job-lifecycle)', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.retryable_errors', 'Outcomes: errors that are retryable',
  'A task that failed with an error containing one of these words is failed_retryable (time-outs, locks, connections); any other error is failed_remediation.',
  'list', '["statement timeout", "canceling statement", "deadlock", "lock timeout", "could not obtain lock", "connection", "timed out", "temporarily", "too many requests"]'::jsonb,
  null, null, 'words', 802, 'Platform upkeep', 'security.job_outcome_compute_v1, security.plan_outcome_compute_v1', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.policy_hold_codes', 'Outcomes: holds that are a policy',
  'A task held (or ended) by one of these lane gates is blocked_policy: a cap, a budget, a switch or a rule a person sets.',
  'list', '["daily_cap", "day_budget", "month_cap", "credit_refused", "credits_reserve", "search_off", "lane_paused", "provider_hidden", "search_stopped", "not_target", "skipped_provider"]'::jsonb,
  null, null, 'gate codes', 803, 'Platform upkeep', 'security.ops_hold_outcome_v1', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.evidence_hold_codes', 'Outcomes: holds that wait for evidence',
  'A task held (or ended) by one of these is blocked_evidence: it needs a fact the platform does not have yet (a website, a site that is not a directory). Any other hold is deferred_dependency.',
  'list', '["no_site", "directory_site", "no_website", "needs_source_discovery"]'::jsonb, null, null, 'gate codes', 804, 'Platform upkeep', 'security.ops_hold_outcome_v1', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.lease_grace_minutes', 'Self-healing: a lease counts as orphaned after',
  'A field item leased to the AI reader whose lease ran out this many minutes ago, and that the reader can no longer pick (at the attempt cap), is orphaned work.',
  'number', '30'::jsonb, '5', '1440', 'minutes', 805, 'Platform upkeep', 'security.ops_lifecycle_detect_v1, security.ops_lease_orphan_close_v1', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.lease_attempts_max', 'Self-healing: AI reader attempts per item',
  'The AI reader picks a field item while its attempts are below this (the picker''s cap, 3). An item at the cap still leased or waiting is never picked again.',
  'number', '3'::jsonb, '1', '10', 'attempts', 806, 'Platform upkeep', 'security.ops_lifecycle_detect_v1, security.ops_lease_orphan_close_v1', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.lease_orphan_close_on', 'Self-healing: close orphaned field items',
  '1: job ops-job-lifecycle closes orphaned field items (lease run out at the attempt cap) as failed with the reason, so their task can finish and the gap is classified. 0: detected only.',
  'number', '0'::jsonb, '0', '1', 'on (1) or off (0)', 807, 'Platform upkeep', 'security.ops_lease_orphan_close_v1', 'CF-247 ops D, 3 Nov 2026: ships off (changes work)'),
 ('pipeline', 'ops.lane_orphan_release_on', 'Self-healing: release task precedence left by ended tasks',
  '1: a course queued for course page search with a task''s precedence (requested_at) but no open task is searched in its normal turn, as when a person cancels a task, so live tasks are not starved. 0: detected only.',
  'number', '0'::jsonb, '0', '1', 'on (1) or off (0)', 808, 'Platform upkeep', 'security.ops_lane_orphan_release_v1', 'CF-247 ops D, 3 Nov 2026: ships off (reorders work)'),
 ('pipeline', 'ops.interrupted_minutes', 'Self-healing: a task counts as interrupted after',
  'A queued or running task the task runner has not touched for this many minutes is interrupted (the runner runs every minute).',
  'number', '15'::jsonb, '5', '1440', 'minutes', 809, 'Platform upkeep', 'security.ops_lifecycle_detect_v1', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.task_dedupe_on', 'Self-healing: stop duplicate tasks',
  '1: of two open tasks of the same kind for the same provider (or scope), the newer one an enrichment plan started is asked to stop at its next boundary. A person''s task is never stopped. 0: detected only.',
  'number', '0'::jsonb, '0', '1', 'on (1) or off (0)', 810, 'Platform upkeep', 'security.ops_task_dedupe_v1', 'CF-247 ops D, 3 Nov 2026: ships off (removes work)'),
 ('pipeline', 'ops.retry_cost_max_usd', 'Self-healing: paid retry cost per task',
  'An open task whose field items read more than once cost more than this in ops.retry_cost_window_hours has excessive paid retry cost.',
  'number', '1'::jsonb, '0.1', '100', 'US$', 811, 'Platform upkeep', 'security.ops_lifecycle_detect_v1, security.ops_retry_cost_pause_v1', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.retry_cost_window_hours', 'Self-healing: paid retry cost window',
  'The paid retry cost of a task is counted over this many hours.',
  'number', '24'::jsonb, '1', '168', 'hours', 812, 'Platform upkeep', 'security.ops_lifecycle_detect_v1, security.ops_retry_cost_pause_v1', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.retry_cost_pause_on', 'Self-healing: pause tasks with excessive paid retries',
  '1: an open task over ops.retry_cost_max_usd is asked to pause at its next boundary, with the reason; a person resumes it. 0: detected only.',
  'number', '0'::jsonb, '0', '1', 'on (1) or off (0)', 813, 'Platform upkeep', 'security.ops_retry_cost_pause_v1', 'CF-247 ops D, 3 Nov 2026: ships off (stops work)'),
 ('pipeline', 'ops.answer_settle_minutes', 'Self-healing: an AI answer counts as unrecorded after',
  'An AI answer kept in pipeline.enrich_ai_answers whose items are still unsettled this many minutes later was not recorded.',
  'number', '2'::jsonb, '1', '60', 'minutes', 814, 'Platform upkeep', 'security.ops_lifecycle_detect_v1, security.ops_answer_replay_v1', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.answer_replay_batch', 'Self-healing: AI answers replayed per run',
  'At most this many unrecorded AI answers (items) are recorded again from the kept answer per run, in one short call each.',
  'number', '20'::jsonb, '1', '200', 'items per run', 815, 'Platform upkeep', 'security.ops_answer_replay_v1', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.answer_replay_on', 'Self-healing: record a paid AI answer again from the kept copy',
  '1: an AI answer that was paid for but whose record failed is recorded again from pipeline.enrich_ai_answers through the same recording rules (svc_enrich_ai_record), never by reading again. Needs the worker to keep its answers first. 0: detected only.',
  'number', '0'::jsonb, '0', '1', 'on (1) or off (0)', 816, 'Platform upkeep', 'security.ops_answer_replay_v1', 'CF-247 ops D, 3 Nov 2026: ships off (admits data)'),
 ('pipeline', 'ops.heal_batch', 'Self-healing: rows changed per remedy per run',
  'Each self-healing remedy changes at most this many rows per run.',
  'number', '200'::jsonb, '1', '5000', 'rows per run', 817, 'Platform upkeep', 'security.ops_lease_orphan_close_v1, security.ops_lane_orphan_release_v1, security.ops_task_dedupe_v1, security.ops_retry_cost_pause_v1', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.heal_max_attempts', 'Self-healing: remedy attempts per issue',
  'The operations controller tries a self-healing remedy on one issue at most this many times before it escalates.',
  'number', '3'::jsonb, '1', '20', 'attempts', 818, 'Platform upkeep', 'pipeline.ops_remedies (workstream D remedies)', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'ops.heal_cooldown_minutes', 'Self-healing: wait between remedy attempts',
  'The operations controller waits this many minutes between two attempts of a self-healing remedy on one issue.',
  'number', '30'::jsonb, '5', '1440', 'minutes', 819, 'Platform upkeep', 'pipeline.ops_remedies (workstream D remedies)', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'plans.empty_cycles_max', 'Plans: stop after this many empty cycles',
  'The automatic planner does not propose a university whose last this many plans moved no data, while no new verified evidence or central pages arrived and its missing values did not grow by plans.replan_min_new_gaps (until plans.empty_cycles_quiet_days pass). A person''s Run now still sees the steps. 0: off.',
  'number', '3'::jsonb, '0', '20', 'plans', 820, 'Platform upkeep', 'security.plan_empty_cycles_v1 (security.enrich_plan_v1)', 'CF-247 ops D, 3 Nov 2026: on (stops waste)'),
 ('pipeline', 'plans.empty_cycles_quiet_days', 'Plans: empty-cycle stop lasts',
  'A university stopped for repeated empty cycles is proposed again after this many days even without new evidence.',
  'number', '14'::jsonb, '1', '180', 'days', 821, 'Platform upkeep', 'security.plan_empty_cycles_v1', 'CF-247 ops D, 3 Nov 2026'),
 ('pipeline', 'plans.lane_backlog_wait_on', 'Plans: Find course pages waits for the provider''s queued searches',
  '1: an automatic plan''s Find course pages step waits (deferred_dependency) while the provider''s course searches are still queued in the course page search lane, because a new task would queue every course again and pay for searches already done or under way; it waits at most plans.step_wait_hours. 0: as before.',
  'number', '1'::jsonb, '0', '1', 'on (1) or off (0)', 822, 'Platform upkeep', 'security.plan_step_dependency_v1 (security.enrich_plan_tick_v1)', 'CF-247 ops D, IQ-00064: on (stops duplicate spend)'),
 ('pipeline', 'plans.step_dependency_on', 'Plans: Fill missing fields waits for Find course pages',
  '1: a plan''s Fill missing fields step waits (deferred_dependency) while the same plan''s Find course pages step is unfinished, because it reads the pages that step finds; it waits at most plans.step_wait_hours, then goes ahead. 0: as before (both run side by side).',
  'number', '0'::jsonb, '0', '1', 'on (1) or off (0)', 823, 'Platform upkeep', 'security.plan_step_dependency_v1 (security.enrich_plan_tick_v1)', 'CF-247 ops D, P0 mandate §7 dependency sequencing: ships off (delays fills)'),
 ('pipeline', 'plans.retry_ignores_min_days', 'Plans: a retry re-plan does not wait plans.replan_min_days',
  '1: with plans.replan_on_retry, a university whose latest plan has a step that can run again is re-planned once that step''s own wait (plans.retry_after_hours) has passed, not only after plans.replan_min_days; the fingerprint and plans.replan_per_hour still apply. 0: as before.',
  'number', '1'::jsonb, '0', '1', 'on (1) or off (0)', 824, 'Platform upkeep', 'security.enrich_plan_auto_v1', 'CF-247 ops D, IQ-00064 (Integration Controller 3 Nov 2026 15:55): on')
on conflict (toolset_key, key) do nothing;

-- 2. tables and columns ----------------------------------------------------------------------------------------------------------------------
alter table pipeline.enrich_plan_runs add column if not exists outcome text references pipeline.ops_outcome_codes(code),
                                      add column if not exists outcome_detail jsonb;
comment on column pipeline.enrich_plan_runs.outcome is 'CF-247 ops D: the plan''s explicit outcome (pipeline.ops_outcome_codes), from the data its steps actually moved; set when it finishes (security.enrich_plan_tick_v1) or reconciled for past plans (security.ops_outcome_reconcile_v1). state, steps and actual are never rewritten.';
comment on column pipeline.enrich_plan_runs.outcome_detail is 'CF-247 ops D: how the outcome was reached: each step''s outcome and movement, basis (at_close or reconciled) and when.';

create table if not exists pipeline.enrich_plan_auto_runs (
  id bigint generated always as identity primary key,
  run_at timestamptz not null default now(),
  outcome text not null,
  created int not null default 0,
  replanned int not null default 0,
  nothing_to_do int not null default 0,
  considered int not null default 0,
  replan_capped int not null default 0,
  open_plans int,
  room int,
  reason text,
  detail jsonb not null default '{}'::jsonb);
comment on table pipeline.enrich_plan_auto_runs is 'CF-247 ops D (Integration Controller 3 Nov 2026 15:55): one row per run of job enrich-plan-auto (security.enrich_plan_auto_v1): what it created and why it created nothing when it did not (off, full, nothing_eligible, replan_cap, nothing_to_do, created), with the counts it saw. An empty cycle is explainable from data.';
create index if not exists enrich_plan_auto_runs_at on pipeline.enrich_plan_auto_runs (run_at desc);

create table if not exists pipeline.enrich_ai_answers (
  id bigint generated always as identity primary key,
  item_id bigint not null,
  attempts int not null,
  evidence_id uuid,
  storage_path text,
  answer jsonb not null,
  cost_usd numeric,
  received_at timestamptz not null default now(),
  state text not null default 'received' check (state in ('received', 'recorded', 'replayed', 'superseded', 'failed')),
  settled_at timestamptz,
  detail jsonb not null default '{}'::jsonb,
  unique (item_id, attempts));
comment on table pipeline.enrich_ai_answers is 'CF-247 ops D (P0 mandate 3 Nov 2026 15:37 §4 and §7; acceptance mandate 15:52 §9: preserve the paid result, retry only the failed recording): the AI reader''s answer for each field item, kept before it is recorded (public.svc_enrich_ai_stash_v1), keyed by the item and its attempt, with the evidence it was read from (evidence_id, storage_path). An answer whose item is still unsettled after ops.answer_settle_minutes, on the same attempt and the same evidence, was not recorded: only the recording is retried from this copy (security.ops_answer_replay_v1, ops.answer_replay_on) and the item''s final state is checked (replayed or failed). recorded: the item settled by the normal path; superseded: the item was leased again or its evidence changed, so the copy is not used.';
create index if not exists enrich_ai_answers_open on pipeline.enrich_ai_answers (received_at) where state = 'received';

-- 3. outcomes (read-only computation; recording only through security.job_outcome_set_v1 and the plan outcome columns) -------------------
create or replace function security.ops_hold_outcome_v1(p_code text) returns text
language sql stable security definer set search_path = '' as $$
  -- CF-247 ops D: the outcome of a lane hold: a policy (cap, budget, switch, rule), missing evidence, or waiting for another step's work
  select case when p_code = any (security.pipeline_list_v1('ops.policy_hold_codes', '["daily_cap", "day_budget", "month_cap", "credit_refused", "credits_reserve", "search_off", "lane_paused", "provider_hidden", "search_stopped", "not_target", "skipped_provider"]')) then 'blocked_policy'
              when p_code = any (security.pipeline_list_v1('ops.evidence_hold_codes', '["no_site", "directory_site", "no_website", "needs_source_discovery"]')) then 'blocked_evidence'
              else 'deferred_dependency' end
$$;

create or replace function security.ops_error_retryable_v1(p_error text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from unnest(security.pipeline_list_v1('ops.retryable_errors', '["statement timeout", "canceling statement", "deadlock", "lock timeout", "could not obtain lock", "connection", "timed out", "temporarily", "too many requests"]')) w
                  where position(lower(w) in lower(coalesce(p_error, ''))) > 0)
$$;

create or replace function security.job_movement_v1(p_job uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
-- CF-247 ops D (P0 mandate §7 "a successful job is not proof of enrichment"): the data a task actually moved, by kind, from the rows it
-- changed (items filled or sent to review, pages found, scholarships added or relinked, provider facts found), never from its progress
-- counter alone. basis 'progress' marks the kinds measured only by their own count of things done.
declare j pipeline.admin_jobs%rowtype; v_t0 timestamptz; v_t1 timestamptz; v_a int := 0; v_b int := 0; v_c int := 0; v_pid uuid;
begin
  select * into j from pipeline.admin_jobs x where x.id = p_job;
  if j.id is null then return null; end if;
  v_t0 := coalesce(j.started_at, j.created_at); v_t1 := coalesce(j.finished_at, now());
  if j.kind = 'enrich_fields' then
    select count(*) filter (where e.state = 'filled'), count(*) filter (where e.state = 'review') into v_a, v_b from pipeline.field_enrich_items e where e.job_id = p_job;
    return jsonb_build_object('moved', v_a + v_b > 0, 'basis', 'field_enrich_items', 'filled', v_a, 'review', v_b);
  elsif j.kind = 'course_page_find' then
    if jsonb_typeof(j.result->'found') = 'number' then v_a := (j.result->>'found')::int;
    else
      select count(*) into v_a from pipeline.course_link_search s
       where s.course_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(j.args->'course_ids', '[]'::jsonb)) x))
         and s.state in ('found', 'verified') and s.done_at between v_t0 and v_t1;
    end if;
    return jsonb_build_object('moved', v_a > 0, 'basis', 'course_link_search', 'pages_found', v_a, 'not_found', coalesce((j.result->>'not_found')::int, 0));
  elsif j.kind in ('scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread') then
    v_a := coalesce((j.result->>'new_scholarships')::int, 0); v_b := coalesce((j.result->>'became')::int, 0); v_c := coalesce((j.result->>'links_changed')::int, 0);
    return jsonb_build_object('moved', v_a + v_b + v_c > 0, 'basis', 'scholarships', 'new_scholarships', v_a, 'became', v_b, 'links_changed', v_c);
  elsif j.kind = 'provider_fill' then
    v_pid := nullif(j.args->>'provider_id', '')::uuid;
    select count(*) into v_a from pipeline.provider_contact_checks k where k.provider_id = v_pid and k.checked_at between v_t0 and v_t1 and k.outcome = 'found';
    select count(*) into v_b from pipeline.provider_central_search s where s.provider_id = v_pid and s.searched_at between v_t0 and v_t1 and coalesce(jsonb_array_length(s.found), 0) > 0;
    select count(*) into v_c from pipeline.coverage_provider_discovery d join catalogue.providers p on p.id = d.provider_id
     where d.provider_id = v_pid and d.site_searched_at between v_t0 and v_t1 and nullif(btrim(p.website), '') is not null;
    return jsonb_build_object('moved', v_a + v_b + v_c > 0, 'basis', 'provider_facts', 'contacts_found', v_a, 'central_found', v_b, 'website_found', v_c);
  elsif j.kind in ('scholarship_ai_qualify', 'scholarship_ai_backfill') then
    select count(*) filter (where coalesce((e.applied->>'admitted')::boolean, false)), count(*) filter (where e.verdict = 'scholarship') into v_a, v_b
      from pipeline.scholarship_ai_extractions e where e.job_id = p_job;
    return jsonb_build_object('moved', case when j.kind = 'scholarship_ai_backfill' then v_a > 0 else v_b > 0 end, 'basis', 'scholarship_ai_extractions', 'admitted', v_a, 'scholarships', v_b);
  elsif j.kind = 'qualify_adapters' then
    return jsonb_build_object('moved', coalesce((j.result->>'passing')::int, 0) > 0, 'basis', 'adapters', 'passing', coalesce((j.result->>'passing')::int, 0));
  end if;
  return jsonb_build_object('moved', coalesce((j.result->>'done')::numeric, 0) > 0 or (j.state = 'done' and not (j.result ? 'done')), 'basis', 'progress',
                            'done', j.result->'done', 'total', j.result->'total');
end $$;

create or replace function security.job_outcome_compute_v1(p_job uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
-- CF-247 ops D (P0 mandate §7): a task's explicit outcome. Open: held by a lane gate gives a provisional deferred_dependency, blocked_policy
-- or blocked_evidence, otherwise none. Ended: not needed (the IQ-00066 path: state cancelled, end_state not_needed, kept cancelled for
-- compatibility, the outcome is the truth); held too long, by the gate's kind (a waiting turn is failed_retryable); an error, retryable or
-- needing remediation; done with work unfinished (IQ-00064), failed_retryable; done, with or without data movement. A person's cancel keeps
-- what it moved (succeeded_with_result) or is not_needed.
declare j pipeline.admin_jobs%rowtype; v_mv jsonb; v_out text; v_code text; v_moved boolean; v_unf boolean;
begin
  select * into j from pipeline.admin_jobs x where x.id = p_job;
  if j.id is null then return null; end if;
  if j.state in ('queued', 'running', 'paused') then
    if j.result ? 'held' then
      v_code := coalesce(j.result->'held'->>'code', 'waiting_turn');
      return jsonb_build_object('outcome', security.ops_hold_outcome_v1(v_code), 'moved', null,
                                'detail', jsonb_build_object('provisional', true, 'state', j.state, 'hold', v_code, 'reason', j.result->'held'->>'reason'));
    end if;
    return jsonb_build_object('outcome', null, 'moved', null, 'detail', null);
  end if;
  v_mv := security.job_movement_v1(p_job);
  v_moved := coalesce((v_mv->>'moved')::boolean, false);
  v_unf := j.state = 'done' and j.kind = any (security.pipeline_list_v1('tasks.hold_kinds', '["course_page_find", "scholarship_provider_scan", "provider_fill"]'))
           and jsonb_typeof(j.result->'done') = 'number' and jsonb_typeof(j.result->'total') = 'number' and (j.result->>'done')::numeric < (j.result->>'total')::numeric;
  v_code := coalesce(j.result->'held'->>'code', j.result->'blocked'->>'code');
  v_out := case
    when j.state = 'cancelled' and j.result->>'end_state' = 'not_needed' then 'not_needed'
    when j.state = 'cancelled' then case when v_moved then 'succeeded_with_result' else 'not_needed' end
    when j.state = 'failed' and j.result->>'end_state' = 'failed' then
      case when security.ops_hold_outcome_v1(coalesce(v_code, 'waiting_turn')) in ('blocked_policy', 'blocked_evidence') then security.ops_hold_outcome_v1(v_code) else 'failed_retryable' end
    when j.state = 'failed' then case when security.ops_error_retryable_v1(j.error) then 'failed_retryable' else 'failed_remediation' end
    when v_unf then 'failed_retryable'
    when v_moved then 'succeeded_with_result'
    else 'succeeded_no_movement' end;
  return jsonb_build_object('outcome', v_out, 'moved', v_moved,
    'detail', jsonb_build_object('state', j.state, 'end_state', j.result->>'end_state', 'movement', v_mv, 'hold', v_code,
                                 'unprocessed', case when v_unf then (j.result->>'total')::numeric - (j.result->>'done')::numeric end,
                                 'cancelled_by_person', j.state = 'cancelled' and coalesce(j.result->>'end_state', '') <> 'not_needed',
                                 'error', left(j.error, 300)));
end $$;

create or replace function security.job_outcome_record_v1(p_job uuid, p_basis text) returns text
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops D: records a task's outcome through workstream A's security.job_outcome_set_v1 (ops.outcome_on). Never fails the caller: a
-- task's close or watch carries on whatever happens here.
declare v jsonb; v_cur text;
begin
  if security.pipeline_num_v1('ops.outcome_on', 0) < 1 then return null; end if;
  v := security.job_outcome_compute_v1(p_job);
  if v is null then return null; end if;
  select j.outcome into v_cur from pipeline.admin_jobs j where j.id = p_job;
  if v->>'outcome' is null and v_cur is null then return null; end if;
  perform security.job_outcome_set_v1(p_job, v->>'outcome', coalesce(v->'detail', '{}'::jsonb) || jsonb_build_object('basis', p_basis, 'at', now()));
  return v->>'outcome';
exception when others then
  raise notice 'job outcome not recorded for %: %', p_job, sqlerrm;
  return null;
end $$;

create or replace function security.plan_outcome_compute_v1(p_run uuid, p_final boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
-- CF-247 ops D (P0 mandate §7, IQ-00066): an enrichment plan's explicit outcome from what its steps' tasks actually moved. Any step that
-- moved data: succeeded_with_result. Otherwise the most pressing step outcome (failed_retryable, failed_remediation, blocked_policy,
-- blocked_evidence, deferred_dependency, succeeded_no_movement), or not_needed when every step that ran was not needed. legacy gives the
-- v2.15.426 words (moved, not_needed, no_movement) for actual.outcome and the plan outcome report. p_final: the plan is finishing now (the tick).
declare r pipeline.enrich_plan_runs%rowtype; e jsonb; v_o text; v_m boolean; v_jo jsonb; v_steps jsonb := '[]'::jsonb; v_moved boolean := false; v_out text;
begin
  select * into r from pipeline.enrich_plan_runs x where x.id = p_run;
  if r.id is null then return null; end if;
  for e in select x from jsonb_array_elements(coalesce(r.steps, '[]'::jsonb)) x loop
    v_o := null; v_m := null;
    if e->'ref'->>'kind' = 'job' and nullif(e->'ref'->>'id', '') is not null then
      v_jo := security.job_outcome_compute_v1((e->'ref'->>'id')::uuid);
      v_o := v_jo->>'outcome'; v_m := (v_jo->>'moved')::boolean;
      if v_o is null and e->>'status' in ('failed', 'timed_out', 'cancelled') then v_o := 'failed_retryable'; end if;
    elsif e->'ref'->>'kind' = 'onboarding' then
      select case when o.status in ('waiting_admit', 'done', 'scholarships') then 'succeeded_with_result'
                  when o.status = 'stopped' then case when security.ops_hold_outcome_v1(o.stop_reason) = 'blocked_evidence' or o.stop_reason in ('too_few_pages', 'nothing_ready') then 'blocked_evidence' else 'failed_remediation' end
                  when o.status = 'cancelled' then 'not_needed' end,
             o.status in ('waiting_admit', 'done', 'scholarships')
        into v_o, v_m from pipeline.provider_onboarding o where o.id = nullif(e->'ref'->>'id', '')::uuid;
    else
      v_o := case e->>'status' when 'not_needed' then 'not_needed' when 'cancelled' then 'not_needed' when 'waiting' then 'deferred_dependency'
                  when 'skipped' then case when coalesce(e->>'note', '') like 'no room in the % share%' then 'blocked_policy'
                                           when coalesce(e->>'note', '') like 'Deferred:%' then 'deferred_dependency' else 'blocked_evidence' end
                  when 'failed' then case when security.ops_error_retryable_v1(e->>'note') then 'failed_retryable' else 'failed_remediation' end end;
    end if;
    v_moved := v_moved or coalesce(v_m, false);
    if e->>'status' <> 'person' then v_steps := v_steps || jsonb_build_object('step', e->>'step', 'status', e->>'status', 'outcome', v_o, 'moved', v_m); end if;
  end loop;
  if v_moved then v_out := 'succeeded_with_result';
  elsif r.state in ('queued', 'running') and not p_final then v_out := null;
  else
    select o into v_out from unnest(array['failed_retryable', 'failed_remediation', 'blocked_policy', 'blocked_evidence', 'deferred_dependency', 'succeeded_no_movement']) with ordinality u(o, n)
     where exists (select 1 from jsonb_array_elements(v_steps) s where s->>'outcome' = u.o) order by n limit 1;
    v_out := coalesce(v_out, case when jsonb_array_length(v_steps) > 0 and not exists (select 1 from jsonb_array_elements(v_steps) s where coalesce(s->>'outcome', '') <> 'not_needed')
                                  then 'not_needed' else 'succeeded_no_movement' end);
  end if;
  return jsonb_build_object('outcome', v_out, 'moved', v_moved, 'legacy', case when v_out is null then null when v_moved then 'moved' when v_out = 'not_needed' then 'not_needed' else 'no_movement' end,
                            'steps', v_steps);
end $$;

create or replace function security.plan_outcome_record_v1(p_run uuid, p_basis text) returns text
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops D: writes a finished plan's outcome to its outcome columns only (ops.outcome_on); state, steps and actual are not touched
declare v jsonb;
begin
  if security.pipeline_num_v1('ops.outcome_on', 0) < 1 then return null; end if;
  v := security.plan_outcome_compute_v1(p_run);
  if v is null or v->>'outcome' is null then return null; end if;
  update pipeline.enrich_plan_runs set outcome = v->>'outcome',
         outcome_detail = jsonb_build_object('moved', v->'moved', 'steps', v->'steps', 'basis', p_basis, 'at', now())
   where id = p_run and outcome is distinct from v->>'outcome';
  return v->>'outcome';
exception when others then
  raise notice 'plan outcome not recorded for %: %', p_run, sqlerrm;
  return null;
end $$;

create or replace function security.ops_outcome_reconcile_v1() returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops D (P0 mandate §7 "historical plans must retain truthful outcomes"): past tasks and plans without an outcome get their reconciled
-- outcome, newest first, ops.outcome_reconcile_batch of each per run. Only the outcome columns are written (basis reconciled).
declare v_n int := greatest(1, security.pipeline_num_v1('ops.outcome_reconcile_batch', 500)::int); r record; v_j int := 0; v_p int := 0;
begin
  if security.pipeline_num_v1('ops.outcome_on', 0) < 1 then return jsonb_build_object('outcomes', 'off'); end if;
  for r in select j.id from pipeline.admin_jobs j where j.state in ('done', 'failed', 'cancelled') and j.outcome is null
            order by j.finished_at desc nulls last, j.created_at desc limit v_n loop
    if security.job_outcome_record_v1(r.id, 'reconciled') is not null then v_j := v_j + 1; end if;
  end loop;
  for r in select x.id from pipeline.enrich_plan_runs x where x.state in ('done', 'failed', 'cancelled') and x.outcome is null
            order by x.finished_at desc nulls last, x.created_at desc limit v_n loop
    if security.plan_outcome_record_v1(r.id, 'reconciled') is not null then v_p := v_p + 1; end if;
  end loop;
  return jsonb_build_object('tasks', v_j, 'plans', v_p,
    'tasks_left', (select count(*) from pipeline.admin_jobs j where j.state in ('done', 'failed', 'cancelled') and j.outcome is null),
    'plans_left', (select count(*) from pipeline.enrich_plan_runs x where x.state in ('done', 'failed', 'cancelled') and x.outcome is null));
end $$;

-- 4. plan step dependencies and repeated empty cycles (read-only) --------------------------------------------------------------------------
create or replace function security.plan_step_dependency_v1(p_run uuid, p_step jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
-- CF-247 ops D (P0 mandate §7 dependency sequencing, IQ-00064): why a pending plan step must wait for work another step or lane is still
-- producing, or null. Find course pages (automatic plans, plans.lane_backlog_wait_on): the provider's course searches still queued or sent in
-- the course page search lane (a new task queues every course again: searches already done or under way would be paid twice). Fill missing
-- fields (plans.step_dependency_on): the same plan's Find course pages step is unfinished.
declare r pipeline.enrich_plan_runs%rowtype; v_n int; v_blk jsonb;
begin
  select * into r from pipeline.enrich_plan_runs x where x.id = p_run;
  if r.id is null or coalesce((p_step->>'person')::boolean, false) then return null; end if;
  if p_step->>'step' = 'pages' and r.mode = 'auto' and security.pipeline_num_v1('plans.lane_backlog_wait_on', 0) >= 1 then
    select count(*) into v_n from pipeline.course_link_search s where s.provider_id = r.provider_id and s.state in ('queued', 'sent');
    if v_n > 0 then
      v_blk := security.link_search_block_v1(r.provider_id, null);
      return jsonb_build_object('code', 'lane_backlog', 'outcome', 'deferred_dependency', 'queued', v_n, 'hold', v_blk->>'code',
        'reason', v_n || ' course search(es) of this provider are still queued in the course page search lane'
                  || coalesce(' (' || (v_blk->>'words') || ')', '') || '; the step starts once they are searched, so none is paid twice');
    end if;
  elsif p_step->>'step' = 'fields' and security.pipeline_num_v1('plans.step_dependency_on', 0) >= 1
        and exists (select 1 from jsonb_array_elements(r.steps) x where x->>'step' = 'pages' and x->>'status' in ('pending', 'waiting', 'running')) then
    return jsonb_build_object('code', 'step_dependency', 'outcome', 'deferred_dependency', 'after', 'pages',
                              'reason', 'waits for this plan''s Find course pages step, whose pages it reads');
  end if;
  return null;
end $$;

create or replace function security.plan_empty_cycles_v1(p_provider uuid, p_missing numeric default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
-- CF-247 ops D (P0 mandate §7 IQ-00066 "prevent repeated empty cycles"): a university whose last plans.empty_cycles_max plans all finished
-- without moving data, with no new verified evidence or central pages since the latest of them, missing values not grown by
-- plans.replan_min_new_gaps, and within plans.empty_cycles_quiet_days of it. Null when it may be proposed.
declare v_n int := security.pipeline_num_v1('plans.empty_cycles_max', 0)::int; v_ids uuid[]; v_outs text[]; v_last record; v_in jsonb;
begin
  if v_n <= 0 then return null; end if;
  select array_agg(id order by created_at desc), array_agg(o order by created_at desc) into v_ids, v_outs
    from (select x.id, x.created_at, coalesce(x.outcome, security.plan_outcome_compute_v1(x.id)->>'outcome') o
            from pipeline.enrich_plan_runs x where x.provider_id = p_provider and x.state in ('done', 'failed', 'cancelled')
           order by x.created_at desc limit v_n) z;
  if coalesce(cardinality(v_ids), 0) < v_n then return null; end if;
  if exists (select 1 from unnest(v_outs) o join pipeline.ops_outcome_codes k on k.code = o where k.counts_as_movement) or array_position(v_outs, null) is not null then return null; end if;
  select x.id, coalesce(x.finished_at, x.created_at) at, (x.estimate->>'missing')::numeric missing into v_last from pipeline.enrich_plan_runs x where x.id = v_ids[1];
  if v_last.at < now() - make_interval(days => security.pipeline_num_v1('plans.empty_cycles_quiet_days', 14)::int) then return null; end if;
  if p_missing is not null and v_last.missing is not null and p_missing >= v_last.missing + security.pipeline_num_v1('plans.replan_min_new_gaps', 5) then return null; end if;
  v_in := security.enrich_plan_inputs_v1(p_provider);
  if coalesce((v_in->>'evidence_new')::int, 0) > 0 or coalesce((v_in->>'central_new')::boolean, false) then return null; end if;
  return jsonb_build_object('plans', to_jsonb(v_ids), 'outcomes', to_jsonb(v_outs), 'since', v_last.at,
    'reason', 'the last ' || v_n || ' plans moved no data (' || array_to_string(v_outs, ', ') || ') and no new verified evidence, central pages or missing values since '
              || to_char(v_last.at at time zone 'Australia/Melbourne', 'DD Mon HH24:MI') || '; proposed again when they change');
end $$;

-- 5. md5-guarded edits of the live engine ---------------------------------------------------------------------------------------------------
-- 5a every ended task records its outcome, whichever path ended it (the runner's done, failed and cancelled paths and a person's cancel)
select pg_temp.edit_once('security.admin_job_close_v1(uuid)', '233236ffc66e438edb21c4f51a6c45a1', '1c33edb08b5ee5724a67a24ebc39913f', array[
  [$o$  if v_j.id is null or v_j.state not in ('done', 'failed', 'cancelled') then return; end if;
$o$,
   $n$  if v_j.id is null or v_j.state not in ('done', 'failed', 'cancelled') then return; end if;
  perform security.job_outcome_record_v1(p_id, 'at_close');  -- CF-247 ops D (P0 mandate 15:37 §7): every ended task records its explicit outcome
$n$]]::text[][], array[1]);

-- 5b a held task carries its provisional outcome (deferred_dependency, blocked_policy or blocked_evidence), cleared when it moves again
select pg_temp.edit_once('security.admin_job_watch_v1(uuid)', '995f26c437f0abfb3c666271cd622fec', 'a7b17b399222f34c3b49460c73a7cef7', array[
  [$o$  if v_fin and v_note is not null then insert into pipeline.admin_job_events(job_id, note) values (p_id, v_note); end if;
  return v_fin;$o$,
   $n$  if v_fin and v_note is not null then insert into pipeline.admin_job_events(job_id, note) values (p_id, v_note); end if;
  -- CF-247 ops D (P0 mandate 15:37 §7): a held task carries its provisional outcome; it is cleared when the task moves again and set for good
  -- when it ends (security.admin_job_close_v1)
  if not v_fin and (v_j.result->'held'->>'code') is distinct from (v_extra->'held'->>'code') then perform security.job_outcome_record_v1(p_id, 'held'); end if;
  return v_fin;$n$]]::text[][], array[1]);

-- 5c a finished plan records its outcome (actual.outcome from real movement); a step whose input is still being produced waits
select pg_temp.edit_once('security.enrich_plan_tick_v1(uuid)', '77705c2b34e13801f4d7ccc5773bd4c1', '9b7c7c05491b95646b99fb7a855a9fa9', array[
  [$o$declare r pipeline.enrich_plan_runs%rowtype; s jsonb; i int; v_ref jsonb;$o$,
   $n$declare r pipeline.enrich_plan_runs%rowtype; s jsonb; i int; v_ref jsonb; v_dep jsonb;$n$],
  [$o$               'outcome', security.plan_run_outcome_v1(r.steps),  -- CF-247 IQ-00066: moved, not_needed or no_movement$o$,
   $n$               -- CF-247 IQ-00066: moved, not_needed or no_movement; CF-247 ops D: from what the steps' tasks actually moved (ops.outcome_on)
               'outcome', coalesce(case when security.pipeline_num_v1('ops.outcome_on', 0) >= 1 then security.plan_outcome_compute_v1(r.id, true)->>'legacy' end,
                                   security.plan_run_outcome_v1(r.steps)),$n$],
  [$o$      insert into search.refresh_requests(requested_by) values ('enrichment plan '$o$,
   $n$      perform security.plan_outcome_record_v1(r.id, 'at_close');  -- CF-247 ops D: the plan's explicit outcome (outcome columns only)
      insert into search.refresh_requests(requested_by) values ('enrichment plan '$n$],
  [$o$                     then security.plan_step_work_v1(r.provider_id, s->>'step') end;
$o$,
   $n$                     then security.plan_step_work_v1(r.provider_id, s->>'step') end;
      -- CF-247 ops D (P0 mandate 15:37 §7 dependency sequencing, IQ-00064): whether the step's input is still being produced; it waits at most
      -- plans.step_wait_hours (counted from when it was first deferred), then goes ahead as before
      v_dep := security.plan_step_dependency_v1(r.id, s);
      if v_dep is not null and coalesce((s->'deferred'->>'since')::timestamptz, now()) < now() - make_interval(hours => v_wait) then v_dep := null; end if;
$n$],
  [$o$      elsif r.mode = 'auto' and s->>'group' not in ('none')$o$,
   $n$      elsif v_dep is not null then
        -- CF-247 ops D: deferred_dependency, with the reason (no task is started, so nothing is queued or paid twice)
        v_state := 'waiting'; v_note := left('Deferred: ' || (v_dep->>'reason'), 300);
      elsif r.mode = 'auto' and s->>'group' not in ('none')$n$],
  [$o$(steps->i) || jsonb_build_object('status', v_state, 'note', v_note)$o$,
   $n$((steps->i) - 'deferred') || jsonb_build_object('status', v_state, 'note', v_note)$n$],
  [$o$                       || case when v_state = 'waiting' and not (steps->i ? 'waiting_since') then jsonb_build_object('waiting_since', now()) else '{}'::jsonb end$o$,
   $n$                       || case when v_state = 'waiting' and v_dep is null and not (steps->i ? 'waiting_since') then jsonb_build_object('waiting_since', now()) else '{}'::jsonb end
                       || case when v_state = 'waiting' and v_dep is not null then jsonb_build_object('deferred', v_dep || jsonb_build_object('since', coalesce(steps->i->'deferred'->'since', to_jsonb(now())))) else '{}'::jsonb end$n$]
  ]::text[][], array[1, 1, 1, 1, 1, 1, 1]);

-- 5d repeated empty cycles: the automatic planner (no person behind the call) is not offered the steps
select pg_temp.edit_once('security.enrich_plan_v1(uuid)', 'a63146c23989eb64ee2248e3f32eade6', '774c061974916b878f7762e55de07bb6', array[
  [$o$v_work jsonb; v_held jsonb := '[]'::jsonb;$o$,
   $n$v_work jsonb; v_held jsonb := '[]'::jsonb; v_empty jsonb;$n$],
  [$o$  return jsonb_build_object('provider_id', p.id, 'name', p.name,$o$,
   $n$  -- CF-247 ops D (P0 mandate 15:37 §7, IQ-00066): repeated empty cycles. The automatic planner (no person behind the call) is not offered
  -- the steps of a university whose last plans.empty_cycles_max plans moved no data and nothing changed since (security.plan_empty_cycles_v1);
  -- they are listed under not_proposed with the reason. A person's Run now sees the steps and the notice.
  v_empty := security.plan_empty_cycles_v1(p_provider, (select coalesce(sum((v->>'missing')::int), 0) from jsonb_each(f) e(k, v)));
  if v_empty is not null and auth.uid() is null and jsonb_array_length(v_steps) > 0 then
    v_held := v_held || (select jsonb_agg(jsonb_build_object('step', x->>'step', 'label', x->>'label', 'code', 'repeated_empty', 'reason', v_empty->>'reason')) from jsonb_array_elements(v_steps) x);
    v_steps := '[]'::jsonb;
  end if;
  return jsonb_build_object('provider_id', p.id, 'name', p.name,$n$],
  [$o$'steps', v_steps, 'not_proposed', v_held,$o$,
   $n$'steps', v_steps, 'not_proposed', v_held, 'empty_cycles', v_empty,$n$]
  ]::text[][], array[1, 1, 1]);

-- 5e the plan outcome report reads the reconciled outcome (a done plan whose steps moved nothing is not "moved")
select pg_temp.edit_once('security.plan_outcomes_v1()', '0f127f0241764413fb87278f403a2e14', 'f63b93e1bc954221e3388625594c7d56', array[
  [$o$coalesce(x.actual->>'outcome', security.plan_run_outcome_v1(x.steps)) outcome$o$,
   $n$coalesce(case when x.outcome is null then null when (select k.counts_as_movement from pipeline.ops_outcome_codes k where k.code = x.outcome) then 'moved'
                       when x.outcome = 'not_needed' then 'not_needed' else 'no_movement' end,  -- CF-247 ops D: the reconciled outcome first
                  x.actual->>'outcome', security.plan_run_outcome_v1(x.steps)) outcome$n$],
  [$o$    'tasks_not_needed', (select count(*)$o$,
   $n$    'by_outcome', (select coalesce(jsonb_object_agg(o, n), '{}'::jsonb) from (select coalesce(x2.outcome, 'not reconciled') o, count(*) n from pipeline.enrich_plan_runs x2, w
                                                                            where x2.finished_at >= w.since and x2.state = 'done' group by 1) z),  -- CF-247 ops D
    'tasks_not_needed', (select count(*)$n$]
  ]::text[][], array[1, 1]);

-- 5f IQ-00064: the retry inputs are read once a step can run again (not only after plans.replan_min_days); every run is recorded
create or replace function security.enrich_plan_auto_note_v1(p jsonb, p_room int default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops D (Integration Controller 3 Nov 2026 15:55): records one automatic planner run and why it created what it did
declare v_out text; v_why text;
begin
  v_out := case when p->>'auto' = 'off' then 'off' when p->>'auto' = 'full' then 'full'
                when coalesce((p->>'started')::int, 0) > 0 then 'created'
                when coalesce((p->>'considered')::int, 0) = 0 then 'nothing_eligible'
                when coalesce((p->>'replan_capped')::int, 0) > 0 then 'replan_cap'
                when coalesce((p->>'nothing_to_do')::int, 0) > 0 then 'nothing_to_do' else 'not_created' end;
  v_why := case v_out when 'off' then 'automatic plans are switched off (Enrichment plans › automatic)'
                      when 'full' then 'open automatic plans are at plans.auto_open_max'
                      when 'created' then (p->>'started') || ' plan(s) created, ' || coalesce(p->>'replanned', '0') || ' of them re-plans'
                      when 'nothing_eligible' then 'no university was due: never planned, past plans.redo_days, missing values grown, new evidence or a step that can run again'
                      when 'replan_cap' then 'universities due only for an early re-plan, and plans.replan_per_hour is used'
                      when 'nothing_to_do' then 'the universities due had no step to run for unchanged inputs (recorded in enrich_plan_noop)'
                      else 'universities were considered but none was created' end;
  insert into pipeline.enrich_plan_auto_runs(outcome, created, replanned, nothing_to_do, considered, replan_capped, open_plans, room, reason, detail)
  values (v_out, coalesce((p->>'started')::int, 0), coalesce((p->>'replanned')::int, 0), coalesce((p->>'nothing_to_do')::int, 0), coalesce((p->>'considered')::int, 0),
          coalesce((p->>'replan_capped')::int, 0), (p->>'open')::int, p_room, v_why, p);
  return p || jsonb_build_object('outcome', v_out, 'reason', v_why);
exception when others then
  raise notice 'automatic planner run not recorded: %', sqlerrm;
  return p;
end $$;

select pg_temp.edit_once('security.enrich_plan_auto_v1()', '14d4769267f827736a0d4e2f013c4dad', '14fee957a992f39a68075da1a952271a', array[
  [$o$v_gaps boolean; v_ev boolean; v_rt jsonb;$o$,
   $n$v_gaps boolean; v_ev boolean; v_rt jsonb; v_seen int := 0; v_capped int := 0;$n$],
  [$o$  if not coalesce(c.auto_enabled, false) then return jsonb_build_object('auto', 'off'); end if;$o$,
   $n$  if not coalesce(c.auto_enabled, false) then return security.enrich_plan_auto_note_v1(jsonb_build_object('auto', 'off')); end if;  -- CF-247 ops D: every run recorded$n$],
  [$o$  if v_room <= 0 then return jsonb_build_object('auto', 'full', 'open', v_open); end if;$o$,
   $n$  if v_room <= 0 then return security.enrich_plan_auto_note_v1(jsonb_build_object('auto', 'full', 'open', v_open), v_room); end if;$n$],
  [$o$                                   and a.created_at <= now() - make_interval(days => v_re_days)) i on true$o$,
   $n$                                   -- CF-247 ops D (IQ-00064, plans.retry_ignores_min_days): also read once the latest plan has a step that can run
                                   -- again; its own plans.retry_after_hours wait (security.enrich_plan_inputs_v1), the fingerprint and the cap still apply
                                   and (a.created_at <= now() - make_interval(days => v_re_days)
                                        or (v_on_rt and security.pipeline_num_v1('plans.retry_ignores_min_days', 0) >= 1
                                            and exists (select 1 from jsonb_array_elements(coalesce(a.steps, '[]'::jsonb)) s0
                                                         where s0->>'status' in ('failed', 'stopped', 'cancelled', 'timed_out', 'skipped'))))) i on true$n$],
  [$o$                   or (v_on_ev and ((i.v->>'evidence_new')::int > 0 or (i.v->>'central_new')::boolean))
$o$,
   $n$                   or (v_on_ev and ((i.v->>'evidence_new')::int > 0 or (i.v->>'central_new')::boolean)
                       and a.created_at <= now() - make_interval(days => v_re_days))  -- CF-247 ops D: evidence re-plans keep plans.replan_min_days
$n$],
  [$o$    exit when v_n >= v_room;
$o$,
   $n$    exit when v_n >= v_room;
    v_seen := v_seen + 1;
$n$],
  [$o$    continue when v_is_re and v_re_used + v_re >= v_re_max;$o$,
   $n$    if v_is_re and v_re_used + v_re >= v_re_max then v_capped := v_capped + 1; continue; end if;$n$],
  [$o$      v_ev := v_on_ev and ((v_in->>'evidence_new')::int > 0 or (v_in->>'central_new')::boolean);$o$,
   $n$      v_ev := v_on_ev and ((v_in->>'evidence_new')::int > 0 or (v_in->>'central_new')::boolean) and q.any_at <= now() - make_interval(days => v_re_days);$n$],
  [$o$  return jsonb_build_object('auto', 'on', 'started', v_n, 'replanned', v_re, 'nothing_to_do', v_same, 'open', v_open + v_n);$o$,
   $n$  return security.enrich_plan_auto_note_v1(jsonb_build_object('auto', 'on', 'started', v_n, 'replanned', v_re, 'nothing_to_do', v_same, 'open', v_open + v_n,
                                                         'considered', v_seen, 'replan_capped', v_capped), v_room);$n$]
  ]::text[][], array[1, 1, 1, 1, 1, 1, 1, 1, 1]);

-- 6. AI answers kept before they are recorded (the worker's call is an interface request to workstream B) ---------------------------------
create or replace function public.svc_enrich_ai_stash_v1(p_results jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops D (P0 mandate 15:37 §4 "do not incur a new paid read simply because a previous task failed to persist a result"): the AI
-- reader keeps its answers here, in one short insert, before it calls svc_enrich_ai_record; a failed record is then replayed from this copy
-- One row per answered item (a "retry" answer, asked again by design, is not kept); an answer already kept for the same attempt is unchanged.
declare v_n int;
begin
  if jsonb_typeof(p_results) <> 'array' or jsonb_array_length(p_results) = 0 then return jsonb_build_object('kept', 0); end if;
  insert into pipeline.enrich_ai_answers(item_id, attempts, evidence_id, storage_path, answer, cost_usd)
  select e.id, e.attempts, e.evidence_id, e.storage_path, x, (x->>'cost')::numeric
    from jsonb_array_elements(p_results) x join pipeline.field_enrich_items e on e.id = (x->>'item_id')::bigint
   where not coalesce((x->>'retry')::boolean, false)
  on conflict (item_id, attempts) do nothing;
  get diagnostics v_n = row_count;
  return jsonb_build_object('kept', v_n);
end $$;
revoke all on function public.svc_enrich_ai_stash_v1(jsonb) from public, anon, authenticated;
grant execute on function public.svc_enrich_ai_stash_v1(jsonb) to service_role;

-- 7. detection (read-only) -----------------------------------------------------------------------------------------------------------------
create or replace function security.ops_lifecycle_detect_v1() returns table(root_cause text, correlation_key text, n bigint, evidence jsonb)
language sql stable security definer set search_path = '' as $$
  -- CF-247 ops D: the job-lifecycle defects open now, one row per root cause and correlation key, with a sample (workstream A's controller
  -- reads it through pipeline.ops_root_causes.detect; job ops-job-lifecycle acts on it)
  with g as (select make_interval(mins => security.pipeline_num_v1('ops.lease_grace_minutes', 30)::int) lease_grace,
                    security.pipeline_num_v1('ops.lease_attempts_max', 3)::int att_max,
                    make_interval(mins => security.pipeline_num_v1('ops.interrupted_minutes', 15)::int) idle,
                    make_interval(hours => security.pipeline_num_v1('ops.retry_cost_window_hours', 24)::int) cost_window,
                    security.pipeline_num_v1('ops.retry_cost_max_usd', 1) cost_max,
                    make_interval(mins => security.pipeline_num_v1('ops.answer_settle_minutes', 2)::int) settle),
  lease as (select e.id, e.job_id, e.field, e.attempts, e.state, e.leased_until from pipeline.field_enrich_items e, g
             where e.attempts >= g.att_max and ((e.state = 'leased' and e.leased_until < now() - g.lease_grace) or e.state = 'ai')),
  lane as (select s.course_id, s.provider_id, s.requested_at from pipeline.course_link_search s
            where s.state = 'queued' and s.requested_at is not null
              and not exists (select 1 from pipeline.admin_jobs j where j.kind = 'course_page_find' and j.state in ('queued', 'running', 'paused')
                                 and j.args->'course_ids' ? s.course_id::text)),
  idle as (select j.id, j.kind, j.state, j.updated_at from pipeline.admin_jobs j, g where j.state in ('queued', 'running') and j.updated_at < now() - g.idle),
  dup as (select j.kind, coalesce(j.args->>'provider_id', j.scope) k, count(*) c, array_agg(j.id order by j.created_at) ids from pipeline.admin_jobs j
           where j.state in ('queued', 'running', 'paused') and coalesce(j.args->>'provider_id', j.scope) is not null group by 1, 2 having count(*) > 1),
  cost as (select e.job_id, round(sum(e.cost_usd), 4) usd, count(*) c from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id, g
            where j.state in ('queued', 'running') and e.attempts > 1 and e.updated_at > now() - g.cost_window group by 1 having sum(e.cost_usd) > (select cost_max from g)),
  ans as (select a.id, a.item_id, a.received_at from pipeline.enrich_ai_answers a join pipeline.field_enrich_items e on e.id = a.item_id, g
           where a.state = 'received' and a.received_at < now() - g.settle and e.state in ('ai', 'leased'))
  select 'lease_orphaned', 'field_enrich_items', (select count(*) from lease),
         (select jsonb_build_object('sample', coalesce(jsonb_agg(to_jsonb(l)), '[]'::jsonb)) from (select * from lease limit 5) l) where exists (select 1 from lease)
  union all
  select 'lane_work_orphaned', 'course_link_search', (select count(*) from lane),
         (select jsonb_build_object('providers', count(distinct provider_id), 'oldest', min(requested_at)) from lane) where exists (select 1 from lane)
  union all
  select 'job_interrupted', 'admin_jobs:' || i.kind, count(*), jsonb_build_object('sample', jsonb_agg(i.id), 'oldest', min(i.updated_at)) from idle i group by i.kind
  union all
  select 'task_duplicate', 'admin_jobs:' || d.kind || ':' || d.k, d.c, jsonb_build_object('tasks', to_jsonb(d.ids)) from dup d
  union all
  select 'retry_cost_excess', 'admin_jobs:' || c.job_id, c.c, jsonb_build_object('usd', c.usd, 'items_read_again', c.c) from cost c
  union all
  select 'answer_not_persisted', 'enrich_ai_answers', (select count(*) from ans),
         (select jsonb_build_object('items', count(*), 'oldest', min(received_at), 'sample', (select jsonb_agg(item_id) from (select item_id from ans limit 5) s)) from ans)
   where exists (select 1 from ans)
  union all
  select 'step_input_pending', 'enrich_plan_runs:' || x.id, 1, jsonb_build_object('provider_id', x.provider_id, 'step', e->>'step', 'deferred', e->'deferred')
    from pipeline.enrich_plan_runs x cross join lateral jsonb_array_elements(x.steps) e
   where x.state in ('queued', 'running') and e->>'status' = 'waiting' and e ? 'deferred'
$$;

-- 8. remedies (action: (issue) -> {ok, changed, evidence}; verify: (issue) -> {passed, measure, evidence}); p_issue null when the
--    scheduled job acts on its own. Each that changes work does nothing while its switch is 0. --------------------------------------------
create or replace function security.ops_d_detect_count_v1(p_root text) returns bigint
language sql stable security definer set search_path = '' as $$
  select coalesce(sum(d.n), 0)::bigint from security.ops_lifecycle_detect_v1() d where d.root_cause = p_root
$$;

create or replace function security.ops_d_run_note_v1(p_issue bigint, p_remedy text, p_before bigint, p_after bigint, p_changed int, p_evidence jsonb) returns void
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops D: one remedy execution in workstream A's pipeline.ops_remedy_runs (only when something was tried with its switch on)
begin
  insert into pipeline.ops_remedy_runs(issue_id, remedy_code, started_at, finished_at, before, after, result, evidence)
  values (p_issue, p_remedy, now(), clock_timestamp(), jsonb_build_object('open', p_before), jsonb_build_object('open', p_after),
          case when p_changed > 0 then 'changed' else 'no_change' end, coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('changed', p_changed));
exception when others then
  raise notice 'remedy run not recorded: %', sqlerrm;
end $$;

create or replace function security.ops_outcome_reconcile_issue_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb;
begin
  v := security.ops_outcome_reconcile_v1();
  return jsonb_build_object('ok', true, 'changed', coalesce((v->>'tasks')::int, 0) + coalesce((v->>'plans')::int, 0), 'evidence', v);
end $$;
create or replace function security.ops_outcome_reconcile_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('passed', t + p = 0, 'measure', jsonb_build_object('tasks_without_outcome', t, 'plans_without_outcome', p), 'evidence', 'ended tasks and plans without an explicit outcome')
    from (select (select count(*) from pipeline.admin_jobs j where j.state in ('done', 'failed', 'cancelled') and j.outcome is null) t,
                 (select count(*) from pipeline.enrich_plan_runs x where x.state in ('done', 'failed', 'cancelled') and x.outcome is null) p) z
$$;

create or replace function security.ops_lease_orphan_close_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops D: orphaned field items (lease run out at the attempt cap, or waiting for the reader at the cap: never picked again) are closed
-- as failed with the reason, so their task can finish and the gap is classified (ops.lease_orphan_close_on)
declare v_b bigint; v_c int := 0;
begin
  if security.pipeline_num_v1('ops.lease_orphan_close_on', 0) < 1 then return jsonb_build_object('ok', true, 'changed', 0, 'evidence', 'switched off (ops.lease_orphan_close_on)'); end if;
  v_b := security.ops_d_detect_count_v1('lease_orphaned');
  with t as (select e.id from pipeline.field_enrich_items e
              where e.attempts >= security.pipeline_num_v1('ops.lease_attempts_max', 3)::int
                and ((e.state = 'leased' and e.leased_until < now() - make_interval(mins => security.pipeline_num_v1('ops.lease_grace_minutes', 30)::int)) or e.state = 'ai')
              order by e.id limit greatest(1, security.pipeline_num_v1('ops.heal_batch', 200)::int) for update skip locked)
  update pipeline.field_enrich_items e set state = 'failed', leased_until = null, updated_at = now(),
         reason = left(coalesce(e.reason || '; ', '') || 'orphaned at the attempt cap (lease ran out); closed by ops-job-lifecycle', 300)
    from t where e.id = t.id;
  get diagnostics v_c = row_count;
  if v_c > 0 then perform security.ops_d_run_note_v1(p_issue, 'lease_orphan_close', v_b, v_b - v_c, v_c, null); end if;
  return jsonb_build_object('ok', true, 'changed', v_c, 'evidence', jsonb_build_object('orphaned_before', v_b));
end $$;
create or replace function security.ops_lease_orphan_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('passed', n = 0, 'measure', jsonb_build_object('orphaned', n), 'evidence', 'field items at the attempt cap still leased or waiting')
    from (select security.ops_d_detect_count_v1('lease_orphaned') n) z
$$;

create or replace function security.ops_lane_orphan_release_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops D: a queued course search keeping a task's precedence (requested_at) after its task ended is searched in its normal turn, as
-- when a person cancels a task (ops.lane_orphan_release_on); nothing is removed from the queue
declare v_b bigint; v_c int := 0;
begin
  if security.pipeline_num_v1('ops.lane_orphan_release_on', 0) < 1 then return jsonb_build_object('ok', true, 'changed', 0, 'evidence', 'switched off (ops.lane_orphan_release_on)'); end if;
  v_b := security.ops_d_detect_count_v1('lane_work_orphaned');
  with t as (select s.course_id from pipeline.course_link_search s
              where s.state = 'queued' and s.requested_at is not null
                and not exists (select 1 from pipeline.admin_jobs j where j.kind = 'course_page_find' and j.state in ('queued', 'running', 'paused') and j.args->'course_ids' ? s.course_id::text)
              order by s.requested_at limit greatest(1, security.pipeline_num_v1('ops.heal_batch', 200)::int) for update skip locked)
  update pipeline.course_link_search s set requested_at = null from t where s.course_id = t.course_id;
  get diagnostics v_c = row_count;
  if v_c > 0 then perform security.ops_d_run_note_v1(p_issue, 'lane_orphan_release', v_b, v_b - v_c, v_c, null); end if;
  return jsonb_build_object('ok', true, 'changed', v_c, 'evidence', jsonb_build_object('orphaned_before', v_b));
end $$;
create or replace function security.ops_lane_orphan_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('passed', n = 0, 'measure', jsonb_build_object('orphaned', n), 'evidence', 'queued course searches with task precedence and no open task')
    from (select security.ops_d_detect_count_v1('lane_work_orphaned') n) z
$$;

create or replace function security.ops_task_dedupe_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops D: of two open tasks of the same kind for the same provider or scope, the newer one an enrichment plan started is asked to stop
-- at its next boundary (the runner cancels it and its outcome is recorded at close); a person's task is never stopped (ops.task_dedupe_on)
declare v_b bigint; v_c int := 0; r record;
begin
  if security.pipeline_num_v1('ops.task_dedupe_on', 0) < 1 then return jsonb_build_object('ok', true, 'changed', 0, 'evidence', 'switched off (ops.task_dedupe_on)'); end if;
  v_b := security.ops_d_detect_count_v1('task_duplicate');
  for r in select j.id, d.first from (select x.kind, coalesce(x.args->>'provider_id', x.scope) k, (array_agg(x.id order by x.created_at))[1] first
                                        from pipeline.admin_jobs x where x.state in ('queued', 'running', 'paused') and coalesce(x.args->>'provider_id', x.scope) is not null
                                       group by 1, 2 having count(*) > 1) d
             join pipeline.admin_jobs j on j.kind = d.kind and coalesce(j.args->>'provider_id', j.scope) = d.k and j.id <> d.first
            where j.state in ('queued', 'running', 'paused') and j.args ? 'plan_run' and not j.cancel_requested
            limit greatest(1, security.pipeline_num_v1('ops.heal_batch', 200)::int) loop
    update pipeline.admin_jobs set cancel_requested = true, updated_at = now() where id = r.id;
    insert into pipeline.admin_job_events(job_id, note, detail) values (r.id, 'asked to stop: the same work is already open in task ' || left(r.first::text, 8), jsonb_build_object('duplicate_of', r.first));
    v_c := v_c + 1;
  end loop;
  if v_c > 0 then perform security.ops_d_run_note_v1(p_issue, 'task_duplicate_stop', v_b, v_b - v_c, v_c, null); end if;
  return jsonb_build_object('ok', true, 'changed', v_c, 'evidence', jsonb_build_object('duplicates_before', v_b));
end $$;
create or replace function security.ops_task_dedupe_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('passed', n = 0, 'measure', jsonb_build_object('duplicate_groups', n), 'evidence', 'open tasks of the same kind for the same provider or scope')
    from (select count(*) n from security.ops_lifecycle_detect_v1() d where d.root_cause = 'task_duplicate') z
$$;

create or replace function security.ops_retry_cost_pause_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops D: an open task whose items read more than once cost more than ops.retry_cost_max_usd in the window is asked to pause, with the
-- reason; a person resumes it (ops.retry_cost_pause_on)
declare v_c int := 0; r record;
begin
  if security.pipeline_num_v1('ops.retry_cost_pause_on', 0) < 1 then return jsonb_build_object('ok', true, 'changed', 0, 'evidence', 'switched off (ops.retry_cost_pause_on)'); end if;
  for r in select split_part(d.correlation_key, ':', 2)::uuid id, d.evidence from security.ops_lifecycle_detect_v1() d where d.root_cause = 'retry_cost_excess'
            limit greatest(1, security.pipeline_num_v1('ops.heal_batch', 200)::int) loop
    update pipeline.admin_jobs set pause_requested = true, updated_at = now() where id = r.id and state in ('queued', 'running') and not pause_requested;
    if found then
      insert into pipeline.admin_job_events(job_id, note, detail) values (r.id, 'asked to pause: items read again cost US$' || (r.evidence->>'usd') || ' (over ops.retry_cost_max_usd)', r.evidence);
      v_c := v_c + 1;
    end if;
  end loop;
  if v_c > 0 then perform security.ops_d_run_note_v1(p_issue, 'retry_cost_pause', null, null, v_c, null); end if;
  return jsonb_build_object('ok', true, 'changed', v_c, 'evidence', null);
end $$;
create or replace function security.ops_retry_cost_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('passed', n = 0, 'measure', jsonb_build_object('tasks_over', n), 'evidence', 'open tasks over the paid retry cost')
    from (select count(*) n from security.ops_lifecycle_detect_v1() d join pipeline.admin_jobs j on j.id = split_part(d.correlation_key, ':', 2)::uuid
           where d.root_cause = 'retry_cost_excess' and not j.pause_requested) z
$$;

create or replace function security.ops_answer_replay_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops D (acceptance mandate 15:52 §9): a kept AI answer whose item is still unsettled after ops.answer_settle_minutes, on the same
-- attempt and the same evidence, was paid for but not recorded. Only the recording is retried, from the kept answer, through
-- public.svc_enrich_ai_record (the same rules), never the AI call; then the item's final state is checked: replayed (settled), or still
-- unsettled (the error kept; tried again up to ops.heal_max_attempts, then failed). Bookkeeping (always, it only records): an answer whose item settled is recorded; one whose item was
-- leased again or whose evidence changed is superseded (the new read is the one that counts). ops.answer_replay_on ships 0.
declare v_on boolean := security.pipeline_num_v1('ops.answer_replay_on', 0) >= 1; v_res jsonb; v_ids bigint[]; v_c int := 0; v_f int := 0; v_err text;
        v_settle interval := make_interval(mins => security.pipeline_num_v1('ops.answer_settle_minutes', 2)::int);
begin
  update pipeline.enrich_ai_answers a set state = 'recorded', settled_at = now()
    from pipeline.field_enrich_items e where e.id = a.item_id and a.state = 'received' and e.state not in ('ai', 'leased', 'queued', 'waiting');
  update pipeline.enrich_ai_answers a set state = 'superseded', settled_at = now(),
         detail = a.detail || jsonb_build_object('why', case when e.attempts <> a.attempts then 'leased again' else 'evidence changed' end)
    from pipeline.field_enrich_items e where e.id = a.item_id and a.state = 'received' and (e.attempts <> a.attempts or e.evidence_id is distinct from a.evidence_id);
  if not v_on then return jsonb_build_object('ok', true, 'changed', 0, 'evidence', 'switched off (ops.answer_replay_on)'); end if;
  select coalesce(jsonb_agg(a.answer), '[]'::jsonb), array_agg(a.item_id) into v_res, v_ids
    from (select a.answer, a.item_id from pipeline.enrich_ai_answers a join pipeline.field_enrich_items e on e.id = a.item_id
           where a.state = 'received' and a.received_at < now() - v_settle and e.state in ('ai', 'leased')
             and e.attempts = a.attempts and e.evidence_id is not distinct from a.evidence_id
           order by a.received_at limit greatest(1, security.pipeline_num_v1('ops.answer_replay_batch', 20)::int)
           for update of a skip locked) a;
  if jsonb_array_length(v_res) = 0 then return jsonb_build_object('ok', true, 'changed', 0, 'evidence', 'nothing unrecorded'); end if;
  begin
    perform public.svc_enrich_ai_record(v_res);
  exception when others then v_err := left(sqlerrm, 300);
  end;
  -- the final state, item by item
  -- (still unsettled: the recording is tried again next run, up to ops.heal_max_attempts, then failed and left to the reader)
  update pipeline.enrich_ai_answers a set state = case when e.state not in ('ai', 'leased') then 'replayed'
                                                       when coalesce((a.detail->>'tries')::int, 0) + 1 >= security.pipeline_num_v1('ops.heal_max_attempts', 3) then 'failed' else 'received' end,
         settled_at = case when e.state not in ('ai', 'leased') or coalesce((a.detail->>'tries')::int, 0) + 1 >= security.pipeline_num_v1('ops.heal_max_attempts', 3) then now() end,
         detail = a.detail || jsonb_build_object('replayed_at', now(), 'item_state', e.state, 'tries', coalesce((a.detail->>'tries')::int, 0) + 1)
                  || case when v_err is not null then jsonb_build_object('error', v_err) else '{}'::jsonb end
    from pipeline.field_enrich_items e where e.id = a.item_id and a.item_id = any (v_ids) and a.state = 'received';
  select count(*) filter (where a.state = 'replayed'), count(*) filter (where a.state <> 'replayed') into v_c, v_f
    from pipeline.enrich_ai_answers a where a.item_id = any (v_ids) and (a.detail->>'replayed_at')::timestamptz = now();
  perform security.ops_d_run_note_v1(p_issue, 'answer_replay', cardinality(v_ids), v_f, v_c, jsonb_build_object('failed', v_f, 'error', v_err));
  return jsonb_build_object('ok', v_f = 0, 'changed', v_c, 'evidence', jsonb_build_object('replayed', v_c, 'still_unsettled', v_f, 'error', v_err));
end $$;
create or replace function security.ops_answer_replay_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('passed', n = 0, 'measure', jsonb_build_object('answers_unrecorded', n), 'evidence', 'kept AI answers whose items are still unsettled')
    from (select security.ops_d_detect_count_v1('answer_not_persisted') n) z
$$;

create or replace function security.ops_job_interrupted_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('passed', n = 0, 'measure', jsonb_build_object('tasks_untouched', n), 'evidence', 'open tasks the task runner has not touched for ops.interrupted_minutes')
    from (select security.ops_d_detect_count_v1('job_interrupted') n) z
$$;

-- 9. the scheduled job ------------------------------------------------------------------------------------------------------------------------
create or replace function security.ops_job_lifecycle_v1() returns jsonb
language plpgsql security definer set search_path = '' as $$
-- CF-247 ops D (job ops-job-lifecycle): reconcile outcomes, then each self-healing remedy whose switch is on, each bounded by its batch
declare v jsonb := '{}'::jsonb;
begin
  v := v || jsonb_build_object('outcomes', security.ops_outcome_reconcile_v1());
  v := v || jsonb_build_object('lease_orphan_close', security.ops_lease_orphan_close_v1(null)->'changed');
  v := v || jsonb_build_object('lane_orphan_release', security.ops_lane_orphan_release_v1(null)->'changed');
  v := v || jsonb_build_object('task_dedupe', security.ops_task_dedupe_v1(null)->'changed');
  v := v || jsonb_build_object('retry_cost_pause', security.ops_retry_cost_pause_v1(null)->'changed');
  v := v || jsonb_build_object('answer_replay', security.ops_answer_replay_v1(null)->'changed');
  return v;
end $$;

revoke all on function security.ops_hold_outcome_v1(text), security.ops_error_retryable_v1(text), security.job_movement_v1(uuid), security.job_outcome_compute_v1(uuid),
  security.job_outcome_record_v1(uuid, text), security.plan_outcome_compute_v1(uuid, boolean), security.plan_outcome_record_v1(uuid, text), security.ops_outcome_reconcile_v1(),
  security.plan_step_dependency_v1(uuid, jsonb), security.plan_empty_cycles_v1(uuid, numeric), security.enrich_plan_auto_note_v1(jsonb, int),
  security.ops_lifecycle_detect_v1(), security.ops_d_detect_count_v1(text), security.ops_d_run_note_v1(bigint, text, bigint, bigint, int, jsonb),
  security.ops_outcome_reconcile_issue_v1(bigint), security.ops_outcome_reconcile_verify_v1(bigint), security.ops_lease_orphan_close_v1(bigint), security.ops_lease_orphan_verify_v1(bigint),
  security.ops_lane_orphan_release_v1(bigint), security.ops_lane_orphan_verify_v1(bigint), security.ops_task_dedupe_v1(bigint), security.ops_task_dedupe_verify_v1(bigint),
  security.ops_retry_cost_pause_v1(bigint), security.ops_retry_cost_verify_v1(bigint), security.ops_answer_replay_v1(bigint), security.ops_answer_replay_verify_v1(bigint),
  security.ops_job_interrupted_verify_v1(bigint), security.ops_job_lifecycle_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('ops-job-lifecycle', 'Platform upkeep', 96, 'Task and plan outcomes, and self-healing',
  'Every 2 minutes: past tasks and enrichment plans without an explicit outcome get their reconciled outcome (ops.outcome_reconcile_batch each, newest first; only the outcome columns), and each self-healing remedy whose switch is on runs within ops.heal_batch: orphaned field items closed (ops.lease_orphan_close_on), task precedence left by ended tasks released (ops.lane_orphan_release_on), duplicate plan tasks stopped (ops.task_dedupe_on), tasks with excessive paid retries paused (ops.retry_cost_pause_on), paid AI answers whose record failed recorded again from the kept copy (ops.answer_replay_on). Detection: security.ops_lifecycle_detect_v1. Root causes and remedies: pipeline.ops_root_causes, pipeline.ops_remedies.',
  4, false, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'ops-job-lifecycle') then
    perform cron.schedule('ops-job-lifecycle', '*/2 * * * *', $c$select security.ops_job_lifecycle_v1()$c$);
  end if;
end $j$;
update pipeline.automation_catalogue set description = description || ' Every run is recorded with why it created what it did (pipeline.enrich_plan_auto_runs); a step that can run again is re-planned once its own wait has passed (plans.retry_ignores_min_days).'
 where jobname = 'enrich-plan-auto' and description not like '%enrich_plan_auto_runs%';

-- 10. root causes and remedies (workstream A's contract) -------------------------------------------------------------------------------------
select security.ops_root_cause_register_v1(c, s) from (values
 ('false_completion', jsonb_build_object('class', 'rule', 'title', 'A task or plan counted as done without moving data',
   'description', 'Done was read as success: a plan whose steps moved nothing (the 17 plans of 3 Nov 12:41) was reported as moved. Every task and plan now records an explicit outcome from real data movement; past ones are reconciled.',
   'detect', jsonb_build_object('fn', 'security.ops_outcome_reconcile_verify_v1(bigint)', 'measure', 'tasks_without_outcome, plans_without_outcome'))),
 ('lease_orphaned', jsonb_build_object('class', 'transient', 'title', 'Field items leased or waiting at the attempt cap',
   'description', 'A field item whose lease ran out at the AI reader''s attempt cap (or that waits for the reader at the cap) is never picked again and never settles.',
   'detect', jsonb_build_object('fn', 'security.ops_lifecycle_detect_v1()', 'root_cause', 'lease_orphaned'))),
 ('lane_work_orphaned', jsonb_build_object('class', 'dependency', 'title', 'Queued searches holding the precedence of an ended task',
   'description', 'Course searches queued by a Find course pages task keep its precedence (requested_at) after the task ended, ahead of live tasks under the day cap.',
   'detect', jsonb_build_object('fn', 'security.ops_lifecycle_detect_v1()', 'root_cause', 'lane_work_orphaned'))),
 ('job_interrupted', jsonb_build_object('class', 'transient', 'title', 'Open task not touched by the task runner',
   'description', 'A queued or running task the runner (job admin-jobs) has not touched for ops.interrupted_minutes: the runner is failing or the task is locked.',
   'detect', jsonb_build_object('fn', 'security.ops_lifecycle_detect_v1()', 'root_cause', 'job_interrupted'))),
 ('task_duplicate', jsonb_build_object('class', 'rule', 'title', 'Two open tasks of the same kind for the same provider',
   'description', 'The same work open twice (open plans are already one per provider by index enrich_plan_runs_one_open; tasks are not).',
   'detect', jsonb_build_object('fn', 'security.ops_lifecycle_detect_v1()', 'root_cause', 'task_duplicate'))),
 ('plan_repeated_empty', jsonb_build_object('class', 'rule', 'title', 'Repeated plans that move no data',
   'description', 'The automatic planner proposing a university again while its last plans moved nothing and nothing changed.',
   'detect', jsonb_build_object('fn', 'security.plan_empty_cycles_v1(uuid,numeric)', 'per', 'provider'))),
 ('retry_cost_excess', jsonb_build_object('class', 'capacity', 'title', 'Excessive paid retries in a task',
   'description', 'An open task whose field items were read (paid) more than once cost more than ops.retry_cost_max_usd in ops.retry_cost_window_hours.',
   'detect', jsonb_build_object('fn', 'security.ops_lifecycle_detect_v1()', 'root_cause', 'retry_cost_excess'))),
 ('answer_not_persisted', jsonb_build_object('class', 'transient', 'title', 'AI answer paid for but not recorded',
   'description', 'svc_enrich_ai_record failed (statement time-out) after the AI answered; the worker kept the answers only in memory, so the items were read and paid again when their lease ran out.',
   'detect', jsonb_build_object('fn', 'security.ops_lifecycle_detect_v1()', 'root_cause', 'answer_not_persisted'))),
 ('step_input_pending', jsonb_build_object('class', 'dependency', 'title', 'A plan step whose input another step or lane is still producing',
   'description', 'Find course pages while the provider''s searches are still queued (IQ-00064: a new task would queue and pay for them again); Fill missing fields while the plan''s Find course pages step is unfinished.',
   'detect', jsonb_build_object('fn', 'security.ops_lifecycle_detect_v1()', 'root_cause', 'step_input_pending')))
) v(c, s);

select security.ops_remedy_register_v1(c, s) from (values
 ('outcome_reconcile', jsonb_build_object('title', 'Record and reconcile explicit outcomes', 'treats', jsonb_build_array('false_completion'), 'authority', 'auto',
   'action_fn', 'security.ops_outcome_reconcile_issue_v1(bigint)', 'verify_fn', 'security.ops_outcome_reconcile_verify_v1(bigint)',
   'max_attempts_key', 'ops.heal_max_attempts', 'cooldown_key', 'ops.heal_cooldown_minutes', 'notes', 'Also at every close (security.admin_job_close_v1, security.enrich_plan_tick_v1). ops.outcome_on (on).')),
 ('lease_orphan_close', jsonb_build_object('title', 'Close orphaned field items as failed', 'treats', jsonb_build_array('lease_orphaned'), 'authority', 'auto',
   'action_fn', 'security.ops_lease_orphan_close_v1(bigint)', 'verify_fn', 'security.ops_lease_orphan_verify_v1(bigint)',
   'max_attempts_key', 'ops.heal_max_attempts', 'cooldown_key', 'ops.heal_cooldown_minutes', 'notes', 'ops.lease_orphan_close_on (ships off).')),
 ('lane_orphan_release', jsonb_build_object('title', 'Release the precedence left by ended tasks', 'treats', jsonb_build_array('lane_work_orphaned'), 'authority', 'auto',
   'action_fn', 'security.ops_lane_orphan_release_v1(bigint)', 'verify_fn', 'security.ops_lane_orphan_verify_v1(bigint)',
   'max_attempts_key', 'ops.heal_max_attempts', 'cooldown_key', 'ops.heal_cooldown_minutes', 'notes', 'ops.lane_orphan_release_on (ships off). Nothing leaves the queue.')),
 ('task_duplicate_stop', jsonb_build_object('title', 'Stop the newer duplicate plan task', 'treats', jsonb_build_array('task_duplicate'), 'authority', 'auto',
   'action_fn', 'security.ops_task_dedupe_v1(bigint)', 'verify_fn', 'security.ops_task_dedupe_verify_v1(bigint)',
   'max_attempts_key', 'ops.heal_max_attempts', 'cooldown_key', 'ops.heal_cooldown_minutes', 'notes', 'ops.task_dedupe_on (ships off). A person''s task is never stopped.')),
 ('retry_cost_pause', jsonb_build_object('title', 'Pause a task with excessive paid retries', 'treats', jsonb_build_array('retry_cost_excess'), 'authority', 'auto',
   'action_fn', 'security.ops_retry_cost_pause_v1(bigint)', 'verify_fn', 'security.ops_retry_cost_verify_v1(bigint)',
   'max_attempts_key', 'ops.heal_max_attempts', 'cooldown_key', 'ops.heal_cooldown_minutes', 'notes', 'ops.retry_cost_pause_on (ships off). A person resumes the task.')),
 ('answer_replay', jsonb_build_object('title', 'Record a paid AI answer again from the kept copy', 'treats', jsonb_build_array('answer_not_persisted'), 'authority', 'auto',
   'action_fn', 'security.ops_answer_replay_v1(bigint)', 'verify_fn', 'security.ops_answer_replay_verify_v1(bigint)',
   'max_attempts_key', 'ops.heal_max_attempts', 'cooldown_key', 'ops.heal_cooldown_minutes', 'notes', 'ops.answer_replay_on (ships off). Needs the worker to call public.svc_enrich_ai_stash_v1 first (workstream B).')),
 ('job_interrupted_check', jsonb_build_object('title', 'Check the task runner', 'treats', jsonb_build_array('job_interrupted'), 'authority', 'admin',
   'verify_fn', 'security.ops_job_interrupted_verify_v1(bigint)', 'notes', 'The runner (job admin-jobs) carries an untouched task on by itself once it runs; a failing runner needs a person.')),
 ('empty_cycle_hold', jsonb_build_object('title', 'Do not propose a university after repeated empty cycles', 'treats', jsonb_build_array('plan_repeated_empty'), 'authority', 'auto',
   'notes', 'Built into security.enrich_plan_v1 (security.plan_empty_cycles_v1); plans.empty_cycles_max (3, on).')),
 ('step_input_wait', jsonb_build_object('title', 'Wait for the step or lane producing the input', 'treats', jsonb_build_array('step_input_pending'), 'authority', 'auto',
   'notes', 'Built into security.enrich_plan_tick_v1 (security.plan_step_dependency_v1); plans.lane_backlog_wait_on (on), plans.step_dependency_on (off).'))
) v(c, s);

-- 11. component register ---------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.enrich_plan_auto_runs', 'Platform', 'Platform upkeep', 'One row per automatic planner run, with why it created what it did', 'active', '{}', '20261104020000'),
 ('table', 'pipeline.enrich_ai_answers', 'Layer 2', 'Platform upkeep', 'AI answers kept before recording, replayed when a record fails', 'active', '{}', '20261104020000'),
 ('job', 'ops-job-lifecycle', 'Platform', 'Platform upkeep', 'Task and plan outcomes (reconciled) and self-healing remedies', 'active', '{}', '20261104020000')
on conflict do nothing;

-- 12. post-check ------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select command from cron.job where jobname = 'ops-job-lifecycle') <> 'select security.ops_job_lifecycle_v1()' then
    raise exception 'ops D post-check: job ops-job-lifecycle runs another command'; end if;
  if exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline'
              and key in ('ops.lease_orphan_close_on', 'ops.lane_orphan_release_on', 'ops.task_dedupe_on', 'ops.retry_cost_pause_on', 'ops.answer_replay_on', 'plans.step_dependency_on')
              and (value #>> '{}')::numeric <> 0) then
    raise exception 'ops D post-check: a remedy that changes, removes or admits work must ship off'; end if;
  if (select count(*) from pipeline.ops_remedies where code in ('outcome_reconcile', 'lease_orphan_close', 'lane_orphan_release', 'task_duplicate_stop', 'retry_cost_pause',
                                                                'answer_replay', 'job_interrupted_check', 'empty_cycle_hold', 'step_input_wait')) <> 9 then
    raise exception 'ops D post-check: the nine remedies are not registered'; end if;
end $$;
