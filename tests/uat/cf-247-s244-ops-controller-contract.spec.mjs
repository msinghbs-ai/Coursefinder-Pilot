// Guards: P0 Autonomous AI Operations (Platform Admin mandates 3 Nov 2026 15:37 §2, §3, §7, §13, §16 and 15:52 §6, §14, §17, §18), workstream A:
// the shared operations contract other workstreams code against (exact names; the fixture stub is the migration's contract section byte for byte);
// the controller's lifecycle on the existing integration queue (Detect, Diagnose, Correlate, Plan, Authorise, Execute, Verify on a later run
// only, Learn, Close only on verified evidence; blocked issues routed once, never retried in a loop); the authority boundary enforced in data;
// the consolidated report; the 48-issue historical cohort. The behaviour runs on isolated fixtures by tests/fixtures/ops-controller/run.sh
// (scratch PostgreSQL; the queue functions checked against their live md5s; the migration applied twice; 62 cases) and dryrun.sh (the live
// queue snapshot of 3 Nov 15:56 AEDT, each row checked against its live md5). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104010000_cf247_ops_controller.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/ops-controller'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const contract = fs.readFileSync(`${FX}/fixtures-contract.sql`, 'utf8')
const stub = fs.readFileSync(`${FX}/stub-ops-contract.sql`, 'utf8')
const dry = fs.readFileSync(`${FX}/dryrun.sh`, 'utf8')
const section = (from, to) => m.slice(m.indexOf(from), m.indexOf(to, m.indexOf(from)))
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); expect(a, name).toBeGreaterThan(-1); return m.slice(a, m.indexOf('$function$;', a)) }

test('the shared contract has exactly the agreed names, and the fixture stub is the migration section byte for byte', () => {
  const c = section('-- >>> contract', '-- <<< contract')
  expect(stub.slice(stub.indexOf('-- >>> contract'))).toBe(c + m.slice(m.indexOf('-- <<< contract'), m.indexOf('\n', m.indexOf('-- <<< contract')) + 1))
  expect(c).toMatch(/create table if not exists pipeline\.ops_root_causes \(\s*code text primary key[^\n]*\n\s*class text not null check \(class in \('transient', 'data', 'rule', 'policy', 'dependency', 'capacity'\)\),\s*title text not null,\s*description text,\s*detect jsonb[^\n]*\n\s*created_at timestamptz/)
  expect(c).toMatch(/create table if not exists pipeline\.ops_remedies \(\s*code text primary key[^\n]*\n\s*title text not null,\s*treats text\[\][^\n]*\n\s*authority text not null check \(authority in \('auto', 'release', 'admin'\)\),\s*action_fn regprocedure,\s*verify_fn regprocedure,\s*max_attempts_key text,\s*cooldown_key text,\s*active boolean not null default true,\s*notes text\s*\)/)
  expect(c).toMatch(/create table if not exists pipeline\.ops_remedy_runs \(\s*id bigserial primary key,\s*issue_id bigint[^\n]*\n\s*remedy_code text[^\n]*\n\s*started_at timestamptz[^\n]*\n\s*finished_at timestamptz,\s*before jsonb,\s*after jsonb,\s*result text,\s*evidence jsonb/)
  expect(c).toMatch(/create table if not exists pipeline\.ops_outcome_codes \(\s*code text primary key,\s*title text not null,\s*counts_as_movement boolean/)
  for (const o of ['succeeded_with_result', 'succeeded_no_movement', 'not_needed', 'deferred_dependency', 'blocked_policy', 'blocked_evidence', 'failed_retryable', 'failed_remediation']) expect(c).toContain(`('${o}', `)
  expect(c).toContain('alter table pipeline.admin_jobs add column if not exists outcome text references pipeline.ops_outcome_codes(code);')
  expect(c).toContain('alter table pipeline.admin_jobs add column if not exists outcome_detail jsonb;')
  for (const col of ['correlation_key text', 'diagnosis jsonb', 'remedy_code text', 'remedy_attempts int not null default 0', 'next_action_at timestamptz'])
    expect(c).toContain(`alter table pipeline.integration_issues add column if not exists ${col};`)
  expect(c).toContain('create or replace function security.ops_root_cause_register_v1(p_code text, p_spec jsonb) returns jsonb')
  expect(c).toContain('create or replace function security.ops_remedy_register_v1(p_code text, p_spec jsonb) returns jsonb')
  expect(c).toContain('create or replace function security.job_outcome_set_v1(p_job uuid, p_outcome text, p_detail jsonb) returns void')
  expect(c).toContain("raise exception 'remedy %: % % does not exist', p_code, v_k, p_spec->>v_k using errcode = '42883';")
  expect(c).not.toMatch(/admin_jobs_state_check/)
  for (const k of ['C1 ops_remedies has exactly the contract columns', 'C2 not needed is a real outcome; the state is unchanged', 'C4 a remedy cannot register remedies or root causes']) expect(contract).toContain(k)
})

test('the controller ships on and spends nothing; AI-assisted diagnosis ships off; the queue functions it calls are md5-checked, none is edited', () => {
  expect(m).toMatch(/\('pipeline', 'ops\.controller_on',[\s\S]*?'number', to_jsonb\(1\), 0, 1, 'on \(1\) or off \(0\)'/)
  expect(m).toMatch(/\('pipeline', 'ops\.ai_diagnosis_on',[\s\S]*?'number', to_jsonb\(0\), 0, 1, 'on \(1\) or off \(0\)'/)
  expect(m).toMatch(/\('pipeline', 'ops\.checkpoint_on',[\s\S]*?'number', to_jsonb\(1\), 0, 1/)
  expect(m).toContain("perform cron.schedule('ops-controller', '24,54 * * * *', $j$select security.ops_controller_tick_v1()$j$);")
  expect(m).not.toMatch(/cron\.alter_job\(\(select jobid from cron\.job where jobname = 'ops-controller'\)/)
  for (const [sig, h] of [['security.integration_issue_upsert_v1(jsonb,text)', 'f292f65689a35e213a3d12a539c11b1d'], ['security.integration_issue_transition_v1(bigint,text,text,text,jsonb)', '3e8fc63663e5120c50f0859da97dd7a8'],
    ['security.integration_issue_close_v1(bigint,text,jsonb)', '4cae8eaee7444e0aa942b2702eb10bc6']]) { expect(m).toContain(`('${sig}', '${h}')`); expect(run).toContain(`["${sig}"]=${h}`) }
  expect(m).not.toMatch(/create or replace function security\.integration_(issue_upsert|issue_transition|issue_close|validate|yield_checks)_v1\(/)
  expect(m).not.toMatch(/edit_once\(/)
  expect(m).toContain("'ops.ai_diagnosis_model'")
  expect(fn('public.svc_ops_diagnosis_next')).toContain("if security.pipeline_num_v1('ops.ai_diagnosis_on', 0) < 1 then return")
  expect(fn('public.svc_ops_diagnosis_next')).toContain("security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14)")
  expect(fn('public.svc_ops_diagnosis_record')).toContain('where position(e in v_ctx) = 0')
})

test('the authority boundary is enforced in data: triggers on every protected table while a remedy runs; the matrix is checked and recorded', () => {
  for (const t of ['pipeline.ops_remedies', 'pipeline.ops_root_causes', 'pipeline.ops_outcome_codes', 'pipeline.ops_remedy_runs', 'pipeline.platform_toolset_settings', 'pipeline.layer4_review_items',
    'pipeline.layer4_decisions', 'pipeline.layer4_auto_admissions', 'pipeline.manual_locks', 'pipeline.layer2_acquisition_providers', 'pipeline.layer3_route_budget', 'pipeline.integration_issues'])
    expect(m).toContain(`('${t}', 'ops_guard_`)
  expect(m).toContain("execute format('create trigger %I before %s on %s for each row when (security.ops_remedy_guard_active_v1()) execute function %s', r.tg, r.ev, r.tbl, r.fn);")
  expect(m).toContain("create trigger ops_guard_registry before insert or update or delete on pipeline.ops_authority_matrix for each row")
  const st = fn('security.ops_guard_settings_v1')
  expect(st).toContain('new.max_value is distinct from old.max_value')
  expect(st).toContain("old.key ~ '^(ops|budgets|layer4|alerts|integration|targets)\\.'")
  expect(fn('security.ops_guard_layer4_v1')).toContain("new.status not in ('pending', 'superseded')")
  expect(fn('security.ops_guard_issue_v1')).toContain("if new.status = 'closed' and old.status <> 'closed' then raise exception")
  const call = fn('security.ops_call_v1')
  expect(call).toContain("perform set_config('cf247.ops_remedy', 'on', true);")
  expect(call).toContain("perform set_config('cf247.ops_remedy', '', true);")
  expect(m).toContain("('auto', true, true, null,")
  expect(m).toContain("('release', false, false, 'needs_release',")
  expect(m).toContain("('admin', false, false, 'needs_decision',")
  const tick = fn('security.ops_controller_tick_v1')
  expect(tick).toContain("v_auth := security.ops_authorise_v1(m.code);")
  expect(tick).toContain("jsonb_build_object('diagnosis', v_diag - 'evidence', 'plan', v_plan, 'authorise', v_auth,")
  expect(tick).toContain("x.active and x.authority = 'auto' and (v_diag->>'root_cause') = any (x.treats)")
  for (const k of ['G1-G15 every protected write by a remedy is refused in data and recorded as refused_guard', 'G0 positive control: an ordinary setting changed within its range is allowed',
    'T12 the matrix says no: the run records refused_authority with the reason; nothing executed']) expect(fixtures).toContain(k)
})

test('verification happens only on a later run; an issue closes only through the close function on passed verification with its condition cleared; blocked issues never loop', () => {
  const tick = fn('security.ops_controller_tick_v1')
  expect(tick).toContain("where x.result = 'acted' and x.finished_at < v_t0 order by x.id loop")
  expect(tick).toContain("if coalesce((v_res->>'passed')::boolean, false) and coalesce((v_res->'measure'->>'condition_cleared')::boolean, false) then")
  expect(tick).toContain("perform security.integration_issue_close_v1(r.issue_id, 'ops-controller', jsonb_build_object('outcome', 'passed',")
  expect(tick).not.toMatch(/update pipeline\.integration_issues set status = 'closed'/)
  expect(tick).toContain("if v_att >= v_max then")
  const route = fn('security.ops_route_v1')
  expect(route).toContain("if r.ops_state is distinct from v_state or r.blocker->>'root_cause' is distinct from rc.code then")
  for (const k of ['T2 never verified in the same run as the action, nor before its cool-down', 'T8 attempts used up after 2 checks: needs a release; 6 more runs execute nothing (no loop)',
    'T7 three more looks add no history and execute nothing', 'T9 reopened as a regression (regression_count 1) with its history; diagnosed regression_after_close; needs a release',
    'T10 one remedy per shared cause per run', "T4 the superseded issue closes with its owner''s verified evidence"]) expect(fixtures).toContain(k)
})

test('diagnosis is deterministic, from live runs and the release clock; IQ-00067 is recognised as a problem created by a release', () => {
  expect(fn('security.ops_job_stats_v1')).toContain("'last_success_before_streak', ok.at")
  expect(fn('security.ops_releases_v1')).toContain("select c.introduced_in, min(c.registered_at), 'migration' from pipeline.component_register c")
  const sig = fn('security.ops_issue_signals_v1')
  for (const s of ["'permanent_failure'", "'retry_loop'", "'timeout'", "'rate_limit'", "'lock_refusal'", "'no_movement'", "'after_release'", "'recurred'", "'cleared_hours'"]) expect(sig).toContain(s)
  for (const rc of ['condition_cleared_stale', 'shared_cause_duplicate', 'regression_after_close', 'regression_after_release', 'manual_lock_unguarded_in_batch', 'permanent_job_error',
    'retry_loop_no_new_evidence', 'rate_limited', 'timeout_under_load', 'runtime_start_failure', 'done_without_movement', 'layer4_generator_defect', 'lifecycle_leak', 'budget_pressure',
    'licensed_import_needed', 'awaiting_decision', 'external_evidence_needed', 'governance_gap', 'missing_capability', 'stalled_work', 'coverage_stall', 'known_code_defect', 'unclassified'])
    expect(m).toContain(` ('${rc}', '{"class": `)
  for (const [r, a] of [['confirm_condition_cleared', 'auto'], ['supersede_into_owner', 'auto'], ['record_capacity_profile', 'auto'], ['fix_in_release', 'release'], ['platform_admin_decision', 'admin']])
    expect(m).toMatch(new RegExp(` \\('${r}', '\\{"title": "[^"]+", "treats": \\[[^\\]]+\\], "authority": "${a}"`))
  expect(fixtures).toContain("'T5 IQ-00067: a regression after release 20261103200000, with the unguarded manual-lock refusal, a permanent error and a retry loop contributing'")
  expect(dry).toContain("[ \"$(printf '%s' \"$(cat $FX/live/cron-jobs-20261103-1607.txt)\" | md5sum | cut -c1-32)\" = 23bce9d864d4926cc6f2de6bb1c45fa4 ]")
  expect(dry).toContain("if bad or len(rows) != 68")
})

test('one consolidated report with the §16 sections and §17 scorecard; checkpoints are table rows; the 48-issue cohort is reconciled to end states', () => {
  const rep = fn('security.ops_report_v1')
  for (const s of ["'platform_health'", "'data_improvement'", "'autonomy'", "'efficiency'", "'governance'", "'reconciliation'", "'groups'"]) expect(rep).toContain(s)
  for (const s of ["'autonomous_resolution_pct'", "'autonomous_resolution_basis'", "'excluded_policy_evidence_approval'", "'detection_to_diagnosis_minutes_median'", "'diagnosis_to_resolution_minutes_median'", "'recurrence'"]) expect(rep).toContain(s)
  expect(fn('security.ops_controller_tick_v1')).toContain("insert into pipeline.ops_checkpoints(kind, window_hours, report) values ('hourly', 1, security.ops_report_v1(1));")
  expect(m).toContain("'p0-2026-11-03-detected-48', 'detected', '2026-11-03 04:41:00+00'::timestamptz")
  expect((m.match(/where i\.id = any \(array\[([0-9, \n]+)\]::bigint\[\]\)/) || [])[1].split(',').length).toBe(48)
  expect(fn('security.ops_issue_end_state_v1')).toContain("then 'verified_resolved'")
  expect(fn('security.ops_remedy_supersede_v1')).toContain("evidence = i.evidence || jsonb_build_object('superseded'")
  for (const k of ['R the mandate §16 sections and the §17 scorecard metrics are present', 'R one hourly checkpoint row, not one per run', 'T4 superseded into the owner both ways with the evidence carried over (traceability kept)'])
    expect(fixtures).toContain(k)
})
