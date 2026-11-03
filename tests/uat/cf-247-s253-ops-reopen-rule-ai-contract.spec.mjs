// Guards: P0 Autonomous AI Operations, workstream A follow-ups (Integration Controller 3 Nov 2026 18:20): a closed integration issue reopens only
// on evidence observed after it closed (IQ-00067 was reopened at 16:51 and 18:21 on failures from before its close), the controller's recurrence
// uses the same rule and closes a stale reopening again with evidence, a closed issue keeps no open controller state; and the AI-assisted
// diagnosis contract for worker mode ops_diagnose (ops-diagnose-v1: spend inside the daily AI ceiling, the existing guards, the lane cap; still
// off). The behaviour runs on isolated fixtures by tests/fixtures/ops-reopen/run.sh (scratch PostgreSQL; the six edited and three called
// definitions loaded and checked against their live md5s; the false reopening reproduced on the live definitions; 25 cases). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104100000_cf247_ops_reopen_rule_ai_contract.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/ops-reopen'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1); return m.slice(a, m.indexOf(']::text[][], array[', a)) }
const after = (block) => block.split('$n$').filter((_, i) => i % 2 === 1).join('\n')

const MD5 = {
  'security.integration_issue_upsert_v1(jsonb,text)': 'f292f65689a35e213a3d12a539c11b1d',
  'security.integration_validate_v1()': '5d88b7c14f4db3b26e7b2650364602db',
  'security.ops_issue_signals_v1(bigint,jsonb)': 'a966f2b39a734f05c045c53e274d0863',
  'security.ops_controller_tick_v1()': '24793664aa99d3d97da1dcb2e63fb28c',
  'public.svc_ops_diagnosis_next(integer)': 'ade1ae9613bbdfd6f45bd6408e20d880',
  'public.svc_ops_diagnosis_record(bigint,jsonb,numeric)': '1ac0cc3359af6bca9c0e28e74ed49bcd',
}

test('six live definitions are edited only from their live md5 and checked after; the fixture loads the same and the called definitions', () => {
  for (const [sig, b] of Object.entries(MD5)) {
    const a = m.match(new RegExp(`^--   ${sig.replace(/[.()]/g, '\\$&')} +${b} -> ([0-9a-f]{32})$`, 'm'))
    expect(a, sig).not.toBeNull()
    expect(edit(sig)).toContain(`'${b}', '${a[1]}'`)
    expect(run).toContain(`["${sig}"]=${b}`)
  }
  for (const [sig, h] of [['security.integration_issue_close_v1(bigint,text,jsonb)', '4cae8eaee7444e0aa942b2702eb10bc6'], ['security.ai_spend_capture_v1()', '5b78fa074a9480d4f127ecc4fe93dcf3'],
    ['security.ai_use_refusal_v1(text)', '60c782e5aec7eb218c1149a3ad85dde2']]) { expect(m).toContain(`('${sig}', '${h}')`); expect(run).toContain(`["${sig}"]=${h}`) }
  expect(m).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(run).toContain("grep -c ': applied$')\" = 6 ]")
  expect(run).toContain("grep -c ': already applied$')\" = 6 ]")
  expect(m).not.toMatch(/edit_once\('security\.ai_spend_today_v1\(/)
})

test('a closed issue reopens only on evidence observed after closed_at; integration-validate gives the evidence time', () => {
  const u = after(edit('security.integration_issue_upsert_v1(jsonb,text)'))
  expect(u).toContain("if r.status = 'closed' and coalesce((p->>'observed_at')::timestamptz, now()) <= r.closed_at then")
  expect(u).toContain("'action', 'closed_evidence_before_close'")
  expect(u).toContain("'observed_at', coalesce((p->>'observed_at')::timestamptz, now()), 'closed_at', r.closed_at));")
  const v = after(edit('security.integration_validate_v1()'))
  expect(v).toContain("join cron.job j on j.jobid = x.jobid where j.jobname = substr(p.check_key, 13) and x.status = 'failed'), p.first_seen)")
  expect(v).toContain("else p.last_seen end observed_at")
  expect(v).toContain("'observed_at', r.observed_at,")
  expect(v).toContain("'observed_at', r.last_at, 'severity', 'P1',")
  expect(before).toContain("'before: the live definitions reopen IQ-00067 as a regression on failures from before its close (as at 16:51)'")
  for (const k of ['R2 the open 24-hour health count no longer reopens it; nothing is changed or recorded', 'R3 a failed run after the close reopens it; the history line records observed_at after closed_at',
    'R4 no observed_at: the evidence is now, after the close: reopened as before', 'R5 a health issue last seen before the close does not reopen it', 'R5 seen after the close: reopened'])
    expect(fixtures).toContain(k)
})

test('the controller uses the same rule; a stale reopening is closed again with evidence on a later run; a closed issue keeps no open state', () => {
  expect(m).toContain('create or replace function security.ops_recurrence_v1(p_issue bigint) returns jsonb')
  expect(m).toContain("return jsonb_build_object('recurred', v_obs > v_closed, 'stale_reopen', v_obs <= v_closed,")
  expect(m).toContain("return jsonb_build_object('recurred', v_fail is not null, 'stale_reopen', v_fail is null, 'basis', 'the job''s runs after the close',")
  expect(after(edit('security.ops_issue_signals_v1(bigint,jsonb)'))).toContain("'recurred', coalesce((v_rec->>'recurred')::boolean, false), 'stale_reopen', coalesce((v_rec->>'stale_reopen')::boolean, false)")
  expect(m).toContain(`select security.ops_root_cause_register_v1('reopened_on_stale_evidence', '{"class": "data",`)
  expect(m).toContain(`"detect": {"priority": 8, "confidence": 0.9, "all": [{"signal": "stale_reopen"}]}}`)
  expect(m).toContain(`select security.ops_remedy_register_v1('reclose_stale_reopen', '{"title": "Close again: the reopening had no evidence after the close", "treats": ["reopened_on_stale_evidence"], "authority": "auto", "action_fn": "security.ops_remedy_reclose_record_v1(bigint)", "verify_fn": "security.ops_verify_stale_reopen_v1(bigint)"`)
  const t = after(edit('security.ops_controller_tick_v1()'))
  expect(t).toContain("where x.status = 'closed' and x.ops_state in ('needs_release', 'needs_decision', 'remedying', 'verifying', 'diagnosed') loop")
  expect(t).toContain("or x.reopened_at > coalesce((x.diagnosis->>'at')::timestamptz, '-infinity'))")
  for (const k of ['R1 closed again through integration_issue_close_v1 with the evidence, on a later run', 'R3 a real recurrence is a regression after close (needs a release), not a stale reopening',
    'R6 closed elsewhere with needs_release: reconciled to verified, blocker cleared, with a history line']) expect(fixtures).toContain(k)
})

test('AI-assisted diagnosis contract ops-diagnose-v1: spend inside the ceiling, the existing guards, the lane cap, the answer schema; still off', () => {
  expect(m).toContain("for each row execute function security.ai_spend_capture_v1('ops_diagnose', 'delta', '{cost_usd}');")
  const n = after(edit('public.svc_ops_diagnosis_next(integer)'))
  expect(n).toContain("if not exists (select 1 from security.ai_spend_today_v1() t where t.use = 'ops_diagnose') then")
  expect(n).toContain("v_ref := security.ai_use_refusal_v1('ops_diagnose');")
  expect(n).toContain("security.pipeline_num_v1('ops.ai_diagnosis_usd_per_day', 0.5)")
  expect(n).toContain("'contract', 'ops-diagnose-v1', 'context', q.context,")
  expect(n).toContain("'response_schema', jsonb_build_object('type', 'object', 'required', jsonb_build_array('root_cause', 'confidence', 'evidence')")
  const r = after(edit('public.svc_ops_diagnosis_record(bigint,jsonb,numeric)'))
  expect(r).toContain("if p_answer ? 'error' then")
  expect(r).toContain(`jsonb_path_query(q.context, 'strict $.** ? (@.type() == "string")')`)
  expect(m).toMatch(/\('pipeline', 'ops\.ai_diagnosis_usd_per_day',[\s\S]*?'number', to_jsonb\(0\.5\), 0, 5, 'US\$'/)
  expect(m).not.toMatch(/set value = '1' where key = 'ops\.ai_diagnosis_on'/)
  for (const k of ['A2 held while security.ai_spend_today_v1 does not count the lane', 'A3 held at the daily AI ceiling', 'A4 held at the lane\'s own daily cap',
    'A5 held at the OpenRouter credit floor (the existing guard)', 'A7 a quote containing quotation marks matches the context text (not its JSON escaping)'])
    expect(fixtures.replace(/''/g, "'")).toContain(k)
})
