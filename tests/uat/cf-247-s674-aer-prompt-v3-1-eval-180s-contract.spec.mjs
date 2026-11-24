// Guards: S674 AER v2 prompt aer-v2-course-v3.1 and a 180 s evaluation call (Platform Admin 18 Nov 2026 20:53 AEDT, session S1-AER): one record per printed requirement row of a table or list, only on the three exact pinned models with no fallback; worker v1.0.19 answers the benchmark in a background task with a 180 s per-call limit inside a 360 s budget (under the 400 s paid-plan wall clock); the qualification gate unchanged; round-5 runs only through aer-v3-replay.yml; the standing 7-day validation renewal runs only on the named thresholds and validators, and a failure is reported, never forced on.
// CF-247 S674. Migration 20261118243000_cf247_s674_aer_prompt_v3_1_round5; worker coverage-sweep v1.0.19 (index.ts mode aer_v3_eval); scripts/aer-v3-replay.mjs;
// scripts/aer-validation-renew.mjs and workflow aer-validation-renew.yml. G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'

const M = fs.readFileSync('supabase/migrations-archive/20261118243000_cf247_s674_aer_prompt_v3_1_round5.sql', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const R = fs.readFileSync('scripts/aer-v3-replay.mjs', 'utf8')
const V = fs.readFileSync('scripts/aer-validation-renew.mjs', 'utf8')
const W = fs.readFileSync('.github/workflows/aer-validation-renew.yml', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const mode = IX.slice(IX.indexOf('if (mode === AER_V3_EVAL_MODE) {'), IX.indexOf('if (mode === AER_V2_MODE) {'))

test('prompt v3.1 is v3 plus one section asking for every requirement row, on the exact pinned models, with its sha-256 checked', () => {
  expect(M).toContain("'AER course page reader, prompt aer-v2-course-v3.', 'AER course page reader, prompt aer-v2-course-v3.1.'")
  expect(M).toContain('Tables and lists (read every row):')
  expect(M).toContain('give one record for EVERY row or item that prints an academic entry requirement, in page order, from the first to the last. Never stop early, never sample, never give one record for several rows.')
  expect(M).toContain('is still a record, with min_grade null')
  expect(M).toContain('check that every requirement row of every table and list on the page is a record or is in seen_not_mapped')
  for (const m of ['qwen/qwen3-30b-a3b-instruct-2507', 'mistralai/mistral-small-3.2-24b-instruct', 'xiaomi/mimo-v2.6-flash']) expect(M).toContain(`'${m}'`)
  expect(M).toContain("p.answer_contract, p.input_format, p.routing, p.params")  // routing and params copied from v3
  expect(M).toContain("a.system_sha256 = encode(sha256(convert_to(a.system_text, 'UTF8')), 'hex') and v.spec->>'system_sha256' = a.system_sha256")
  expect(M).toContain("coalesce((a.routing->>'allow_fallbacks')::boolean, true) = false")
})

test('round 5 is opened queued with the gate unchanged; nothing is switched, qualified or created', () => {
  expect(M).toContain("v.version || '-r5'")
  expect(M).toContain("'min_source_integrity_pct', 100, 'max_error_rate_pts', 10")
  expect(M).toContain("'false_positives', 0")
  const c = code(M)
  expect(c).not.toMatch(/update pipeline\.platform_toolset_settings|on_demand_open_v1|set\s+status\s*=\s*'qualified'/i)
  expect(c).not.toMatch(/create\s+(or\s+replace\s+)?(function|table|view|trigger)/i)
  expect(c).toContain("security.pipeline_num_v1('ai_eval.offline_runs_on', 1) <> 0")
  expect(c).toContain("security.pipeline_num_v1('aer.machine_min_confidence', -1) <> 0.8")
  expect(M).toContain("'aer.validation_renew_after_days'")
  expect(M).toMatch(/'number', '5'::jsonb, 1, 6, 'days'/)
  expect(M).toContain('-- Replaces: nothing. Retires: nothing.')
})

test('worker v1.0.19: the benchmark answers in a background task, 180 s a call inside 360 s; other modes keep their limits', () => {
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.37"')  // v1.0.37 from s1029  // v1.0.36 from s1017  // v1.0.35 from s992  // v1.0.34 from s851  // v1.0.25 from s721
  expect(IX).toContain('const AER_V3_EVAL_BUDGET_MS = 360_000;  // fixed:')
  expect(IX).toContain('const AER_V3_EVAL_CALL_MS = 180_000;  // fixed:')
  expect(IX).toContain('const BUDGET_MS = 110_000;')
  expect(mode).toContain('const callMs = Math.min(AER_V3_EVAL_CALL_MS, t0 + AER_V3_EVAL_BUDGET_MS - 10000 - Date.now());')
  expect(mode).toContain('const late = () => Date.now() - t0 > AER_V3_EVAL_BUDGET_MS - 25000;')
  expect(mode).not.toContain('Math.min(90000')
  expect(mode).toContain('edge.waitUntil(work().catch(')
  expect(mode).toContain('background: true, examples: Math.min(AER_V3_EVAL_TASK_MAX,')
  expect(mode).toContain('return await work();')
  // after the 21:23 attempt (CPU Time exceeded, nothing recorded): each answer is recorded at once and a task starts at most AER_V3_EVAL_TASK_MAX examples
  expect(IX).toContain('const AER_V3_EVAL_TASK_MAX = 8;  // fixed: CPU guard')
  expect(mode).toContain('.slice(0, bg || streamed ? AER_V3_EVAL_TASK_MAX : undefined)')
  // 22:15: a background task waiting on a slow model is dropped (EarlyDrop), so the replay asks for a streamed answer straight from the worker
  expect(mode).toContain('const tick = setInterval(() => { try { ctl.enqueue(enc.encode(" ")) } catch { /* closed */ } }, 10000);  // fixed: keep-alive')
  expect(mode).toContain('headers: { "content-type": "application/json", "x-cf-stream": "1" }')
  expect(IX).toContain('if (modeOf && res.headers.get("x-cf-stream") !== "1") {')
  expect(R).toContain("select public.svc_pilot_issue_nonce('coverage-sweep') as n")
  expect(R).toContain("'x-cf-run-nonce': String(n)")
  expect(mode).toContain('await rpc("svc_ai_eval_answer_record_v1", { p_run: w.run, p_answers: { answers: [ans], worker: WORKER } })')
  // the version check and the credential check stay before the background task, so a refused run answers at once
  expect(mode.indexOf('the benchmark version is not an AER v3 prompt')).toBeLessThan(mode.indexOf('const work = async () => {'))
  expect(mode.indexOf('OpenRouter credential unavailable')).toBeLessThan(mode.indexOf('const work = async () => {'))
  expect(IX).toContain('signal: AbortSignal.timeout(90000) });  // fixed: API time-out of one call')  // other modes unchanged
})

test('the replay waits for each background task before releasing a lease, and answers v3 and v3.1 rounds alike', () => {
  expect(R).toContain('const CODE = `aer-v2-course-v3%-${ROUND}`')
  expect(R).toContain('while (res.some((r) => r.error) && Date.now() - t < 410000 && Date.now() < until) {  // fixed: longer than the 400 s wall clock of the background task')
  expect(R.indexOf('while (res.some((r) => r.error) && Date.now() - t < 410000')).toBeLessThan(R.lastIndexOf("x.state = 'answering' and x.leased_until > now()`)"))
  expect(R).toContain("res.filter((r) => r.run).every((r) => (now[String(r.run)] || 0) >= (before[String(r.run)] || 0) + (Number(r.examples) || 1))) break")
  expect(R).toContain("reason like ${lit(`S672 AER v3 replay ${ROUND} %`)}")
})

test('the standing renewal runs only on the named thresholds and validators, reports and fails otherwise, and changes nothing else', () => {
  expect(V).toContain("thresholds: { 'aer.machine_min_confidence': 0.8, 'aer.machine_min_quote_chars': 8 }")
  expect(V).toContain("md5: '945077fe5dc291cc0893976f8fe65aef'")
  expect(V).toContain("md5: '162cfa24e35bfcc9100c1bea81c61b6a'")
  expect(V).toContain("if (age < after) { await summary(`${r.name}: not due")
  expect(V).toContain('NOT renewed, the standing rule does not cover it')
  expect(V).toContain("const pass = String(v.passed) === 'true' && Number(v.regressions_on_recheck) === 0")
  expect(V).not.toMatch(/update pipeline\.platform_toolset_settings|machine_mode['"]?\s*=|set value/i)
  expect(V).toContain("'Platform Admin standing rule 18 Nov 2026 20:53 AEDT (S1-AER s674): automatic 7-day renewal on unchanged thresholds'")
  expect(W).toContain("- cron: '17 7 * * *'")
  for (const f of ['scripts/aer-validation-renew.mjs', 'scripts/aer-v3-replay.mjs']) expect(() => execFileSync('node', ['--check', f]), f).not.toThrow()
  expect(W).toContain("MODE: ${{ github.event_name == 'schedule' && 'renew' || inputs.mode }}")
})
