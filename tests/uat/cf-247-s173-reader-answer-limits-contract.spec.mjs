// Guards: CF-247 decision W32 (reader answer limits): every AI read's answer limit in the worker is a setting per read type (defaults are the values formerly fixed in code), an answer cut at its limit (finish_reason length, or not JSON at the limit) holds the whole read as held_partial: output_truncated on the existing failure path and is never parsed or proposed, and the cost of every call is recorded also when the read fails
// No network and no AI: the worker's pure functions (answer.ts, fees.ts) run against recorded long and cut answers; the worker and migration are read as text.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { READ_ANSWER_LIMITS, answerLimit, callCost, errorCost, readAnswer, readError } from '../../supabase/functions/coverage-sweep/answer.ts'
import { feeAiRequest } from '../../supabase/functions/coverage-sweep/fees.ts'

const FX = 'tests/fixtures/reader-answer-limits'
const fx = (f) => JSON.parse(fs.readFileSync(`${FX}/${f}`, 'utf8'))
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const [mig] = fs.readdirSync('supabase/migrations').filter((f) => f.endsWith('_cf247_reader_answer_limits.sql'))
const sql = mig ? fs.readFileSync(`supabase/migrations/${mig}`, 'utf8') : ''
const block = (from, to) => { const a = worker.indexOf(from); expect(a, from).toBeGreaterThan(-1); const b = worker.indexOf(to, a + from.length); expect(b, to).toBeGreaterThan(a); return worker.slice(a, b) }

test('the live fault: a course fields answer cut at 2,000 tokens is held_partial: output_truncated with its cost, never parsed (it was "Unterminated string in JSON", cost 0)', () => {
  const cut = fx('course-fields-truncated-response.json')
  expect(() => JSON.parse(cut.choices[0].message.content)).toThrow(/Unterminated string in JSON/)
  const r = readAnswer(cut, 'course_fields', 2000)
  expect(r).toEqual({ ok: false, cut: true, cost: 0.005648, error: 'held_partial: output_truncated: course_fields reached reading.answer_tokens.course_fields (2000)' })
  // a provider that reports "stop" on a cut answer: unreadable while it used the whole limit is still a cut answer
  const r2 = readAnswer(fx('course-fields-cut-finish-stop-response.json'), 'course_fields', 2000, 'course_fields')
  expect(r2.ok).toBe(false); expect(r2.cut).toBe(true)
  expect(r2.error).toBe('held_partial: output_truncated: course_fields used all of reading.answer_tokens.course_fields (2000)')
  // the same unreadable answer below the limit is named unreadable, not cut
  const r3 = readAnswer(fx('course-fields-cut-finish-stop-response.json'), 'course_fields', 4000)
  expect(r3.cut).toBe(false); expect(r3.error).toMatch(/^unreadable_answer: course_fields \(Unterminated string in JSON/)
})

test('a cut answer with nothing in it is a cut read, not "no answer"; an empty answer is named with its reason; cost is kept on both', () => {
  const r = readAnswer(fx('scholarship-cut-empty-response.json'), 'scholarship_page', 3000)
  expect(r).toMatchObject({ ok: false, cut: true, cost: 0.000611 })
  expect(r.error).toBe('held_partial: output_truncated: scholarship_page reached reading.answer_tokens.scholarship_page (3000)')
  const e = readAnswer({ choices: [{ finish_reason: 'error', error: { message: 'upstream' }, message: { content: '' } }], usage: { cost: 0.0002 } }, 'scholarship_recheck', 800)
  expect(e).toEqual({ ok: false, cut: false, cost: 0.0002, error: 'no_answer: scholarship_recheck (upstream)' })
  // an error carries its cost to the catch that records the failure
  const err = readError(r.error, r.cost)
  expect(errorCost(err)).toBe(0.000611); expect(errorCost(Error('x'))).toBe(0); expect(errorCost(null)).toBe(0)
})

test('a long whole answer is read; the same answer cut at a lower limit proposes no row', () => {
  const whole = readAnswer(fx('fee-page-long-whole-response.json'), 'fee_page', 32000)
  expect(whole.ok).toBe(true); expect(whole.a.rows.length).toBe(123); expect(whole.cost).toBe(0.02688)
  const cut = readAnswer(fx('fee-page-cut-response.json'), 'fee_page', 8000)
  expect(cut.ok).toBe(false); expect(cut.cut).toBe(true); expect(cut.a).toBeUndefined(); expect(cut.cost).toBe(0.01696)
  expect(callCost({ usage: { cost: 'x' } })).toBe(0); expect(callCost({})).toBe(0)
})

test('limits are settings per read type; the defaults are the values formerly fixed in the worker', () => {
  const was = { course_fields: 2000, course_titles: 2000, campus_regions: 2000, campus_lists: 2000, provider_address: 2000, scholarship_page: 3000, scholarship_recheck: 800,
    central_page: 1500, fee_page: 32000, course_page_match: 300, adapter_proposal: 4000, adapter_proposal_retry: 8000 }
  expect(Object.fromEntries(Object.entries(READ_ANSWER_LIMITS).map(([k, v]) => [k, v.def]))).toEqual(was)
  for (const [k, v] of Object.entries(READ_ANSWER_LIMITS)) {
    expect(v.key).toBe(`reading.answer_tokens.${k}`)  // prefix reading.: returned by svc_worker_settings_v1 unchanged
    expect(answerLimit({}, k)).toBe(v.def)
    expect(answerLimit({ [v.key]: 5000 }, k)).toBe(5000)
    expect(answerLimit({ [v.key]: 0 }, k)).toBe(v.def)
    expect(answerLimit({ [v.key]: 'x' }, k)).toBe(v.def)
  }
  expect(answerLimit(null, 'fee_page')).toBe(32000)
  // the fee request carries the limit only when given (none was sent before W32)
  const it = { provider: 'U', country: 'AU', url: 'https://u.example/fees', notes: '', profile: {}, findings: [], courses: [] }
  expect(feeAiRequest('openai/gpt-4.1-mini', it, 'A$1').max_tokens).toBeUndefined()
  expect(feeAiRequest('openai/gpt-4.1-mini', it, 'A$1', 32000).max_tokens).toBe(32000)
})

test('worker v0.54.0: every reader takes its limit from its setting, reads its answer with readAnswer, and records the cost of a failed read', () => {
  expect(worker).toMatch(/(const WORKER = "coverage-sweep-worker-v0\.54\.0"; |\/\/ was v0\.54\.0 )\/\/ v0\.54\.0 \(30 Oct 2026, CF-247 decisions W30 and W32; W32, reader answer limits\)/) // shipped with W30 in v2.15.370; later versions keep the note
  expect(worker).toContain('import { answerLimit, errorCost, readAnswer, readError, type ReadType } from "./answer.ts";')
  // enrich_ai: one ask for five read types, each with its own setting; a failed read records its cost over its items
  const ask = block('const ASK_READ: Record<string, ReadType>', 'const ENTRY_PROMPT')
  expect(ask).toContain('{ course_fields: "course_fields", titles: "course_titles", campus_regions: "campus_regions", campus_list: "campus_lists", address: "provider_address" }')
  expect(ask).toContain('max_tokens: maxTokens,'); expect(ask).not.toMatch(/max_tokens: \d/)
  expect(ask).toContain('const ans = readAnswer(d, read, maxTokens, name); cost += ans.cost;')
  expect(ask).toContain('if (!ans.ok) throw readError(ans.error, ans.cost);')
  expect(worker).toContain('const c1 = errorCost(e) / Math.max(1, ids.length); for (const id of ids) out.push({ item_id: id, error: (e instanceof Error ? e.message : String(e)).slice(0, 300), cost: c1 });')
  for (const n of ['"course_fields"', '"titles"', '"campus_regions"', '"campus_list"', '"address"']) expect(worker).toContain(`, ${n},`)
  // scholarship pages, re-check, central pages, fee pages, page match: limit from the setting, answer through readAnswer
  for (const [read, v] of [['scholarship_page', 'schTokens'], ['scholarship_recheck', 'recheckTokens'], ['central_page', 'centralTokens'], ['fee_page', 'feeTokens'], ['course_page_match', 'matchTokens']]) {
    expect(worker).toContain(`${v} = answerLimit(ws, "${read}")`)
    expect(worker).toContain(`readAnswer(d, "${read}", ${v})`)
  }
  expect(worker).toContain('scholarshipAiRequest(it.model, it.prompt, { provider: it.provider || "", url: finalUrl, title, h1, text }, schTokens)')
  expect(worker).toContain('centralAiRequest(it.model, it.kind, { provider: it.provider || "", url: it.url, text }, centralTokens)')
  expect(worker).toContain('aiMatchRequest(it, matchTokens)')
  expect(worker).toContain('course_page: it.course_page === true }, text, feeTokens)')
  expect(worker).toContain('p_cost: errorCost(e), p_storage_path: path')  // scholarship page failure
  expect((worker.match(/await rec\(\{ p_error: \(e instanceof Error \? e\.message : String\(e\)\)\.slice\(0, 400\), p_cost: errorCost\(e\) \}\)/g) || []).length).toBe(2)  // central and fee failures
  // adapter proposal: the two-step ladder from settings
  expect(worker).toContain('const firstTokens = answerLimit(ws, "adapter_proposal"), retryTokens = answerLimit(ws, "adapter_proposal_retry");')
  // no answer limit is left as a number in a request builder of the worker, except the page-identity qualification contract (pageid.ts, not used here)
  expect(worker).not.toMatch(/max_tokens: \d/)
  for (const f of ['aiMatchRequest', 'scholarshipAiRequest', 'scholarshipRecheckRequest', 'centralAiRequest']) expect(worker).toMatch(new RegExp(`export function ${f}\\([^\\n]*, maxTokens = \\d+\\) \\{`))
})

test('migration: twelve answer-limit settings with label, range, unit, used_by and reason; Replaces and Retires; nothing dropped', () => {
  expect(mig).toBe('20261030020000_cf247_reader_answer_limits.sql')
  expect(sql).toMatch(/^-- Replaces: .+/m); expect(sql).toMatch(/^-- Retires: nothing/m)
  const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
  expect(code).not.toMatch(/\b(drop|delete|truncate|alter table|rename)\b/i)
  for (const [k, v] of Object.entries(READ_ANSWER_LIMITS)) {
    const m = code.match(new RegExp(`\\('pipeline', '${v.key.replace(/\./g, '\\.')}', 'AI answer length: [^']+',\\s*'(?:[^']|'')+', 'number',\\s*to_jsonb\\((\\d+)\\), (\\d+), (\\d+), 'tokens', (\\d+), 'AI answer limits', '([^']+)',\\s*'CF-247 decision W32`))
    expect(m, k).not.toBeNull()
    const [, val, lo, hi] = m.map(Number)
    expect(val).toBe(v.def); expect(lo).toBeLessThanOrEqual(val); expect(hi).toBeGreaterThanOrEqual(val)
    expect(m[5]).toMatch(/^worker coverage-sweep /)
  }
  expect(code).toContain('on conflict (toolset_key, key) do nothing;')
  expect(code).toContain("if v_n <> 12 then raise exception 'W32 post-check")
})
