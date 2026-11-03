-- CF-247 P0 Autonomous AI Operations, workstream A: the shared operations contract and the AI Operations Controller (root-cause engine)
-- (Platform Admin mandate 3 Nov 2026 15:37, admin docs/platform/nz-enrichment-brief/2026-11-03-p0-autonomous-ai-operations-mandate-1537.md
-- §2, §3, §7, §13, §15, §16; architecture and ownership 2026-11-03-ai-operations-workstreams-1540.md §2-§3).
-- Why: the platform detects well but nothing diagnoses, remedies or verifies on its own. On 3 Nov 2026 15:41 AEDT (read-only) the integration
--   queue held 68 issues: 48 detected, 8 triaged, 5 deployed, 7 closed. No issue had a recorded cause beyond root_cause_class, no correction
--   was ever executed or verified by the platform, and issues whose condition had cleared hours earlier stayed open until a person closed them.
-- What: the missing lifecycle stages on the existing queue (pipeline.integration_issues), not a new queue:
--   Classify -> Correlate -> Diagnose -> Select remedy -> Execute -> Validate -> Learn -> Close.
--   Part 1 (the shared contract; other workstreams code against these exact names): pipeline.ops_root_causes, pipeline.ops_remedies,
--     pipeline.ops_remedy_runs, pipeline.ops_outcome_codes (the eight job outcomes of mandate §7), pipeline.admin_jobs.outcome and
--     outcome_detail (nullable; the state check is unchanged), five columns on pipeline.integration_issues, and
--     security.ops_root_cause_register_v1, security.ops_remedy_register_v1, security.job_outcome_set_v1.
--   Part 2 (the controller): see the header of part 2 below.
-- Replaces: nothing (new stages on the existing queue; integration-validate, the yield checks and the queue functions are not edited)
-- Retires: nothing
-- Nothing is dropped or deleted. No existing function is edited. Consumer API untouched (G3): no consumer function, table, column or edge
-- function changes. No Firecrawl or AI spend.

-- >>> contract (tests/fixtures/ops-controller/stub-ops-contract.sql is this section, byte for byte) ------------------------------------------
-- The authority boundary (mandate §2, §6, §15 "the AI must never grant itself broader permissions"): while the controller runs a remedy it sets
-- cf247.ops_remedy to on for that call only. Writes that a remedy may never make are refused in data (triggers in part 2) while it is on.
create or replace function security.ops_remedy_guard_active_v1() returns boolean
language sql stable set search_path to '' as $function$
  select coalesce(current_setting('cf247.ops_remedy', true), '') = 'on'
$function$;
revoke all on function security.ops_remedy_guard_active_v1() from public, anon, authenticated;

create table if not exists pipeline.ops_root_causes (
  code text primary key check (code ~ '^[a-z][a-z0-9_]*$'),
  class text not null check (class in ('transient', 'data', 'rule', 'policy', 'dependency', 'capacity')),
  title text not null,
  description text,
  detect jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
comment on table pipeline.ops_root_causes is 'CF-247 P0 autonomous operations (mandate 3 Nov 2026 15:37 §3): the root-cause taxonomy. One row per cause: its class (transient, data, rule, policy, dependency, capacity), a plain description and detect, the deterministic rule the controller''s classifier evaluates (security.ops_diagnose_v1; grammar in that function''s comment). Written only through security.ops_root_cause_register_v1, by a release; never by a remedy (refused in data). Never read by the consumer API.';
alter table pipeline.ops_root_causes enable row level security;
revoke all on pipeline.ops_root_causes from public, anon, authenticated;

create table if not exists pipeline.ops_remedies (
  code text primary key check (code ~ '^[a-z][a-z0-9_]*$'),
  title text not null,
  treats text[] not null default '{}',
  authority text not null check (authority in ('auto', 'release', 'admin')),
  action_fn regprocedure,
  verify_fn regprocedure,
  max_attempts_key text,
  cooldown_key text,
  active boolean not null default true,
  notes text
);
comment on table pipeline.ops_remedies is 'CF-247 P0 autonomous operations (mandate §3, §15): the remedy registry. treats names the root causes (pipeline.ops_root_causes) a remedy applies to; authority auto is executed by the controller (job ops-controller), release means a code change through the release gates and admin a Platform Admin decision (both only route the issue). action_fn(p_issue bigint) returns jsonb {ok, changed, evidence}; verify_fn(p_issue bigint) returns jsonb {passed, measure, evidence}, called on a later controller run than the action. max_attempts_key and cooldown_key name pipeline settings. Written only through security.ops_remedy_register_v1, by a release; never by a remedy (refused in data). Never read by the consumer API.';
alter table pipeline.ops_remedies enable row level security;
revoke all on pipeline.ops_remedies from public, anon, authenticated;

create table if not exists pipeline.ops_remedy_runs (
  id bigserial primary key,
  issue_id bigint not null references pipeline.integration_issues(id),
  remedy_code text not null references pipeline.ops_remedies(code),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  before jsonb,
  after jsonb,
  result text,
  evidence jsonb not null default '{}'::jsonb
);
comment on table pipeline.ops_remedy_runs is 'CF-247 P0 autonomous operations (mandate §3, §13): every remedy execution by the controller: the issue, the remedy, the measure before the action, the measure after verification, the result (running, acted, action_failed, refused_guard, verified, verify_failed) and the evidence (the action''s answer, then the verification''s). A run is verified only on a later controller run than its action. Never read by the consumer API.';
create index if not exists ops_remedy_runs_issue_idx on pipeline.ops_remedy_runs (issue_id, started_at desc);
create index if not exists ops_remedy_runs_open_idx on pipeline.ops_remedy_runs (result) where result in ('running', 'acted');
alter table pipeline.ops_remedy_runs enable row level security;
revoke all on pipeline.ops_remedy_runs from public, anon, authenticated;
revoke all on sequence pipeline.ops_remedy_runs_id_seq from public, anon, authenticated;

create table if not exists pipeline.ops_outcome_codes (
  code text primary key,
  title text not null,
  counts_as_movement boolean not null default false
);
comment on table pipeline.ops_outcome_codes is 'CF-247 P0 autonomous operations (mandate §7): the explicit outcome of a job or task, beside its state (pipeline.admin_jobs.outcome). Only succeeded_with_result counts as data movement; a cancellation is never read as success or as not needed. Never read by the consumer API.';
alter table pipeline.ops_outcome_codes enable row level security;
revoke all on pipeline.ops_outcome_codes from public, anon, authenticated;
insert into pipeline.ops_outcome_codes(code, title, counts_as_movement) values
 ('succeeded_with_result', 'Succeeded with a measurable result', true),
 ('succeeded_no_movement', 'Succeeded without data movement', false),
 ('not_needed', 'Not needed', false),
 ('deferred_dependency', 'Deferred for a dependency', false),
 ('blocked_policy', 'Blocked by policy', false),
 ('blocked_evidence', 'Blocked by evidence', false),
 ('failed_retryable', 'Failed and retryable', false),
 ('failed_remediation', 'Failed and requiring remediation', false)
on conflict (code) do nothing;

-- the job outcome beside the job state (backwards compatible: nullable, the state check is unchanged, nothing is rewritten)
alter table pipeline.admin_jobs add column if not exists outcome text references pipeline.ops_outcome_codes(code);
alter table pipeline.admin_jobs add column if not exists outcome_detail jsonb;
comment on column pipeline.admin_jobs.outcome is 'CF-247 P0 (mandate §7): the explicit outcome (pipeline.ops_outcome_codes), set through security.job_outcome_set_v1. Null for history recorded before it existed.';

-- the controller's columns on the existing queue
alter table pipeline.integration_issues add column if not exists correlation_key text;
alter table pipeline.integration_issues add column if not exists diagnosis jsonb;
alter table pipeline.integration_issues add column if not exists remedy_code text;
alter table pipeline.integration_issues add column if not exists remedy_attempts int not null default 0;
alter table pipeline.integration_issues add column if not exists next_action_at timestamptz;
comment on column pipeline.integration_issues.diagnosis is 'CF-247 P0 (mandate §3): {root_cause, confidence 0..1, evidence[], method, at}, written by the controller''s classifier (security.ops_diagnose_v1).';
comment on column pipeline.integration_issues.correlation_key is 'CF-247 P0 (mandate §3): issues that share an upstream cause share this key (security.ops_correlation_key_v1); one open issue per key owns its remedies.';

create or replace function security.ops_root_cause_register_v1(p_code text, p_spec jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 P0 (mandate §3): add or replace a root cause by code (B, C, D, E, F and G register theirs in their own migrations). Spec keys mirror
-- the columns: class, title, description, detect. Refused while a remedy runs (a remedy never changes the taxonomy).
declare v_new boolean;
begin
  if security.ops_remedy_guard_active_v1() then raise exception 'ops guard: a remedy cannot change the root-cause register' using errcode = '42501'; end if;
  if coalesce(p_code, '') !~ '^[a-z][a-z0-9_]*$' then raise exception 'a root cause code is lower case letters, digits and underscores' using errcode = '22023'; end if;
  if p_spec is null or jsonb_typeof(p_spec) <> 'object' or coalesce(p_spec->>'class', '') not in ('transient', 'data', 'rule', 'policy', 'dependency', 'capacity') then
    raise exception 'root cause %: class must be transient, data, rule, policy, dependency or capacity', p_code using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_spec->>'title', ''))) < 3 then raise exception 'root cause %: give it a title', p_code using errcode = '22023'; end if;
  if p_spec ? 'detect' and jsonb_typeof(p_spec->'detect') <> 'object' then raise exception 'root cause %: detect is an object', p_code using errcode = '22023'; end if;
  v_new := not exists (select 1 from pipeline.ops_root_causes where code = p_code);
  insert into pipeline.ops_root_causes as r(code, class, title, description, detect)
  values (p_code, p_spec->>'class', btrim(p_spec->>'title'), p_spec->>'description', coalesce(p_spec->'detect', '{}'::jsonb))
  on conflict (code) do update set class = excluded.class, title = excluded.title, description = excluded.description, detect = excluded.detect;
  return jsonb_build_object('code', p_code, 'action', case when v_new then 'created' else 'replaced' end);
end $function$;
revoke all on function security.ops_root_cause_register_v1(text, jsonb) from public, anon, authenticated;

create or replace function security.ops_remedy_register_v1(p_code text, p_spec jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 P0 (mandate §3, §15): add or replace a remedy by code. Spec keys mirror the columns: title, treats (root-cause codes), authority
-- (auto, release, admin), action_fn and verify_fn (text such as 'security.x_v1(bigint)'), max_attempts_key, cooldown_key, active, notes.
-- Refused: a function that does not exist, or that is not (bigint) returning jsonb, or is not SQL or PL/pgSQL; an auto remedy without both an
-- action and a verification; a root cause that is not registered; a settings key that does not exist; a function whose text reaches the
-- authority boundary (the guard switch, trigger switches, the remedy or root-cause registers, settings ceilings); a call made by a remedy.
declare v_auth text := p_spec->>'authority'; v_treats text[]; v_fn regprocedure; v_vf regprocedure; v_tmp regprocedure; v_k text; v_new boolean; v_bad text;
begin
  if security.ops_remedy_guard_active_v1() then raise exception 'ops guard: a remedy cannot change the remedy register' using errcode = '42501'; end if;
  if coalesce(p_code, '') !~ '^[a-z][a-z0-9_]*$' then raise exception 'a remedy code is lower case letters, digits and underscores' using errcode = '22023'; end if;
  if p_spec is null or jsonb_typeof(p_spec) <> 'object' then raise exception 'remedy %: give a spec object', p_code using errcode = '22023'; end if;
  if coalesce(v_auth, '') not in ('auto', 'release', 'admin') then raise exception 'remedy %: authority must be auto, release or admin', p_code using errcode = '22023'; end if;
  if length(btrim(coalesce(p_spec->>'title', ''))) < 3 then raise exception 'remedy %: give it a title', p_code using errcode = '22023'; end if;
  v_treats := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_spec->'treats', '[]'::jsonb)) x), '{}');
  if cardinality(v_treats) = 0 then raise exception 'remedy %: name the root causes it treats', p_code using errcode = '22023'; end if;
  select string_agg(t, ', ') into v_bad from unnest(v_treats) t where not exists (select 1 from pipeline.ops_root_causes r where r.code = t);
  if v_bad is not null then raise exception 'remedy %: unknown root cause(s) %', p_code, v_bad using errcode = '22023'; end if;
  foreach v_k in array array['action_fn', 'verify_fn'] loop
    if nullif(p_spec->>v_k, '') is not null then
      v_tmp := to_regprocedure(p_spec->>v_k);
      if v_tmp is null then raise exception 'remedy %: % % does not exist', p_code, v_k, p_spec->>v_k using errcode = '42883'; end if;
      if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                      where p.oid = v_tmp and p.pronargs = 1 and p.proargtypes[0] = 'bigint'::regtype and p.prorettype = 'jsonb'::regtype and l.lanname in ('sql', 'plpgsql')) then
        raise exception 'remedy %: % must be an SQL or PL/pgSQL function (p_issue bigint) returning jsonb', p_code, v_k using errcode = '22023';
      end if;
      if pg_get_functiondef(v_tmp) ~* '(set_config|cf247\.ops_remedy|session_replication_role|disable\s+trigger|ops_remedies|ops_root_causes|ops_remedy_register|ops_root_cause_register|max_value|min_value)' then
        raise exception 'remedy %: % reaches the authority boundary (guard switch, triggers, registers or settings ceilings); that is a release change, not a remedy', p_code, v_k using errcode = '42501';
      end if;
      if v_k = 'action_fn' then v_fn := v_tmp; else v_vf := v_tmp; end if;
    end if;
  end loop;
  if v_auth = 'auto' and (v_fn is null or v_vf is null) then raise exception 'remedy %: an auto remedy needs an action and a verification', p_code using errcode = '22023'; end if;
  foreach v_k in array array['max_attempts_key', 'cooldown_key'] loop
    if nullif(p_spec->>v_k, '') is not null and not exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_spec->>v_k) then
      raise exception 'remedy %: setting % (%) does not exist', p_code, p_spec->>v_k, v_k using errcode = '22023';
    end if;
  end loop;
  v_new := not exists (select 1 from pipeline.ops_remedies where code = p_code);
  insert into pipeline.ops_remedies as r(code, title, treats, authority, action_fn, verify_fn, max_attempts_key, cooldown_key, active, notes)
  values (p_code, btrim(p_spec->>'title'), v_treats, v_auth, v_fn, v_vf, nullif(p_spec->>'max_attempts_key', ''), nullif(p_spec->>'cooldown_key', ''),
          coalesce((p_spec->>'active')::boolean, true), p_spec->>'notes')
  on conflict (code) do update set title = excluded.title, treats = excluded.treats, authority = excluded.authority, action_fn = excluded.action_fn,
     verify_fn = excluded.verify_fn, max_attempts_key = excluded.max_attempts_key, cooldown_key = excluded.cooldown_key, active = excluded.active, notes = excluded.notes;
  return jsonb_build_object('code', p_code, 'action', case when v_new then 'created' else 'replaced' end, 'authority', v_auth);
end $function$;
revoke all on function security.ops_remedy_register_v1(text, jsonb) from public, anon, authenticated;

create or replace function security.job_outcome_set_v1(p_job uuid, p_outcome text, p_detail jsonb) returns void
language plpgsql security definer set search_path to '' as $function$
-- CF-247 P0 (mandate §7): record a job's explicit outcome beside its state. The state is not changed; history is never rewritten here (a
-- reconciled outcome for an old job is recorded with its basis in p_detail).
begin
  if not exists (select 1 from pipeline.ops_outcome_codes c where c.code = p_outcome) then
    raise exception 'unknown job outcome % (pipeline.ops_outcome_codes)', p_outcome using errcode = '22023';
  end if;
  update pipeline.admin_jobs set outcome = p_outcome, outcome_detail = coalesce(p_detail, '{}'::jsonb) where id = p_job;
  if not found then raise exception 'no job %', p_job using errcode = 'P0002'; end if;
end $function$;
revoke all on function security.job_outcome_set_v1(uuid, text, jsonb) from public, anon, authenticated;
-- <<< contract ----------------------------------------------------------------------------------------------------------------------------

-- ==========================================================================================================================================
-- Part 2: the AI Operations Controller (workstream A owns it; other workstreams register root causes and remedies through part 1).
-- Why, from production (read-only, 3 Nov 2026 15:41-15:49 AEDT):
--   * 48 of 68 issues sat at detected; 8 of them had a condition the checks had already cleared (4 to 11 hours earlier) and nobody closed them.
--   * Repeats are not new evidence: issue evidence keeps the first observation (an unchanged repeat only bumps retry_count), so IQ-00067 still
--     read "3 of 6 runs failed" while coverage-admit had failed 12 of 12 runs since 13:53. Diagnosis must read the live job runs.
--   * IQ-00067 (coverage-admit) is a permanent rule defect, not load: every run since 13:53 AEDT raised the same refusal from
--     security.layer4_course_link_apply_impl ("this course's page was set by hand"), called by the Decision 263 "take" rule in
--     security.coverage_admission_apply_v1 outside its per-row exception block; the take rule checks held links (IQ-00043) but not
--     pipeline.manual_locks, so one locked course with a differing page rolls the whole batch back (written values too), and the same row
--     returns next run: a retry loop with no new evidence. Fixing that function is not this change (diagnosis only).
-- What (ships ON: it diagnoses, records, routes and closes on verified evidence; it spends nothing, admits nothing and changes no catalogue data):
--   1 settings ops.* (G2), pipeline.ops_checkpoints (hourly and daily report rows), integration_issues.ops_state (needs_release,
--     needs_decision and the controller's own stages; the existing status graph is unchanged).
--   2 the authority boundary in data: while a remedy or a verification runs, triggers refuse writes to the remedy and root-cause registers and
--     remedy runs, settings ceilings (min_value, max_value), budget, admission and controller settings, service-toolset settings, values
--     outside a setting's range, Layer 4 decisions and approvals, automatic admissions, manual locks, paid-service limits and closing an issue.
--   3 correlation (security.ops_issue_subject_v1, ops_correlation_key_v1, ops_group_owner_v1, ops_correlation_groups_v1): same job (by name or
--     by the function the job runs), same worker mode or edge function, same function in the error text, same check family, else same source.
--   4 diagnosis (security.ops_issue_signals_v1, ops_detect_match_v1, ops_diagnose_v1): deterministic rules over the issue, the live job runs,
--     its history and recorded releases; {root_cause, confidence, evidence[], method, at}. AI-assisted diagnosis is not built in this change.
--   5 remedies (security.ops_controller_tick_v1, job ops-controller at :24 and :54): one owner per group; auto remedies only, within
--     attempts and cool-down; before and after measures; verification on a later run only; close through security.integration_issue_close_v1
--     only when verification passed and the condition cleared; needs_release or needs_decision otherwise, never a loop. Reopening on
--     recurrence stays with security.integration_issue_upsert_v1 (regression_count). Jobs that keep ending without data movement
--     (pipeline.admin_jobs.outcome succeeded_no_movement) open one issue per kind.
--   6 seeds: root causes and remedies for the issue families live today.
--   7 security.ops_report_v1(p_window_hours): the one consolidated report (mandate §16); the controller writes an hourly checkpoint row and a
--     daily summary row (ops.checkpoint_on).

-- 2.0 the queue functions this part calls are the ones it was written against (not edited here)
do $g$
declare r record;
begin
  for r in select * from (values ('security.integration_issue_upsert_v1(jsonb,text)', 'f292f65689a35e213a3d12a539c11b1d'),
                                 ('security.integration_issue_transition_v1(bigint,text,text,text,jsonb)', '3e8fc63663e5120c50f0859da97dd7a8'),
                                 ('security.integration_issue_close_v1(bigint,text,jsonb)', '4cae8eaee7444e0aa942b2702eb10bc6')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
end $g$;

-- 2.1 settings (G2) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'ops.controller_on', 'Operations controller: on',
  'On (1): the controller diagnoses open integration issues, runs the automatic remedies registered for their causes, verifies them on a later run and closes them only on verified evidence. Off (0): nothing runs.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1100, 'Operations controller', 'security.ops_controller_tick_v1 (job ops-controller)', 'P0 autonomous operations mandate 3 Nov 2026 15:37 §2-§3: ships on (diagnoses, records and closes on evidence; spends nothing)'),
 ('pipeline', 'ops.issues_per_run', 'Operations controller: issues examined a run',
  'At most this many open issues are diagnosed and acted on in one run (most severe first). The rest wait for the next run.',
  'number', to_jsonb(60), 5, 500, 'issues', 1101, 'Operations controller', 'security.ops_controller_tick_v1', 'P0 mandate §3'),
 ('pipeline', 'ops.max_attempts', 'Operations controller: attempts per remedy',
  'A remedy is run at most this many times for one issue (unless the remedy names its own setting). After that the issue needs a release.',
  'number', to_jsonb(3), 1, 10, 'attempts', 1102, 'Operations controller', 'security.ops_controller_tick_v1 (remedies without max_attempts_key)', 'P0 mandate §3 "a failed operation must not continue retrying indefinitely"'),
 ('pipeline', 'ops.cooldown_minutes', 'Operations controller: wait before verifying',
  'A remedy''s result is verified no sooner than this after the action, and never in the same run (keep it at or above the 30 minutes between runs).',
  'number', to_jsonb(30), 10, 1440, 'minutes', 1103, 'Operations controller', 'security.ops_controller_tick_v1 (remedies without cooldown_key)', 'P0 mandate §13'),
 ('pipeline', 'ops.stale_clear_hours', 'Operations controller: clear for this long before closing',
  'An issue whose check has not seen its condition for this long, with no recurrence, is verified and closed with that evidence.',
  'number', to_jsonb(6), 1, 168, 'hours', 1104, 'Operations controller', 'security.ops_verify_cleared_v1; root cause condition_cleared_stale', 'P0 mandate §13 "close when the expected operational result is verified"'),
 ('pipeline', 'ops.retry_loop_runs', 'Operations controller: repeats that make a retry loop',
  'A job that fails this many runs in a row with the same error, or an issue seen this many times with no new evidence, is diagnosed as a retry loop.',
  'number', to_jsonb(6), 2, 100, 'runs', 1105, 'Operations controller', 'security.ops_issue_signals_v1 (retry_loop)', 'P0 mandate §3 "detect repeated no-yield activity and retry loops"'),
 ('pipeline', 'ops.permanent_after_runs', 'Operations controller: failed runs in a row that make a failure permanent',
  'A job that fails this many runs in a row with an error that is not a time-out or rate limit is diagnosed as a permanent rule or data defect, not load.',
  'number', to_jsonb(3), 2, 50, 'runs', 1106, 'Operations controller', 'security.ops_issue_signals_v1 (permanent_failure)', 'P0 mandate §3 "distinguish transient infrastructure failure from permanent data or rule defects"'),
 ('pipeline', 'ops.job_runs_examined', 'Operations controller: newest runs read per job',
  'The diagnosis reads this many of a job''s newest scheduler runs.',
  'number', to_jsonb(12), 3, 100, 'runs', 1107, 'Operations controller', 'security.ops_job_stats_v1', 'P0 mandate §3'),
 ('pipeline', 'ops.runs_scan', 'Operations controller: scheduler runs looked through',
  'Job runs are found among this many of the newest scheduler runs (all jobs), so the read stays small. About 7,000 runs are written in 24 hours.',
  'number', to_jsonb(20000), 1000, 200000, 'runs', 1108, 'Operations controller', 'security.ops_job_stats_v1; security.ops_report_v1', 'P0 mandate §3, §16'),
 ('pipeline', 'ops.transient_share_max', 'Operations controller: failure share still counted as load',
  'Time-outs on a job that fails no more than this share of its newest runs are diagnosed as load (transient); above it, as a capacity defect.',
  'number', to_jsonb(50), 1, 100, '%', 1109, 'Operations controller', 'security.ops_issue_signals_v1 (transient_share)', 'P0 mandate §3'),
 ('pipeline', 'ops.regression_window_hours', 'Operations controller: a new failure this soon after a release is a regression',
  'A failure that starts within this many hours after a recorded release (deploy check or an issue moved to deployed) is diagnosed as a regression of that release.',
  'number', to_jsonb(2), 1, 72, 'hours', 1110, 'Operations controller', 'security.ops_issue_signals_v1 (after_release)', 'P0 mandate §3 "detect problems created by previous fixes"'),
 ('pipeline', 'ops.recheck_hours', 'Operations controller: look again at an issue that needs a release or a decision',
  'An issue routed to a release or a decision is diagnosed again after this long (no remedy runs; its state changes only on new evidence).',
  'number', to_jsonb(6), 1, 72, 'hours', 1111, 'Operations controller', 'security.ops_controller_tick_v1', 'P0 mandate §3'),
 ('pipeline', 'ops.capacity_recheck_minutes', 'Operations controller: capacity issues checked every',
  'A time-out, rate-limit or runtime start-up issue is recorded with its load profile and checked again after this long.',
  'number', to_jsonb(120), 30, 1440, 'minutes', 1112, 'Operations controller', 'remedy record_capacity_profile', 'P0 mandate §7 (IQ-00053: tune with evidence, within limits)'),
 ('pipeline', 'ops.capacity_max_checks', 'Operations controller: capacity checks before a release is needed',
  'After this many checks with the condition still present, a capacity issue needs a release (batch size or concurrency change).',
  'number', to_jsonb(6), 1, 48, 'checks', 1113, 'Operations controller', 'remedy record_capacity_profile', 'P0 mandate §7'),
 ('pipeline', 'ops.no_movement_min', 'Operations controller: tasks without data movement before an issue',
  'This many tasks of one kind ending succeeded_no_movement in the window open (or update) one integration issue for that kind.',
  'number', to_jsonb(3), 1, 100, 'tasks', 1114, 'Operations controller', 'security.ops_controller_tick_v1 (no_movement)', 'P0 mandate §3 "detect jobs marked completed without actual data movement"'),
 ('pipeline', 'ops.no_movement_window_hours', 'Operations controller: window for tasks without data movement',
  'Tasks finished in this many hours are counted for the check above.',
  'number', to_jsonb(6), 1, 72, 'hours', 1115, 'Operations controller', 'security.ops_controller_tick_v1 (no_movement)', 'P0 mandate §3'),
 ('pipeline', 'ops.checkpoint_on', 'Operations report: hourly checkpoint and daily summary',
  'On (1): the controller writes one checkpoint row an hour and one daily summary row (pipeline.ops_checkpoints), never a notification.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1116, 'Operations controller', 'security.ops_controller_tick_v1; security.ops_report_v1', 'P0 mandate §16 (reports only)'),
 ('pipeline', 'ops.checkpoint_minutes', 'Operations report: minutes between checkpoints',
  'A checkpoint is written when the last one is at least this old.',
  'number', to_jsonb(60), 15, 1440, 'minutes', 1117, 'Operations controller', 'security.ops_controller_tick_v1', 'P0 mandate §16 "hourly internal checkpoints"'),
 ('pipeline', 'ops.daily_summary_hour', 'Operations report: hour of the daily summary (Melbourne time)',
  'The first checkpoint at or after this hour writes the day''s consolidated summary (24 hours).',
  'number', to_jsonb(7), 0, 23, 'hour', 1118, 'Operations controller', 'security.ops_controller_tick_v1', 'P0 mandate §16 "daily consolidated summaries"'),
 ('pipeline', 'ops.report_items_scan', 'Operations report: newest field items read',
  'The report counts filled and reviewed field values among this many of the newest field items, so the read stays bounded.',
  'number', to_jsonb(200000), 10000, 2000000, 'items', 1119, 'Operations controller', 'security.ops_report_v1', 'P0 mandate §16')
on conflict do nothing;

-- 2.2 tables and the state column ---------------------------------------------------------------------------------------------------------
alter table pipeline.integration_issues add column if not exists ops_state text;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'integration_issues_ops_state_check' and conrelid = 'pipeline.integration_issues'::regclass) then
    alter table pipeline.integration_issues add constraint integration_issues_ops_state_check
      check (ops_state is null or ops_state in ('diagnosed', 'remedying', 'verifying', 'verified', 'superseded', 'needs_release', 'needs_decision'));
  end if;
end $c$;
comment on column pipeline.integration_issues.ops_state is 'CF-247 P0 (mandate 15:37 §3, §13; acceptance mandate 15:52 §6, §18): where the controller has the issue: diagnosed, remedying (an action failed; retried within attempts), verifying (acted; verified on a later run), verified (closed on evidence), superseded (by the issue that owns its shared root cause: superseded_by, with its evidence carried over; closed when that issue is verified), needs_release (blocked: a code change is the remedy, or attempts are used up) or needs_decision (blocked: a Platform Admin decision); the blocker column holds the evidence and the decision required. Beside status, whose graph is unchanged.';
alter table pipeline.integration_issues add column if not exists superseded_by bigint references pipeline.integration_issues(id);
alter table pipeline.integration_issues add column if not exists supersedes bigint[] not null default '{}';
alter table pipeline.integration_issues add column if not exists blocker jsonb;
alter table pipeline.integration_issues add column if not exists ops_plan jsonb;
comment on column pipeline.integration_issues.superseded_by is 'CF-247 P0 (acceptance mandate 15:52 §6, §18): the issue that owns this issue''s shared root cause (same correlation key); this issue''s evidence is carried over to it (evidence.superseded) and it lists this one in supersedes.';
comment on column pipeline.integration_issues.blocker is 'CF-247 P0 (acceptance mandate §18, §22): for needs_release or needs_decision, {kind, required, root_cause, evidence, impact, recommended, issue_statement, at}: the exact evidence and the release or external decision required.';
comment on column pipeline.integration_issues.ops_plan is 'CF-247 P0 (acceptance mandate §6 incident intelligence): the controller''s plan: proposed corrective action (remedy), its authority (approval category), risk, the alternatives it weighed and their verified success rates.';
create index if not exists integration_issues_next_action_idx on pipeline.integration_issues (next_action_at) where status <> 'closed';
create index if not exists integration_issues_correlation_idx on pipeline.integration_issues (correlation_key) where status <> 'closed';

create table if not exists pipeline.ops_checkpoints (
  id bigserial primary key,
  at timestamptz not null default now(),
  kind text not null check (kind in ('hourly', 'daily')),
  window_hours int not null,
  report jsonb not null
);
comment on table pipeline.ops_checkpoints is 'CF-247 P0 autonomous operations (mandate §16): the hourly internal checkpoint and the daily consolidated summary, each the output of security.ops_report_v1 for its window, written by the controller (job ops-controller) while ops.checkpoint_on is 1. A table row, never a notification. Never read by the consumer API.';
create index if not exists ops_checkpoints_kind_at_idx on pipeline.ops_checkpoints (kind, at desc);
alter table pipeline.ops_checkpoints enable row level security;
revoke all on pipeline.ops_checkpoints from public, anon, authenticated;
revoke all on sequence pipeline.ops_checkpoints_id_seq from public, anon, authenticated;

-- 2.3 the authority boundary in data (mandate §6, §15) ------------------------------------------------------------------------------------
create or replace function security.ops_guard_refuse_v1() returns trigger
language plpgsql set search_path to '' as $function$
-- Fires only while a remedy or verification runs (trigger WHEN security.ops_remedy_guard_active_v1()). TG_ARGV[0] names what is protected.
begin
  raise exception 'ops guard: a remedy cannot change % (%.%; that is a release or a Platform Admin decision)', TG_ARGV[0], TG_TABLE_SCHEMA, TG_TABLE_NAME using errcode = '42501';
end $function$;
revoke all on function security.ops_guard_refuse_v1() from public, anon, authenticated;

create or replace function security.ops_guard_settings_v1() returns trigger
language plpgsql set search_path to '' as $function$
-- While a remedy runs a setting may change only within its own range, and never: a range (min_value, max_value), a service toolset (paid
-- services), a budget, spend, credit, reserve or ceiling, an admission or Layer 4 setting, the controller's own or the alerts' settings.
declare v_num numeric;
begin
  if TG_OP <> 'UPDATE' then raise exception 'ops guard: a remedy cannot add or remove settings' using errcode = '42501'; end if;
  if new.min_value is distinct from old.min_value or new.max_value is distinct from old.max_value or new.key is distinct from old.key or new.toolset_key is distinct from old.toolset_key then
    raise exception 'ops guard: a remedy cannot change a setting''s range or identity (%.%)', old.toolset_key, old.key using errcode = '42501';
  end if;
  -- fixed: the protected settings are the authority boundary itself; widening or narrowing them is a release, never a setting
  if old.toolset_key <> 'pipeline' or old.key ~ '^(ops|budgets|layer4|alerts|integration|targets)\.'
     or old.key ~* '(budget|_usd|credit|ceiling|reserve|spend|admit|admission|auto_approve|search_per_run|paid)' then
    raise exception 'ops guard: a remedy cannot change % (budgets, admission and controller settings are changed by a person)', old.key using errcode = '42501';
  end if;
  if jsonb_typeof(new.value) = 'number' then
    v_num := (new.value #>> '{}')::numeric;
    if (old.min_value is not null and v_num < old.min_value) or (old.max_value is not null and v_num > old.max_value) then
      raise exception 'ops guard: % must stay within % to %', old.key, old.min_value, old.max_value using errcode = '42501';
    end if;
  end if;
  return new;
end $function$;
revoke all on function security.ops_guard_settings_v1() from public, anon, authenticated;

create or replace function security.ops_guard_layer4_v1() returns trigger
language plpgsql set search_path to '' as $function$
-- While a remedy runs a Layer 4 item may only stay pending or be superseded (duplicate reconciliation); approving, rejecting, returning or
-- deleting is a decision (mandate §10: technical repair authority is not admission authority).
begin
  if TG_OP = 'DELETE' or new.status not in ('pending', 'superseded') or (TG_OP = 'UPDATE' and old.status <> 'pending' and new.status is distinct from old.status) then
    raise exception 'ops guard: a remedy cannot decide or admit a Layer 4 item' using errcode = '42501';
  end if;
  return new;
end $function$;
revoke all on function security.ops_guard_layer4_v1() from public, anon, authenticated;

create or replace function security.ops_guard_issue_v1() returns trigger
language plpgsql set search_path to '' as $function$
-- While a remedy runs it cannot close an issue (only the controller closes, after a verification on a later run) or change its controller fields.
begin
  if new.status = 'closed' and old.status <> 'closed' then raise exception 'ops guard: a remedy cannot close an issue; the controller closes on verified evidence' using errcode = '42501'; end if;
  if new.remedy_attempts is distinct from old.remedy_attempts or new.remedy_code is distinct from old.remedy_code or new.ops_state is distinct from old.ops_state
     or new.diagnosis is distinct from old.diagnosis or new.next_action_at is distinct from old.next_action_at then
    raise exception 'ops guard: a remedy cannot change the controller''s record of an issue' using errcode = '42501';
  end if;
  return new;
end $function$;
revoke all on function security.ops_guard_issue_v1() from public, anon, authenticated;

do $t$
declare r record;
begin
  for r in select * from (values
      ('pipeline.ops_remedies', 'ops_guard_registry', 'security.ops_guard_refuse_v1(''the remedy register'')', 'insert or update or delete'),
      ('pipeline.ops_root_causes', 'ops_guard_registry', 'security.ops_guard_refuse_v1(''the root-cause register'')', 'insert or update or delete'),
      ('pipeline.ops_outcome_codes', 'ops_guard_registry', 'security.ops_guard_refuse_v1(''the outcome codes'')', 'insert or update or delete'),
      ('pipeline.ops_remedy_runs', 'ops_guard_registry', 'security.ops_guard_refuse_v1(''the record of remedy runs'')', 'insert or update or delete'),
      ('pipeline.platform_toolset_settings', 'ops_guard_settings', 'security.ops_guard_settings_v1()', 'insert or update or delete'),
      ('pipeline.layer4_review_items', 'ops_guard_layer4', 'security.ops_guard_layer4_v1()', 'insert or update or delete'),
      ('pipeline.layer4_decisions', 'ops_guard_layer4', 'security.ops_guard_refuse_v1(''Layer 4 decisions'')', 'insert or update or delete'),
      ('pipeline.layer4_auto_admissions', 'ops_guard_layer4', 'security.ops_guard_refuse_v1(''automatic admissions'')', 'insert or update or delete'),
      ('pipeline.manual_locks', 'ops_guard_locks', 'security.ops_guard_refuse_v1(''manual locks'')', 'insert or update or delete'),
      ('pipeline.layer2_acquisition_providers', 'ops_guard_budget', 'security.ops_guard_refuse_v1(''paid-service limits and budgets'')', 'insert or update or delete'),
      ('pipeline.layer3_route_budget', 'ops_guard_budget', 'security.ops_guard_refuse_v1(''AI route budgets'')', 'insert or update or delete'),
      ('pipeline.integration_issues', 'ops_guard_issue', 'security.ops_guard_issue_v1()', 'update')) v(tbl, tg, fn, ev) loop
    if to_regclass(r.tbl) is not null and not exists (select 1 from pg_trigger where tgname = r.tg and tgrelid = r.tbl::regclass) then
      execute format('create trigger %I before %s on %s for each row when (security.ops_remedy_guard_active_v1()) execute function %s', r.tg, r.ev, r.tbl, r.fn);
    end if;
  end loop;
end $t$;

-- 2.4 the authority matrix (acceptance mandate 15:52 §6 "Authorise", §16): what each remedy authority may do. Changed only by a release.
create table if not exists pipeline.ops_authority_matrix (
  authority text primary key check (authority in ('auto', 'release', 'admin')),
  executes boolean not null,
  may_close boolean not null,
  route_state text check (route_state in ('needs_release', 'needs_decision')),
  description text not null
);
comment on table pipeline.ops_authority_matrix is 'CF-247 P0 (acceptance mandate 15:52 §6, §16): the backend decision-authority matrix the controller checks at its Authorise step before any remedy runs, recorded on the run (ops_remedy_runs.evidence.authorise). auto: executed and verified by the controller; release: a code change through the release gates (the issue is blocked as needs_release); admin: a Platform Admin decision (needs_decision). A remedy can never change it (refused in data); a release changes it. Never read by the consumer API.';
alter table pipeline.ops_authority_matrix enable row level security;
revoke all on pipeline.ops_authority_matrix from public, anon, authenticated;
insert into pipeline.ops_authority_matrix(authority, executes, may_close, route_state, description) values
 ('auto', true, true, null, 'Operational and reversible: recording evidence, confirming a cleared condition, linking an issue to the issue that owns its shared cause, measuring load. Executed by the controller within attempts and cool-down; closed only on a verification passed on a later run.'),
 ('release', false, false, 'needs_release', 'Code, schema, function or routing changes: developed and tested by a workstream and released through the existing gates (mandate §16 "governed engineering control").'),
 ('admin', false, false, 'needs_decision', 'Spend, D1 paid search, destructive changes, consumer API shape, manual locks, Layer 4 safeguards, permissions, publishing unverified sources, licences and external evidence: the Platform Admin decides (mandate §16 "explicit authorisation").')
on conflict (authority) do nothing;
do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'ops_guard_registry' and tgrelid = 'pipeline.ops_authority_matrix'::regclass) then
    create trigger ops_guard_registry before insert or update or delete on pipeline.ops_authority_matrix for each row
      when (security.ops_remedy_guard_active_v1()) execute function security.ops_guard_refuse_v1('the authority matrix');
  end if;
end $t$;

-- the historical cohort (acceptance mandate §18): the 48 issues at detected in the 15:41 AEDT baseline, each to end verified resolved, superseded
-- with traceability, or blocked with evidence and the decision required (ids from the read-only baseline of 3 Nov 2026 15:41-15:56 AEDT)
create table if not exists pipeline.ops_baseline_cohort (
  issue_id bigint primary key references pipeline.integration_issues(id),
  cohort text not null,
  status_at_baseline text not null,
  captured_at timestamptz not null
);
comment on table pipeline.ops_baseline_cohort is 'CF-247 P0 (acceptance mandate 15:52 §18 "integration issue reconciliation"): the fixed cohort of historical issues the controller must bring to an end state (verified resolved, superseded with traceability, or blocked with evidence and the decision required), kept apart from issues found later so progress is not misleading. Reported by security.ops_reconciliation_v1 and security.ops_report_v1. Never read by the consumer API.';
alter table pipeline.ops_baseline_cohort enable row level security;
revoke all on pipeline.ops_baseline_cohort from public, anon, authenticated;
insert into pipeline.ops_baseline_cohort(issue_id, cohort, status_at_baseline, captured_at)
select i.id, 'p0-2026-11-03-detected-48', 'detected', '2026-11-03 04:41:00+00'::timestamptz
  from pipeline.integration_issues i
 where i.id = any (array[3, 4, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 24, 25, 29, 30, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 45, 46, 47, 49,
                         50, 51, 52, 54, 56, 57, 58, 59, 61, 65, 67, 68, 69]::bigint[])
on conflict (issue_id) do nothing;

-- 2.5 AI-assisted diagnosis (acceptance mandate §6; ships OFF): requests the existing worker answers through its OpenRouter guards ------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'ops.ai_diagnosis_on', 'Operations controller: AI-assisted diagnosis',
  'On (1): an issue the deterministic rules diagnose with low confidence is queued for the worker''s AI diagnosis (pinned model, the existing OpenRouter guards and the daily AI ceiling). Off (0): rules only.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1120, 'Operations controller', 'security.ops_controller_tick_v1; public.svc_ops_diagnosis_next', 'Acceptance mandate 3 Nov 2026 15:52 §6: AI where deterministic methods are insufficient; spends AI credit, so it ships off'),
 ('pipeline', 'ops.ai_min_confidence', 'Operations controller: confidence below which AI is asked',
  'A deterministic diagnosis below this confidence (0 to 1) is queued for AI-assisted diagnosis while it is on; an AI answer below it is kept as advice only.',
  'number', to_jsonb(0.5), 0, 1, 'confidence', 1121, 'Operations controller', 'security.ops_controller_tick_v1; public.svc_ops_diagnosis_record', 'Acceptance mandate §6'),
 ('pipeline', 'ops.ai_requests_per_day', 'Operations controller: AI diagnoses a day',
  'At most this many AI diagnosis requests are handed to the worker a day (Melbourne time).',
  'number', to_jsonb(20), 0, 500, 'requests', 1122, 'Operations controller', 'public.svc_ops_diagnosis_next', 'Acceptance mandate §6; mandate 15:37 §11 bounded spend'),
 ('pipeline', 'ops.ai_diagnosis_model', 'Operations controller: pinned AI diagnosis model',
  'The one model that writes AI-assisted diagnoses (OpenRouter id). Pinned: never an automatic router; changing it is a qualification decision.',
  'text', '"openai/gpt-4.1-mini"'::jsonb, null, null, null, 1123, 'Operations controller', 'public.svc_ops_diagnosis_next (worker mode ops_diagnose)', 'Project rule: model routing pinned to an individually qualified model')
on conflict do nothing;

create table if not exists pipeline.ops_ai_diagnosis_requests (
  id bigserial primary key,
  issue_id bigint not null references pipeline.integration_issues(id),
  requested_at timestamptz not null default now(),
  state text not null default 'queued' check (state in ('queued', 'leased', 'answered', 'refused')),
  leased_until timestamptz,
  context jsonb not null,
  answer jsonb,
  model text,
  cost_usd numeric,
  answered_at timestamptz,
  note text
);
comment on table pipeline.ops_ai_diagnosis_requests is 'CF-247 P0 (acceptance mandate 15:52 §6): issues the deterministic classifier diagnosed with low confidence, queued (only while ops.ai_diagnosis_on is 1) for the coverage-sweep worker''s AI diagnosis (mode ops_diagnose; pinned model ops.ai_diagnosis_model; the existing OpenRouter guards and the daily AI ceiling). An answer must name a registered root cause and quote its evidence from the context given; it changes the diagnosis only, never the remedy authority. Never read by the consumer API.';
create index if not exists ops_ai_diagnosis_requests_open_idx on pipeline.ops_ai_diagnosis_requests (state, requested_at) where state in ('queued', 'leased');
alter table pipeline.ops_ai_diagnosis_requests enable row level security;
revoke all on pipeline.ops_ai_diagnosis_requests from public, anon, authenticated;
revoke all on sequence pipeline.ops_ai_diagnosis_requests_id_seq from public, anon, authenticated;

-- 2.6 correlation ---------------------------------------------------------------------------------------------------------------------------
create or replace function security.ops_issue_subject_v1(p_issue bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 P0 (mandate 15:37 §3; acceptance mandate §14): what an issue is about, in order of strength:
--   1 the scheduled job (its fingerprint, or evidence.detail.job), 2 the worker mode or edge function (mapped to the job whose command names the
--   mode), 3 the first function named in its text that exists (the innermost first in an error stack), mapped to the job whose command calls it,
--   4 its check family (the fingerprint before the first colon). These are strong keys: issues that share one share an upstream cause.
--   5 a job only mentioned in the text, or 6 the same source document: weak keys, grouped for reporting and one owner, never superseded.
declare r pipeline.integration_issues; v_text text; v_seg1 text; v_job text; v_mode text; v_fn text; v_key text; v_strength text := 'strong';
begin
  select * into r from pipeline.integration_issues where id = p_issue;
  if not found then return null; end if;
  v_text := concat_ws(' ', r.title, r.failure, r.subsystem, r.evidence::text);
  v_seg1 := split_part(r.fingerprint, ':', 1);
  if r.fingerprint like 'job_failed:%' then v_job := substr(r.fingerprint, 12);
  elsif v_seg1 = 'job' then v_job := split_part(r.fingerprint, ':', 2);
  elsif exists (select 1 from cron.job j where j.jobname = v_seg1) then v_job := v_seg1;
  elsif exists (select 1 from cron.job j where j.jobname = r.evidence->'detail'->>'job') then v_job := r.evidence->'detail'->>'job';
  end if;
  if v_job is null then
    v_mode := coalesce(substring(r.fingerprint from '^hidden_worker_error:[^:]+:(.+)$'), substring(r.fingerprint from '^zero_yield:(.+)$'),
                       substring(r.fingerprint from '^health:queue_watch:(.+)$'));
    if v_mode is not null then
      select j.jobname into v_job from cron.job j where j.command ~ ('[''"]' || v_mode || '[''"]') order by j.active desc, j.jobname limit 1;
    elsif r.fingerprint like 'health:edge_calls:%' then
      v_key := 'edge:' || split_part(r.fingerprint, ':', 4);
    end if;
  end if;
  if v_job is null and v_mode is null and v_key is null then
    select x.m[1] into v_fn from regexp_matches(v_text, '([a-z_][a-z0-9_]*(?:_v[0-9]+|_impl|_next|_record))\M', 'g') with ordinality x(m, n)
     where exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname in ('security', 'public') and p.proname = x.m[1])
     order by x.n limit 1;
    if v_fn is not null then
      select j.jobname into v_job from cron.job j where j.command ~ ('\m' || v_fn || '\(') order by j.active desc, j.jobname limit 1;
    end if;
  end if;
  v_key := coalesce(v_key, 'job:' || v_job, 'mode:' || v_mode, 'fn:' || v_fn);
  if v_key is null and position(':' in r.fingerprint) > 0 and v_seg1 not in ('seed', 'synthetic', 'health') then v_key := 'family:' || v_seg1; end if;
  if v_key is null and v_seg1 = 'health' then v_key := 'family:health:' || split_part(r.fingerprint, ':', 2); end if;
  if v_key is null then
    v_strength := 'weak';
    select 'jobtext:' || j.jobname into v_key from cron.job j where j.jobname like '%-%' and position(j.jobname in v_text) > 0
     order by position(j.jobname in v_text), length(j.jobname) desc limit 1;
    v_key := coalesce(v_key, 'source:' || nullif(lower(btrim(regexp_replace(r.detection_source, '\s+[0-9].*$', ''))), ''), 'issue:' || r.fingerprint);
  end if;
  return jsonb_build_object('key', v_key, 'strength', v_strength, 'job', v_job, 'mode', v_mode, 'fn', v_fn);
end $function$;
revoke all on function security.ops_issue_subject_v1(bigint) from public, anon, authenticated;

create or replace function security.ops_correlation_key_v1(p_issue bigint) returns text
language sql stable security definer set search_path to '' as $function$
  select security.ops_issue_subject_v1(p_issue)->>'key'
$function$;
revoke all on function security.ops_correlation_key_v1(bigint) from public, anon, authenticated;

create or replace function security.ops_group_owner_v1(p_key text) returns bigint
language sql stable security definer set search_path to '' as $function$
-- One owner per correlated group (mandate §3 "prevent multiple agents independently repairing the same underlying defect"): the open issue of
-- the key that is not superseded, most severe first, then the oldest.
  select i.id from pipeline.integration_issues i
   where i.correlation_key = p_key and i.status <> 'closed' and i.superseded_by is null
   order by i.severity, i.detected_at, i.id limit 1
$function$;
revoke all on function security.ops_group_owner_v1(text) from public, anon, authenticated;

create or replace function security.ops_correlation_groups_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
-- The correlated groups of open issues (and those superseded into them): key, strength, owner, members, root causes.
  select coalesce(jsonb_agg(g order by (g->>'open')::int desc, g->>'key'), '[]'::jsonb) from (
    select jsonb_build_object('key', i.correlation_key, 'strength', min(i.diagnosis->'subject'->>'strength'),
             'owner', (select o.issue_ref from pipeline.integration_issues o where o.id = security.ops_group_owner_v1(i.correlation_key)),
             'open', count(*), 'issues', jsonb_agg(i.issue_ref order by i.id),
             'superseded', count(*) filter (where i.superseded_by is not null),
             'root_causes', jsonb_agg(distinct i.diagnosis->>'root_cause') filter (where i.diagnosis is not null)) g
      from pipeline.integration_issues i where i.status <> 'closed' and i.correlation_key is not null group by i.correlation_key) x
$function$;
revoke all on function security.ops_correlation_groups_v1() from public, anon, authenticated;

-- 2.7 diagnosis ------------------------------------------------------------------------------------------------------------------------------
create or replace function security.ops_job_stats_v1(p_job text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- A job's newest runs (ops.job_runs_examined of them, among the newest ops.runs_scan scheduler runs): runs, failures, time-outs, the current
-- failure streak, how many different errors it has, when it started and the last success.
declare v_scan int := security.pipeline_num_v1('ops.runs_scan', 20000)::int; v_n int := security.pipeline_num_v1('ops.job_runs_examined', 12)::int; v jsonb;
begin
  if p_job is null then return null; end if;
  with d as (select x.runid, x.status, x.return_message msg, x.start_time at from cron.job_run_details x
              where x.runid > (select coalesce(max(y.runid), 0) from cron.job_run_details y) - v_scan
                and x.jobid in (select j.jobid from cron.job j where j.jobname = p_job)
              order by x.runid desc limit v_n),
       o as (select d.*, row_number() over (order by d.runid desc) rn from d),
       s as (select coalesce(min(o.rn) filter (where o.status <> 'failed') - 1, count(*)) streak from o)
  select jsonb_build_object('job', p_job, 'runs', count(o.runid), 'failed', count(*) filter (where o.status = 'failed'),
           'failed_timeouts', count(*) filter (where o.status = 'failed' and o.msg ~* '(statement timeout|canceling statement|timed? ?out)'),
           'streak', s.streak,
           'streak_timeouts', count(*) filter (where o.rn <= s.streak and o.msg ~* '(statement timeout|canceling statement|timed? ?out)'),
           'streak_messages', count(distinct split_part(coalesce(o.msg, ''), E'\n', 1)) filter (where o.rn <= s.streak),
           'streak_started_at', min(o.at) filter (where o.rn <= s.streak),
           'last_success_at', max(o.at) filter (where o.status = 'succeeded'),
           'last_status', (array_agg(o.status order by o.runid desc))[1],
           'last_failure_message', (array_agg(left(o.msg, 400) order by o.runid desc) filter (where o.status = 'failed'))[1])
    into v from s left join o on true group by s.streak;
  -- a streak that fills the runs examined: its true start and the last success before it, among the newest ops.runs_scan scheduler runs
  if coalesce((v->>'streak')::int, 0) > 0 then
    with w as (select x.status, x.start_time at from cron.job_run_details x
                where x.runid > (select coalesce(max(y.runid), 0) from cron.job_run_details y) - v_scan
                  and x.jobid in (select j.jobid from cron.job j where j.jobname = p_job)),
         ok as (select max(w.at) at from w where w.status = 'succeeded')
    select v || jsonb_build_object('last_success_before_streak', ok.at,
                                   'streak_started_at', coalesce((select min(w.at) from w where w.status = 'failed' and w.at > coalesce(ok.at, '-infinity')), (v->>'streak_started_at')::timestamptz),
                                   'streak_total', (select count(*) from w where w.status = 'failed' and w.at > coalesce(ok.at, '-infinity')))
      into v from ok;
  end if;
  return v;
end $function$;
revoke all on function security.ops_job_stats_v1(text) from public, anon, authenticated;

create or replace function security.ops_releases_v1() returns table(release text, at timestamptz, source text)
language sql stable security definer set search_path to '' as $function$
-- When releases reached production: each migration's apply time (the first component it registered), the release controller's deploy
-- checks, and issues moved to deployed.
  select c.introduced_in, min(c.registered_at), 'migration' from pipeline.component_register c where c.introduced_in ~ '^[0-9]{14}$' group by c.introduced_in
  union all select d.release, d.checked_at, 'deploy check' from pipeline.integration_deploy_checks d
  union all select coalesce(e.detail->>'deployed_version', 'issue ' || e.issue_id), e.at, 'issue deployed' from pipeline.integration_issue_events e where e.to_status = 'deployed'
$function$;
revoke all on function security.ops_releases_v1() from public, anon, authenticated;

create or replace function security.ops_issue_signals_v1(p_issue bigint, p_ctx jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 P0 (mandate 15:37 §3): deterministic signals for one issue from the issue, its history, its job's live runs and recorded releases.
-- p_ctx carries the group (owner, members, strength) worked out by the controller.
declare r pipeline.integration_issues; v_subj jsonb; v_job jsonb; v_text text; v_rel_r text; v_rel_at timestamptz; v_rel_src text; v_start timestamptz; v jsonb;
        v_loop int := security.pipeline_num_v1('ops.retry_loop_runs', 6)::int; v_perm int := security.pipeline_num_v1('ops.permanent_after_runs', 3)::int;
        v_share numeric; v_material int; v_clear numeric;
begin
  select * into r from pipeline.integration_issues where id = p_issue;
  if not found then return null; end if;
  v_subj := coalesce(p_ctx->'subject', security.ops_issue_subject_v1(p_issue));
  v_job := security.ops_job_stats_v1(v_subj->>'job');
  v_text := concat_ws(' ', r.title, r.failure, r.evidence::text, v_job->>'last_failure_message');
  v_share := case when coalesce((v_job->>'runs')::int, 0) > 0 then round(100.0 * (v_job->>'failed')::int / (v_job->>'runs')::int, 1) end;
  select count(*) into v_material from pipeline.integration_issue_events e
   where e.issue_id = p_issue and e.kind in ('observed', 'escalated', 'observed_again', 'reopened_regression');
  v_clear := case when r.condition_cleared_at is not null and r.last_observed_at <= r.condition_cleared_at
                  then round(extract(epoch from now() - r.condition_cleared_at) / 3600.0, 2) end;
  -- a failure streak that began soon after a release, on a job that succeeded before it: a new error type after a release
  v_start := (v_job->>'streak_started_at')::timestamptz;
  if v_start is not null and coalesce((v_job->>'streak')::int, 0) > 0 and v_job->>'last_success_before_streak' is not null then
    select x.release, x.at, x.source into v_rel_r, v_rel_at, v_rel_src from security.ops_releases_v1() x
     where x.at <= v_start and x.at >= v_start - make_interval(hours => security.pipeline_num_v1('ops.regression_window_hours', 2)::int)
     order by x.at desc limit 1;
  end if;
  v := jsonb_build_object(
    'subject', v_subj, 'job', v_job,
    'job_failing', coalesce((v_job->>'streak')::int, 0) >= 1,
    'job_quiet', v_job is not null and coalesce((v_job->>'runs')::int, 0) > 0 and coalesce((v_job->>'failed')::int, 0) = 0,
    'failure_share_pct', v_share,
    'transient_share', v_share is not null and v_share <= security.pipeline_num_v1('ops.transient_share_max', 50),
    'permanent_failure', coalesce((v_job->>'streak')::int, 0) >= v_perm and coalesce((v_job->>'streak_timeouts')::int, 0) = 0 and coalesce((v_job->>'streak_messages')::int, 0) = 1,
    'retry_loop', (coalesce((v_job->>'streak')::int, 0) >= v_loop and coalesce((v_job->>'streak_messages')::int, 0) = 1)
                  or (r.retry_count >= v_loop and v_material = 0 and r.condition_cleared_at is null),
    'timeout', v_text ~* '(statement timeout|canceling statement|timed out|time-out|timeout)',
    'rate_limit', v_text ~* '(\m429\M|rate.?limit|too many requests)',
    'boot_error', v_text ~* '(BOOT_ERROR|failed to start)',
    'lock_refusal', v_text ~* '(set by hand|manual lock|locked by hand)',
    'no_movement', r.fingerprint like 'zero_yield:%' or r.fingerprint like 'no_movement:%' or v_text ~* '(0 items done|0 of 0|moved no data|no data moved|without data movement|done while)',
    'cleared_hours', v_clear,
    'observed_by_check', r.validation_layer = 'V4' or r.condition_cleared_at is not null,
    'recurred', r.regression_count > 0 or r.status = 'reopened',
    'material_observations', v_material, 'retry_count', r.retry_count,
    'after_release', v_rel_r is not null,
    'release', case when v_rel_r is not null then jsonb_build_object('release', v_rel_r, 'at', v_rel_at, 'source', v_rel_src, 'failures_from', v_start,
                    'minutes_after', round(extract(epoch from v_start - v_rel_at) / 60.0), 'last_success_before', v_job->>'last_success_before_streak',
                    'failed_runs_since', v_job->'streak_total') end,
    'seed', r.fingerprint like 'seed:%' or r.validation_layer = 'manual',
    'group', coalesce(p_ctx->'group', '{}'::jsonb));
  return v;
end $function$;
revoke all on function security.ops_issue_signals_v1(bigint, jsonb) from public, anon, authenticated;

create or replace function security.ops_detect_match_v1(p_detect jsonb, p_ctx jsonb) returns boolean
language plpgsql stable security definer set search_path to '' as $function$
-- The detect grammar of pipeline.ops_root_causes: {"priority": n, "confidence": 0..1, "all": [cond], "any": [cond], "none": [cond],
-- "fallback": true, "route": "needs_decision" | "needs_release", "recommend": "text"}. A condition is one of:
--   {"signal": name} true when the signal is true, a number above 0 or a non-empty value; with "min": n, "max": n or "min_setting": key and
--   "default": n it compares the number; {"fingerprint_like": [patterns]}; {"text": regex} on title, failure and evidence; {"class_in": [...]}
--   (root_cause_class); {"status_in": [...]}. all: every condition holds; any: at least one; none: none. An empty rule never matches unless fallback.
declare c jsonb; v_ok boolean;
begin
  if coalesce((p_detect->>'fallback')::boolean, false) then return true; end if;
  if not (p_detect ? 'all' or p_detect ? 'any') then return false; end if;
  for c in select * from jsonb_array_elements(coalesce(p_detect->'all', '[]'::jsonb)) loop
    if not security.ops_cond_v1(c, p_ctx) then return false; end if;
  end loop;
  if p_detect ? 'any' then
    v_ok := false;
    for c in select * from jsonb_array_elements(p_detect->'any') loop
      if security.ops_cond_v1(c, p_ctx) then v_ok := true; exit; end if;
    end loop;
    if not v_ok then return false; end if;
  end if;
  for c in select * from jsonb_array_elements(coalesce(p_detect->'none', '[]'::jsonb)) loop
    if security.ops_cond_v1(c, p_ctx) then return false; end if;
  end loop;
  return true;
end $function$;

create or replace function security.ops_cond_v1(c jsonb, p_ctx jsonb) returns boolean
language plpgsql stable security definer set search_path to '' as $function$
declare v jsonb; v_num numeric;
begin
  if c ? 'signal' then
    v := p_ctx->'signals'->(c->>'signal');
    if v is null or jsonb_typeof(v) = 'null' then return false; end if;
    if c ? 'min' or c ? 'max' or c ? 'min_setting' then
      if jsonb_typeof(v) <> 'number' then return false; end if;
      v_num := (v #>> '{}')::numeric;
      if c ? 'min' and v_num < (c->>'min')::numeric then return false; end if;
      if c ? 'max' and v_num > (c->>'max')::numeric then return false; end if;
      if c ? 'min_setting' and v_num < security.pipeline_num_v1(c->>'min_setting', coalesce((c->>'default')::numeric, 0)) then return false; end if;
      return true;
    end if;
    return case jsonb_typeof(v) when 'boolean' then (v #>> '{}')::boolean when 'number' then (v #>> '{}')::numeric > 0
                when 'string' then length(v #>> '{}') > 0 else true end;
  elsif c ? 'fingerprint_like' then
    return exists (select 1 from jsonb_array_elements_text(case jsonb_typeof(c->'fingerprint_like') when 'array' then c->'fingerprint_like' else jsonb_build_array(c->'fingerprint_like') end) p
                    where p_ctx->>'fingerprint' like p);
  elsif c ? 'text' then return coalesce(p_ctx->>'text', '') ~* (c->>'text');
  elsif c ? 'class_in' then return p_ctx->>'class' in (select jsonb_array_elements_text(c->'class_in'));
  elsif c ? 'status_in' then return p_ctx->>'status' in (select jsonb_array_elements_text(c->'status_in'));
  end if;
  return false;
end $function$;
revoke all on function security.ops_cond_v1(jsonb, jsonb) from public, anon, authenticated;
revoke all on function security.ops_detect_match_v1(jsonb, jsonb) from public, anon, authenticated;

create or replace function security.ops_diagnose_v1(p_issue bigint, p_signals jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 P0 (mandate 15:37 §3): the deterministic classifier. Root causes are tried in priority order; the first that matches is the root
-- cause, the others that match are contributing causes. Evidence lists the signals the rule used and the facts behind them.
declare r pipeline.integration_issues; rc record; v_ctx jsonb; v_first text; v_conf numeric; v_contrib text[] := '{}'; v_ev jsonb := '[]'::jsonb; v_prio int;
begin
  select * into r from pipeline.integration_issues where id = p_issue;
  if not found then return null; end if;
  v_ctx := jsonb_build_object('fingerprint', r.fingerprint, 'text', concat_ws(' ', r.title, r.failure, r.evidence::text, p_signals->'job'->>'last_failure_message'),
                              'class', r.root_cause_class, 'status', r.status, 'signals', p_signals);
  for rc in select c.code, c.class, c.detect from pipeline.ops_root_causes c
             order by coalesce((c.detect->>'priority')::int, 1000), c.code loop
    if security.ops_detect_match_v1(rc.detect, v_ctx) then
      if v_first is null then v_first := rc.code; v_conf := coalesce((rc.detect->>'confidence')::numeric, 0.5); v_prio := (rc.detect->>'priority')::int;
      elsif not coalesce((rc.detect->>'fallback')::boolean, false) then v_contrib := v_contrib || rc.code; end if;
    end if;
  end loop;
  -- confidence: a time-out on a job failing only part of its runs is load (higher confidence); one failing most runs is less certain
  if v_first = 'timeout_under_load' and (p_signals->>'transient_share')::boolean is false then v_conf := greatest(v_conf - 0.2, 0.1); end if;
  if cardinality(v_contrib) > 0 and v_first not in ('condition_cleared_stale') then v_conf := least(v_conf + 0.05, 0.99); end if;
  select coalesce(jsonb_agg(jsonb_build_object('signal', k, 'value', p_signals->k)), '[]'::jsonb) into v_ev
    from unnest(array['job_failing', 'permanent_failure', 'retry_loop', 'timeout', 'rate_limit', 'boot_error', 'lock_refusal', 'no_movement', 'cleared_hours',
                      'recurred', 'after_release', 'job_quiet', 'failure_share_pct']) k
   where p_signals->k is not null and jsonb_typeof(p_signals->k) <> 'null' and p_signals->>k not in ('false', '0');
  if p_signals->'job' is not null and jsonb_typeof(p_signals->'job') = 'object' then
    v_ev := v_ev || jsonb_build_array(jsonb_build_object('job_runs', p_signals->'job'));
  end if;
  if p_signals->'release' is not null and jsonb_typeof(p_signals->'release') = 'object' then
    v_ev := v_ev || jsonb_build_array(jsonb_build_object('release', p_signals->'release'));
  end if;
  return jsonb_build_object('root_cause', v_first, 'confidence', round(v_conf, 2), 'evidence', v_ev, 'method', 'deterministic', 'at', now(),
                            'contributing', to_jsonb(v_contrib), 'rule_priority', v_prio, 'subject', p_signals->'subject', 'group', p_signals->'group');
end $function$;
revoke all on function security.ops_diagnose_v1(bigint, jsonb) from public, anon, authenticated;

-- 2.8 remedies (actions and verifications: (p_issue bigint) returns jsonb) --------------------------------------------------------------------
create or replace function security.ops_issue_measure_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object('status', i.status, 'severity', i.severity, 'retry_count', i.retry_count, 'last_observed_at', i.last_observed_at,
           'condition_cleared_at', i.condition_cleared_at, 'regression_count', i.regression_count, 'providers', cardinality(i.provider_ids),
           'courses', cardinality(i.course_ids), 'superseded_by', i.superseded_by, 'supersedes', to_jsonb(i.supersedes), 'at', now())
    from pipeline.integration_issues i where i.id = p_issue
$function$;
revoke all on function security.ops_issue_measure_v1(bigint) from public, anon, authenticated;

create or replace function security.ops_remedy_confirm_cleared_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Action of remedy confirm_condition_cleared: records that the issue's own check no longer sees its condition. Changes nothing.
declare r pipeline.integration_issues; v_ok boolean;
begin
  select * into r from pipeline.integration_issues where id = p_issue;
  v_ok := r.condition_cleared_at is not null and r.last_observed_at <= r.condition_cleared_at;
  return jsonb_build_object('ok', v_ok, 'changed', false, 'evidence', jsonb_build_object('check', r.detection_source, 'condition_cleared_at', r.condition_cleared_at,
           'last_observed_at', r.last_observed_at, 'hours_clear', round(extract(epoch from now() - r.condition_cleared_at) / 3600.0, 2), 'regression_count', r.regression_count));
end $function$;
revoke all on function security.ops_remedy_confirm_cleared_v1(bigint) from public, anon, authenticated;

create or replace function security.ops_verify_cleared_v1(p_issue bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- Verification (a later controller run than the action): passed when the issue's check has not seen the condition for ops.stale_clear_hours
-- with no recurrence. Cleared for less than that: waiting. Still seen: failed.
declare r pipeline.integration_issues; v_need numeric := security.pipeline_num_v1('ops.stale_clear_hours', 6); v_h numeric; v_clear boolean;
begin
  select * into r from pipeline.integration_issues where id = p_issue;
  v_clear := r.condition_cleared_at is not null and r.last_observed_at <= r.condition_cleared_at;
  v_h := case when v_clear then round(extract(epoch from now() - r.condition_cleared_at) / 3600.0, 2) end;
  return jsonb_build_object('passed', v_clear and v_h >= v_need,
    'measure', jsonb_build_object('condition_cleared', v_clear and v_h >= v_need, 'waiting', v_clear and v_h < v_need, 'cleared_at', r.condition_cleared_at,
                                  'hours_clear', v_h, 'hours_needed', v_need, 'last_observed_at', r.last_observed_at, 'regression_count', r.regression_count),
    'evidence', case when v_clear then format('The check (%s) has not seen the condition since %s: %s hours, %s needed; last seen %s; regressions %s.',
                                             r.detection_source, r.condition_cleared_at, v_h, v_need, r.last_observed_at, r.regression_count)
                     else format('The check (%s) still sees the condition (last seen %s).', r.detection_source, r.last_observed_at) end);
end $function$;
revoke all on function security.ops_verify_cleared_v1(bigint) from public, anon, authenticated;

create or replace function security.ops_remedy_capacity_profile_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Action of remedy record_capacity_profile: records the load profile (job runs, failure share, time-outs, rate limits, start-up failures).
-- Changes nothing; batch size and concurrency changes stay with the lane owners and their settings.
declare v jsonb := security.ops_issue_signals_v1(p_issue);
begin
  return jsonb_build_object('ok', true, 'changed', false, 'evidence', jsonb_build_object('job', v->'job', 'failure_share_pct', v->'failure_share_pct',
           'transient_share', v->'transient_share', 'timeout', v->'timeout', 'rate_limit', v->'rate_limit', 'boot_error', v->'boot_error', 'retry_count', v->'retry_count'));
end $function$;
revoke all on function security.ops_remedy_capacity_profile_v1(bigint) from public, anon, authenticated;

create or replace function security.ops_remedy_supersede_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Action of remedy supersede_into_owner (acceptance mandate §6, §18): the issue joins the issue that owns its shared cause. Its evidence, entities
-- and fingerprint are carried over to the owner (evidence.superseded), the owner lists it in supersedes, both histories record the link.
declare r pipeline.integration_issues; o pipeline.integration_issues; v_owner bigint; v_max int := security.pipeline_num_v1('integration.entity_ids_max', 500)::int;
begin
  select * into r from pipeline.integration_issues where id = p_issue;
  v_owner := security.ops_group_owner_v1(r.correlation_key);
  if v_owner is null or v_owner = p_issue then
    return jsonb_build_object('ok', false, 'changed', false, 'evidence', jsonb_build_object('reason', 'no other open issue owns this cause', 'key', r.correlation_key));
  end if;
  select * into o from pipeline.integration_issues where id = v_owner for update;
  update pipeline.integration_issues set superseded_by = v_owner, updated_at = now() where id = p_issue;
  update pipeline.integration_issues i set supersedes = (select coalesce(array_agg(distinct x), '{}') from unnest(i.supersedes || p_issue) x),
         evidence = i.evidence || jsonb_build_object('superseded', coalesce(i.evidence->'superseded', '{}'::jsonb) || jsonb_build_object(r.issue_ref,
                    jsonb_build_object('fingerprint', r.fingerprint, 'title', r.title, 'failure', left(r.failure, 500), 'evidence', r.evidence, 'detected_at', r.detected_at,
                                       'providers', cardinality(r.provider_ids), 'courses', cardinality(r.course_ids)))),
         provider_ids = (select coalesce(array_agg(distinct x), '{}') from unnest(i.provider_ids || r.provider_ids) x)[1:v_max],
         course_ids = (select coalesce(array_agg(distinct x), '{}') from unnest(i.course_ids || r.course_ids) x)[1:v_max],
         updated_at = now()
   where i.id = v_owner;
  insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail) values
    (p_issue, 'updated', r.status, r.status, 'ops-controller', 'Superseded by ' || o.issue_ref || ' (shared cause ' || r.correlation_key || ')', jsonb_build_object('superseded_by', v_owner)),
    (v_owner, 'updated', o.status, o.status, 'ops-controller', 'Supersedes ' || r.issue_ref || ' (shared cause ' || r.correlation_key || '); its evidence is carried over', jsonb_build_object('supersedes', p_issue));
  return jsonb_build_object('ok', true, 'changed', true, 'evidence', jsonb_build_object('owner', v_owner, 'owner_ref', o.issue_ref, 'key', r.correlation_key));
end $function$;
revoke all on function security.ops_remedy_supersede_v1(bigint) from public, anon, authenticated;

create or replace function security.ops_verify_owner_resolved_v1(p_issue bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- Verification of supersede_into_owner: passed when the owner was closed on verified evidence and this issue was not seen after that.
-- Owner still open: waiting (the issue stays superseded). Seen again after the owner closed: the link was wrong (superseded_invalid).
declare r pipeline.integration_issues; o pipeline.integration_issues;
begin
  select * into r from pipeline.integration_issues where id = p_issue;
  select * into o from pipeline.integration_issues where id = r.superseded_by;
  if o.id is null then return jsonb_build_object('passed', false, 'measure', jsonb_build_object('superseded_invalid', true), 'evidence', 'not linked to an owner'); end if;
  if o.status <> 'closed' then
    return jsonb_build_object('passed', false, 'measure', jsonb_build_object('waiting', true, 'owner', o.issue_ref, 'owner_status', o.status), 'evidence', o.issue_ref || ' is still open');
  end if;
  if r.last_observed_at > o.closed_at then
    return jsonb_build_object('passed', false, 'measure', jsonb_build_object('superseded_invalid', true, 'owner', o.issue_ref, 'owner_closed_at', o.closed_at, 'last_observed_at', r.last_observed_at),
                              'evidence', r.issue_ref || ' was seen again after ' || o.issue_ref || ' closed');
  end if;
  return jsonb_build_object('passed', o.verification_outcome = 'passed',
    'measure', jsonb_build_object('condition_cleared', o.verification_outcome = 'passed', 'owner', o.issue_ref, 'owner_closed_at', o.closed_at, 'owner_verification', o.verification_evidence),
    'evidence', format('Resolved by the shared correction verified on %s (closed %s): %s', o.issue_ref, o.closed_at, left(coalesce(o.verification_evidence->>'evidence', ''), 400)));
end $function$;
revoke all on function security.ops_verify_owner_resolved_v1(bigint) from public, anon, authenticated;

-- 2.9 the controller -------------------------------------------------------------------------------------------------------------------------
create or replace function security.ops_call_v1(p_fn regprocedure, p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Runs one registered action or verification with the authority boundary switched on for that call only (the triggers of part 2 refuse
-- protected writes while it is on). An error is returned, not raised, so one remedy never stops the run.
declare v jsonb;
begin
  perform set_config('cf247.ops_remedy', 'on', true);
  begin
    execute format('select %s($1)', p_fn::oid::regproc) into v using p_issue;
  exception when others then
    v := jsonb_build_object('ok', false, 'passed', false, 'error', left(sqlerrm, 300), 'sqlstate', sqlstate, 'refused_guard', sqlstate = '42501' and sqlerrm like 'ops guard:%');
  end;
  perform set_config('cf247.ops_remedy', '', true);
  return coalesce(v, '{}'::jsonb);
end $function$;
revoke all on function security.ops_call_v1(regprocedure, bigint) from public, anon, authenticated;

create or replace function security.ops_authorise_v1(p_remedy text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- The Authorise step (acceptance mandate §6): the remedy's authority against the backend matrix; the remedy is active; its functions still exist,
-- are still (bigint) returning jsonb and still stay inside the authority boundary (their text is checked again at every run).
declare m pipeline.ops_remedies; a pipeline.ops_authority_matrix; v_why text;
begin
  select * into m from pipeline.ops_remedies where code = p_remedy;
  select * into a from pipeline.ops_authority_matrix where authority = m.authority;
  v_why := case when m.code is null then 'remedy not registered' when a.authority is null then 'authority not in the matrix'
                when not a.executes then 'authority ' || m.authority || ' does not execute (' || coalesce(a.route_state, 'route') || ')'
                when not m.active then 'remedy switched off' when m.action_fn is null or m.verify_fn is null then 'no action or verification'
                when pg_get_functiondef(m.action_fn) ~* '(set_config|cf247\.ops_remedy|session_replication_role|disable\s+trigger|ops_remed[a-z]*_register|ops_root_cause)'
                  or pg_get_functiondef(m.verify_fn) ~* '(set_config|cf247\.ops_remedy|session_replication_role|disable\s+trigger|ops_remed[a-z]*_register|ops_root_cause)'
                  then 'function text reaches the authority boundary' end;
  return jsonb_build_object('remedy', p_remedy, 'authority', m.authority, 'matrix', to_jsonb(a), 'permitted', v_why is null, 'reason', coalesce(v_why, 'permitted'), 'at', now(),
                            'guarded', jsonb_build_array('remedy and root-cause registers', 'authority matrix', 'remedy runs', 'settings ranges, budgets, admission and controller settings',
                                                         'Layer 4 decisions and automatic admissions', 'manual locks', 'paid-service limits', 'closing an issue'));
end $function$;
revoke all on function security.ops_authorise_v1(text) from public, anon, authenticated;

create or replace function security.ops_route_v1(p_issue bigint, p_diag jsonb, p_reason text) returns text
language plpgsql security definer set search_path to '' as $function$
-- No executable remedy (or attempts used up): the issue is blocked with its evidence and the release or decision required. Changes the record
-- (and writes one history line) only when the state or the root cause changes, so a blocked issue is never retried in a loop.
declare r pipeline.integration_issues; rc pipeline.ops_root_causes; m pipeline.ops_remedies; v_state text; v_blocker jsonb;
begin
  select * into r from pipeline.integration_issues where id = p_issue;
  select * into rc from pipeline.ops_root_causes where code = p_diag->>'root_cause';
  select x.* into m from pipeline.ops_remedies x where x.active and x.authority in ('admin', 'release') and rc.code = any (x.treats)
   order by case x.authority when 'admin' then 0 else 1 end, x.code limit 1;
  v_state := coalesce(case when p_reason like 'attempts used up%' then 'needs_release' end,
                      (select a.route_state from pipeline.ops_authority_matrix a where a.authority = m.authority), rc.detect->>'route',
                      case when rc.class = 'policy' then 'needs_decision' else 'needs_release' end);
  v_blocker := jsonb_build_object('kind', case v_state when 'needs_decision' then 'decision' else 'release' end,
    'required', coalesce(m.title, 'A change through the release gates') || ': ' || coalesce(rc.description, rc.title),
    'root_cause', rc.code, 'reason', p_reason, 'recommended', rc.detect->>'recommend', 'issue_statement', left(r.failure, 500), 'expected', left(r.expected, 300),
    'impact', jsonb_build_object('severity', r.severity, 'providers', cardinality(r.provider_ids), 'courses', cardinality(r.course_ids), 'layer', r.layer),
    'evidence', p_diag->'evidence', 'owner_workstream', r.workstream, 'at', now());
  if r.ops_state is distinct from v_state or r.blocker->>'root_cause' is distinct from rc.code then
    update pipeline.integration_issues set ops_state = v_state, remedy_code = m.code, blocker = v_blocker, updated_at = now() where id = p_issue;
    insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail)
    values (p_issue, 'updated', r.status, r.status, 'ops-controller',
            case v_state when 'needs_decision' then 'Blocked: needs a Platform Admin decision. ' else 'Blocked: needs a release. ' end || left(v_blocker->>'required', 400),
            jsonb_build_object('ops_state', v_state, 'blocker', v_blocker));
  end if;
  return v_state;
end $function$;
revoke all on function security.ops_route_v1(bigint, jsonb, text) from public, anon, authenticated;

create or replace function security.ops_controller_tick_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 P0 (mandate 15:37 §2-§3, §13; acceptance mandate 15:52 §6, §18), job ops-controller. One run:
--   1 Verify: remedy runs acted on an earlier run whose cool-down has passed are verified; passed with the condition cleared closes the issue
--     through security.integration_issue_close_v1 (a superseded issue closes with its owner's verified evidence); a wrong supersession is undone.
--   2 Correlate: every open issue gets its correlation key; one owner per key.
--   3 Detect: task kinds that keep ending without data movement open one issue each (fingerprint no_movement:<kind>).
--   4 Diagnose, Plan, Authorise, Execute for the issues due (ops.issues_per_run, most severe first): deterministic diagnosis (AI-assisted
--     requests queued only while ops.ai_diagnosis_on); a non-owner of a strong group whose own cause is not a policy matter is superseded into
--     the owner; one remedy per group per run; auto remedies only, within attempts and cool-down, the most often verified first (Learn);
--     otherwise blocked as needs_release or needs_decision with the evidence and the decision required.
--   5 Report: an hourly checkpoint and a daily summary row (ops.checkpoint_on).
declare v_t0 timestamptz := now(); v_out jsonb; r record; i pipeline.integration_issues; m pipeline.ops_remedies; v_sig jsonb; v_diag jsonb; v_res jsonb;
        v_subj jsonb; v_key text; v_owner bigint; v_members int; v_auth jsonb; v_run bigint; v_max int; v_att int; v_cool int; v_keys text[] := '{}';
        v_n jsonb := jsonb_build_object('verified', 0, 'verify_failed', 0, 'waiting', 0, 'diagnosed', 0, 'acted', 0, 'action_failed', 0, 'blocked', 0,
                                        'superseded', 0, 'unlinked', 0, 'no_movement_issues', 0, 'ai_queued', 0, 'skipped_group', 0);
        v_rc pipeline.ops_root_causes; v_plan jsonb; v_prev text; v_seen text[] := '{}'; v_tz text := 'Australia/Melbourne';  -- fixed: the platform's reporting time zone
        v_ai boolean := security.pipeline_num_v1('ops.ai_diagnosis_on', 0) >= 1;
begin
  if security.pipeline_num_v1('ops.controller_on', 1) < 1 then return jsonb_build_object('off', true); end if;
  if not pg_try_advisory_xact_lock(hashtext('cf247:ops-controller')) then return jsonb_build_object('busy', true); end if;  -- fixed: one controller at a time
  perform set_config('cf247.ops_remedy', '', true);

  -- 1 Verify (only runs whose action finished before this run started) ------------------------------------------------------------------
  for r in select x.id run_id, x.issue_id, x.remedy_code, x.evidence from pipeline.ops_remedy_runs x
            where x.result = 'acted' and x.finished_at < v_t0 order by x.id loop
    select * into i from pipeline.integration_issues where id = r.issue_id;
    select * into m from pipeline.ops_remedies where code = r.remedy_code;
    if i.status = 'closed' and m.code <> 'supersede_into_owner' then
      update pipeline.ops_remedy_runs set result = 'closed_elsewhere', after = security.ops_issue_measure_v1(r.issue_id) where id = r.run_id; continue;
    end if;
    if coalesce(i.next_action_at, '-infinity') > v_t0 then continue; end if;
    v_res := security.ops_call_v1(m.verify_fn, r.issue_id);
    if coalesce((v_res->>'passed')::boolean, false) and coalesce((v_res->'measure'->>'condition_cleared')::boolean, false) then
      if i.status <> 'closed' then
        perform security.integration_issue_close_v1(r.issue_id, 'ops-controller', jsonb_build_object('outcome', 'passed',
          'evidence', m.title || ' verified on a later controller run than its action: ' || coalesce(v_res->>'evidence', ''),
          'checked_at', now(), 'reference', 'pipeline.ops_remedy_runs#' || r.run_id, 'remedy', m.code, 'root_cause', i.diagnosis->>'root_cause', 'measure', v_res->'measure'));
      end if;
      update pipeline.ops_remedy_runs set result = 'verified', after = security.ops_issue_measure_v1(r.issue_id) || jsonb_build_object('verify', v_res->'measure'),
             evidence = evidence || jsonb_build_object('verify', v_res->'evidence', 'verified_at', now(),
               'learn', jsonb_build_object('remedy', m.code, 'root_cause', i.diagnosis->>'root_cause', 'outcome', 'verified'))
       where id = r.run_id;
      update pipeline.integration_issues set ops_state = 'verified', next_action_at = null where id = r.issue_id;
      v_n := jsonb_set(v_n, '{verified}', to_jsonb((v_n->>'verified')::int + 1));
    elsif coalesce((v_res->'measure'->>'waiting')::boolean, false) then
      update pipeline.ops_remedy_runs set evidence = evidence || jsonb_build_object('last_wait', jsonb_build_object('at', now(), 'measure', v_res->'measure')) where id = r.run_id;
      update pipeline.integration_issues set next_action_at = now() + make_interval(mins => security.pipeline_num_v1(coalesce(m.cooldown_key, 'ops.cooldown_minutes'), 30)::int)
       where id = r.issue_id;
      v_n := jsonb_set(v_n, '{waiting}', to_jsonb((v_n->>'waiting')::int + 1));
    else
      update pipeline.ops_remedy_runs set result = 'verify_failed', after = security.ops_issue_measure_v1(r.issue_id) || jsonb_build_object('verify', v_res->'measure'),
             evidence = evidence || jsonb_build_object('verify', coalesce(v_res->'evidence', v_res->'error'), 'verified_at', now(),
               'learn', jsonb_build_object('remedy', m.code, 'root_cause', i.diagnosis->>'root_cause', 'outcome', 'verify_failed'))
       where id = r.run_id;
      if coalesce((v_res->'measure'->>'superseded_invalid')::boolean, false) and i.superseded_by is not null then
        update pipeline.integration_issues o set supersedes = array_remove(o.supersedes, r.issue_id) where o.id = i.superseded_by;
        update pipeline.integration_issues set superseded_by = null, ops_state = null, diagnosis = null where id = r.issue_id;
        insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail)
        values (r.issue_id, 'updated', i.status, i.status, 'ops-controller', 'No longer superseded: ' || coalesce(v_res->>'evidence', 'seen again after its owner closed'), v_res->'measure');
        v_n := jsonb_set(v_n, '{unlinked}', to_jsonb((v_n->>'unlinked')::int + 1));
      else
        update pipeline.integration_issues set ops_state = 'remedying', next_action_at = clock_timestamp() where id = r.issue_id;
      end if;
      v_n := jsonb_set(v_n, '{verify_failed}', to_jsonb((v_n->>'verify_failed')::int + 1));
    end if;
  end loop;

  -- 2 Correlate ---------------------------------------------------------------------------------------------------------------------------
  update pipeline.integration_issues x set correlation_key = k.key
    from (select y.id, security.ops_correlation_key_v1(y.id) key from pipeline.integration_issues y where y.status <> 'closed') k
   where x.id = k.id and x.correlation_key is distinct from k.key;

  -- 3 Detect: tasks that keep ending without data movement (outcome set by their runners, security.job_outcome_set_v1) -------------------------
  for r in select j.kind, count(*) n, max(j.finished_at) last_at from pipeline.admin_jobs j
            where j.outcome = 'succeeded_no_movement' and j.finished_at >= now() - make_interval(hours => security.pipeline_num_v1('ops.no_movement_window_hours', 6)::int)
            group by j.kind having count(*) >= security.pipeline_num_v1('ops.no_movement_min', 3) loop
    perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'no_movement:' || r.kind,
      'title', 'Tasks of kind ' || r.kind || ' end succeeded without data movement', 'layer', 'Scheduling', 'subsystem', 'pipeline.admin_jobs (' || r.kind || ')',
      'failure', r.n || ' task(s) of kind ' || r.kind || ' ended succeeded_no_movement in the window, the last at ' || r.last_at,
      'expected', 'A task with eligible work moves data; one without ends not_needed', 'source', 'ops-controller', 'validation_layer', 'V4',
      'evidence', jsonb_build_object('tasks', r.n, 'last_at', r.last_at), 'severity', 'P2', 'root_cause_class', 'code_defect', 'workstream', 'A7'), 'ops-controller');
    v_seen := v_seen || ('no_movement:' || r.kind);
    v_n := jsonb_set(v_n, '{no_movement_issues}', to_jsonb((v_n->>'no_movement_issues')::int + 1));
  end loop;
  for r in select x.id, x.status from pipeline.integration_issues x
            where x.fingerprint like 'no_movement:%' and x.status <> 'closed' and x.condition_cleared_at is null and not (x.fingerprint = any (v_seen)) loop
    update pipeline.integration_issues set condition_cleared_at = now() where id = r.id;
    insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note)
    values (r.id, 'not_observed', r.status, r.status, 'ops-controller', 'condition no longer observed; closes after verification');
  end loop;

  -- 4 Diagnose, Plan, Authorise, Execute ----------------------------------------------------------------------------------------------------
  for r in select x.id from pipeline.integration_issues x
            where x.status <> 'closed' and coalesce(x.next_action_at, '-infinity') <= v_t0
              and not exists (select 1 from pipeline.ops_remedy_runs u where u.issue_id = x.id and u.result in ('running', 'acted'))
            order by x.severity, x.id limit security.pipeline_num_v1('ops.issues_per_run', 60)::int loop
    select * into i from pipeline.integration_issues where id = r.id;
    v_subj := security.ops_issue_subject_v1(i.id);
    v_key := i.correlation_key;
    v_owner := security.ops_group_owner_v1(v_key);
    select count(*) into v_members from pipeline.integration_issues y where y.correlation_key = v_key and y.status <> 'closed';
    v_sig := security.ops_issue_signals_v1(i.id, jsonb_build_object('subject', v_subj,
               'group', jsonb_build_object('key', v_key, 'strength', v_subj->>'strength', 'owner', v_owner, 'members', v_members, 'is_owner', v_owner = i.id)));
    v_diag := security.ops_diagnose_v1(i.id, v_sig);
    select * into v_rc from pipeline.ops_root_causes where code = v_diag->>'root_cause';
    -- a non-owner of a strong group whose own cause is not a policy matter, and not already resolved on its own, is superseded into the owner
    if v_subj->>'strength' = 'strong' and v_members > 1 and v_owner is not null and v_owner <> i.id and i.superseded_by is null
       and v_rc.class <> 'policy' and v_rc.code <> 'condition_cleared_stale' then
      v_diag := v_diag || jsonb_build_object('root_cause', 'shared_cause_duplicate', 'contributing', jsonb_build_array(v_rc.code) || coalesce(v_diag->'contributing', '[]'::jsonb),
                                             'confidence', 0.8, 'evidence', coalesce(v_diag->'evidence', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('group', v_diag->'group')));
      select * into v_rc from pipeline.ops_root_causes where code = 'shared_cause_duplicate';
    end if;
    v_prev := i.diagnosis->>'root_cause';
    v_diag := v_diag || jsonb_build_object('first_at', coalesce(i.diagnosis->'first_at', to_jsonb(now())));
    if v_prev is distinct from v_diag->>'root_cause' or (i.diagnosis->>'confidence') is distinct from (v_diag->>'confidence') then
      update pipeline.integration_issues set diagnosis = v_diag, ops_state = coalesce(ops_state, 'diagnosed') where id = i.id;
      if i.status in ('detected', 'reopened') then
        perform security.integration_issue_transition_v1(i.id, 'triaged', 'ops-controller',
          'Diagnosed: ' || coalesce(v_rc.title, v_diag->>'root_cause') || ' (confidence ' || (v_diag->>'confidence') || ', ' || (v_diag->>'method') || ')', '{}'::jsonb);
      else
        insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail)
        values (i.id, 'updated', i.status, i.status, 'ops-controller', 'Diagnosis: ' || coalesce(v_rc.title, v_diag->>'root_cause') || ' (confidence ' || (v_diag->>'confidence') || ')', v_diag);
      end if;
      v_n := jsonb_set(v_n, '{diagnosed}', to_jsonb((v_n->>'diagnosed')::int + 1));
    else
      update pipeline.integration_issues set diagnosis = v_diag where id = i.id and diagnosis is distinct from v_diag;
    end if;
    -- AI-assisted diagnosis (off by default): a low-confidence diagnosis is queued once for the worker
    if v_ai and (v_diag->>'confidence')::numeric < security.pipeline_num_v1('ops.ai_min_confidence', 0.5)
       and not exists (select 1 from pipeline.ops_ai_diagnosis_requests q where q.issue_id = i.id and (q.state in ('queued', 'leased') or q.requested_at > now() - make_interval(hours => security.pipeline_num_v1('ops.recheck_hours', 6)::int))) then
      insert into pipeline.ops_ai_diagnosis_requests(issue_id, context)
      values (i.id, jsonb_build_object('issue', i.issue_ref, 'title', i.title, 'failure', i.failure, 'expected', i.expected, 'evidence', i.evidence, 'signals', v_sig,
                                       'deterministic', v_diag, 'root_causes', (select jsonb_agg(jsonb_build_object('code', c.code, 'class', c.class, 'title', c.title, 'description', c.description)) from pipeline.ops_root_causes c)));
      v_n := jsonb_set(v_n, '{ai_queued}', to_jsonb((v_n->>'ai_queued')::int + 1));
    end if;
    -- Plan: the auto remedies for the cause, the most often verified first (Learn); alternatives recorded
    select x.* into m from pipeline.ops_remedies x
     where x.active and x.authority = 'auto' and (v_diag->>'root_cause') = any (x.treats)
       -- a remedy verified through the issue's own check cannot help an issue no check observes (recorded by hand)
       and not (x.verify_fn = 'security.ops_verify_cleared_v1(bigint)'::regprocedure and not coalesce((v_sig->>'observed_by_check')::boolean, false))
     order by (select count(*) filter (where u.result = 'verified')::numeric / nullif(count(*) filter (where u.result in ('verified', 'verify_failed')), 0)
                 from pipeline.ops_remedy_runs u where u.remedy_code = x.code) desc nulls first, x.code limit 1;
    v_plan := jsonb_build_object('root_cause', v_diag->>'root_cause', 'proposed', m.code, 'authority', coalesce(m.authority, 'none'),
      'risk', case when m.code is null then 'none: no automatic action' else 'low: records, links or closes on verified evidence; protected writes refused in data' end,
      'alternatives', (select coalesce(jsonb_agg(jsonb_build_object('remedy', x.code, 'authority', x.authority,
                         'verified_rate', (select round(count(*) filter (where u.result = 'verified')::numeric / nullif(count(*) filter (where u.result in ('verified', 'verify_failed')), 0), 2)
                                            from pipeline.ops_remedy_runs u where u.remedy_code = x.code))), '[]'::jsonb)
                       from pipeline.ops_remedies x where x.active and (v_diag->>'root_cause') = any (x.treats)), 'at', now());
    update pipeline.integration_issues set ops_plan = v_plan where id = i.id and ops_plan is distinct from v_plan;
    if m.code is null then
      perform security.ops_route_v1(i.id, v_diag, 'no automatic remedy for ' || coalesce(v_diag->>'root_cause', 'this cause'));
      update pipeline.integration_issues set next_action_at = case
               when condition_cleared_at is not null and last_observed_at <= condition_cleared_at
                 then least(condition_cleared_at + make_interval(hours => security.pipeline_num_v1('ops.stale_clear_hours', 6)::int),
                            now() + make_interval(hours => security.pipeline_num_v1('ops.recheck_hours', 6)::int))
               else now() + make_interval(hours => security.pipeline_num_v1('ops.recheck_hours', 6)::int) end
       where id = i.id;
      v_n := jsonb_set(v_n, '{blocked}', to_jsonb((v_n->>'blocked')::int + 1));
      continue;
    end if;
    v_max := security.pipeline_num_v1(coalesce(m.max_attempts_key, 'ops.max_attempts'), 3)::int;
    v_att := case when i.remedy_code = m.code then i.remedy_attempts else 0 end;
    if v_att >= v_max then
      perform security.ops_route_v1(i.id, v_diag, 'attempts used up: ' || m.code || ' ran ' || v_att || ' time(s) without a verified result');
      update pipeline.integration_issues set next_action_at = now() + make_interval(hours => security.pipeline_num_v1('ops.recheck_hours', 6)::int) where id = i.id;
      v_n := jsonb_set(v_n, '{blocked}', to_jsonb((v_n->>'blocked')::int + 1));
      continue;
    end if;
    -- one remedy per shared cause per run (linking a duplicate to its owner does not act on the defect, so it is not held back)
    if m.code <> 'supersede_into_owner' and v_key = any (v_keys) then v_n := jsonb_set(v_n, '{skipped_group}', to_jsonb((v_n->>'skipped_group')::int + 1)); continue; end if;
    perform pg_advisory_xact_lock(hashtext('cf247:ops:group:' || coalesce(v_key, i.fingerprint)));  -- fixed: one remedy per shared cause at a time
    -- Authorise (recorded on the run)
    v_auth := security.ops_authorise_v1(m.code);
    insert into pipeline.ops_remedy_runs(issue_id, remedy_code, started_at, before, result, evidence)
    values (i.id, m.code, clock_timestamp(), security.ops_issue_measure_v1(i.id), 'running',
            jsonb_build_object('diagnosis', v_diag - 'evidence', 'plan', v_plan, 'authorise', v_auth, 'group', v_key, 'controller_run', v_t0))
    returning id into v_run;
    if not (v_auth->>'permitted')::boolean then
      update pipeline.ops_remedy_runs set finished_at = clock_timestamp(), result = 'refused_authority' where id = v_run;
      perform security.ops_route_v1(i.id, v_diag, 'not authorised: ' || (v_auth->>'reason'));
      continue;
    end if;
    -- Execute
    v_res := security.ops_call_v1(m.action_fn, i.id);
    update pipeline.ops_remedy_runs set finished_at = clock_timestamp(),
           result = case when coalesce((v_res->>'ok')::boolean, false) then 'acted' when coalesce((v_res->>'refused_guard')::boolean, false) then 'refused_guard' else 'action_failed' end,
           evidence = evidence || jsonb_build_object('action', v_res)
     where id = v_run;
    update pipeline.integration_issues set remedy_code = m.code, remedy_attempts = v_att + 1,
           ops_state = case when coalesce((v_res->>'ok')::boolean, false) then case when m.code = 'supersede_into_owner' then 'superseded' else 'verifying' end else 'remedying' end,
           blocker = null,
           next_action_at = now() + make_interval(mins => security.pipeline_num_v1(coalesce(m.cooldown_key, 'ops.cooldown_minutes'), 30)::int)
     where id = i.id;
    if m.code <> 'supersede_into_owner' then v_keys := v_keys || coalesce(v_key, i.fingerprint); end if;
    if coalesce((v_res->>'ok')::boolean, false) then
      v_n := jsonb_set(v_n, '{acted}', to_jsonb((v_n->>'acted')::int + 1));
      if m.code = 'supersede_into_owner' then v_n := jsonb_set(v_n, '{superseded}', to_jsonb((v_n->>'superseded')::int + 1)); end if;
    else v_n := jsonb_set(v_n, '{action_failed}', to_jsonb((v_n->>'action_failed')::int + 1)); end if;
  end loop;

  -- 5 Report: hourly checkpoint and daily summary rows (never a notification) ---------------------------------------------------------------
  if security.pipeline_num_v1('ops.checkpoint_on', 1) >= 1 then
    if not exists (select 1 from pipeline.ops_checkpoints c where c.kind = 'hourly' and c.at > now() - make_interval(mins => security.pipeline_num_v1('ops.checkpoint_minutes', 60)::int)) then
      insert into pipeline.ops_checkpoints(kind, window_hours, report) values ('hourly', 1, security.ops_report_v1(1));
    end if;
    if extract(hour from now() at time zone v_tz) >= security.pipeline_num_v1('ops.daily_summary_hour', 7)
       and not exists (select 1 from pipeline.ops_checkpoints c where c.kind = 'daily' and (c.at at time zone v_tz)::date = (now() at time zone v_tz)::date) then
      insert into pipeline.ops_checkpoints(kind, window_hours, report) values ('daily', 24, security.ops_report_v1(24));  -- fixed: a daily summary covers a day
    end if;
  end if;

  v_out := v_n || jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  insert into pipeline.integration_validate_state as t(check_key, last_run_at, last_found, last_ms, detail)
  values ('ops_controller', now(), (v_n->>'diagnosed')::int, (v_out->>'ms')::int, v_out)
  on conflict (check_key) do update set last_run_at = now(), last_found = excluded.last_found, last_ms = excluded.last_ms, detail = excluded.detail, last_error = null;
  return v_out;
end $function$;
revoke all on function security.ops_controller_tick_v1() from public, anon, authenticated;

-- 2.10 reconciliation and the consolidated report ---------------------------------------------------------------------------------------------
create or replace function security.ops_issue_end_state_v1(p_issue bigint) returns text
language sql stable security definer set search_path to '' as $function$
-- Acceptance mandate §18: verified_resolved, superseded (with traceability), blocked (evidence and the decision required) are end states;
-- remedy_verifying and open are not.
  select case when i.status = 'closed' and i.verification_outcome = 'passed' then 'verified_resolved'
              when i.superseded_by is not null then 'superseded'
              when i.ops_state in ('needs_release', 'needs_decision') and i.blocker is not null then 'blocked'
              when i.ops_state = 'verifying' then 'remedy_verifying' else 'open' end
    from pipeline.integration_issues i where i.id = p_issue
$function$;
revoke all on function security.ops_issue_end_state_v1(bigint) from public, anon, authenticated;

create or replace function security.ops_reconciliation_v1(p_cohort text default null) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- Acceptance mandate §18: issue -> end state -> evidence, for a baseline cohort (pipeline.ops_baseline_cohort) or, with no cohort, every issue.
  select jsonb_build_object('cohort', p_cohort,
    'by_end_state', (select coalesce(jsonb_object_agg(e, n), '{}'::jsonb) from (select security.ops_issue_end_state_v1(i.id) e, count(*) n from pipeline.integration_issues i
                      where p_cohort is null or i.id in (select b.issue_id from pipeline.ops_baseline_cohort b where b.cohort = p_cohort) group by 1) x),
    'issues', (select coalesce(jsonb_agg(jsonb_build_object('issue', i.issue_ref, 'status', i.status, 'end_state', security.ops_issue_end_state_v1(i.id),
                 'root_cause', i.diagnosis->>'root_cause', 'confidence', i.diagnosis->'confidence', 'contributing', i.diagnosis->'contributing', 'group', i.correlation_key,
                 'superseded_by', (select o.issue_ref from pipeline.integration_issues o where o.id = i.superseded_by), 'supersedes', to_jsonb(i.supersedes),
                 'blocked', case when i.blocker is not null then jsonb_build_object('kind', i.blocker->>'kind', 'required', i.blocker->>'required') end,
                 'verification', case when i.status = 'closed' then left(i.verification_evidence->>'evidence', 300) end, 'remedy', i.remedy_code) order by i.id), '[]'::jsonb)
                 from pipeline.integration_issues i
                where p_cohort is null or i.id in (select b.issue_id from pipeline.ops_baseline_cohort b where b.cohort = p_cohort)))
$function$;
revoke all on function security.ops_reconciliation_v1(text) from public, anon, authenticated;

create or replace function security.ops_report_v1(p_window_hours int default 24) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 P0: the one consolidated operational report (mandate 15:37 §16; acceptance mandate 15:52 §17 scorecard, §18 targets), built from
-- existing tables only. Sections: platform health, data improvement, autonomy (with the scorecard metrics), efficiency, governance,
-- reconciliation of the historical cohort and the correlated groups. Each section is read on its own; one that cannot be read reports its
-- error instead of failing the report. Bounded reads (ops.runs_scan scheduler runs, ops.report_items_scan field items, indexed windows).
declare v_since timestamptz := now() - make_interval(hours => greatest(coalesce(p_window_hours, 24), 1));
        v_scan int := security.pipeline_num_v1('ops.runs_scan', 20000)::int; v_items int := security.pipeline_num_v1('ops.report_items_scan', 200000)::int;
        v_out jsonb := '{}'::jsonb; v jsonb; v_eligible int; v_resolved int; v_x jsonb; v_maxid bigint;
begin
  v_out := jsonb_build_object('window_hours', p_window_hours, 'since', v_since, 'generated_at', now(),
    'operating_mode', (select jsonb_build_object('mode', m.mode, 'set_by', m.set_by, 'set_at', m.set_at) from pipeline.integration_operating_mode m where m.id = 1),
    'controller', (select jsonb_build_object('on', security.pipeline_num_v1('ops.controller_on', 1) >= 1, 'job_active', coalesce((select j.active from cron.job j where j.jobname = 'ops-controller'), false),
                   'last_run', s.last_run_at, 'last', s.detail) from pipeline.integration_validate_state s where s.check_key = 'ops_controller'));

  -- platform health: scheduler and workers, failures, time-outs, stuck work, recovery
  begin
    with d as (select x.jobid, x.status, x.return_message, x.start_time from cron.job_run_details x
                where x.runid > (select coalesce(max(y.runid), 0) from cron.job_run_details y) - v_scan and x.start_time >= v_since)
    select jsonb_build_object('active_jobs', (select count(*) from cron.job j where j.active), 'runs', count(*), 'failed', count(*) filter (where d.status = 'failed'),
             'failed_timeouts', count(*) filter (where d.status = 'failed' and d.return_message ~* '(statement timeout|canceling statement|timed? ?out)'),
             'failing_jobs', coalesce((select jsonb_agg(jsonb_build_object('job', z.jobname, 'failed', z.n, 'last', z.msg) order by z.n desc) from (
                select j.jobname, count(*) n, (array_agg(left(split_part(d2.return_message, E'\n', 1), 160) order by d2.start_time desc))[1] msg from d d2 join cron.job j on j.jobid = d2.jobid
                 where d2.status = 'failed' group by j.jobname order by count(*) desc limit 10) z), '[]'::jsonb))
      into v from d;
    v := v || jsonb_build_object('workers', (select jsonb_build_object('calls', count(*), 'failed_calls', count(*) filter (where l.status >= 400 or coalesce(l.failed, 0) > 0),
               'items', coalesce(sum(l.items), 0), 'ok', coalesce(sum(l.ok), 0), 'zero_item_calls', count(*) filter (where coalesce(l.items, 0) = 0))
               from pipeline.mode_outcome_ledger l where l.run_at >= v_since),
             'stuck', jsonb_build_object('stale_lease_issues', (select count(*) from pipeline.integration_issues i where i.status <> 'closed' and i.fingerprint like 'stale_lease:%'),
               'stuck_draft_issues', (select count(*) from pipeline.integration_issues i where i.status <> 'closed' and i.fingerprint like 'draft_stuck:%'),
               'tasks_running_without_progress', (select count(*) from pipeline.admin_jobs j where j.state = 'running'
                  and j.updated_at < now() - make_interval(mins => security.pipeline_num_v1('integration.lease_stale_minutes', 60)::int))),
             'recovery', (select coalesce(jsonb_object_agg(z.result, z.n), '{}'::jsonb) from (select u.result, count(*) n from pipeline.ops_remedy_runs u where u.started_at >= v_since group by 1) z));
    v_out := v_out || jsonb_build_object('platform_health', v);
  exception when others then v_out := v_out || jsonb_build_object('platform_health', jsonb_build_object('error', left(sqlerrm, 200)));
  end;

  -- data improvement: missing values at the start and end of the window, values filled, courses repaired, scholarships, page identities
  begin
    select max(id) into v_maxid from pipeline.field_enrich_items;
    v := jsonb_build_object(
      'missing_values', (with s as (select min(g.at) a0, max(g.at) a1 from pipeline.gap_cause_snapshots g where g.at >= v_since)
                         select coalesce(jsonb_object_agg(x.attribute, jsonb_build_object('start', x.st, 'end', x.en, 'change', x.en - x.st)), '{}'::jsonb)
                           from (select g.attribute, sum(g.courses) filter (where g.at = s.a0) st, sum(g.courses) filter (where g.at = s.a1) en
                                   from pipeline.gap_cause_snapshots g, s where g.at in (s.a0, s.a1) group by g.attribute) x),
      'field_values', (select coalesce(jsonb_object_agg(x.field, jsonb_build_object('filled', x.f, 'to_review', x.rv, 'skipped', x.sk, 'failed', x.fa)), '{}'::jsonb)
                         from (select e.field, count(*) filter (where e.state = 'filled') f, count(*) filter (where e.state = 'review') rv,
                                      count(*) filter (where e.state = 'skipped') sk, count(*) filter (where e.state = 'failed') fa
                                 from pipeline.field_enrich_items e where e.id > coalesce(v_maxid, 0) - v_items and e.updated_at >= v_since group by e.field) x),
      'courses_repaired', (select count(distinct e.course_id) from pipeline.field_enrich_items e where e.id > coalesce(v_maxid, 0) - v_items and e.updated_at >= v_since and e.state = 'filled'),
      'scholarships_added', (select count(*) from scholarship.scholarships s where s.created_at >= v_since),
      'scholarships_published', (select count(*) from scholarship.scholarships s where s.created_at >= v_since and s.publication_status = 'published'),
      'page_identities_proven', (select count(*) from pipeline.course_page_proofs p where p.proven and p.checked_at >= v_since));
    v_out := v_out || jsonb_build_object('data_improvement', v);
  exception when others then v_out := v_out || jsonb_build_object('data_improvement', jsonb_build_object('error', left(sqlerrm, 200)));
  end;

  -- autonomy, with the scorecard metrics (acceptance mandate §17, §18)
  begin
    select count(*) filter (where c.class <> 'policy'), count(*) filter (where c.class <> 'policy' and i.status = 'closed' and i.closed_at >= v_since and i.verified_by = 'ops-controller')
      into v_eligible, v_resolved
      from pipeline.integration_issues i join pipeline.ops_root_causes c on c.code = i.diagnosis->>'root_cause'
     where (i.status <> 'closed' or i.closed_at >= v_since) and i.detected_at < now();
    v := jsonb_build_object(
      'detected', (select count(*) from pipeline.integration_issues i where i.detected_at >= v_since),
      'detected_automatically', (select count(*) from pipeline.integration_issues i where i.detected_at >= v_since and i.validation_layer in ('V3', 'V4')),
      'diagnosed', (select count(*) from pipeline.integration_issues i where (i.diagnosis->>'first_at')::timestamptz >= v_since),
      'remedies_executed', (select count(*) from pipeline.ops_remedy_runs u where u.started_at >= v_since and u.result not in ('refused_authority')),
      'remedies_verified', (select count(*) from pipeline.ops_remedy_runs u where u.result = 'verified' and (u.evidence->>'verified_at')::timestamptz >= v_since),
      'remedies_failed_verification', (select count(*) from pipeline.ops_remedy_runs u where u.result = 'verify_failed' and (u.evidence->>'verified_at')::timestamptz >= v_since),
      'closed_by_controller', (select count(*) from pipeline.integration_issues i where i.status = 'closed' and i.closed_at >= v_since and i.verified_by = 'ops-controller'),
      'reopened', (select count(*) from pipeline.integration_issue_events e where e.kind = 'reopened_regression' and e.at >= v_since),
      'needing_decisions', (select count(*) from pipeline.integration_issues i where i.status <> 'closed' and i.ops_state = 'needs_decision'),
      'needing_release', (select count(*) from pipeline.integration_issues i where i.status <> 'closed' and i.ops_state = 'needs_release'),
      'superseded_open', (select count(*) from pipeline.integration_issues i where i.status <> 'closed' and i.superseded_by is not null),
      'root_causes_open', (select coalesce(jsonb_object_agg(z.rc, z.n), '{}'::jsonb) from (select coalesce(i.diagnosis->>'root_cause', 'not diagnosed') rc, count(*) n
                            from pipeline.integration_issues i where i.status <> 'closed' group by 1) z),
      'scorecard', jsonb_build_object(
        'autonomous_resolution_pct', case when v_eligible > 0 then round(100.0 * v_resolved / v_eligible, 1) end,
        'autonomous_resolution_basis', jsonb_build_object('resolved_by_controller', v_resolved, 'eligible', v_eligible,
          'excluded_policy_evidence_approval', (select count(*) from pipeline.integration_issues i join pipeline.ops_root_causes c on c.code = i.diagnosis->>'root_cause'
                                                 where c.class = 'policy' and (i.status <> 'closed' or i.closed_at >= v_since)),
          'rule', 'eligible: issues open in the window whose diagnosed cause is not a policy, external-evidence or approval matter (those are reported separately); needs_release issues stay in the denominator'),
        'detection_to_diagnosis_minutes_median', (select round(percentile_cont(0.5) within group (order by extract(epoch from (i.diagnosis->>'first_at')::timestamptz - i.detected_at) / 60)::numeric, 1)
                                                   from pipeline.integration_issues i where (i.diagnosis->>'first_at')::timestamptz >= v_since),
        'diagnosis_to_resolution_minutes_median', (select round(percentile_cont(0.5) within group (order by extract(epoch from i.closed_at - (i.diagnosis->>'first_at')::timestamptz) / 60)::numeric, 1)
                                                    from pipeline.integration_issues i where i.status = 'closed' and i.closed_at >= v_since and i.verified_by = 'ops-controller'),
        'recurrence', jsonb_build_object('reopened_in_window', (select count(*) from pipeline.integration_issue_events e where e.kind = 'reopened_regression' and e.at >= v_since),
                                         'controller_closures_reopened', (select count(*) from pipeline.integration_issues i where i.regression_count > 0 and i.status <> 'closed'
                                                                           and exists (select 1 from pipeline.ops_remedy_runs u where u.issue_id = i.id and u.result = 'verified')))));
    v_out := v_out || jsonb_build_object('autonomy', v);
  exception when others then v_out := v_out || jsonb_build_object('autonomy', jsonb_build_object('error', left(sqlerrm, 200)));
  end;

  -- efficiency: paid work, AI, yield, avoided reads, cost per verified improvement
  begin
    v := jsonb_build_object(
      'firecrawl_credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.at >= v_since),
      'ai_usd', (select round(coalesce(sum(a.cost_usd), 0), 2) from pipeline.ai_spend_ledger a where a.at >= v_since),
      'ai_calls', (select coalesce(sum(a.calls), 0) from pipeline.ai_spend_ledger a where a.at >= v_since),
      'paid_reads_refused_today', (select coalesce(sum(r.n), 0) from pipeline.firecrawl_budget_refusals r where r.day = (now() at time zone 'UTC')::date),
      'items_per_worker_call', (select round(coalesce(sum(l.items), 0)::numeric / nullif(count(*), 0), 2) from pipeline.mode_outcome_ledger l where l.run_at >= v_since),
      'zero_item_share_pct', (select round(100.0 * count(*) filter (where coalesce(l.items, 0) = 0) / nullif(count(*), 0), 1) from pipeline.mode_outcome_ledger l where l.run_at >= v_since));
    v := v || jsonb_build_object('usd_per_filled_value', case when coalesce(((v_out->'data_improvement'->>'courses_repaired')::int), 0) > 0
             then round((v->>'ai_usd')::numeric / (select sum((x.value->>'filled')::int) from jsonb_each(coalesce(v_out->'data_improvement'->'field_values', '{}'::jsonb)) x)::numeric, 4) end,
             'note', 'repeated paid reads and evidence-cache reuse come from workstream F (ops_cost_*) when released');
    v_out := v_out || jsonb_build_object('efficiency', v);
  exception when others then v_out := v_out || jsonb_build_object('efficiency', jsonb_build_object('error', left(sqlerrm, 200)));
  end;

  -- governance: releases, regressions, Layer 4, open policy blockers, consumer consistency
  begin
    v := jsonb_build_object(
      'releases', (select coalesce(jsonb_agg(jsonb_build_object('release', x.release, 'at', x.at, 'source', x.source) order by x.at), '[]'::jsonb) from security.ops_releases_v1() x where x.at >= v_since),
      'deploy_checks_failed', (select count(*) from pipeline.integration_deploy_checks d where d.checked_at >= v_since and not d.ok),
      'regressions_reopened', (select count(*) from pipeline.integration_issue_events e where e.kind = 'reopened_regression' and e.at >= v_since),
      'layer4', (select jsonb_build_object('pending', count(*) filter (where r.status = 'pending'),
                   'decided_in_window', count(*) filter (where r.decided_at >= v_since), 'approved_in_window', count(*) filter (where r.decided_at >= v_since and r.status in ('approved', 'edited_approved')))
                   from pipeline.layer4_review_items r where r.status = 'pending' or r.decided_at >= v_since),
      'open_policy_blockers', (select coalesce(jsonb_agg(jsonb_build_object('issue', i.issue_ref, 'title', left(i.title, 120), 'required', left(i.blocker->>'required', 300)) order by i.severity, i.id), '[]'::jsonb)
                                 from pipeline.integration_issues i where i.status <> 'closed' and i.ops_state = 'needs_decision'),
      'consumer_guard', (select jsonb_build_object('last_status', (array_agg(d.status order by d.runid desc))[1], 'last_at', max(d.start_time))
                           from cron.job_run_details d where d.runid > (select coalesce(max(y.runid), 0) from cron.job_run_details y) - v_scan
                            and d.jobid in (select j.jobid from cron.job j where j.jobname = 'consumer-api-guard')),
      'learning', case when to_regclass('pipeline.ai_instruction_versions') is not null then 'see workstream E (ai_instruction_versions)' else 'workstream E not released' end);
    v_out := v_out || jsonb_build_object('governance', v);
  exception when others then v_out := v_out || jsonb_build_object('governance', jsonb_build_object('error', left(sqlerrm, 200)));
  end;

  -- the historical cohort and the correlated groups
  begin
    v_x := security.ops_reconciliation_v1('p0-2026-11-03-detected-48');
    v_out := v_out || jsonb_build_object('reconciliation', jsonb_build_object('cohort', v_x->'cohort', 'by_end_state', v_x->'by_end_state',
               'issues', (select count(*) from pipeline.ops_baseline_cohort b where b.cohort = 'p0-2026-11-03-detected-48')),
             'groups', (select coalesce(jsonb_agg(g), '[]'::jsonb) from jsonb_array_elements(security.ops_correlation_groups_v1()) g where (g->>'open')::int > 1));
  exception when others then v_out := v_out || jsonb_build_object('reconciliation', jsonb_build_object('error', left(sqlerrm, 200)));
  end;
  return v_out;
end $function$;
revoke all on function security.ops_report_v1(int) from public, anon, authenticated;

-- 2.11 AI-assisted diagnosis: the worker's picker and recorder (DB side; the worker mode ops_diagnose is an interface request to workstream B) --
create or replace function public.svc_ops_diagnosis_next(p_limit int) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Hands queued AI diagnosis requests to the worker while ops.ai_diagnosis_on is 1, within ops.ai_requests_per_day and while today's AI spend is
-- under budgets.ai_daily_ceiling_usd. Each comes with the pinned model and the context it may quote.
declare v jsonb; v_today int; v_room int; v_tz text := 'Australia/Melbourne';  -- fixed: the platform's reporting time zone
begin
  if security.pipeline_num_v1('ops.ai_diagnosis_on', 0) < 1 then return jsonb_build_object('items', '[]'::jsonb, 'held', 'ops.ai_diagnosis_on is 0'); end if;
  if (select coalesce(sum(t.spent), 0) from security.ai_spend_today_v1() t) >= security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) then
    return jsonb_build_object('items', '[]'::jsonb, 'held', 'daily AI ceiling reached');
  end if;
  select count(*) into v_today from pipeline.ops_ai_diagnosis_requests q where q.state in ('leased', 'answered') and (q.requested_at at time zone v_tz)::date = (now() at time zone v_tz)::date;
  v_room := greatest(least(coalesce(p_limit, 1), security.pipeline_num_v1('ops.ai_requests_per_day', 20)::int - v_today), 0);
  with c as (select q.id from pipeline.ops_ai_diagnosis_requests q where q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())
              order by q.requested_at limit v_room for update skip locked)
  update pipeline.ops_ai_diagnosis_requests q set state = 'leased', leased_until = now() + interval '10 minutes',  -- fixed: lease timer
         model = coalesce(security.toolset_setting('pipeline', 'ops.ai_diagnosis_model') #>> '{}', 'openai/gpt-4.1-mini')
    from c where q.id = c.id;
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'model', q.model, 'context', q.context)), '[]'::jsonb) into v
    from pipeline.ops_ai_diagnosis_requests q where q.state = 'leased' and q.leased_until > now();
  return jsonb_build_object('items', v);
end $function$;
revoke all on function public.svc_ops_diagnosis_next(int) from public, anon, authenticated;

create or replace function public.svc_ops_diagnosis_record(p_id bigint, p_answer jsonb, p_cost_usd numeric default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Records an AI diagnosis answer {root_cause, confidence, evidence: [quotes], reasoning}. Refused unless it names a registered root cause and
-- every quote is found in the context it was given. Applied to the issue (method ai_assisted) only when its confidence reaches
-- ops.ai_min_confidence and beats the deterministic one; otherwise kept as advice. It never chooses a remedy or an authority.
declare q pipeline.ops_ai_diagnosis_requests; v_ctx text; v_bad int; v_conf numeric := (p_answer->>'confidence')::numeric; v_applied boolean := false; i pipeline.integration_issues;
begin
  select * into q from pipeline.ops_ai_diagnosis_requests where id = p_id for update;
  if not found or q.state <> 'leased' then raise exception 'no leased AI diagnosis request %', p_id using errcode = 'P0002'; end if;
  v_ctx := q.context::text;
  select count(*) into v_bad from jsonb_array_elements_text(coalesce(p_answer->'evidence', '[]'::jsonb)) e where position(e in v_ctx) = 0;
  if not exists (select 1 from pipeline.ops_root_causes c where c.code = p_answer->>'root_cause') or v_conf is null or v_conf < 0 or v_conf > 1
     or jsonb_array_length(coalesce(p_answer->'evidence', '[]'::jsonb)) = 0 or v_bad > 0 then
    update pipeline.ops_ai_diagnosis_requests set state = 'refused', answer = p_answer, cost_usd = p_cost_usd, answered_at = now(),
           note = 'refused: unknown root cause, confidence outside 0 to 1, or evidence not quoted from the context' where id = p_id;
    return jsonb_build_object('id', p_id, 'state', 'refused');
  end if;
  select * into i from pipeline.integration_issues where id = q.issue_id for update;
  if v_conf >= security.pipeline_num_v1('ops.ai_min_confidence', 0.5) and v_conf > coalesce((i.diagnosis->>'confidence')::numeric, 0) then
    update pipeline.integration_issues set diagnosis = coalesce(diagnosis, '{}'::jsonb) || jsonb_build_object('root_cause', p_answer->>'root_cause', 'confidence', v_conf,
             'evidence', p_answer->'evidence', 'method', 'ai_assisted', 'at', now(), 'model', q.model, 'deterministic', i.diagnosis->>'root_cause', 'request', p_id),
           next_action_at = now() where id = q.issue_id;
    v_applied := true;
  end if;
  update pipeline.ops_ai_diagnosis_requests set state = 'answered', answer = p_answer, cost_usd = p_cost_usd, answered_at = now(),
         note = case when v_applied then 'applied to the diagnosis' else 'kept as advice (confidence not above the deterministic diagnosis or the minimum)' end where id = p_id;
  return jsonb_build_object('id', p_id, 'state', 'answered', 'applied', v_applied);
end $function$;
revoke all on function public.svc_ops_diagnosis_record(bigint, jsonb, numeric) from public, anon, authenticated;
do $g$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.svc_ops_diagnosis_next(int) to service_role';
    execute 'grant execute on function public.svc_ops_diagnosis_record(bigint, jsonb, numeric) to service_role';
  end if;
end $g$;

-- 2.12 seeds: root causes and remedies for the issue families live on 3 Nov 2026 --------------------------------------------------------------
select security.ops_root_cause_register_v1(x.code, x.spec) from (values
 ('condition_cleared_stale', '{"class": "transient", "title": "The condition has cleared and stayed clear", "description": "The issue''s own check has not seen the condition for ops.stale_clear_hours with no recurrence; it is verified and closed on that evidence.", "detect": {"priority": 5, "confidence": 0.9, "all": [{"signal": "cleared_hours", "min_setting": "ops.stale_clear_hours", "default": 6}]}}'::jsonb),
 ('shared_cause_duplicate', '{"class": "data", "title": "Same upstream cause as another open issue", "description": "Another open issue owns this issue''s correlated cause (same job, worker mode, function or check family); this one is superseded into it with its evidence carried over and closes when the owner is verified.", "detect": {"priority": 6, "confidence": 0.8}}'::jsonb),
 ('regression_after_close', '{"class": "rule", "title": "Regression: the defect came back after it was closed", "description": "The same fingerprint was seen again after the issue closed (regression_count above 0): the earlier correction did not hold.", "detect": {"priority": 10, "confidence": 0.8, "any": [{"signal": "recurred"}]}}'::jsonb),
 ('regression_after_release', '{"class": "rule", "title": "Regression: a new failure started right after a release", "description": "A job that succeeded before began failing within ops.regression_window_hours after a recorded release (migration apply time, deploy check or issue moved to deployed).", "detect": {"priority": 15, "confidence": 0.75, "all": [{"signal": "after_release"}, {"signal": "job_failing"}], "recommend": "Compare the release''s changes with the failing path; fix forward in the owning workstream, then verify the job''s runs."}}'::jsonb),
 ('manual_lock_unguarded_in_batch', '{"class": "rule", "title": "A batch job stops on one item''s manual-lock refusal", "description": "An item-level refusal (a page or value set by hand) is raised inside a batch outside the per-item exception block, so the whole batch rolls back and the same item returns next run.", "detect": {"priority": 20, "confidence": 0.9, "all": [{"signal": "lock_refusal"}, {"signal": "job_failing"}], "recommend": "Skip locked items before the apply (as for held links), or catch the refusal per item; never remove the lock."}}'::jsonb),
 ('permanent_job_error', '{"class": "rule", "title": "A job fails every run with the same error (not load)", "description": "ops.permanent_after_runs or more failed runs in a row with one error that is not a time-out or rate limit: a rule or data defect, not transient.", "detect": {"priority": 25, "confidence": 0.8, "all": [{"signal": "permanent_failure"}]}}'::jsonb),
 ('retry_loop_no_new_evidence', '{"class": "rule", "title": "Retry loop with no new evidence", "description": "The same failure repeats run after run (ops.retry_loop_runs) with nothing new: retrying cannot help.", "detect": {"priority": 30, "confidence": 0.7, "all": [{"signal": "retry_loop"}, {"signal": "job_failing"}]}}'::jsonb),
 ('rate_limited', '{"class": "transient", "title": "Rate limited by a service", "description": "HTTP 429 or a rate-limit answer: transient; the load profile is recorded and the issue is checked again.", "detect": {"priority": 35, "confidence": 0.7, "any": [{"signal": "rate_limit"}]}}'::jsonb),
 ('timeout_under_load', '{"class": "capacity", "title": "Time-outs under load", "description": "Statement or call time-outs. When a job fails only part of its runs they are load (transient); the load profile is recorded and checked again; a lasting pattern needs a batch-size or concurrency release.", "detect": {"priority": 40, "confidence": 0.7, "any": [{"signal": "timeout"}, {"fingerprint_like": ["health:search_probe:%"]}]}}'::jsonb),
 ('runtime_start_failure', '{"class": "dependency", "title": "The worker runtime failed to start", "description": "Edge runtime start-up failures (BOOT_ERROR, 503) during bursts; the calls are retried by their lanes.", "detect": {"priority": 45, "confidence": 0.6, "any": [{"signal": "boot_error"}, {"fingerprint_like": ["health:edge_calls:%"]}]}}'::jsonb),
 ('done_without_movement', '{"class": "rule", "title": "Work counted as done without data movement", "description": "Calls or tasks that report success while moving no data (zero-yield, 0 of 0, done while held).", "detect": {"priority": 50, "confidence": 0.7, "any": [{"signal": "no_movement"}]}}'::jsonb),
 ('layer4_generator_defect', '{"class": "rule", "title": "Layer 4 items raised twice or raised again after a decision", "description": "A generator raises duplicate pending items or a proposal already decided (Decision 263): fix the generator, not the reviews.", "detect": {"priority": 55, "confidence": 0.8, "any": [{"fingerprint_like": ["l4_duplicate:%", "l4_regenerated:%"]}]}}'::jsonb),
 ('lifecycle_leak', '{"class": "data", "title": "Work or records left behind by a retirement", "description": "Pending items, spend or search records that belong to retired or archived entities.", "detect": {"priority": 56, "confidence": 0.8, "any": [{"fingerprint_like": ["l4_orphan:%", "search_leak:%", "archived_provider_work:%"]}, {"class_in": ["lifecycle_leak"]}]}}'::jsonb),
 ('budget_pressure', '{"class": "policy", "title": "Spend at or near an approved limit", "description": "A paid-service budget or ceiling is near or over its limit. Raising a budget is the Platform Admin''s decision; the platform paces itself to the limit meanwhile.", "detect": {"priority": 60, "confidence": 0.9, "any": [{"fingerprint_like": ["health:budgets:%", "spend:%"]}, {"class_in": ["budget"]}], "route": "needs_decision", "recommend": "Keep within the limit; a budget change needs the cost-and-yield case (mandate 15:52 §4)."}}'::jsonb),
 ('licensed_import_needed', '{"class": "policy", "title": "A licensed source file must be imported", "description": "A new edition is published but importing it needs a licensed file (rankings): a person supplies the file.", "detect": {"priority": 61, "confidence": 0.8, "any": [{"fingerprint_like": ["ranking_edition:%"]}], "route": "needs_decision"}}'::jsonb),
 ('awaiting_decision', '{"class": "policy", "title": "Waiting on a Platform Admin decision", "description": "The issue records a decision that only the Platform Admin can take (approval, rule, spend or policy).", "detect": {"priority": 62, "confidence": 0.8, "any": [{"class_in": ["human_decision"]}], "route": "needs_decision"}}'::jsonb),
 ('external_evidence_needed', '{"class": "policy", "title": "Blocked by external evidence or access", "description": "The fix depends on something outside the platform: a provider''s site, a vendor, a network allowlist or an account setting that cannot be read.", "detect": {"priority": 63, "confidence": 0.7, "any": [{"class_in": ["external"]}], "route": "needs_decision"}}'::jsonb),
 ('governance_gap', '{"class": "policy", "title": "Governance record gap", "description": "Source, release or documentation records disagree with what is live; reconciled through governance, not by the platform.", "detect": {"priority": 64, "confidence": 0.8, "any": [{"class_in": ["governance_gap"]}], "route": "needs_decision"}}'::jsonb),
 ('missing_capability', '{"class": "dependency", "title": "A required job, setting or capability does not exist", "description": "The issue needs something built (a job, a setting, a runbook step) through a release.", "detect": {"priority": 66, "confidence": 0.7, "any": [{"class_in": ["missing_dependency"]}]}}'::jsonb),
 ('stalled_work', '{"class": "dependency", "title": "Work stuck in a queue", "description": "Drafts, leases or lanes not moving for longer than their limit.", "detect": {"priority": 70, "confidence": 0.6, "any": [{"fingerprint_like": ["draft_stuck:%", "stale_lease:%", "health:queue_watch:%"]}, {"class_in": ["queue_or_lease"]}]}}'::jsonb),
 ('coverage_stall', '{"class": "data", "title": "Coverage below target and not moving", "description": "Fields, lists or reads below target with no recovery under way: routed to the coverage workstreams (B and C).", "detect": {"priority": 72, "confidence": 0.6, "any": [{"fingerprint_like": ["health:field_stalled:%", "incomplete_pagination:%", "incomplete_read:%", "health:scholarship_queues:%", "provider_failed_attempts:%"]}]}}'::jsonb),
 ('known_code_defect', '{"class": "rule", "title": "A code defect recorded on the issue", "description": "The issue states a defect in a named function or job configuration: fixed through a release.", "detect": {"priority": 75, "confidence": 0.6, "any": [{"class_in": ["code_defect", "job_config"]}]}}'::jsonb),
 ('unclassified', '{"class": "rule", "title": "No rule explains it yet", "description": "No deterministic rule matched: a person triages it (and a new rule is registered for it).", "detect": {"priority": 999, "confidence": 0.2, "fallback": true, "route": "needs_decision"}}'::jsonb)
) x(code, spec);

select security.ops_remedy_register_v1(x.code, x.spec) from (values
 ('confirm_condition_cleared', '{"title": "Confirm the condition stays clear, then close on that evidence", "treats": ["condition_cleared_stale"], "authority": "auto", "action_fn": "security.ops_remedy_confirm_cleared_v1(bigint)", "verify_fn": "security.ops_verify_cleared_v1(bigint)", "max_attempts_key": "ops.max_attempts", "cooldown_key": "ops.cooldown_minutes", "notes": "Changes nothing; verification on a later run reads the issue''s own check."}'::jsonb),
 ('supersede_into_owner', '{"title": "Supersede into the issue that owns the shared cause", "treats": ["shared_cause_duplicate"], "authority": "auto", "action_fn": "security.ops_remedy_supersede_v1(bigint)", "verify_fn": "security.ops_verify_owner_resolved_v1(bigint)", "max_attempts_key": "ops.max_attempts", "cooldown_key": "ops.cooldown_minutes", "notes": "Links both ways and carries the evidence over; closes when the owner closes on verified evidence and the issue is not seen again."}'::jsonb),
 ('record_capacity_profile', '{"title": "Record the load profile and check again", "treats": ["timeout_under_load", "rate_limited", "runtime_start_failure"], "authority": "auto", "action_fn": "security.ops_remedy_capacity_profile_v1(bigint)", "verify_fn": "security.ops_verify_cleared_v1(bigint)", "max_attempts_key": "ops.capacity_max_checks", "cooldown_key": "ops.capacity_recheck_minutes", "notes": "No setting is changed: batch size and concurrency belong to the lane owners (IQ-00053). After the checks are used up the issue needs a release."}'::jsonb),
 ('fix_in_release', '{"title": "Fix through a release by the owning workstream", "treats": ["regression_after_close", "regression_after_release", "manual_lock_unguarded_in_batch", "permanent_job_error", "retry_loop_no_new_evidence", "done_without_movement", "layer4_generator_defect", "lifecycle_leak", "missing_capability", "stalled_work", "coverage_stall", "known_code_defect", "timeout_under_load", "rate_limited", "runtime_start_failure"], "authority": "release"}'::jsonb),
 ('platform_admin_decision', '{"title": "Platform Admin decision", "treats": ["budget_pressure", "licensed_import_needed", "awaiting_decision", "external_evidence_needed", "governance_gap", "unclassified"], "authority": "admin"}'::jsonb)
) x(code, spec);

-- 2.13 the job (G1: catalogued first; ships ON: it diagnoses, records, links and closes on verified evidence, and spends nothing) -----------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('ops-controller', 'Platform upkeep', 17, 'Operations controller (diagnose, remedy, verify)',
  'At :24 and :54 (after the integration checks at :21 and :51; clear of :x3, :x5, :x9, :35-:42 and :47-:48): verifies remedies acted on an earlier run and closes an issue only on a passed verification with its condition cleared; correlates open issues (one owner per shared cause); diagnoses the issues due with deterministic rules (pipeline.ops_root_causes); supersedes an issue into the one that owns its shared cause; runs only automatic remedies the authority matrix permits, within attempts and cool-down; blocks the rest as needs_release or needs_decision with the evidence and the decision required; writes an hourly checkpoint and a daily summary (pipeline.ops_checkpoints). Settings ops.*. Spends nothing; AI-assisted diagnosis is off (ops.ai_diagnosis_on).',
  6, false, null)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'ops-controller') then
    perform cron.schedule('ops-controller', '24,54 * * * *', $j$select security.ops_controller_tick_v1()$j$);
  end if;
end $c$;

-- 2.14 component register ------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.ops_root_causes', 'Platform', 'CF-247 P0: root-cause taxonomy with deterministic detect rules', 'active', '{}', '20261104010000'),
 ('table', 'pipeline.ops_remedies', 'Platform', 'CF-247 P0: remedy registry (auto, release, admin)', 'active', '{}', '20261104010000'),
 ('table', 'pipeline.ops_remedy_runs', 'Platform', 'CF-247 P0: every remedy execution with before and after measures', 'active', '{}', '20261104010000'),
 ('table', 'pipeline.ops_outcome_codes', 'Platform', 'CF-247 P0: the eight job outcomes', 'active', '{}', '20261104010000'),
 ('table', 'pipeline.ops_authority_matrix', 'Platform', 'CF-247 P0: backend decision-authority matrix (Authorise step)', 'active', '{}', '20261104010000'),
 ('table', 'pipeline.ops_baseline_cohort', 'Platform', 'CF-247 P0: the 48 historical issues to reconcile', 'active', '{}', '20261104010000'),
 ('table', 'pipeline.ops_checkpoints', 'Platform', 'CF-247 P0: hourly checkpoints and daily summaries', 'active', '{}', '20261104010000'),
 ('table', 'pipeline.ops_ai_diagnosis_requests', 'Platform', 'CF-247 P0: AI-assisted diagnosis requests (off by default)', 'active', '{}', '20261104010000'),
 ('job', 'ops-controller', 'Platform', 'CF-247 P0: the AI Operations Controller', 'active', '{}', '20261104010000'),
 ('function', 'security.ops_controller_tick_v1', 'Platform', 'CF-247 P0: job ops-controller', 'active', '{}', '20261104010000'),
 ('function', 'security.ops_report_v1', 'Platform', 'CF-247 P0: the one consolidated operational report', 'active', '{}', '20261104010000'),
 ('function', 'security.ops_reconciliation_v1', 'Platform', 'CF-247 P0: issue to end state to evidence', 'active', '{}', '20261104010000'),
 ('function', 'security.ops_root_cause_register_v1', 'Platform', 'CF-247 P0 contract: register a root cause', 'active', '{}', '20261104010000'),
 ('function', 'security.ops_remedy_register_v1', 'Platform', 'CF-247 P0 contract: register a remedy', 'active', '{}', '20261104010000'),
 ('function', 'security.job_outcome_set_v1', 'Platform', 'CF-247 P0 contract: record a job outcome', 'active', '{}', '20261104010000'),
 ('function', 'public.svc_ops_diagnosis_next', 'Platform', 'CF-247 P0: AI diagnosis picker for the worker (off by default)', 'active', '{}', '20261104010000'),
 ('function', 'public.svc_ops_diagnosis_record', 'Platform', 'CF-247 P0: AI diagnosis recorder (quotes checked)', 'active', '{}', '20261104010000')
on conflict do nothing;
