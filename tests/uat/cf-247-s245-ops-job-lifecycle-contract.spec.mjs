// Guards: P0 Autonomous AI Operations mandate (3 Nov 2026 15:37) §7, workstream D: every task and plan ends with an explicit outcome from
// pipeline.ops_outcome_codes measured from real data movement (the not-needed path is outcome not_needed, state cancelled kept for
// compatibility); past tasks and plans are reconciled in the outcome columns without rewriting history (the 17 empty plans of 12:41 report
// no movement); self-healing of orphaned leases and lane work, interrupted and duplicate tasks, repeated empty cycles, excessive paid retries
// and paid AI answers whose record failed (acceptance mandate 15:52 §9: only the recording is retried), each with a root cause and remedy
// registered through workstream A's contract and changing work only behind its own switch; dependency sequencing (deferred_dependency);
// IQ-00064 (the retry re-plan no longer waits plans.replan_min_days; every automatic planner run records why). The behaviour runs on
// isolated fixtures by tests/fixtures/ops-lifecycle/run.sh (scratch PostgreSQL; the live v2.15.426 definitions checked against their live
// md5s; the defects reproduced; the switches off; the migration applied twice; every case asserted). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104020000_cf247_ops_job_lifecycle.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/ops-lifecycle'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const off = fs.readFileSync(`${FX}/fixtures-off.sql`, 'utf8')
const stub = fs.readFileSync(`${FX}/stub-ops-contract.sql`, 'utf8')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1); return m.slice(a, m.indexOf(']::text[][], array[', a)) }
const after = (block) => block.split('$n$').filter((_, i) => i % 2 === 1).join('\n')

const MD5 = {
  'security.admin_job_close_v1(uuid)': '233236ffc66e438edb21c4f51a6c45a1',
  'security.admin_job_watch_v1(uuid)': '995f26c437f0abfb3c666271cd622fec',
  'security.enrich_plan_tick_v1(uuid)': '77705c2b34e13801f4d7ccc5773bd4c1',
  'security.enrich_plan_v1(uuid)': 'a63146c23989eb64ee2248e3f32eade6',
  'security.plan_outcomes_v1()': '0f127f0241764413fb87278f403a2e14',
  'security.enrich_plan_auto_v1()': '14d4769267f827736a0d4e2f013c4dad',
}

test('six live definitions are edited only from their live md5 and checked after; it lands after workstream A; Release B and the worker are not edited', () => {
  for (const [sig, b] of Object.entries(MD5)) {
    const a = m.match(new RegExp(`^--   ${sig.replace(/[.()]/g, '\\$&')} +${b} -> ([0-9a-f]{32})$`, 'm'))
    expect(a, sig).not.toBeNull()
    expect(edit(sig)).toContain(`'${b}', '${a[1]}'`)
    expect(run).toContain(`["${sig}"]=${b}`)
  }
  expect(m).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(m).toContain("if to_regclass('pipeline.ops_remedies') is null or to_regclass('pipeline.ops_outcome_codes') is null")
  for (const f of ['svc_enrich_ai_record', 'svc_enrich_ai_next', 'enrich_fields_slice_v1', 'admin_jobs_tick_v1', 'enrich_plan_inputs_v1', 'provider_task_prepare_v1'])
    expect(m).not.toMatch(new RegExp(`edit_once\\('[a-z]+\\.${f}\\(`))
  expect(run).toContain("grep -c ': applied$')\" = 6 ]")
  expect(run).toContain("grep -c ': already applied$')\" = 6 ]")
  for (const k of ['pipeline.ops_outcome_codes', 'security.job_outcome_set_v1(p_job uuid, p_outcome text, p_detail jsonb)', 'security.ops_remedy_register_v1(p_code text, p_spec jsonb)'])
    expect(stub).toContain(k)
})

test('what ships on only records, diagnoses or stops waste; every remedy that changes, removes or admits work ships off', () => {
  for (const k of ['ops.outcome_on', 'plans.lane_backlog_wait_on', 'plans.retry_ignores_min_days'])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}', [\\s\\S]*?'number', '1'::jsonb, '0', '1', 'on \\(1\\) or off \\(0\\)'`))
  for (const k of ['ops.lease_orphan_close_on', 'ops.lane_orphan_release_on', 'ops.task_dedupe_on', 'ops.retry_cost_pause_on', 'ops.answer_replay_on', 'plans.step_dependency_on'])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}', [\\s\\S]*?'number', '0'::jsonb, '0', '1', 'on \\(1\\) or off \\(0\\)'`))
  expect(m).toContain("raise exception 'ops D post-check: a remedy that changes, removes or admits work must ship off'")
  for (const k of ["'off: an ended task records no outcome, as before'", "'off: Find course pages starts with searches queued, as before'", "'off: the retry re-plan waits plans.replan_min_days, as before'"])
    expect(off).toContain(k)
})

test('every ended task records an explicit outcome from real data movement, whichever path ended it; the not-needed path is not_needed', () => {
  expect(after(edit('security.admin_job_close_v1(uuid)'))).toContain("perform security.job_outcome_record_v1(p_id, 'at_close');")
  expect(m).toContain("select count(*) filter (where e.state = 'filled'), count(*) filter (where e.state = 'review') into v_a, v_b from pipeline.field_enrich_items e where e.job_id = p_job;")
  expect(m).toContain("when j.state = 'cancelled' and j.result->>'end_state' = 'not_needed' then 'not_needed'")
  expect(m).toContain("when v_unf then 'failed_retryable'")
  expect(m).toContain("when j.state = 'failed' then case when security.ops_error_retryable_v1(j.error) then 'failed_retryable' else 'failed_remediation' end")
  expect(after(edit('security.admin_job_watch_v1(uuid)'))).toContain("perform security.job_outcome_record_v1(p_id, 'held')")
  expect(before).toContain("'before: an ended task is mirrored but has no outcome'")
  for (const k of ['O1 Fill missing fields done with 2 items filled', 'O3 IQ-00064 shape', 'O4 the not-needed path', 'O5 failed on a statement time-out', 'O6 failed on a data or rule cause',
    'O7 held too long by the day cap: blocked_policy', "O10 the runner''s three ended paths", 'O11 a failure to record the outcome never fails the close', 'W1 a Find course pages task held by the day budget'])
    expect(fixtures).toContain(k)
})

test('history: past tasks and plans are reconciled in the outcome columns only; the 17 empty 12:41 plans report no movement', () => {
  expect(m).toContain('alter table pipeline.enrich_plan_runs add column if not exists outcome text references pipeline.ops_outcome_codes(code)')
  expect(m).toContain("update pipeline.enrich_plan_runs set outcome = v->>'outcome',")
  expect(after(edit('security.plan_outcomes_v1()'))).toContain("when x.outcome = 'not_needed' then 'not_needed' else 'no_movement' end")
  expect(after(edit('security.enrich_plan_tick_v1(uuid)'))).toContain("security.plan_outcome_compute_v1(r.id, true)->>'legacy'")
  expect(before).toContain("'before: the 12:41 plan (scan of 0 of 0, nothing found) is reported as moved'")
  for (const k of ['R2 the reconciliation is bounded by ops.outcome_reconcile_batch', 'R3 the 17 empty plans reconcile to succeeded_no_movement', 'R4 state, steps, actual and results are untouched',
    'T1 a plan whose scan found nothing finishes no_movement (was moved)'])
    expect(fixtures).toContain(k)
})

test('IQ-00064 and dependency sequencing: the retry re-plan fires after the step\'s own wait; no search is queued and paid twice; every planner run says why', () => {
  const a = after(edit('security.enrich_plan_auto_v1()'))
  expect(a).toContain("or (v_on_rt and security.pipeline_num_v1('plans.retry_ignores_min_days', 0) >= 1")
  expect(a).toContain("and a.created_at <= now() - make_interval(days => v_re_days))  -- CF-247 ops D: evidence re-plans keep plans.replan_min_days")
  expect(a).toContain('return security.enrich_plan_auto_note_v1(')
  expect(m).toContain('comment on table pipeline.enrich_plan_auto_runs is')
  const t = after(edit('security.enrich_plan_tick_v1(uuid)'))
  expect(t).toContain('v_dep := security.plan_step_dependency_v1(r.id, s);')
  expect(t).toContain("v_state := 'waiting'; v_note := left('Deferred: ' || (v_dep->>'reason'), 300);")
  expect(m).toContain("select count(*) into v_n from pipeline.course_link_search s where s.provider_id = r.provider_id and s.state in ('queued', 'sent');")
  expect(before).toContain("'before IQ-00064: the retry re-plan does not fire 6.5 hours after the step failed (plans.replan_min_days 2)'")
  for (const k of ['A1 IQ-00064: 6.5 hours after the step failed', 'A3 the next run creates nothing and says why', "A4 not before the step''s own wait", 'A6 a re-plan on new evidence still waits',
    "T3 IQ-00064: Find course pages waits while 3 of the provider''s searches are queued", 'T6 after plans.step_wait_hours', "T7 a person''s Run now plan is not deferred", 'T9 on: Fill missing fields waits'])
    expect(fixtures).toContain(k)
})

test('repeated empty cycles stop the automatic planner, never a person; self-healing remedies and paid-answer replay are registered and bounded', () => {
  const p = after(edit('security.enrich_plan_v1(uuid)'))
  expect(p).toContain("if v_empty is not null and auth.uid() is null and jsonb_array_length(v_steps) > 0 then")
  expect(m).toContain("perform public.svc_enrich_ai_record(v_res);")
  expect(m).toContain('unique (item_id, attempts));')
  expect(m).toContain('and e.attempts = a.attempts and e.evidence_id is not distinct from a.evidence_id')
  expect(m).toContain("grant execute on function public.svc_enrich_ai_stash_v1(jsonb) to service_role;")
  for (const r of ['outcome_reconcile', 'lease_orphan_close', 'lane_orphan_release', 'task_duplicate_stop', 'retry_cost_pause', 'answer_replay', 'job_interrupted_check', 'empty_cycle_hold', 'step_input_wait'])
    expect(m).toContain(`('${r}', jsonb_build_object(`)
  expect(m).toContain("perform cron.schedule('ops-job-lifecycle', '*/2 * * * *', $c$select security.ops_job_lifecycle_v1()$c$);")
  for (const k of ['E1 the scheduled planner is not offered', 'E2 a person still sees the steps', 'E3 new verified evidence: proposed again', 'H1 switch off: detected only', 'H2 on: closed as failed',
    'H4 on: released to their normal turn', 'H6 on: the newer plan task is asked to stop', 'H8 on: asked to pause', 'P4 replayed: only the recording', 'P5 leased again: superseded', 'P7 still failing after',
    'G1 nine root causes registered', 'G2 nine remedies'])
    expect(fixtures).toContain(k)
})
