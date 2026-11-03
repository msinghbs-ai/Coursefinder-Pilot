-- CF-247 first-run operational verification, producer-to-consumer progress and recovery-loop repair (Platform Admin mandate 4 Nov 2026 08:16 AEDT,
-- admin docs/platform/2026-11-04-p0-autonomous-operations-acceptance-mandate-0816.md §3, §4, §5, §10; audit
-- docs/platform/2026-11-04-first-run-failure-audit.md). Lands after the human-assisted recovery release (20261104450000, ops_report_v1 3ba694dc).
--
-- Why (live, read-only, 4 Nov 2026 08:19-08:31 AEDT; the audit has every run id):
--   F1 A release was "verified" on its migration and function md5s (security.integration_deploy_check_v1, V3) and nothing then watched its scheduled
--      jobs' first runs: v2.15.443 course-relink, v2.15.447 rule executor, v2.15.460 scholarship-coverage-classify each failed on the first production
--      call after a green suite and a green V3 check. Nothing records "deployed but operationally unverified".
--   F2 Jobs reported success while their transition did not advance: AER scheduled reading succeeded every hour with 0 admissions (daily cap 200 at
--      03:13, 605 waiting against the 600 limit); course page discovery is paused, so 1,438 AER gap findings are no_source with no source attempt.
--      No record says which transitions moved, which stalled, and why a zero-output run was zero.
--   F3 The controller could not route a new job's first failure: its release-regression rule needs a success before the failure streak, so a job
--      that never succeeded is "unclassified" and goes to needs_decision (IQ-00239, job_failed:scholarship-coverage-classify, "no automatic remedy
--      for unclassified"). The hand-raised IQ-00241 for the same fault got a weak key (jobtext:scholarship-coverage-classify), and weak keys are
--      never superseded, so the two were never linked. Neither has an assignee; none of the open code-defect issues has an owner or a checkpoint.
-- What:
--   1 First-run verification (§3), extending the V3 release contract: pipeline.release_job_verifications (one row per release and changed scheduled
--     job: expected first run from the job's own schedule, observed run and its result, expected and actual output, downstream eligibility, status
--     awaiting_first_run / operationally_verified / failed_first_run) and two columns on pipeline.integration_deploy_checks (operational_status,
--     operational_checked_at), so a release is "deployed, operationally unverified" until its jobs' first runs prove it.
--     security.release_first_run_register_v1 is called by the release controller with security.integration_deploy_check_v1 (it registers every
--     job whose command calls a function the release changed, plus those named). A failed first run raises or updates the job's own issue
--     (fingerprint job_failed:<job>, the controller's key) with the run id and error text.
--   2 Progress contract (§4): pipeline.progress_transitions (one shared record per transition of the scholarship and AER chains) kept by a bounded
--     reader, security.progress_measure_v1 (each transition counted over progress.window_hours from existing tables; nothing is written by the
--     producers in this step). Every zero-output transition carries a reason class (no_eligible_work, cap_reached, blocked_authority,
--     correctly_excluded, technical_failure); a transition with eligible input and no advancement for progress.stall_hours is stalled even when its
--     job succeeds, and is raised by fingerprint stall:<transition>. History in pipeline.progress_observations.
--   3 Recovery loop (§5): security.recovery_link_duplicates_v1 links an open issue that names a job and carries the same error signature as that
--     job's own job_failed: issue (one canonical issue: the furthest along its lifecycle, then the most severe, then the oldest; the other
--     superseded into it the way the controller supersedes, with its evidence carried over and a supersede_into_owner run so the controller closes
--     it with its owner); security.recovery_route_engineering_v1 makes a code or SQL defect (error classes in pipeline.recovery_error_classes) owned
--     engineering work: assignee engineering, root cause class, remediation status, the error text and run id, and a bounded next checkpoint
--     (recovery.engineering_checkpoint_hours). A failed first run after a fix returns the issue to in_progress with the new evidence. Root cause
--     first_run_sql_defect and remedy engineering_remediation (authority release) are registered through workstream A's contract, so the controller
--     routes these to needs_release, not needs_decision.
--   4 Job first-run-verify (:02 and :32, catalogued): moves first-run statuses, reads progress, links and routes. Settings frv.*, progress.*,
--     recovery.* (Settings › Pipeline settings, "First-run verification and progress").
--   5 Scorecard (§10): security.self_sustainability_v1 (read only), a self_sustainability section of security.ops_report_v1 (md5-guarded edit on the
--     human-assisted recovery definition 3ba694dc).
-- Activation: ON (records only): frv.on, progress.on, recovery.link_on, recovery.route_on. OFF: recovery.close_on_verified_on (closing an issue on
--   operational verification stays with the controller and the Integration Controller until switched on). Nothing here merges, grants a budget,
--   decides a Layer 4 item, overrides a lock, admits, publishes, changes another setting or destroys anything.
-- md5 (before = live / the human-assisted recovery release; after = local replay on PostgreSQL 16, tests/fixtures/first-run-verification/run.sh):
--   security.ops_report_v1(integer)           3ba694dc078995d88a983e8e92b2f425 -> 518b5bf873549931a15d4173fef793d5
-- Called, not edited (live md5 4 Nov 2026 08:19): security.integration_issue_upsert_v1(jsonb,text) b0a1a64982680ae5d588c2d73b779e4e,
--   security.integration_issue_transition_v1(bigint,text,text,text,jsonb) 3e8fc63663e5120c50f0859da97dd7a8,
--   security.integration_issue_close_v1(bigint,text,jsonb) 4cae8eaee7444e0aa942b2702eb10bc6,
--   security.integration_deploy_check_v1(text,jsonb,jsonb,timestamp with time zone,text[]) 889ae2b374e1b930cf87f65549f0cc5e (not edited; extended beside).
-- Replaces: security.ops_report_v1 (same name; md5-guarded edit: one report section)
-- Retires: nothing
-- Nothing is dropped or deleted. Consumer API untouched (G3): api.* and scholarship.scholarships are only read; no consumer function, table, column or
-- edge function changes. No Firecrawl or AI spend.

do $guard$
begin
  if to_regclass('pipeline.integration_issues') is null or to_regclass('pipeline.integration_deploy_checks') is null then
    raise exception 'first-run verification needs the integration queue (20261102120000) first';
  end if;
  if to_regprocedure('security.ops_remedy_register_v1(text,jsonb)') is null or to_regclass('pipeline.ops_remedy_runs') is null then
    raise exception 'first-run verification needs workstream A''s shared contract (20261104010000) first';
  end if;
  if to_regclass('pipeline.work_items') is null then raise exception 'first-run verification needs the work-continuity contract (20261104170000) first'; end if;
  if to_regclass('pipeline.scholarship_coverage_items') is null then raise exception 'first-run verification needs scholarship coverage (20261104390000) first'; end if;
end $guard$;

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

-- 0. the queue functions this change calls are the ones it was written against (not edited here) --------------------------------------------------
do $g$
declare v record;
begin
  for v in select * from (values ('security.integration_issue_upsert_v1(jsonb,text)', 'b0a1a64982680ae5d588c2d73b779e4e'),
                                 ('security.integration_issue_transition_v1(bigint,text,text,text,jsonb)', '3e8fc63663e5120c50f0859da97dd7a8')) x(sig, m) loop
    if md5(pg_get_functiondef(v.sig::regprocedure)) <> v.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', v.sig, md5(pg_get_functiondef(v.sig::regprocedure));
    end if;
  end loop;
end $g$;

-- 1. settings (G2) ---------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'frv.on', 'First-run verification: watch each release''s scheduled jobs',
  '1: every half hour each released scheduled job is followed to its first production run, its output is counted against what was expected and its downstream work is checked; the release stays "deployed, operationally unverified" until that passes, and a failed first run raises the job''s own issue. Reads and records only. 0: off.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1500, 'Mandate 4 Nov 2026 08:16 §3: ships on (records only)', 'First-run verification and progress',
  'security.first_run_verify_tick_v1 (job first-run-verify); security.release_first_run_register_v1'),
 ('pipeline', 'frv.next_run_search_hours', 'First-run verification: look this far ahead for a job''s next scheduled run',
  'The expected first run is the job''s next scheduled time after the deployment, searched minute by minute in its schedule for at most this long.',
  'number', to_jsonb(48), 1, 168, 'hours', 1501, 'Mandate 4 Nov 2026 08:16 §3 "expected first run"', 'First-run verification and progress', 'security.cron_next_run_v1'),
 ('pipeline', 'frv.grace_minutes', 'First-run verification: a scheduled run is missing after',
  'When no run has started this long after the expected first run (a job left inactive, unscheduled or not firing), the first run is recorded as failed: did not run.',
  'number', to_jsonb(20), 5, 240, 'minutes', 1502, 'Mandate 4 Nov 2026 08:16 §2 "Was that switch actually activated? Did the first scheduled run complete?"', 'First-run verification and progress',
  'security.first_run_verify_tick_v1'),
 ('pipeline', 'frv.verify_deadline_hours', 'First-run verification: raise an issue when still unverified after',
  'A release job still awaiting operational verification this long after its deployment (output not measurable, downstream not eligible) is raised as an issue owned by engineering.',
  'number', to_jsonb(24), 1, 168, 'hours', 1503, 'Mandate 4 Nov 2026 08:16 §3 "deployed but operationally unverified"', 'First-run verification and progress', 'security.first_run_verify_tick_v1'),
 ('pipeline', 'frv.runs_scan', 'First-run verification: scheduler runs looked through per check',
  'Each check reads only scheduler runs newer than the last one it looked at, at most this many, so the read stays small (about 850 runs between two checks).',
  'number', to_jsonb(5000), 500, 50000, 'runs', 1504, 'Mandate 4 Nov 2026 08:16 §3; production validation load policy', 'First-run verification and progress', 'security.first_run_verify_tick_v1'),
 ('pipeline', 'frv.expected_min_output', 'First-run verification: output expected from a first run (default)',
  'A released job''s first run is expected to create at least this many output records on its transition, unless the release names another figure or the zero has a justified reason (no eligible work, a valid cap, blocked by authority, correctly excluded).',
  'number', to_jsonb(1), 0, 100000, 'records', 1505, 'Mandate 4 Nov 2026 08:16 §3 item 5 "expected-versus-actual output count"', 'First-run verification and progress',
  'security.release_first_run_register_v1'),
 ('pipeline', 'progress.on', 'Progress contract: read every pipeline transition',
  '1: every half hour each transition of the scholarship and AER chains is counted from the existing tables (input eligible, processed, output created, rejected with reason, parked with next action, downstream queued, admitted, published, last advancement); a zero gets a reason, and a transition with eligible input that has not advanced is raised as stalled. Reads and records only. 0: off.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1510, 'Mandate 4 Nov 2026 08:16 §4: ships on (records only)', 'First-run verification and progress', 'security.progress_read_v1'),
 ('pipeline', 'progress.window_hours', 'Progress contract: counting window',
  'Movement (processed, created, rejected, admitted, published) is counted over this many hours before each reading.',
  'number', to_jsonb(24), 1, 168, 'hours', 1511, 'Mandate 4 Nov 2026 08:16 §4', 'First-run verification and progress', 'security.progress_measure_v1'),
 ('pipeline', 'progress.stall_hours', 'Progress contract: a transition with eligible work is stalled after',
  'A transition that has eligible input but has not advanced (no output created) for this long is stalled, whatever its job reports, unless a valid cap, an authority block or a correct exclusion explains it.',
  'number', to_jsonb(6), 1, 168, 'hours', 1512, 'Mandate 4 Nov 2026 08:16 §4 "detect a stalled transition even when its scheduler reports success"', 'First-run verification and progress',
  'security.progress_read_v1'),
 ('pipeline', 'progress.keep_observations_days', 'Progress contract: readings kept for trends',
  'Readings older than this are not read by the scorecard (nothing is deleted).',
  'number', to_jsonb(30), 1, 365, 'days', 1513, 'Mandate 4 Nov 2026 08:16 §10 "baseline, change and verified outcome"', 'First-run verification and progress', 'security.self_sustainability_v1'),
 ('pipeline', 'recovery.link_on', 'Recovery loop: link issues that describe the same failure',
  '1: an open issue that names a failing job and carries that job''s own error is linked to the job''s issue: one canonical issue, the other superseded into it with its evidence and history kept, closed with its owner. Records only. 0: off.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1520, 'Mandate 4 Nov 2026 08:16 §5 (IQ-00239 and IQ-00241): ships on (records only)', 'First-run verification and progress',
  'security.recovery_link_duplicates_v1'),
 ('pipeline', 'recovery.route_on', 'Recovery loop: make code and SQL defects owned engineering work',
  '1: an open issue whose job fails with a code or SQL defect (pipeline.recovery_error_classes) gets assignee engineering, its root cause class, a remediation status, the error text and run id, and a bounded next checkpoint. Records only; never merges, deploys or changes a setting. 0: off.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1521, 'Mandate 4 Nov 2026 08:16 §5: ships on (records only)', 'First-run verification and progress', 'security.recovery_route_engineering_v1'),
 ('pipeline', 'recovery.engineering_checkpoint_hours', 'Recovery loop: next checkpoint of an engineering remediation',
  'An engineering remediation is checked again this long after it was routed or last moved; a checkpoint passed without a fix is recorded in the issue''s history and the next one set.',
  'number', to_jsonb(4), 1, 72, 'hours', 1522, 'Mandate 4 Nov 2026 08:16 §5 "bounded next checkpoint"', 'First-run verification and progress', 'security.recovery_route_engineering_v1'),
 ('pipeline', 'recovery.issues_per_run', 'Recovery loop: issues looked at per run',
  'Each run links and routes at most this many open issues (newest observations first).',
  'number', to_jsonb(200), 10, 2000, 'issues', 1523, 'Mandate 4 Nov 2026 08:16 §5', 'First-run verification and progress',
  'security.recovery_link_duplicates_v1; security.recovery_route_engineering_v1'),
 ('pipeline', 'recovery.close_on_verified_on', 'Recovery loop: close an engineering issue when its fix is operationally verified',
  '1: when a release''s job is operationally verified after its failed first run, its open issue is closed with that evidence. 0: the issue is marked verified and left for the controller or the Integration Controller to close.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1524, 'Mandate 4 Nov 2026 08:16 §1 "only close after production verification": ships off', 'First-run verification and progress',
  'security.first_run_verify_tick_v1')
on conflict (toolset_key, key) do nothing;

-- 2. tables and columns (beside the consumer API; nothing it reads changes) ---------------------------------------------------------------------------
create table if not exists pipeline.release_job_verifications (
  id bigserial primary key,
  release text not null,
  jobname text not null,
  jobid bigint,
  deploy_check_id bigint references pipeline.integration_deploy_checks(id),
  deployed_at timestamptz not null,
  registered_at timestamptz not null default now(),
  registered_by text not null,
  schedule text,
  active_at_deploy boolean,
  expected_first_run timestamptz,
  scan_from_runid bigint,
  first_runid bigint,
  first_run_at timestamptz,
  first_run_status text,
  first_run_message text,
  transition_key text,
  expected_min_output numeric,
  actual_output numeric,
  output_measure jsonb,
  downstream_eligible numeric,
  zero_reason text check (zero_reason is null or zero_reason in ('no_eligible_work', 'cap_reached', 'blocked_authority', 'correctly_excluded', 'technical_failure')),
  status text not null default 'awaiting_first_run' check (status in ('awaiting_first_run', 'operationally_verified', 'failed_first_run')),
  status_reason text,
  issue_id bigint references pipeline.integration_issues(id),
  evidence jsonb not null default '{}'::jsonb,
  checked_at timestamptz,
  verified_at timestamptz,
  unique (release, jobname));
comment on table pipeline.release_job_verifications is 'CF-247 (mandate 4 Nov 2026 08:16 §3): first-run operational verification, part of the V3 release contract (pipeline.integration_deploy_checks). One row per release and changed scheduled job: the expected first run from the job''s own schedule, the observed first run and its result, expected and actual output on the job''s transition (pipeline.progress_transitions), downstream eligibility, a zero-output reason, and the status awaiting_first_run, operationally_verified or failed_first_run. Registered by the release controller (security.release_first_run_register_v1); moved only by job first-run-verify. A failed first run raises or updates the job''s own issue (job_failed:<job>). Never read by the consumer API.';
create index if not exists release_job_verifications_open_idx on pipeline.release_job_verifications (status) where status = 'awaiting_first_run';
alter table pipeline.release_job_verifications enable row level security;
revoke all on pipeline.release_job_verifications from public, anon, authenticated;
revoke all on sequence pipeline.release_job_verifications_id_seq from public, anon, authenticated;

alter table pipeline.integration_deploy_checks add column if not exists operational_status text
  check (operational_status is null or operational_status in ('not_applicable', 'awaiting_first_run', 'operationally_verified', 'failed_first_run'));
alter table pipeline.integration_deploy_checks add column if not exists operational_checked_at timestamptz;
comment on column pipeline.integration_deploy_checks.operational_status is 'CF-247 (mandate 4 Nov 2026 08:16 §3): the release''s operational state from its jobs'' first runs (pipeline.release_job_verifications): awaiting_first_run (deployed, operationally unverified), operationally_verified, failed_first_run, or not_applicable (no scheduled job changed). A green deploy check alone is not operational success.';

alter table pipeline.integration_issues add column if not exists remediation_owner text;
alter table pipeline.integration_issues add column if not exists remediation_status text
  check (remediation_status is null or remediation_status in ('engineering_open', 'fix_released', 'awaiting_first_run', 'verified', 'returned'));
alter table pipeline.integration_issues add column if not exists remediation_checkpoint_at timestamptz;
alter table pipeline.integration_issues add column if not exists remediation_evidence jsonb;
comment on column pipeline.integration_issues.remediation_status is 'CF-247 (mandate 4 Nov 2026 08:16 §5): an engineering remediation''s state, set by job first-run-verify: engineering_open (a code or SQL defect, owned by remediation_owner, with its error text and run id in remediation_evidence), fix_released (a release registered a changed job for it), awaiting_first_run, verified (the fixed job''s first run was operationally verified) or returned (the fix''s first run failed; the issue went back to in_progress with the new evidence). remediation_checkpoint_at is the bounded next checkpoint.';

create table if not exists pipeline.recovery_error_classes (
  pattern text primary key,
  error_class text not null,
  root_cause_class text not null,
  owner text not null default 'engineering',
  title text not null,
  repeat_setting text,
  sort int not null default 100);
comment on table pipeline.recovery_error_classes is 'CF-247 (mandate 4 Nov 2026 08:16 §5): the error texts (LIKE patterns, case-insensitive) that mark a scheduled job''s failure as a code or SQL defect needing development, with its root cause class and owner. repeat_setting names a pipeline setting: the class applies only after that many consecutive failures (a time-out can be load). Changed only by a release. Never read by the consumer API.';
alter table pipeline.recovery_error_classes enable row level security;
revoke all on pipeline.recovery_error_classes from public, anon, authenticated;
insert into pipeline.recovery_error_classes(pattern, error_class, root_cause_class, title, repeat_setting, sort) values
 ('%cannot affect row a second time%', 'sql_cardinality', 'code_defect', 'One statement writes the same key twice (input not production-shaped)', null, 10),
 ('%more than one row returned by a subquery%', 'sql_cardinality', 'code_defect', 'A subquery returns more than one row', null, 11),
 ('%query returned more than one row%', 'sql_cardinality', 'code_defect', 'A single-row query returned more rows', null, 12),
 ('%violates check constraint%', 'sql_constraint', 'code_defect', 'A write breaks a check constraint', null, 20),
 ('%violates unique constraint%', 'sql_constraint', 'code_defect', 'A write breaks a unique constraint', null, 21),
 ('%violates not-null constraint%', 'sql_constraint', 'code_defect', 'A write leaves a required column empty', null, 22),
 ('%violates foreign key constraint%', 'sql_constraint', 'code_defect', 'A write points at a missing row', null, 23),
 ('%column % does not exist%', 'schema_drift', 'deployment_drift', 'Code and the live table disagree on a column (live-only object drift)', null, 30),
 ('%relation % does not exist%', 'schema_drift', 'deployment_drift', 'A table the code needs is missing live', null, 31),
 ('%function % does not exist%', 'schema_drift', 'deployment_drift', 'A function the code calls is missing or has another signature live', null, 32),
 ('%invalid input syntax%', 'sql_data', 'code_defect', 'Input of an unexpected shape reached a typed column', null, 40),
 ('%division by zero%', 'sql_data', 'code_defect', 'Division by zero', null, 41),
 ('%out of range%', 'sql_data', 'code_defect', 'A value out of range', null, 42),
 ('%syntax error%', 'sql_syntax', 'code_defect', 'SQL syntax error', null, 50),
 ('%canceling statement due to statement timeout%', 'time_budget', 'code_defect', 'The job does not fit its time budget (whole run rolled back)', 'ops.permanent_after_runs', 60)
on conflict (pattern) do nothing;

create table if not exists pipeline.progress_transitions (
  key text primary key check (key ~ '^[a-z][a-z0-9_]*$'),
  chain text not null check (chain in ('scholarship', 'aer')),
  step int not null,
  title text not null,
  producer_jobs text[] not null default '{}',
  next_key text references pipeline.progress_transitions(key),
  switch_keys text[] not null default '{}',
  measured_at timestamptz,
  window_start timestamptz,
  input_eligible numeric,
  input_processed numeric,
  output_created numeric,
  output_rejected numeric,
  rejected_reasons jsonb,
  output_parked numeric,
  parked_next_actions jsonb,
  downstream_queued numeric,
  output_admitted numeric,
  output_published numeric,
  last_advanced_at timestamptz,
  zero_reason text check (zero_reason is null or zero_reason in ('no_eligible_work', 'cap_reached', 'blocked_authority', 'correctly_excluded', 'technical_failure')),
  zero_detail text,
  stalled boolean not null default false,
  stalled_since timestamptz,
  issue_id bigint references pipeline.integration_issues(id),
  measure_error text,
  unique (chain, step));
comment on table pipeline.progress_transitions is 'CF-247 (mandate 4 Nov 2026 08:16 §4): the producer-to-consumer progress contract. One shared record per pipeline transition (scholarship: coverage classification, source recovery, listing traversal, candidate matching, reading, eligibility validation, Layer 4, admission, publication; AER: source discovery, extraction, completeness validation, technical correction, Layer 4 review, active entry records, consumer publication) with its producing jobs, the next stage, the switches it depends on, and the last reading: input eligible, processed, output created, rejected with reasons, parked with next actions, downstream queued, admitted, published, last advancement, the reason for a zero, and whether it is stalled. A null measure is not held (not measured), never zero. Kept by job first-run-verify (security.progress_read_v1) from existing tables; producers do not write it. Never read by the consumer API.';
alter table pipeline.progress_transitions enable row level security;
revoke all on pipeline.progress_transitions from public, anon, authenticated;

create table if not exists pipeline.progress_observations (
  id bigserial primary key,
  transition_key text not null references pipeline.progress_transitions(key),
  measured_at timestamptz not null default now(),
  window_start timestamptz not null,
  measures jsonb not null,
  zero_reason text,
  stalled boolean not null default false);
comment on table pipeline.progress_observations is 'CF-247 (mandate 4 Nov 2026 08:16 §4, §10): every reading of every transition (the measures as read), for baseline, change and verified outcome in the self-sustainability scorecard. Written by job first-run-verify; nothing is deleted. Never read by the consumer API.';
create index if not exists progress_observations_key_at_idx on pipeline.progress_observations (transition_key, measured_at desc);
alter table pipeline.progress_observations enable row level security;
revoke all on pipeline.progress_observations from public, anon, authenticated;
revoke all on sequence pipeline.progress_observations_id_seq from public, anon, authenticated;

-- the two chains of mandate §4 (next_key filled after both rows exist)
insert into pipeline.progress_transitions(key, chain, step, title, producer_jobs, switch_keys) values
 ('sch_classification', 'scholarship', 10, 'Coverage classification', '{scholarship-coverage-classify}', '{sch_cov.classify_on}'),
 ('sch_source_recovery', 'scholarship', 20, 'Source recovery', '{scholarship-coverage-recover}', '{sch_cov.recover_register_pages_on,sch_cov.recover_stored_reads_on,sch_cov.recover_listings_on}'),
 ('sch_listing_traversal', 'scholarship', 30, 'Listing traversal', '{scholarship-listing}', '{}'),
 ('sch_candidate_matching', 'scholarship', 40, 'Candidate matching', '{scholarship-discover,scholarship-listing}', '{}'),
 ('sch_reading', 'scholarship', 50, 'Reading', '{scholarship-read,scholarship-ai-extract}', '{}'),
 ('sch_eligibility', 'scholarship', 60, 'Eligibility validation', '{scholarship-ai-extract}', '{}'),
 ('sch_layer4', 'scholarship', 70, 'Layer 4 where required', '{}', '{}'),
 ('sch_admission', 'scholarship', 80, 'Admission', '{scholarship-ai-extract}', '{}'),
 ('sch_publication', 'scholarship', 90, 'Publication', '{scholarship-auto-publish}', '{}'),
 ('aer_source_discovery', 'aer', 10, 'Source discovery', '{coverage-discover,coverage-discover-2}', '{}'),
 ('aer_extraction', 'aer', 20, 'Extraction', '{aer-scheduled-read,entry-matrix-read}', '{}'),
 ('aer_completeness', 'aer', 30, 'Completeness validation', '{aer-scheduled-read}', '{}'),
 ('aer_technical_correction', 'aer', 40, 'Technical correction where needed', '{work-continuity}', '{}'),
 ('aer_layer4_review', 'aer', 50, 'Layer 4 review', '{}', '{}'),
 ('aer_active_records', 'aer', 60, 'Active entry records', '{}', '{}'),
 ('aer_publication', 'aer', 70, 'Consumer publication', '{}', '{}')
on conflict (key) do nothing;
update pipeline.progress_transitions t set next_key = n.key
  from pipeline.progress_transitions n
 where n.chain = t.chain and n.step = (select min(x.step) from pipeline.progress_transitions x where x.chain = t.chain and x.step > t.step) and t.next_key is null;

-- 3. the expected first run, from the job's own schedule -------------------------------------------------------------------------------------------
create or replace function security.cron_field_match_v1(p_field text, p_value int, p_min int, p_max int) returns boolean
language plpgsql immutable set search_path to '' as $function$
-- One field of a five-field cron schedule: lists of *, n, a-b, */s, a-b/s and n/s. Day of week 7 is Sunday (0).
declare v_part text; v_range text; v_step int; v_lo int; v_hi int;
begin
  foreach v_part in array string_to_array(p_field, ',') loop
    v_step := 1; v_range := v_part;
    if position('/' in v_part) > 0 then v_range := split_part(v_part, '/', 1); v_step := split_part(v_part, '/', 2)::int; end if;
    if v_range = '*' then v_lo := p_min; v_hi := p_max;
    elsif position('-' in v_range) > 0 then v_lo := split_part(v_range, '-', 1)::int; v_hi := split_part(v_range, '-', 2)::int;
    else v_lo := v_range::int; v_hi := case when position('/' in v_part) > 0 then p_max else v_lo end;
    end if;
    if p_max = 6 and v_hi = 7 then  -- fixed: cron day of week 7 is Sunday
      if p_value = 0 and (7 - v_lo) % v_step = 0 and v_lo <= 7 then return true; end if;
    end if;
    if p_value between v_lo and v_hi and (p_value - v_lo) % v_step = 0 then return true; end if;
  end loop;
  return false;
end $function$;
revoke all on function security.cron_field_match_v1(text, integer, integer, integer) from public, anon, authenticated;

create or replace function security.cron_next_run_v1(p_schedule text, p_after timestamptz) returns timestamptz
language plpgsql stable set search_path to '' as $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §3): the first time after p_after at which a pg_cron schedule fires (pg_cron runs in UTC), searched minute by
-- minute for frv.next_run_search_hours. Null for a schedule that is not five fields (pg_cron's "n seconds" form) or that does not fire in that time.
declare f text[] := regexp_split_to_array(btrim(coalesce(p_schedule, '')), '\s+'); v_t timestamp; v_end timestamp; v_dom_any boolean; v_dow_any boolean; v_dom boolean; v_dow boolean;
begin
  if cardinality(f) <> 5 then return null; end if;
  v_t := date_trunc('minute', p_after at time zone 'UTC') + interval '1 minute';  -- fixed: the next whole minute
  v_end := v_t + make_interval(hours => security.pipeline_num_v1('frv.next_run_search_hours', 48)::int);
  v_dom_any := f[3] = '*'; v_dow_any := f[5] = '*';
  while v_t < v_end loop
    if security.cron_field_match_v1(f[4], extract(month from v_t)::int, 1, 12) then
      v_dom := security.cron_field_match_v1(f[3], extract(day from v_t)::int, 1, 31);
      v_dow := security.cron_field_match_v1(f[5], extract(dow from v_t)::int, 0, 6);
      if (case when v_dom_any or v_dow_any then v_dom and v_dow else v_dom or v_dow end)
         and security.cron_field_match_v1(f[2], extract(hour from v_t)::int, 0, 23) then
        if security.cron_field_match_v1(f[1], extract(minute from v_t)::int, 0, 59) then return v_t at time zone 'UTC'; end if;
        v_t := v_t + interval '1 minute';  -- fixed: minute steps within a matching hour
      else
        v_t := date_trunc('hour', v_t) + interval '1 hour';  -- fixed: skip a non-matching hour
      end if;
    else
      v_t := date_trunc('hour', v_t) + interval '1 hour';  -- fixed: skip a non-matching month hour by hour (bounded by the search window)
    end if;
  end loop;
  return null;
end $function$;
revoke all on function security.cron_next_run_v1(text, timestamptz) from public, anon, authenticated;

-- 4. the progress contract: one bounded reading per transition ----------------------------------------------------------------------------------
create or replace function security.progress_measure_v1(p_key text, p_since timestamptz) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §4): one transition counted from the tables its producers already write, movement since p_since. Keys: eligible,
-- processed, created, rejected, rejected_reasons, excluded (correct exclusions among the rejected), parked, parked_next, downstream, admitted,
-- published, last_output_at, cap (a valid cap holds the transition) and cap_detail, basis (what each count reads). A key left out is not measured.
declare v jsonb; v_l4max numeric := security.pipeline_num_v1('aer.schedule_layer4_max', 600);
begin
  case p_key
  when 'sch_classification' then
    select jsonb_build_object(
      'eligible', (select count(distinct c.provider_id) from pipeline.scholarship_page_candidates c),
      'processed', (select count(*) from pipeline.scholarship_coverage_providers p where p.classified_at >= p_since),
      'created', (select count(*) from pipeline.scholarship_coverage_items i where i.present and i.classified_at >= p_since),
      'parked', (select count(*) from pipeline.scholarship_coverage_items i join pipeline.scholarship_coverage_state_codes s on s.code = i.state where i.present and not s.resolved),
      'parked_next', (select coalesce(jsonb_object_agg(z.state, z.n), '{}'::jsonb) from (select i.state, count(*) n from pipeline.scholarship_coverage_items i
                        join pipeline.scholarship_coverage_state_codes s on s.code = i.state where i.present and not s.resolved group by 1) z),
      'downstream', (select count(*) from pipeline.scholarship_coverage_items i where i.present and i.state in ('source_found_unread', 'traversal_incomplete', 'rejected_incorrectly')),
      'last_output_at', (select max(i.classified_at) from pipeline.scholarship_coverage_items i),
      'basis', 'eligible: providers with any scholarship candidate; created: coverage cases classified; parked: unresolved cases by state; downstream: recoverable cases') into v;
  when 'sch_source_recovery' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_coverage_items i where i.present and i.state in ('source_found_unread', 'traversal_incomplete', 'rejected_incorrectly')
                     and not exists (select 1 from pipeline.scholarship_coverage_recoveries r where r.item_key = i.item_key)),
      'processed', (select count(*) from pipeline.scholarship_coverage_recoveries r where r.at >= p_since),
      'created', (select count(*) from pipeline.scholarship_coverage_recoveries r where r.outcome = 'succeeded' and r.outcome_at >= p_since),
      'rejected', (select count(*) from pipeline.scholarship_coverage_recoveries r where r.outcome = 'failed' and r.outcome_at >= p_since),
      'rejected_reasons', jsonb_build_object('case did not move', (select count(*) from pipeline.scholarship_coverage_recoveries r where r.outcome = 'failed' and r.outcome_at >= p_since)),
      'downstream', (select count(*) from pipeline.scholarship_coverage_recoveries r where r.outcome is null),
      'last_output_at', (select max(r.outcome_at) from pipeline.scholarship_coverage_recoveries r where r.outcome = 'succeeded'),
      'basis', 'eligible: recoverable coverage cases with no recovery yet; created: recoveries whose case moved; downstream: recoveries awaiting their verification') into v;
  when 'sch_listing_traversal' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_listing_pages l where l.active and coalesce(l.status, '') <> 'suggested' and (l.next_read_at is null or l.next_read_at <= now())),
      'processed', (select count(*) from pipeline.scholarship_listing_pages l where l.read_at >= p_since),
      'created', (select count(*) from pipeline.scholarship_listing_members m where m.first_seen >= p_since),
      'rejected', (select count(*) from pipeline.scholarship_listing_pages l where l.read_at >= p_since and l.error is not null),
      'rejected_reasons', (select coalesce(jsonb_object_agg(z.r, z.n), '{}'::jsonb) from (select left(l.error, 60) r, count(*) n from pipeline.scholarship_listing_pages l
                             where l.read_at >= p_since and l.error is not null group by 1 order by 2 desc limit 10) z),
      'parked', (select count(*) from pipeline.scholarship_listing_pages l where l.status = 'suggested'),
      'parked_next', jsonb_build_object('listing suggested, not yet a listing source (promote_listing, sch_cov.recover_listings_on)',
                                        (select count(*) from pipeline.scholarship_listing_pages l where l.status = 'suggested')),
      'downstream', (select count(*) from pipeline.scholarship_listing_members m where m.present and m.candidate_id is null),
      'last_output_at', (select max(m.first_seen) from pipeline.scholarship_listing_members m),
      'basis', 'eligible: active listing sources due a read; created: listing items found; parked: suggested listings; downstream: items not yet candidates') into v;
  when 'sch_candidate_matching' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_listing_members m where m.present and m.candidate_id is null),
      'processed', (select count(*) from pipeline.scholarship_page_candidates c where c.found_at >= p_since),
      'created', (select count(*) from pipeline.scholarship_page_candidates c where c.found_at >= p_since),
      'downstream', (select count(*) from pipeline.scholarship_page_candidates c where c.read_status is null and c.read_at is null),
      'last_output_at', (select max(c.found_at) from pipeline.scholarship_page_candidates c),
      'basis', 'eligible: listing items not yet candidates; created: candidate pages found; downstream: candidates never read') into v;
  when 'sch_reading' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at is null and (c.next_read_at is null or c.next_read_at <= now())),
      'processed', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at >= p_since),
      'created', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at >= p_since and c.http_status between 200 and 299),
      'rejected', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at >= p_since and c.http_status is distinct from null and c.http_status not between 200 and 299),
      'rejected_reasons', (select coalesce(jsonb_object_agg(z.r, z.n), '{}'::jsonb) from (select coalesce(c.read_status, 'http ' || c.http_status) r, count(*) n
                             from pipeline.scholarship_page_candidates c where c.read_at >= p_since and c.http_status not between 200 and 299 group by 1 order by 2 desc limit 10) z),
      'downstream', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at is not null and c.http_status between 200 and 299 and c.admit_status is null),
      'last_output_at', (select max(c.read_at) from pipeline.scholarship_page_candidates c where c.http_status between 200 and 299),
      'basis', 'eligible: candidates never read and due; created: pages read (HTTP 2xx); downstream: read pages awaiting an admission decision') into v;
  when 'sch_eligibility' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at is not null and c.http_status between 200 and 299 and c.admit_status is null),
      'processed', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since),
      'created', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since and a.action = 'admitted'),
      'rejected', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since and a.action in ('rejected', 'skipped', 'duplicate')),
      'excluded', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since and a.action in ('skipped', 'duplicate')),
      'rejected_reasons', (select coalesce(jsonb_object_agg(z.r, z.n), '{}'::jsonb) from (select a.action || ': ' || coalesce(left(coalesce(a.detail->>'reason', a.detail->>'skip_reason',
                             a.detail->>'reasons'), 50), 'not stated') r, count(*) n from pipeline.scholarship_admission_log a
                             where a.at >= p_since and a.action in ('rejected', 'skipped', 'duplicate') group by 1 order by 2 desc limit 10) z),
      'parked', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending'),
      'parked_next', jsonb_build_object('held for a person (Layer 4)', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending')),
      'downstream', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending'),
      'admitted', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since and a.action = 'admitted'),
      'last_output_at', (select max(a.at) from pipeline.scholarship_admission_log a where a.action = 'admitted'),
      'basis', 'eligible: read pages with no admission decision; created/admitted: admission log admitted; excluded: skipped (directory site) and duplicates') into v;
  when 'sch_layer4' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending'),
      'processed', (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= p_since),
      'created', (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= p_since and r.status = 'admitted'),
      'rejected', (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= p_since and r.status in ('refused', 'superseded')),
      'excluded', (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= p_since and r.status = 'superseded'),
      'rejected_reasons', (select coalesce(jsonb_object_agg(z.s, z.n), '{}'::jsonb) from (select r.status s, count(*) n from pipeline.scholarship_ai_reviews r
                             where r.decided_at >= p_since and r.status in ('refused', 'superseded') group by 1) z),
      'parked', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending'),
      'parked_next', jsonb_build_object('a person decides in Layer 4', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending')),
      'admitted', (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= p_since and r.status = 'admitted'),
      'last_output_at', (select max(r.decided_at) from pipeline.scholarship_ai_reviews r where r.status = 'admitted'),
      'basis', 'scholarship AI reviews held for a person: pending, admitted, refused, superseded') into v;
  when 'sch_admission' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since and a.action = 'admitted'),
      'processed', (select count(*) from pipeline.scholarship_admission_log a where a.at >= p_since and a.action = 'admitted'),
      'created', (select count(*) from scholarship.scholarships s where s.created_at >= p_since and s.lifecycle_status = 'active'),
      'admitted', (select count(*) from scholarship.scholarships s where s.created_at >= p_since and s.lifecycle_status = 'active'),
      'downstream', (select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.publication_status not in ('published', 'withdrawn')),
      'last_output_at', (select max(s.created_at) from scholarship.scholarships s where s.lifecycle_status = 'active'),
      'basis', 'admitted: active catalogue scholarships created (scholarship.scholarships, read only); downstream: active, not published, not withdrawn') into v;
  when 'sch_publication' then
    select jsonb_build_object(
      'eligible', (select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.publication_status not in ('published', 'withdrawn')),
      'processed', (select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.updated_at >= p_since),
      'created', (select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.publication_status = 'published' and s.updated_at >= p_since),
      'published', (select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.publication_status = 'published' and s.updated_at >= p_since),
      'published_total', (select count(*) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.publication_status = 'published'),
      'last_output_at', (select max(s.updated_at) from scholarship.scholarships s where s.lifecycle_status = 'active' and s.publication_status = 'published'),
      'basis', 'published: active scholarships marked published and changed in the window (updated_at); consumer read-back (Website API v2, Zoho) is verified separately') into v;
  when 'aer_source_discovery' then
    select jsonb_build_object(
      'eligible', (select count(distinct g.provider_id) from pipeline.aer_gap_findings g where g.state = 'open' and g.root_cause = 'no_source'),
      'processed', (select count(*) from pipeline.aer_source_inventory s where s.recorded_at >= p_since) + (select count(*) from pipeline.entry_matrix_sources e where e.created_at >= p_since),
      'created', (select count(*) from pipeline.entry_matrix_sources e where e.created_at >= p_since),
      'parked', (select count(*) from pipeline.aer_gap_findings g where g.state = 'open' and g.root_cause = 'no_source'),
      'parked_next', (select coalesce(jsonb_object_agg(z.a, z.n), '{}'::jsonb) from (select coalesce(left(g.next_action, 60), 'no next action') a, count(*) n from pipeline.aer_gap_findings g
                        where g.state = 'open' and g.root_cause = 'no_source' group by 1 order by 2 desc limit 5) z),
      'downstream', (select count(*) from pipeline.entry_matrix_sources e where e.read_at is null and coalesce(e.status, '') <> 'failed'),
      'last_output_at', (select max(e.created_at) from pipeline.entry_matrix_sources e),
      'basis', 'eligible: providers with an open no_source AER gap; created: AER matrix sources found; downstream: sources not yet read') into v;
  when 'aer_extraction' then
    select jsonb_build_object(
      'eligible', (select count(distinct e.provider_id) from pipeline.entry_matrix_sources e where e.status = 'read'),
      'processed', coalesce((select sum(r.course_reads) from pipeline.aer_schedule_runs r where r.ran_at >= p_since), 0)
                   + (select count(*) from pipeline.entry_matrix_runs m where m.created_at >= p_since),
      'created', (select count(*) from catalogue.course_entry_requirements c where c.created_at >= p_since),
      'rejected', (select count(*) from pipeline.entry_matrix_runs m where m.created_at >= p_since and m.error is not null),
      'rejected_reasons', (select coalesce(jsonb_object_agg(z.r, z.n), '{}'::jsonb) from (select left(m.error, 60) r, count(*) n from pipeline.entry_matrix_runs m
                             where m.created_at >= p_since and m.error is not null group by 1 order by 2 desc limit 10) z),
      'downstream', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'cap', coalesce((select r.back_pressure or r.refusal is not null from pipeline.aer_schedule_runs r order by r.ran_at desc limit 1), false),
      'cap_detail', (select jsonb_build_object('ran_at', r.ran_at, 'back_pressure', r.back_pressure, 'room', r.room, 'layer4_waiting', r.layer4_waiting, 'refusal', r.refusal,
                       'layer4_limit', v_l4max) from pipeline.aer_schedule_runs r order by r.ran_at desc limit 1),
      'last_output_at', (select max(c.created_at) from catalogue.course_entry_requirements c),
      'basis', 'eligible: providers with a read AER source; processed: scheduled course reads and matrix runs; created: course entry rows proposed; cap: the last scheduled run''s back-pressure or refusal') into v;
  when 'aer_completeness' then
    select jsonb_build_object(
      'eligible', (select count(*) from catalogue.course_entry_requirements c where c.created_at >= p_since),
      'processed', (select count(*) from catalogue.course_entry_requirements c where c.created_at >= p_since),
      'created', (select count(*) from pipeline.layer4_review_items i where i.created_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'rejected', coalesce((select sum(m.rows_dropped) from pipeline.entry_matrix_runs m where m.created_at >= p_since), 0),
      'rejected_reasons', jsonb_build_object('rows dropped by the completeness gate (matrix runs)', coalesce((select sum(m.rows_dropped) from pipeline.entry_matrix_runs m where m.created_at >= p_since), 0)),
      'downstream', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'last_output_at', (select max(i.created_at) from pipeline.layer4_review_items i where i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'basis', 'eligible: course entry rows proposed; created: AER Layer 4 items raised; rejected: matrix rows dropped') into v;
  when 'aer_technical_correction' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.stage = 'eligible'),
      'processed', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.last_attempt_at >= p_since),
      'created', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.recovered_at >= p_since),
      'parked', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.stage = 'parked'),
      'parked_next', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb) from (select coalesce(w.failure_class, 'unclassified') || case when w.next_eligible_at is null then ' (no next time)' else '' end k,
                        count(*) n from pipeline.work_items w where w.lane = 'aer_technical' and w.stage = 'parked' group by 1) z),
      'last_output_at', (select max(w.recovered_at) from pipeline.work_items w where w.lane = 'aer_technical'),
      'basis', 'work items of lane aer_technical: eligible, attempted, recovered, parked by failure class') into v;
  when 'aer_layer4_review' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'processed', (select count(*) from pipeline.layer4_review_items i where i.decided_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'created', (select count(*) from pipeline.layer4_review_items i where i.decided_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')
                    and i.status not in ('pending', 'rejected', 'superseded', 'returned')),
      'rejected', (select count(*) from pipeline.layer4_review_items i where i.decided_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')
                     and i.status in ('rejected', 'superseded', 'returned')),
      'excluded', (select count(*) from pipeline.layer4_review_items i where i.decided_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run') and i.status = 'superseded'),
      'parked', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')),
      'parked_next', jsonb_build_object('a person decides in Layer 4; reading pauses at the limit', v_l4max),
      'downstream', (select count(*) from pipeline.layer4_review_items i where i.decided_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')
                       and i.status not in ('pending', 'rejected', 'superseded', 'returned')),
      'last_output_at', (select max(i.decided_at) from pipeline.layer4_review_items i where i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')
                           and i.status not in ('pending', 'rejected', 'superseded', 'returned')),
      'basis', 'Layer 4 AER items (course first read, matrix first run): pending, decided for admission, rejected or superseded') into v;
  when 'aer_active_records' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.layer4_review_items i where i.decided_at >= p_since and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')
                     and i.status not in ('pending', 'rejected', 'superseded', 'returned')),
      'processed', (select count(*) from catalogue.course_entry_requirements c where c.updated_at >= p_since and c.status in ('active', 'inactive')),
      'created', (select count(*) from catalogue.course_entry_requirements c where c.updated_at >= p_since and c.status = 'active'),
      'admitted', (select count(*) from catalogue.course_entry_requirements c where c.updated_at >= p_since and c.status = 'active'),
      'active_total', (select count(*) from catalogue.course_entry_requirements c where c.status = 'active'),
      'last_output_at', (select max(c.updated_at) from catalogue.course_entry_requirements c where c.status = 'active'),
      'basis', 'admitted: course entry rows made active in the window (catalogue.course_entry_requirements, read only)') into v;
  when 'aer_publication' then
    select jsonb_build_object(
      'eligible', (select count(*) from catalogue.course_entry_requirements c where c.updated_at >= p_since and c.status = 'active'),
      'processed', (select count(*) from catalogue.course_entry_requirements c where c.updated_at >= p_since and c.status = 'active'),
      'created', (select count(*) from catalogue.course_entry_requirements c join catalogue.courses k on k.id = c.course_id join catalogue.providers p on p.id = k.provider_id
                    where c.updated_at >= p_since and c.status = 'active' and p.publication_status = 'published'),
      'published', (select count(*) from catalogue.course_entry_requirements c join catalogue.courses k on k.id = c.course_id join catalogue.providers p on p.id = k.provider_id
                      where c.updated_at >= p_since and c.status = 'active' and p.publication_status = 'published'),
      'last_output_at', (select max(c.updated_at) from catalogue.course_entry_requirements c join catalogue.courses k on k.id = c.course_id join catalogue.providers p on p.id = k.provider_id
                           where c.status = 'active' and p.publication_status = 'published'),
      'basis', 'published: active entry rows of published providers, which the consumer API reads; read-back through Website API v2 and Zoho is verified separately') into v;
  else
    raise exception 'no progress measure for transition %', p_key using errcode = '22023';
  end case;
  return v;
end $function$;
revoke all on function security.progress_measure_v1(text, timestamptz) from public, anon, authenticated;
comment on function security.progress_measure_v1(text, timestamptz) is 'CF-247 (mandate 4 Nov 2026 08:16 §4): one transition of the progress contract counted from existing tables (read only).';

create or replace function security.progress_zero_reason_v1(p_key text, m jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §4 "a zero-output run must have a reason"): why a transition created nothing, in order: its producing jobs are
-- all paused, or every switch it depends on is off (blocked_authority); a valid cap holds it (cap_reached); nothing is eligible
-- (no_eligible_work); everything processed was correctly excluded (correctly_excluded); otherwise technical_failure. Null when it created output.
declare t pipeline.progress_transitions; v_jobs int; v_active int; v_off text[];
begin
  select * into t from pipeline.progress_transitions where key = p_key;
  if coalesce((m->>'created')::numeric, 0) > 0 then return null; end if;
  select count(*), count(*) filter (where j.active) into v_jobs, v_active from cron.job j where j.jobname = any (t.producer_jobs);
  if v_jobs > 0 and v_active = 0 then
    return jsonb_build_object('reason', 'blocked_authority', 'detail', 'producing job(s) paused: ' || array_to_string(t.producer_jobs, ', '));
  end if;
  select coalesce(array_agg(k), '{}') into v_off from unnest(t.switch_keys) k where security.pipeline_num_v1(k, 0) < 1;
  if cardinality(t.switch_keys) > 0 and cardinality(v_off) = cardinality(t.switch_keys) then
    return jsonb_build_object('reason', 'blocked_authority', 'detail', 'switched off: ' || array_to_string(v_off, ', '));
  end if;
  if coalesce((m->>'cap')::boolean, false) then return jsonb_build_object('reason', 'cap_reached', 'detail', coalesce(m->>'cap_detail', 'a valid cap')); end if;
  if coalesce((m->>'eligible')::numeric, 0) = 0 then return jsonb_build_object('reason', 'no_eligible_work', 'detail', 'nothing eligible: ' || coalesce(m->>'basis', '')); end if;
  if coalesce((m->>'processed')::numeric, 0) > 0 and coalesce((m->>'excluded')::numeric, 0) >= (m->>'processed')::numeric then
    return jsonb_build_object('reason', 'correctly_excluded', 'detail', 'every processed input was excluded by a recorded rule');
  end if;
  return jsonb_build_object('reason', 'technical_failure', 'detail', coalesce(m->>'eligible', '?') || ' eligible, ' || coalesce(m->>'processed', '0') || ' processed, nothing created');
end $function$;
revoke all on function security.progress_zero_reason_v1(text, jsonb) from public, anon, authenticated;

create or replace function security.progress_read_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §4): reads every transition (each isolated: one that fails to read is recorded and the others still read), keeps
-- the reading on pipeline.progress_transitions and in pipeline.progress_observations, and raises a stalled transition by fingerprint
-- stall:<transition> (eligible input, a technical zero, no advancement for progress.stall_hours), whatever its producing job reports.
declare t pipeline.progress_transitions; m jsonb; z jsonb; v_since timestamptz := now() - make_interval(hours => security.pipeline_num_v1('progress.window_hours', 24)::int);
        v_stall_h int := security.pipeline_num_v1('progress.stall_hours', 6)::int; v_last timestamptz; v_stalled boolean; v_res jsonb; v_issue bigint;
        v_n int := 0; v_err int := 0; v_st int := 0; v_jobs jsonb;
begin
  if security.pipeline_num_v1('progress.on', 1) < 1 then return jsonb_build_object('off', true); end if;
  for t in select * from pipeline.progress_transitions order by chain, step loop
    begin
      m := security.progress_measure_v1(t.key, v_since);
      z := security.progress_zero_reason_v1(t.key, m);
      v_last := greatest(t.last_advanced_at, case when coalesce((m->>'created')::numeric, 0) > 0 then (m->>'last_output_at')::timestamptz end);
      v_stalled := z is not null and z->>'reason' = 'technical_failure' and coalesce((m->>'eligible')::numeric, 0) > 0
                   and coalesce(v_last, '-infinity'::timestamptz) < now() - make_interval(hours => v_stall_h);
      v_issue := t.issue_id;
      if v_stalled then
        select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'active', j.active)), '[]'::jsonb) into v_jobs from cron.job j where j.jobname = any (t.producer_jobs);
        v_res := security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'stall:' || t.key,
          'title', 'Pipeline transition stalled: ' || t.chain || ' ' || lower(t.title) || ' (' || coalesce(m->>'eligible', '?') || ' eligible, nothing created for ' || v_stall_h || ' h)',
          'layer', case t.chain when 'aer' then 'AER' else 'Scholarships' end, 'subsystem', 'progress contract: ' || t.key,
          'failure', coalesce(z->>'detail', 'no output') || '; last advanced ' || coalesce(v_last::text, 'never') || '; producing jobs ' || v_jobs::text,
          'expected', 'Eligible input advances to the next stage (' || coalesce(t.next_key, 'end of chain') || '), or the zero has a valid reason',
          'source', 'first-run-verify (progress contract)', 'validation_layer', 'V4', 'severity', 'P2', 'root_cause_class', 'unclassified', 'workstream', 'A7',
          'evidence', jsonb_build_object('transition', t.key, 'measures', m, 'zero_reason', z, 'jobs', v_jobs, 'window_start', v_since), 'observed_at', now()),
          'first-run-verify');
        v_issue := (v_res->>'id')::bigint; v_st := v_st + 1;
      end if;
      update pipeline.progress_transitions set measured_at = now(), window_start = v_since,
             input_eligible = (m->>'eligible')::numeric, input_processed = (m->>'processed')::numeric, output_created = (m->>'created')::numeric,
             output_rejected = (m->>'rejected')::numeric, rejected_reasons = m->'rejected_reasons', output_parked = (m->>'parked')::numeric, parked_next_actions = m->'parked_next',
             downstream_queued = (m->>'downstream')::numeric, output_admitted = (m->>'admitted')::numeric, output_published = (m->>'published')::numeric,
             last_advanced_at = v_last, zero_reason = z->>'reason', zero_detail = z->>'detail',
             stalled = v_stalled, stalled_since = case when v_stalled then coalesce(t.stalled_since, now()) end, issue_id = v_issue, measure_error = null
       where key = t.key;
      insert into pipeline.progress_observations(transition_key, window_start, measures, zero_reason, stalled) values (t.key, v_since, m || jsonb_build_object('zero', z), z->>'reason', v_stalled);
      v_n := v_n + 1;
    exception when others then
      update pipeline.progress_transitions set measure_error = left(sqlerrm, 300), measured_at = now() where key = t.key;
      v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('read', v_n, 'errors', v_err, 'stalled', v_st, 'since', v_since);
end $function$;
revoke all on function security.progress_read_v1() from public, anon, authenticated;

-- 5. first-run verification (extends the V3 release contract) ------------------------------------------------------------------------------------
create or replace function security.recovery_error_class_v1(p_text text) returns pipeline.recovery_error_classes
language sql stable security definer set search_path to '' as $function$
  select c.* from pipeline.recovery_error_classes c where coalesce(p_text, '') ilike c.pattern order by c.sort, c.pattern limit 1
$function$;
revoke all on function security.recovery_error_class_v1(text) from public, anon, authenticated;

create or replace function security.release_first_run_register_v1(p_release text, p_jobs jsonb default '[]'::jsonb, p_functions jsonb default '{}'::jsonb,
                                                                 p_deployed_at timestamptz default null, p_actor text default 'release controller') returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §3): called by the release controller with security.integration_deploy_check_v1 (same release name, same
-- p_functions). Registers every scheduled job whose command calls a function the release changed, and every job named in p_jobs (a name, or
-- {"job", "transition", "expected_min_output"}), as awaiting its first run: the expected first run from its schedule, where the run scan starts, the
-- transition its output is counted on and the output expected. A job already registered for the release is left as it is. The release's deploy
-- check is marked awaiting_first_run (or not_applicable when no scheduled job changed). Records only.
declare v_at timestamptz; v_dc bigint; v_scan int := security.pipeline_num_v1('frv.runs_scan', 5000)::int; v_from bigint; v_names text[]; v_fns text[];
        j record; v_spec jsonb; v_tr text; v_min numeric; v_n int := 0; v_new int := 0; v_out jsonb := '[]'::jsonb; v_id bigint;
begin
  if coalesce(btrim(p_release), '') = '' then raise exception 'name the release' using errcode = '22023'; end if;
  select d.id, d.checked_at into v_dc, v_at from pipeline.integration_deploy_checks d where d.release = p_release order by d.id desc limit 1;
  v_at := coalesce(p_deployed_at, v_at, now());
  select coalesce(array_agg(distinct split_part(k, '(', 1)), '{}') into v_fns from jsonb_object_keys(coalesce(p_functions, '{}'::jsonb)) k;
  select coalesce(array_agg(distinct x), '{}') into v_names from (
    select case jsonb_typeof(e) when 'string' then e #>> '{}' else e->>'job' end x from jsonb_array_elements(coalesce(p_jobs, '[]'::jsonb)) e
    union select c.jobname from cron.job c
     where exists (select 1 from unnest(v_fns) f where c.command ~ ('\m' || replace(f, '.', '\.') || '\s*\('))) z where x is not null;
  select coalesce(max(d.runid), (select max(x.runid) from cron.job_run_details x)) into v_from
    from (select r.runid, r.start_time from cron.job_run_details r order by r.runid desc limit v_scan) d where d.start_time < v_at;
  for j in select n.name, c.jobid, c.schedule, c.active from unnest(v_names) n(name) left join cron.job c on c.jobname = n.name order by n.name loop
    select e into v_spec from jsonb_array_elements(coalesce(p_jobs, '[]'::jsonb)) e where jsonb_typeof(e) = 'object' and e->>'job' = j.name limit 1;
    v_tr := coalesce(v_spec->>'transition', (select t.key from pipeline.progress_transitions t where j.name = any (t.producer_jobs) order by t.chain, t.step limit 1));
    v_min := coalesce((v_spec->>'expected_min_output')::numeric, security.pipeline_num_v1('frv.expected_min_output', 1));
    insert into pipeline.release_job_verifications(release, jobname, jobid, deploy_check_id, deployed_at, registered_by, schedule, active_at_deploy, expected_first_run,
           scan_from_runid, transition_key, expected_min_output, status, status_reason, evidence)
    values (p_release, j.name, j.jobid, v_dc, v_at, coalesce(nullif(btrim(p_actor), ''), 'release controller'), j.schedule, j.active,
            case when j.active then security.cron_next_run_v1(j.schedule, v_at) end, v_from, v_tr, v_min,
            case when j.jobid is null then 'failed_first_run' else 'awaiting_first_run' end,
            case when j.jobid is null then 'not scheduled: no cron job of this name' when not j.active then 'job inactive: awaiting activation'
                 when v_tr is null then 'no output measure named for this job' else 'awaiting the first scheduled run' end,
            jsonb_build_object('functions', to_jsonb(v_fns), 'spec', v_spec))
    on conflict (release, jobname) do nothing returning id into v_id;
    if v_id is not null then v_new := v_new + 1; end if;
    v_n := v_n + 1;
    v_out := v_out || jsonb_build_object('job', j.name, 'expected_first_run', case when j.active then security.cron_next_run_v1(j.schedule, v_at) end, 'transition', v_tr, 'active', j.active);
    -- an engineering remediation on this job is now released
    update pipeline.integration_issues i set remediation_status = 'fix_released', remediation_checkpoint_at = now(),
           remediation_evidence = coalesce(i.remediation_evidence, '{}'::jsonb) || jsonb_build_object('fix_release', p_release, 'fix_registered_at', now())
     where i.status <> 'closed' and i.remediation_status in ('engineering_open', 'returned')
       and (i.fingerprint = 'job_failed:' || j.name or i.remediation_evidence->>'job' = j.name);
  end loop;
  if v_dc is not null then
    update pipeline.integration_deploy_checks set operational_status = case when v_n = 0 then 'not_applicable' else 'awaiting_first_run' end, operational_checked_at = now() where id = v_dc;
  end if;
  return jsonb_build_object('release', p_release, 'deploy_check', v_dc, 'deployed_at', v_at, 'jobs', v_n, 'registered', v_new, 'detail', v_out);
end $function$;
revoke all on function security.release_first_run_register_v1(text, jsonb, jsonb, timestamptz, text) from public, anon, authenticated;
comment on function security.release_first_run_register_v1(text, jsonb, jsonb, timestamptz, text) is 'CF-247 mandate 4 Nov 2026 08:16 §3: the release controller registers the scheduled jobs a release changed (with security.integration_deploy_check_v1); job first-run-verify then follows each to its first production run';

create or replace function security.first_run_verify_jobs_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §3): moves each awaiting release job. The first run after deployment is found among scheduler runs newer than
-- the row's scan point (at most frv.runs_scan a check). A failed run: failed_first_run, and the job's own issue (job_failed:<job>) is raised or
-- updated with the run id and error; an issue whose fix was deployed goes back to in_progress with that evidence. A successful run: the output
-- on the job's transition since that run is counted against the expected output and the next stage's queue; it is operationally_verified only
-- when output arrived and moved downstream, or the zero is justified (no eligible work, correctly excluded). A cap or an authority block keeps it
-- awaiting; a technical zero is a failed first run. No run within frv.grace_minutes of the expected time: failed_first_run (did not run). Still
-- awaiting after frv.verify_deadline_hours: raised as unverified (first_run:<job>). Records only, unless recovery.close_on_verified_on.
declare r pipeline.release_job_verifications; d record; v_max bigint; v_hi bigint; v_scan int := security.pipeline_num_v1('frv.runs_scan', 5000)::int;
        v_grace int := security.pipeline_num_v1('frv.grace_minutes', 20)::int; v_dead int := security.pipeline_num_v1('frv.verify_deadline_hours', 24)::int;
        m jsonb; z jsonb; v_status text; v_reason text; v_res jsonb; v_cls pipeline.recovery_error_classes; i pipeline.integration_issues; t pipeline.progress_transitions;
        v_n jsonb := jsonb_build_object('found_runs', 0, 'verified', 0, 'failed', 0, 'awaiting', 0, 'unverified_raised', 0);
begin
  select max(x.runid) into v_max from cron.job_run_details x;
  -- 1 the first run of each awaiting job
  for r in select * from pipeline.release_job_verifications where status = 'awaiting_first_run' and first_runid is null and jobid is not null order by id loop
    v_hi := least(v_max, coalesce(r.scan_from_runid, v_max - v_scan) + v_scan);
    select x.runid, x.status, x.start_time, x.end_time, x.return_message into d from cron.job_run_details x
     where x.runid > coalesce(r.scan_from_runid, v_max - v_scan) and x.runid <= v_hi and x.jobid = r.jobid and x.start_time >= r.deployed_at
     order by x.runid limit 1;
    if d.runid is not null and d.status in ('succeeded', 'failed') then
      update pipeline.release_job_verifications set first_runid = d.runid, first_run_at = d.start_time, first_run_status = d.status,
             first_run_message = left(d.return_message, 1000), scan_from_runid = d.runid, checked_at = now() where id = r.id;
      v_n := jsonb_set(v_n, '{found_runs}', to_jsonb((v_n->>'found_runs')::int + 1));
    elsif d.runid is not null then
      update pipeline.release_job_verifications set scan_from_runid = d.runid - 1, checked_at = now(), status_reason = 'first run in progress (run ' || d.runid || ')' where id = r.id;
    else
      update pipeline.release_job_verifications set scan_from_runid = v_hi, checked_at = now() where id = r.id;
      if v_hi = v_max and r.expected_first_run is not null and now() > r.expected_first_run + make_interval(mins => v_grace) then
        update pipeline.release_job_verifications set status = 'failed_first_run', first_run_status = 'did_not_run',
               status_reason = 'no run started by ' || (r.expected_first_run + make_interval(mins => v_grace)) || ' (expected ' || r.expected_first_run || ')' where id = r.id;
      end if;
    end if;
  end loop;
  -- 2 judge the first runs found
  for r in select * from pipeline.release_job_verifications where status = 'awaiting_first_run' and first_runid is not null order by id loop
    v_status := 'awaiting_first_run'; v_reason := r.status_reason; m := null; z := null;
    if r.first_run_status = 'failed' then
      v_status := 'failed_first_run'; v_reason := 'first run ' || r.first_runid || ' failed: ' || left(coalesce(r.first_run_message, ''), 200);
    elsif r.transition_key is null then
      v_reason := 'first run ' || r.first_runid || ' succeeded; no output measure is named for this job';
    else
      select * into t from pipeline.progress_transitions where key = r.transition_key;
      m := security.progress_measure_v1(r.transition_key, r.first_run_at);
      z := security.progress_zero_reason_v1(r.transition_key, m);
      if coalesce((m->>'created')::numeric, 0) >= coalesce(r.expected_min_output, 0) and coalesce((m->>'created')::numeric, 0) > 0 then
        if t.next_key is null or coalesce((m->>'downstream')::numeric, 0) > 0 or coalesce((m->>'admitted')::numeric, 0) > 0 or coalesce((m->>'published')::numeric, 0) > 0 then
          v_status := 'operationally_verified'; v_reason := 'first run ' || r.first_runid || ' succeeded; ' || (m->>'created') || ' created, ' || coalesce(m->>'downstream', '0') || ' queued downstream';
        else
          v_reason := 'output created but nothing is eligible downstream yet (' || coalesce(t.next_key, '') || ')';
        end if;
      elsif coalesce(r.expected_min_output, 0) = 0 or z->>'reason' in ('no_eligible_work', 'correctly_excluded') then
        v_status := 'operationally_verified'; v_reason := 'first run ' || r.first_runid || ' succeeded with a justified zero: ' || coalesce(z->>'reason', 'none expected');
      elsif z->>'reason' in ('cap_reached', 'blocked_authority') then
        v_reason := 'first run ' || r.first_runid || ' succeeded but is held: ' || (z->>'reason') || ' (' || left(coalesce(z->>'detail', ''), 160) || ')';
      elsif coalesce((m->>'created')::numeric, 0) > 0 then
        v_reason := 'first run ' || r.first_runid || ' created ' || (m->>'created') || ' of ' || r.expected_min_output || ' expected';
      else
        v_status := 'failed_first_run'; v_reason := 'first run ' || r.first_runid || ' succeeded but created nothing with eligible work: ' || left(coalesce(z->>'detail', ''), 200);
      end if;
    end if;
    update pipeline.release_job_verifications set status = v_status, status_reason = v_reason, checked_at = now(),
           actual_output = (m->>'created')::numeric, output_measure = m, downstream_eligible = (m->>'downstream')::numeric, zero_reason = z->>'reason',
           verified_at = case when v_status = 'operationally_verified' then now() end where id = r.id;
  end loop;
  -- 3 outcomes: issues for failed first runs; verified fixes; unverified past the deadline
  for r in select * from pipeline.release_job_verifications where checked_at >= now() - make_interval(mins => 1) or (status = 'failed_first_run' and issue_id is null) order by id loop
    if r.status = 'failed_first_run' and r.issue_id is null then
      v_cls := security.recovery_error_class_v1(r.first_run_message);
      v_res := security.integration_issue_upsert_v1(jsonb_build_object(
        'fingerprint', case when r.first_run_status = 'failed' then 'job_failed:' || r.jobname else 'first_run:' || r.jobname end,
        'title', 'Release ' || r.release || ': scheduled job "' || r.jobname || '" failed its first production run', 'layer', 'Release', 'subsystem', 'scheduled jobs',
        'failure', r.status_reason, 'expected', 'The first scheduled run after the release completes, creates its expected output and makes downstream work eligible',
        'source', 'first-run-verify', 'validation_layer', 'V3', 'severity', 'P1', 'root_cause_class', coalesce(v_cls.root_cause_class, 'unclassified'), 'workstream', 'A8',
        'evidence', jsonb_build_object('first_run', jsonb_build_object('release', r.release, 'job', r.jobname, 'runid', r.first_runid, 'at', r.first_run_at,
                    'status', r.first_run_status, 'message', left(r.first_run_message, 500), 'expected_first_run', r.expected_first_run, 'error_class', v_cls.error_class)),
        'observed_at', coalesce(r.first_run_at, now())), 'first-run-verify');
      update pipeline.release_job_verifications set issue_id = (v_res->>'id')::bigint where id = r.id;
      if v_res->>'action' <> 'created' and v_res->>'status' <> 'closed' then  -- an existing issue: the first-run evidence goes on it with a history line
        perform security.integration_issue_transition_v1((v_res->>'id')::bigint, null, 'first-run-verify', 'Release ' || r.release || ': first run of ' || r.jobname || ' failed: '
          || left(r.status_reason, 300), jsonb_build_object('evidence', jsonb_build_object('first_run', jsonb_build_object('release', r.release, 'job', r.jobname, 'runid', r.first_runid,
          'at', r.first_run_at, 'status', r.first_run_status, 'message', left(r.first_run_message, 500), 'error_class', v_cls.error_class))));
      end if;
      select * into i from pipeline.integration_issues where id = (v_res->>'id')::bigint;
      -- a fix that was deployed failed its first run: back to remediation with the new evidence (the canonical issue, when this one is superseded)
      if i.superseded_by is not null then select * into i from pipeline.integration_issues where id = i.superseded_by; end if;
      if i.status in ('integration_testing', 'deployed', 'production_verification') then
        perform security.integration_issue_transition_v1(i.id, 'in_progress', 'first-run-verify',
          'Release ' || r.release || ': the first scheduled run of ' || r.jobname || ' failed again (run ' || coalesce(r.first_runid::text, 'none') || '): ' || left(coalesce(r.first_run_message, r.status_reason), 300),
          jsonb_build_object('evidence', jsonb_build_object('first_run_failed', jsonb_build_object('release', r.release, 'runid', r.first_runid, 'message', left(r.first_run_message, 500)))));
        update pipeline.integration_issues set remediation_status = 'returned', remediation_checkpoint_at = now(),
               remediation_evidence = coalesce(remediation_evidence, '{}'::jsonb) || jsonb_build_object('returned_by', r.release, 'runid', r.first_runid) where id = i.id;
      end if;
      v_n := jsonb_set(v_n, '{failed}', to_jsonb((v_n->>'failed')::int + 1));
    elsif r.status = 'operationally_verified' and r.verified_at >= now() - make_interval(mins => 1) then
      for i in select * from pipeline.integration_issues x where x.status <> 'closed' and x.remediation_status in ('fix_released', 'awaiting_first_run', 'returned', 'engineering_open')
                 and (x.fingerprint = 'job_failed:' || r.jobname or x.remediation_evidence->>'job' = r.jobname) loop
        update pipeline.integration_issues set remediation_status = 'verified', remediation_checkpoint_at = null,
               remediation_evidence = coalesce(remediation_evidence, '{}'::jsonb) || jsonb_build_object('verified_by', r.release, 'runid', r.first_runid, 'output', r.actual_output) where id = i.id;
        perform security.integration_issue_transition_v1(i.id, null, 'first-run-verify', 'Release ' || r.release || ': first scheduled run ' || r.first_runid || ' of ' || r.jobname
          || ' operationally verified (' || coalesce(r.status_reason, '') || ')', '{}'::jsonb);
        if security.pipeline_num_v1('recovery.close_on_verified_on', 0) >= 1 then
          perform security.integration_issue_close_v1(i.id, 'first-run-verify', jsonb_build_object('outcome', 'passed', 'checked_at', now(),
            'reference', 'pipeline.release_job_verifications#' || r.id, 'evidence', 'Release ' || r.release || ': first scheduled run ' || r.first_runid || ' of ' || r.jobname
            || ' succeeded and was operationally verified: ' || coalesce(r.status_reason, '')));
        end if;
      end loop;
      v_n := jsonb_set(v_n, '{verified}', to_jsonb((v_n->>'verified')::int + 1));
    end if;
  end loop;
  for r in select * from pipeline.release_job_verifications where status = 'awaiting_first_run' and deployed_at < now() - make_interval(hours => v_dead) loop
    v_res := security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'first_run:' || r.jobname,
      'title', 'Release ' || r.release || ': job "' || r.jobname || '" still not operationally verified after ' || v_dead || ' h', 'layer', 'Release', 'subsystem', 'scheduled jobs',
      'failure', coalesce(r.status_reason, 'awaiting its first run'), 'expected', 'A released job is operationally verified, or its block is owned with a next checkpoint',
      'source', 'first-run-verify', 'validation_layer', 'V3', 'severity', 'P2', 'root_cause_class', 'unclassified', 'workstream', 'A8', 'assignee', 'engineering',
      'evidence', jsonb_build_object('first_run', jsonb_build_object('release', r.release, 'job', r.jobname, 'status_reason', r.status_reason, 'active_at_deploy', r.active_at_deploy,
                  'expected_first_run', r.expected_first_run, 'zero_reason', r.zero_reason))), 'first-run-verify');
    if r.issue_id is null then update pipeline.release_job_verifications set issue_id = (v_res->>'id')::bigint where id = r.id; end if;
    v_n := jsonb_set(v_n, '{unverified_raised}', to_jsonb((v_n->>'unverified_raised')::int + 1));
  end loop;
  -- 4 each release's operational state on its deploy check
  update pipeline.integration_deploy_checks c set operational_status = s.st, operational_checked_at = now()
    from (select v.deploy_check_id id, case when bool_or(v.status = 'failed_first_run') then 'failed_first_run' when bool_or(v.status = 'awaiting_first_run') then 'awaiting_first_run'
                 else 'operationally_verified' end st from pipeline.release_job_verifications v where v.deploy_check_id is not null group by 1) s
   where c.id = s.id and c.operational_status is distinct from s.st;
  select count(*) into v_max from pipeline.release_job_verifications where status = 'awaiting_first_run';
  return v_n || jsonb_build_object('awaiting', v_max);
end $function$;
revoke all on function security.first_run_verify_jobs_v1() from public, anon, authenticated;

-- 6. the recovery loop: one canonical issue per failure; code and SQL defects become owned engineering work -------------------------------------------
create or replace function security.recovery_issue_text_v1(i pipeline.integration_issues) returns text
language sql stable set search_path to '' as $function$
  select concat_ws(' ', i.title, i.failure, i.subsystem, i.evidence->'detail'->>'last_error', i.evidence->>'message', i.evidence->'first_run'->>'message', i.evidence::text)
$function$;
revoke all on function security.recovery_issue_text_v1(pipeline.integration_issues) from public, anon, authenticated;

create or replace function security.recovery_link_duplicates_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §5; IQ-00239 and IQ-00241): an open issue that names a job (evidence.job, evidence.detail.job, or the job's name in
-- its title, failure or subsystem) and carries the same error class (pipeline.recovery_error_classes) as that job's own job_failed: issue describes
-- the same failure. The canonical issue is the one furthest along its lifecycle, then the most severe, then the oldest; the other is superseded into
-- it exactly as the controller supersedes (superseded_by, supersedes, its evidence carried over under evidence.superseded, a history line on both,
-- ops_state superseded) and a supersede_into_owner run is recorded, so the controller closes it when the canonical issue is verified, or unlinks it
-- if it is seen again after that. History is kept; nothing is closed here.
declare a pipeline.integration_issues; b pipeline.integration_issues; o pipeline.integration_issues; s pipeline.integration_issues; v_job text; v_cls pipeline.recovery_error_classes;
        v_max int := security.pipeline_num_v1('integration.entity_ids_max', 500)::int; v_n int := 0;
        v_rank jsonb := '{"production_verification": 7, "deployed": 6, "integration_testing": 5, "code_ready": 4, "in_progress": 3, "assigned": 2, "triaged": 1, "reopened": 1, "detected": 0}'::jsonb;
begin
  if security.pipeline_num_v1('recovery.link_on', 1) < 1 then return jsonb_build_object('off', true); end if;
  for a in select * from pipeline.integration_issues x where x.status <> 'closed' and x.superseded_by is null and x.fingerprint like 'job_failed:%'
            order by x.last_observed_at desc limit security.pipeline_num_v1('recovery.issues_per_run', 200)::int loop
    v_job := substr(a.fingerprint, 12);
    v_cls := security.recovery_error_class_v1(security.recovery_issue_text_v1(a));
    continue when v_cls.pattern is null;
    for b in select * from pipeline.integration_issues x where x.status <> 'closed' and x.superseded_by is null and x.id <> a.id and x.fingerprint not like 'job_failed:%'
               and (x.evidence->>'job' = v_job or x.evidence->'detail'->>'job' = v_job or position(v_job in concat_ws(' ', x.title, x.failure, x.subsystem)) > 0)
               and security.recovery_issue_text_v1(x) ilike v_cls.pattern
             order by x.id loop
      select * into o from pipeline.integration_issues x where x.id = a.id;  -- a may have changed in this loop
      exit when o.superseded_by is not null;
      if coalesce((v_rank->>b.status)::int, 0) > coalesce((v_rank->>o.status)::int, 0)
         or (coalesce((v_rank->>b.status)::int, 0) = coalesce((v_rank->>o.status)::int, 0) and (b.severity < o.severity or (b.severity = o.severity and (b.detected_at, b.id) < (o.detected_at, o.id)))) then
        s := o; o := b;   -- b is canonical, a is the duplicate
      else
        s := b;           -- a is canonical, b is the duplicate
      end if;
      perform 1 from pipeline.integration_issues x where x.id in (o.id, s.id) order by x.id for update;
      update pipeline.integration_issues set superseded_by = o.id, ops_state = 'superseded', next_action_at = now(), remedy_code = 'supersede_into_owner', updated_at = now() where id = s.id;
      update pipeline.integration_issues i set supersedes = (select coalesce(array_agg(distinct x), '{}') from unnest(i.supersedes || s.id) x),
             evidence = i.evidence || jsonb_build_object('superseded', coalesce(i.evidence->'superseded', '{}'::jsonb) || jsonb_build_object(s.issue_ref,
                        jsonb_build_object('fingerprint', s.fingerprint, 'title', s.title, 'failure', left(s.failure, 500), 'evidence', s.evidence, 'detected_at', s.detected_at,
                                           'providers', cardinality(s.provider_ids), 'courses', cardinality(s.course_ids), 'linked_by', 'first-run-verify', 'error_class', v_cls.error_class))),
             provider_ids = (select coalesce(array_agg(distinct x), '{}') from unnest(i.provider_ids || s.provider_ids) x)[1:v_max],
             course_ids = (select coalesce(array_agg(distinct x), '{}') from unnest(i.course_ids || s.course_ids) x)[1:v_max], updated_at = now()
       where i.id = o.id;
      insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail) values
        (s.id, 'updated', s.status, s.status, 'first-run-verify', 'Same failure as ' || o.issue_ref || ' (job ' || v_job || ', ' || v_cls.error_class || '): linked as its duplicate; closes with it',
         jsonb_build_object('superseded_by', o.id, 'job', v_job, 'error_class', v_cls.error_class, 'pattern', v_cls.pattern)),
        (o.id, 'updated', o.status, o.status, 'first-run-verify', 'Canonical issue for ' || s.issue_ref || ' (job ' || v_job || ', ' || v_cls.error_class || '); its evidence is carried over',
         jsonb_build_object('supersedes', s.id, 'job', v_job, 'error_class', v_cls.error_class));
      if exists (select 1 from pipeline.ops_remedies m where m.code = 'supersede_into_owner') then
        insert into pipeline.ops_remedy_runs(issue_id, remedy_code, finished_at, before, result, evidence)
        values (s.id, 'supersede_into_owner', now(), jsonb_build_object('status', s.status), 'acted',
                jsonb_build_object('action', jsonb_build_object('owner', o.id, 'owner_ref', o.issue_ref, 'job', v_job, 'error_class', v_cls.error_class), 'linked_by', 'first-run-verify'));
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return jsonb_build_object('linked', v_n);
end $function$;
revoke all on function security.recovery_link_duplicates_v1() from public, anon, authenticated;

create or replace function security.recovery_route_engineering_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §5 "a SQL or code defect requiring development must become an owned engineering remediation task automatically,
-- with evidence and a bounded next checkpoint"). An open, canonical issue whose text carries an error class of pipeline.recovery_error_classes (a
-- class with repeat_setting only after that many consecutive failures or observations) gets, once: assignee and remediation_owner engineering,
-- the class's root cause class where none was recorded, status assigned (from detected, triaged or reopened), remediation_status engineering_open
-- (awaiting_first_run when its fix is already deployed), the error text, run id and job in remediation_evidence, and the next checkpoint
-- (recovery.engineering_checkpoint_hours). At each checkpoint passed without a change of status, one history line and the next checkpoint. Writes
-- through security.integration_issue_transition_v1; never merges, deploys, grants a budget, changes a setting or decides Layer 4 work.
declare i pipeline.integration_issues; v_cls pipeline.recovery_error_classes; v_text text; v_job text; v_run text; v_err text; v_h int := security.pipeline_num_v1('recovery.engineering_checkpoint_hours', 4)::int;
        v_to text; v_rem text; v_new int := 0; v_chk int := 0; v_rep numeric;
begin
  if security.pipeline_num_v1('recovery.route_on', 1) < 1 then return jsonb_build_object('off', true); end if;
  for i in select * from pipeline.integration_issues x where x.status <> 'closed' and x.superseded_by is null
             and (x.remediation_owner is null or x.remediation_checkpoint_at <= now())
            order by x.last_observed_at desc limit security.pipeline_num_v1('recovery.issues_per_run', 200)::int loop
    v_text := security.recovery_issue_text_v1(i);
    if i.remediation_owner is null then
      v_cls := security.recovery_error_class_v1(v_text);
      continue when v_cls.pattern is null;
      if v_cls.repeat_setting is not null then
        v_rep := security.pipeline_num_v1(v_cls.repeat_setting, 3);
        continue when not (coalesce((i.evidence->'detail'->>'last_three_failed')::boolean, false) or coalesce((i.evidence->>'failed_runs')::numeric, 0) >= v_rep or i.retry_count >= v_rep);
      end if;
      v_job := coalesce(case when i.fingerprint like 'job_failed:%' then substr(i.fingerprint, 12) end, i.evidence->>'job', i.evidence->'detail'->>'job', i.evidence->'first_run'->>'job');
      v_run := coalesce(i.evidence->'first_run'->>'runid', i.evidence->>'last_runid', i.evidence->'detail'->>'last_runid');
      v_err := left(coalesce(i.evidence->'first_run'->>'message', i.evidence->'detail'->>'last_error', i.evidence->>'message', i.failure), 600);
      v_rem := case when i.status in ('integration_testing', 'deployed', 'production_verification') then 'awaiting_first_run' else 'engineering_open' end;
      v_to := case when i.status in ('detected', 'triaged', 'reopened') then 'assigned' end;
      perform security.integration_issue_transition_v1(i.id, v_to, 'first-run-verify',
        'Owned engineering remediation (' || v_cls.error_class || ': ' || v_cls.title || '); next checkpoint ' || (now() + make_interval(hours => v_h)),
        jsonb_strip_nulls(jsonb_build_object('assignee', coalesce(i.assignee, v_cls.owner),
          'root_cause_class', case when i.root_cause_class = 'unclassified' then v_cls.root_cause_class end,
          'evidence', jsonb_build_object('engineering_remediation', jsonb_build_object('error_class', v_cls.error_class, 'error', v_err, 'runid', v_run, 'job', v_job)))));
      update pipeline.integration_issues set remediation_owner = v_cls.owner, remediation_status = v_rem, remediation_checkpoint_at = now() + make_interval(hours => v_h),
             remediation_evidence = jsonb_strip_nulls(jsonb_build_object('error_class', v_cls.error_class, 'pattern', v_cls.pattern, 'error', v_err, 'runid', v_run, 'job', v_job,
                                    'routed_at', now(), 'status_at_checkpoint', coalesce(v_to, i.status)))
       where id = i.id;
      v_new := v_new + 1;
    else
      -- a checkpoint passed: record it once and set the next (a moved issue resets the baseline)
      perform security.integration_issue_transition_v1(i.id, null, 'first-run-verify',
        case when i.status = i.remediation_evidence->>'status_at_checkpoint'
             then 'Engineering checkpoint passed with no change (still ' || i.status || ', remediation ' || coalesce(i.remediation_status, '?') || '); next checkpoint '
             else 'Engineering checkpoint: moved to ' || i.status || ' (remediation ' || coalesce(i.remediation_status, '?') || '); next checkpoint ' end
          || (now() + make_interval(hours => v_h)), '{}'::jsonb);
      update pipeline.integration_issues set remediation_checkpoint_at = now() + make_interval(hours => v_h),
             remediation_evidence = coalesce(remediation_evidence, '{}'::jsonb) || jsonb_build_object('status_at_checkpoint', i.status, 'last_checkpoint', now())
       where id = i.id;
      v_chk := v_chk + 1;
    end if;
  end loop;
  return jsonb_build_object('routed', v_new, 'checkpoints', v_chk);
end $function$;
revoke all on function security.recovery_route_engineering_v1() from public, anon, authenticated;

-- 7. the job ------------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.first_run_verify_tick_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §3-§5): job first-run-verify. Four isolated steps: a step that fails is recorded in the result and the others still
-- run (the failure of one never rolls back another's records).
declare v jsonb := '{}'::jsonb; v_r jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247:first-run-verify')) then return jsonb_build_object('busy', true); end if;  -- fixed: one check at a time
  if security.pipeline_num_v1('frv.on', 1) >= 1 then
    begin v_r := security.first_run_verify_jobs_v1(); exception when others then v_r := jsonb_build_object('error', left(sqlerrm, 300)); end;
    v := v || jsonb_build_object('first_runs', v_r);
  end if;
  begin v_r := security.progress_read_v1(); exception when others then v_r := jsonb_build_object('error', left(sqlerrm, 300)); end;
  v := v || jsonb_build_object('progress', v_r);
  begin v_r := security.recovery_link_duplicates_v1(); exception when others then v_r := jsonb_build_object('error', left(sqlerrm, 300)); end;
  v := v || jsonb_build_object('link', v_r);
  begin v_r := security.recovery_route_engineering_v1(); exception when others then v_r := jsonb_build_object('error', left(sqlerrm, 300)); end;
  v := v || jsonb_build_object('route', v_r);
  return v;
end $function$;
revoke all on function security.first_run_verify_tick_v1() from public, anon, authenticated;

-- 8. the scorecard (§10), read only -----------------------------------------------------------------------------------------------------------------
create or replace function security.self_sustainability_v1(p_window_hours int default 24) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 (mandate 4 Nov 2026 08:16 §10): the ten self-sustainability measures from existing records, each with its evidence and a verdict of
-- met, not_met or not_measured (null means not held, never zero). A window with no errors but no eligible data processed is not met unless the
-- absence of eligible work is proven (every transition's zero reason is no_eligible_work). Reads only.
declare v_since timestamptz := now() - make_interval(hours => p_window_hours); v_scan int := security.pipeline_num_v1('ops.runs_scan', 20000)::int;
        v_runs int; v_failed int; v_last_fail timestamptz; v_tr jsonb; v_created numeric; v_stalled int; v_justified int; v_technical int; v_noelig boolean;
        v_auto_det int; v_man_det int; v_owned int; v_unowned int; v_rem_ok int; v_rem_fail int; v_wc_rec int; v_wc_parked_no_time int;
        v_sch_adm numeric; v_aer_adm numeric; v_sch_pub numeric; v_aer_pub numeric; v_l4 int; v_int int; v_ai numeric; v_ai_cap numeric; v_fc numeric;
        v_rel jsonb; v_dc int; v_out jsonb;
begin
  select count(*), count(*) filter (where d.status = 'failed'), max(d.start_time) filter (where d.status = 'failed') into v_runs, v_failed, v_last_fail
    from (select x.status, x.start_time from cron.job_run_details x order by x.runid desc limit v_scan) d where d.start_time >= v_since;
  select coalesce(jsonb_object_agg(t.key, jsonb_build_object('created', t.output_created, 'eligible', t.input_eligible, 'zero', t.zero_reason, 'stalled', t.stalled,
           'admitted', t.output_admitted, 'published', t.output_published, 'last_advanced_at', t.last_advanced_at, 'measured_at', t.measured_at)), '{}'::jsonb),
         sum(t.output_created), count(*) filter (where t.stalled), count(*) filter (where t.zero_reason in ('no_eligible_work', 'cap_reached', 'blocked_authority', 'correctly_excluded')),
         count(*) filter (where t.zero_reason = 'technical_failure'), bool_and(t.zero_reason = 'no_eligible_work')
    into v_tr, v_created, v_stalled, v_justified, v_technical, v_noelig from pipeline.progress_transitions t;
  select count(*) filter (where i.validation_layer <> 'manual'), count(*) filter (where i.validation_layer = 'manual') into v_auto_det, v_man_det
    from pipeline.integration_issues i where i.detected_at >= v_since;
  select count(*) filter (where i.remediation_owner is not null or i.ops_state in ('verifying', 'verified', 'remedying', 'superseded')), count(*) filter (where i.remediation_owner is null and coalesce(i.assignee, '') = '' and coalesce(i.ops_state, '') not in ('verifying', 'verified', 'remedying', 'superseded'))
    into v_owned, v_unowned from pipeline.integration_issues i where i.status <> 'closed';
  select count(*) filter (where r.result = 'verified'), count(*) filter (where r.result = 'verify_failed') into v_rem_ok, v_rem_fail
    from pipeline.ops_remedy_runs r join pipeline.ops_remedies m on m.code = r.remedy_code where r.started_at >= v_since and m.authority = 'auto';
  select count(*) filter (where w.recovered_at >= v_since), count(*) filter (where w.stage = 'parked' and w.next_eligible_at is null) into v_wc_rec, v_wc_parked_no_time from pipeline.work_items w;
  select t.output_admitted into v_sch_adm from pipeline.progress_transitions t where t.key = 'sch_admission';
  select t.output_admitted into v_aer_adm from pipeline.progress_transitions t where t.key = 'aer_active_records';
  select t.output_published into v_sch_pub from pipeline.progress_transitions t where t.key = 'sch_publication';
  select t.output_published into v_aer_pub from pipeline.progress_transitions t where t.key = 'aer_publication';
  select count(*) into v_l4 from pipeline.layer4_review_items i where i.status = 'pending';
  if to_regclass('pipeline.layer4_interventions') is not null then
    execute 'select count(*) from pipeline.layer4_interventions where status = ''awaiting_input''' into v_int;
  end if;
  select coalesce(sum(l.cost_usd), 0) into v_ai from pipeline.ai_spend_ledger l where l.at >= v_since;
  v_ai_cap := security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', null);
  select coalesce(sum(u.units), 0) into v_fc from pipeline.coverage_vendor_usage u where u.at >= v_since;
  select coalesce(jsonb_object_agg(z.status, z.n), '{}'::jsonb) into v_rel from (select v.status, count(*) n from pipeline.release_job_verifications v group by 1) z;
  select count(*) into v_dc from pipeline.integration_deploy_checks d where d.checked_at >= v_since;
  v_out := jsonb_build_object('window_hours', p_window_hours, 'since', v_since, 'measures', jsonb_build_array(
    jsonb_build_object('measure', 'scheduled_job_reliability', 'runs', v_runs, 'failed', v_failed, 'justified_idle_transitions', v_justified,
      'verdict', case when v_runs is null or v_runs = 0 then 'not_measured' when v_failed = 0 then 'met' else 'not_met' end, 'basis', 'cron.job_run_details (newest ops.runs_scan runs); progress zero reasons'),
    jsonb_build_object('measure', 'automatic_diagnosis', 'detected_automatically', v_auto_det, 'raised_by_hand', v_man_det, 'open_owned', v_owned, 'open_unowned', v_unowned,
      'verdict', case when v_man_det = 0 and v_unowned = 0 then 'met' else 'not_met' end, 'basis', 'integration issues by validation layer; owner, remediation owner or controller state'),
    jsonb_build_object('measure', 'automatic_recovery', 'remedies_verified', v_rem_ok, 'remedies_failed', v_rem_fail,
      'verdict', case when v_rem_ok + v_rem_fail = 0 then 'not_measured' when v_rem_fail = 0 then 'met' else 'not_met' end, 'basis', 'pipeline.ops_remedy_runs of authority auto'),
    jsonb_build_object('measure', 'queue_continuity', 'work_items_recovered', v_wc_rec, 'parked_without_next_time', v_wc_parked_no_time, 'stalled_transitions', v_stalled,
      'verdict', case when v_stalled is null then 'not_measured' when v_stalled = 0 and v_wc_parked_no_time = 0 then 'met' else 'not_met' end, 'basis', 'pipeline.work_items; pipeline.progress_transitions'),
    jsonb_build_object('measure', 'source_to_admission_yield', 'scholarships_admitted', v_sch_adm, 'aer_rows_admitted', v_aer_adm,
      'verdict', case when v_sch_adm is null and v_aer_adm is null then 'not_measured' when coalesce(v_sch_adm, 0) > 0 and coalesce(v_aer_adm, 0) > 0 then 'met' else 'not_met' end,
      'basis', 'progress transitions sch_admission and aer_active_records'),
    jsonb_build_object('measure', 'admission_to_publication_yield', 'scholarships_published', v_sch_pub, 'aer_rows_on_published_providers', v_aer_pub,
      'verdict', case when v_sch_pub is null and v_aer_pub is null then 'not_measured' else 'needs_read_back' end,
      'basis', 'progress transitions sch_publication and aer_publication; Website API v2, Wix and Zoho read-back is a separate check (consumer-api-guard and the Integration Controller)'),
    jsonb_build_object('measure', 'human_intervention', 'layer4_pending', v_l4, 'interventions_awaiting_input', v_int,
      'verdict', 'reported', 'basis', 'pipeline.layer4_review_items; pipeline.layer4_interventions when present'),
    jsonb_build_object('measure', 'spending', 'ai_usd', round(v_ai, 3), 'ai_daily_ceiling_usd', v_ai_cap, 'firecrawl_units', v_fc,
      'verdict', case when v_ai_cap is null then 'not_measured' when v_ai <= v_ai_cap * greatest(p_window_hours, 1) / 24.0 then 'met' else 'not_met' end,
      'basis', 'pipeline.ai_spend_ledger against budgets.ai_daily_ceiling_usd; pipeline.coverage_vendor_usage'),
    jsonb_build_object('measure', 'release_correctness', 'first_run_verifications', v_rel, 'deploy_checks_in_window', v_dc,
      'verdict', case when v_rel = '{}'::jsonb then 'not_measured' when coalesce((v_rel->>'failed_first_run')::int, 0) = 0 and coalesce((v_rel->>'awaiting_first_run')::int, 0) = 0 then 'met' else 'not_met' end,
      'basis', 'pipeline.release_job_verifications; pipeline.integration_deploy_checks'),
    jsonb_build_object('measure', 'unattended_operation', 'last_job_failure', v_last_fail, 'hours_since_failure', round(extract(epoch from now() - coalesce(v_last_fail, v_since)) / 3600.0, 1),
      'eligible_data_processed', coalesce(v_created, 0) > 0, 'absence_of_work_proven', coalesce(v_noelig, false),
      'verdict', case when v_last_fail is null and (coalesce(v_created, 0) > 0 or coalesce(v_noelig, false)) and coalesce(v_technical, 0) = 0 then 'met' else 'not_met' end,
      'basis', 'no failed run in the window, eligible data processed (or no eligible work proven), no technical zero')),
    'transitions', v_tr);
  return v_out;
end $function$;
revoke all on function security.self_sustainability_v1(integer) from public, anon, authenticated;
comment on function security.self_sustainability_v1(integer) is 'CF-247 mandate 4 Nov 2026 08:16 §10: the ten self-sustainability measures from existing records (a section of security.ops_report_v1). Read only.';

select pg_temp.edit_once('security.ops_report_v1(integer)', '3ba694dc078995d88a983e8e92b2f425', '518b5bf873549931a15d4173fef793d5',
  array[array[$o$  return v_out;
end $o$, $n$  -- self-sustainability scorecard (Platform Admin mandate 4 Nov 2026 08:16 §10): the ten measures (security.self_sustainability_v1)
  begin
    v_out := v_out || jsonb_build_object('self_sustainability', security.self_sustainability_v1(p_window_hours));
  exception when others then v_out := v_out || jsonb_build_object('self_sustainability', jsonb_build_object('error', left(sqlerrm, 200)));
  end;
  return v_out;
end $n$]], array[1]);

-- 9. the controller routes a job's code or SQL defect to a release, not to a decision (workstream A's contract; no controller function is edited) ------
select security.ops_root_cause_register_v1('first_run_sql_defect', jsonb_build_object('class', 'rule',
  'title', 'A scheduled job fails on a code or SQL defect (often its first production run)',
  'description', 'The job fails with an error a retry cannot clear: one statement writing the same key twice, a constraint, a missing column, table or function, input of an unexpected shape, a syntax error. First seen as unclassified on new jobs, whose first run has no earlier success for the release-regression rule (IQ-00239, scholarship-coverage-classify, 4 Nov 2026). The fix is development through the release gates; job first-run-verify owns it as engineering work and follows the fix to its first run.',
  'detect', jsonb_build_object('priority', 7, 'confidence', 0.85, 'route', 'needs_release',
    'all', jsonb_build_array(jsonb_build_object('signal', 'job_failing')),
    'any', jsonb_build_array(jsonb_build_object('text', '(cannot affect row a second time|more than one row returned|query returned more than one row|violates (check|unique|not-null|foreign key) constraint|column .* does not exist|relation .* does not exist|function .* does not exist|invalid input syntax|division by zero|syntax error)')),
    'recommend', 'Engineering fixes it through the release gates with a production-shaped fixture; the release registers the job for first-run verification (security.release_first_run_register_v1).')));
select security.ops_remedy_register_v1('engineering_remediation', jsonb_build_object('authority', 'release', 'treats', jsonb_build_array('first_run_sql_defect'),
  'title', 'Owned engineering remediation, then first-run verification of the fix',
  'notes', 'Job first-run-verify sets assignee engineering, the evidence and a bounded checkpoint (recovery.engineering_checkpoint_hours); the fix is released through the normal gates and its first scheduled run is verified (pipeline.release_job_verifications). Never merged or deployed automatically.'));

-- 10. job (G1), catalogue first ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('first-run-verify', 'Platform upkeep', 18, 'First-run verification, progress and recovery routing',
  'At :02 and :32 (after the operations controller at :24 and :54; clear of :x3, :x5, :x9, :35-:42 and :47-:48): follows each released scheduled job to its first production run and records awaiting_first_run, operationally_verified or failed_first_run (a failed first run raises the job''s own issue); reads every scholarship and AER transition (input, output, rejections, parked work, downstream, admitted, published, last advancement) with a reason for every zero, and raises a stalled transition; links issues that describe the same failure (one canonical issue); makes code and SQL defects owned engineering work with evidence and a checkpoint. Settings frv.*, progress.*, recovery.*. Reads and records only; spends nothing.',
  6, false, null)
on conflict (jobname) do nothing;
do $j$ begin
  if not exists (select 1 from cron.job where jobname = 'first-run-verify') then
    perform cron.schedule('first-run-verify', '2,32 * * * *', 'select security.first_run_verify_tick_v1()');
  end if;
end $j$;

-- 11. component register (housekeeping) --------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'first-run-verify', 'Platform', 'Platform upkeep', 'First-run verification, progress contract and recovery routing', 'active', '{}', '20261104460000'),
 ('table', 'pipeline.release_job_verifications', 'Platform', 'Platform upkeep', 'First run of each released scheduled job (V3 release contract)', 'active', '{}', '20261104460000'),
 ('table', 'pipeline.progress_transitions', 'Platform', 'Platform upkeep', 'Producer-to-consumer progress contract, one record per transition', 'active', '{}', '20261104460000'),
 ('table', 'pipeline.progress_observations', 'Platform', 'Platform upkeep', 'Readings of the progress contract', 'active', '{}', '20261104460000'),
 ('table', 'pipeline.recovery_error_classes', 'Platform', 'Platform upkeep', 'Errors that make a job failure owned engineering work', 'active', '{}', '20261104460000'),
 ('function', 'security.release_first_run_register_v1', 'Platform', 'Platform upkeep', 'Release controller: register changed jobs for first-run verification', 'active', '{}', '20261104460000'),
 ('function', 'security.first_run_verify_tick_v1', 'Platform', 'Platform upkeep', 'Job first-run-verify', 'active', '{}', '20261104460000'),
 ('function', 'security.progress_measure_v1', 'Platform', 'Platform upkeep', 'Progress contract: one transition counted', 'active', '{}', '20261104460000'),
 ('function', 'security.self_sustainability_v1', 'Platform', 'Platform upkeep', 'The ten self-sustainability measures (in ops_report_v1)', 'active', '{}', '20261104460000')
on conflict do nothing;

-- 12. post-check -----------------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if md5(pg_get_functiondef('security.ops_report_v1(integer)'::regprocedure)) <> '518b5bf873549931a15d4173fef793d5' then raise exception 'post-check: ops_report_v1'; end if;
  if md5(pg_get_functiondef('security.integration_issue_upsert_v1(jsonb,text)'::regprocedure)) <> 'b0a1a64982680ae5d588c2d73b779e4e' then raise exception 'post-check: upsert unchanged'; end if;
  if (select count(*) from pipeline.progress_transitions) <> 16 then raise exception 'post-check: 16 transitions'; end if;
  if (select count(*) from pipeline.progress_transitions where next_key is null) <> 2 then raise exception 'post-check: two chain ends'; end if;
  if (select count(*) from cron.job where jobname = 'first-run-verify') <> 1 then raise exception 'post-check: job'; end if;
  if (select count(*) from pipeline.automation_catalogue where jobname = 'first-run-verify') <> 1 then raise exception 'post-check: catalogue'; end if;
  if security.pipeline_num_v1('recovery.close_on_verified_on', 1) <> 0 then raise exception 'post-check: closing on verification ships off'; end if;
  if (select authority from pipeline.ops_remedies where code = 'engineering_remediation') <> 'release' then raise exception 'post-check: engineering remediation is never automatic'; end if;
end $$;
