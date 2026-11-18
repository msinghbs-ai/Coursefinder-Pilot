// Guards: Course description prompt v3, smart retry gate, per-attempt AI ledger flush and the telemetry reads (Platform Admin 16 Nov 2026 12:36): v3 forbids the introducing opener sentence and is released with its registry row; the second model is asked only for the rules in enrich.cdesc_retry_rules; every AI attempt is written to pipeline.ai_invocations as it completes; refreshed declines carry the rule that made them
// CF-247 S559. Migration 20261116090000_cf247_cdesc_v3_retry_gate_telemetry; worker coverage-sweep v1.0.5 (course-text.ts, cascade.ts, index.ts).
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42; the prompt registry by s553.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'
import { CDESC_SYSTEM_V3 as CDESC_SYSTEM, CDESC_SYSTEM_V3_SHA256 as CDESC_SYSTEM_SHA256, CDESC_SYSTEM_V2 } from '../../supabase/functions/coverage-sweep/course-text.ts'

const D = 'supabase/functions/coverage-sweep'
const M = fs.readFileSync('supabase/migrations/20261116090000_cf247_cdesc_v3_retry_gate_telemetry.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const IX = fs.readFileSync(`${D}/index.ts`, 'utf8')
const CS = fs.readFileSync(`${D}/cascade.ts`, 'utf8')

test('prompt v3: v2 plus the opener rule, released in the worker and the database together', () => {
  // v1.0.20 (s662): v4 is released; v3 is kept as CDESC_SYSTEM_V3 and checked here as it was sent
  expect(CDESC_SYSTEM.startsWith('SYSTEM — STUDYSEARCH COURSE DESCRIPTION / cdesc-source-grounded-v3\n')).toBe(true)
  expect(crypto.createHash('sha256').update(CDESC_SYSTEM).digest('hex')).toBe(CDESC_SYSTEM_SHA256)
  expect(CDESC_SYSTEM).toContain('Do not open with, and do not write, a sentence that only introduces the course, such as\n"The <course title> at <provider> is a ..."')
  expect(CDESC_SYSTEM).toContain('Start the first sentence directly with a substantive fact about this course that a cited span\nprints')
  // nothing else changed: removing the two added lines and the version gives v2 back
  const back = CDESC_SYSTEM.replace(/Do not open with[\s\S]*?and cite that span\.\n/, '').replaceAll('cdesc-source-grounded-v3', 'cdesc-source-grounded-v2')
  expect(back).toBe(CDESC_SYSTEM_V2)
  expect(code).toContain("select pg_temp.edit_all('security.cdesc_prompt_version_v1()', '37742f360fde35048aa1fc044a908051', '46449a8715ab34d3826ec80dc9e1724b'")
  expect(code).toContain(`'${CDESC_SYSTEM_SHA256}'`)
  expect(code).toContain("set status = 'retired'")
})

test('smart retry gate: the second model only for the listed rules, from a setting the policy stamp does not read', () => {
  expect(IX).toContain('const retryRules = (() => { const v = ws["enrich.cdesc_retry_rules"];')
  expect(IX).toContain('if (rule1 && rule1 !== "not_stated" && retryRules.includes(rule1)) {')
  expect(IX).toContain('tally.desc_quality_retry_skipped')
  expect(code).toMatch(/'pipeline', 'enrich\.cdesc_retry_rules', 'Course description: rules that earn a second model',/)
  expect(code).toContain("'list', '[\"quote_not_on_page\", \"identity_margin_thin\"]'::jsonb")
  // the machine rule's policy stamp reads enrich.course_description_%: this key stays outside it, so no re-evaluation wave starts
  expect('enrich.cdesc_retry_rules'.startsWith('enrich.course_description_')).toBe(false)
})

test('per-attempt flush: each attempt is written as it completes; a refused write is kept for the end, a timed-out write is never sent twice', async () => {
  expect(IX).toContain('setTraceWriter(async (rows) => { const { error } = await cw.rpc("svc_ai_model_answered_v1"')
  expect((CS.match(/await flushAiTrace\(\)/g) || []).length).toBe(4)
  const { transformSync } = await import('esbuild')
  const out = `test-results/cascade-s559-${process.pid}.mjs`
  fs.mkdirSync('test-results', { recursive: true }); fs.writeFileSync(out, transformSync(CS, { loader: 'ts', format: 'esm' }).code)
  const { cascadeFetch, setTraceWriter, takeAiTrace, traceStats } = await import(`${process.cwd()}/${out}`)
  const ans = (m) => new Response(JSON.stringify({ model: m, choices: [{ finish_reason: 'stop', message: { content: '{}' } }], usage: { prompt_tokens: 10, completion_tokens: 2, cost: 0.001 } }), { status: 200 })
  const init = { method: 'POST', body: JSON.stringify({ model: 'v/a', response_format: { type: 'json_object' }, messages: [] }) }
  const models = [{ model_identifier: 'v/a' }, { model_identifier: 'v/b' }]
  // written while the call runs: the failed first attempt is in the ledger before the second model answers
  const written = []; let atSecond = -1
  setTraceWriter(async (rows) => { written.push(...rows) })
  await cascadeFetch(async (_u, i) => { const m = JSON.parse(i.body).model; if (m === 'v/a') return new Response(JSON.stringify({ error: { message: 'down' }, usage: { cost: 0.002 } }), { status: 503 }); atSecond = written.length; return ans(m) }, { models, service: 's' }, 'u', init)
  expect(atSecond).toBe(1)
  expect(written.map((r) => [r.model, r.outcome, r.cost])).toEqual([['v/a', 'failed', 0.002], ['v/b', 'answered', 0.001]])
  expect(takeAiTrace()).toEqual([])
  // a refused write keeps the rows for the end-of-call write
  setTraceWriter(async () => { throw Error('refused') })
  await cascadeFetch(async () => ans('v/a'), { models: [{ model_identifier: 'v/a' }], service: 's' }, 'u', { ...init })
  expect(takeAiTrace().map((r) => r.model)).toEqual(['v/a'])
  expect(traceStats.kept_for_end).toBeGreaterThan(0)
  setTraceWriter(null)
})

test('the decline label and the telemetry reads', () => {
  expect(code).toContain("array[$o$do update set reason_code = excluded.reason_code,$o$], array[$n$do update set rule = excluded.rule, reason_code = excluded.reason_code,$n$]")
  expect(code).toContain("update pipeline.course_description_machine_admissions set rule = 'cdesc-machine-v2'")
  for (const fn of ['telemetry_model_tier_v1', 'telemetry_layer_funnel_v1']) {
    const i = code.indexOf(`create or replace function security.${fn}(p_hours int)`), body = code.slice(i, code.indexOf('$f$;', i))
    expect(i, fn).toBeGreaterThan(0)
    expect(body).toContain('language sql stable security definer')
    expect(body).not.toMatch(/\b(insert into|update pipeline|delete from)\b/i)   // read only
    expect(code).toContain(`revoke all on function security.${fn}(int) from public, anon, authenticated;`)
  }
  for (const k of ['first_pass_admit_rate_pct', 'retry_rescue_rate_pct', 'cost_per_admitted_record_usd', 'unlogged_546_gap_usd', 'L3_ai_called', 'L4_auto_admitted', 'L4_human_review', 'L4_held', 'Catalogue_live_delta', 'AI_waste_pct', 'end_to_end_yield_pct'])
    expect(code, k).toContain(`'${k}'`)
  expect(code).toContain("security.consumer_api_check_v1() - 'checked_at'")
  expect(M).toMatch(/^-- Replaces: /m); expect(M).toMatch(/^-- Retires: /m)
})
