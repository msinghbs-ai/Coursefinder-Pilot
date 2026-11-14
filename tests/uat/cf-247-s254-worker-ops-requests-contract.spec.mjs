// Guards: P0 Autonomous AI Operations, worker release v0.59.5 for the workstreams' interface requests (Integration Controller 3 Nov 2026 18:20):
// AI diagnosis through the existing OpenRouter path with the pinned model under workstream A2's contract ops-diagnose-v1 (only the contract's
// fields, {error} on any failure, every request answered exactly once), a job that does nothing while ops.ai_diagnosis_on is 0 (workstream A);
// enrich_ai answers kept before they are recorded (workstream D); entry reader fidelity: dropped entries keep the model's values, printed ranges,
// subject-equivalence rows and global-qualification pages, each behind a setting that ships off and still to Layer 4 (workstream C); one paid
// course-page search per query, behind a setting that ships off (workstream F). The migration runs on isolated fixtures by
// tests/fixtures/ops-worker-requests/run.sh (scratch PostgreSQL; the live functions the worker calls loaded from the repository and checked against
// the live md5s; applied twice; every case asserted). This spec runs the worker's pure functions and holds the wiring.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { OPS_DIAGNOSE_CONTRACT, OPS_DIAGNOSE_TOKENS_DEFAULT, OPS_DIAGNOSE_TOKENS_KEY, opsContextText, opsDiagnoseAnswer, opsDiagnoseLimit, opsDiagnoseRequest, opsDiagnoseUsable } from '../../supabase/functions/coverage-sweep/ops-diagnose.ts'
import { linkQueryKey, linkSearchGroups, linkSearchShareOn } from '../../supabase/functions/coverage-sweep/link-share.ts'
import { entryGlobalQualification, entryMatrixParsed, entryNonCountryShape, entryRangeLower, entrySubjectRows } from '../../supabase/functions/coverage-sweep/entry.ts'

const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const MIG = 'supabase/migrations/20261104110000_cf247_ops_worker_requests.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/ops-worker-requests'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const mode = (name) => { const a = worker.indexOf(`if (mode === "${name}") {`); expect(a, name).toBeGreaterThan(-1); return worker.slice(a, worker.indexOf('\n    if (mode === "', a + 10)) }

const ctx = { issue: 'IQ-00070', failure: 'coverage-admit failed 3 of 6 runs', evidence: { error: 'canceling statement "refresh" due to statement timeout' } }
const item = { id: 7, model: 'openai/gpt-4.1-mini', lease_until: '2026-11-03T08:00:00Z', contract: 'ops-diagnose-v1', context: ctx, instructions: 'You diagnose one issue.',
  response_schema: { type: 'object', required: ['root_cause', 'confidence', 'evidence'], additionalProperties: false,
    properties: { root_cause: { type: 'string', enum: ['lock_conflict', 'statement_timeout'] }, confidence: { type: 'number', minimum: 0, maximum: 1 },
                  evidence: { type: 'array', minItems: 1, items: { type: 'string' } }, reasoning: { type: 'string' } } } }
const reply = (content, extra = {}) => ({ model: 'openai/gpt-4.1-mini', usage: { cost: 0.0012, completion_tokens: 90 }, choices: [{ finish_reason: 'stop', message: { content: JSON.stringify(content) } }], ...extra })

test('version: v0.59.5, below v0.60, with the v0.59.4 note kept in the chain', () => {
  // the v0.59.5 note stays in the version chain once a later worker is released ("// was v0.59.5 // ..."), as s233 does for v0.59.4
  expect(worker).toMatch(/(?:const WORKER = "coverage-sweep-worker-v0\.59\.5"; |\n\/\/ was v0\.59\.5 )\/\/ v0\.59\.5 \(3 Nov 2026, CF-247 P0 autonomous operations/)
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v(?:[1-9]\d*\.\d+\.\d+|0\.(?:59\.\d+|[6-9]\d\.\d+))";/)  // v0.59 or a later worker
  expect(worker).toContain('\n// was v0.59.4 // v0.59.4 (3 Nov 2026, CF-247 Workstream C')
})

test('ops_diagnose (A2 contract ops-diagnose-v1): the given instructions and schema to the pinned model; only the contract fields; {error} on failure', () => {
  expect(OPS_DIAGNOSE_CONTRACT).toBe('ops-diagnose-v1')
  expect(opsDiagnoseUsable(item)).toBeNull()
  expect(opsDiagnoseUsable({ ...item, contract: 'old' })).toContain('unsupported contract')
  expect(opsDiagnoseUsable({ ...item, response_schema: null })).toContain('no instructions or response_schema')
  const r = opsDiagnoseRequest(item, 800)
  expect(r.model).toBe('openai/gpt-4.1-mini'); expect(r.temperature).toBe(0); expect(r.provider).toEqual({ require_parameters: true }); expect(r.max_tokens).toBe(800)
  expect(r.messages[0]).toEqual({ role: 'system', content: 'You diagnose one issue.' })
  expect(r.response_format.json_schema.schema).toBe(item.response_schema)
  expect(r.response_format.json_schema.strict).toBe(false)  // reasoning is optional, so strict mode cannot be asked
  expect(opsDiagnoseLimit({})).toBe(OPS_DIAGNOSE_TOKENS_DEFAULT); expect(opsDiagnoseLimit({ [OPS_DIAGNOSE_TOKENS_KEY]: 1200 })).toBe(1200)
  expect(opsContextText(ctx)).toBe('IQ-00070\ncoverage-admit failed 3 of 6 runs\ncanceling statement "refresh" due to statement timeout')
  // an answer: exactly the contract's fields; quotes from the context's text (quotation marks allowed), invented ones left out
  const ok = opsDiagnoseAnswer(reply({ root_cause: 'statement_timeout', confidence: 0.8, evidence: ['statement "refresh" due to statement timeout', 'invented text'], reasoning: 'It says so.', extra: 1 }), item, 800, true)
  expect(ok.answer).toEqual({ root_cause: 'statement_timeout', confidence: 0.8, evidence: ['statement "refresh" due to statement timeout'], reasoning: 'It says so.' })
  expect(ok.dropped_quotes).toBe(1); expect(ok.cost).toBe(0.0012)
  expect(Object.keys(opsDiagnoseAnswer(reply({ root_cause: 'lock_conflict', confidence: 0.4, evidence: ['coverage-admit failed'] }), item, 800, true).answer).sort()).toEqual(['confidence', 'evidence', 'root_cause'])
  // every failure is {error} with the cost spent
  const errs = [
    opsDiagnoseAnswer(reply({}, { choices: [{ finish_reason: 'length', message: { content: '{"root' } }] }), item, 800, true),
    opsDiagnoseAnswer(reply({ root_cause: 'lock_conflict', confidence: 0.9, evidence: ['coverage-admit'] }, { model: 'other/model' }), item, 800, true),
    opsDiagnoseAnswer(reply({ root_cause: 'not_registered', confidence: 0.9, evidence: ['coverage-admit'] }), item, 800, true),
    opsDiagnoseAnswer(reply({ root_cause: 'lock_conflict', confidence: 1.4, evidence: ['coverage-admit'] }), item, 800, true),
    opsDiagnoseAnswer(reply({ root_cause: 'lock_conflict', confidence: 0.9, evidence: ['nowhere in it'] }), item, 800, true),
    opsDiagnoseAnswer({ error: { message: 'bad request' } }, item, 800, false, 400),
    opsDiagnoseAnswer({ choices: [{ finish_reason: 'stop', message: { content: '' } }] }, item, 800, true),
  ]
  for (const e of errs) expect(Object.keys(e.answer)).toEqual(['error'])
  expect(errs[0].answer.error).toContain('output_truncated'); expect(errs[0].cost).toBe(0.0012)
  expect(errs[1].answer.error).toContain('not openai/gpt-4.1-mini')
  // the mode answers every leased request exactly once: one record call, after either the answer or the error
  const d = mode('ops_diagnose')
  expect(d).toContain('await rpc("svc_ops_diagnosis_next", { p_limit: Math.min(Number(body.limit || 5), 20) })')
  expect((d.match(/rpc\("svc_ops_diagnosis_record"/g) || []).length).toBe(1)
  expect(d).toContain('await rpc("svc_ops_diagnosis_record", { p_id: Number(it.id), p_answer: out.answer, p_cost_usd: out.cost })')
  expect(d).toContain('if (why) out = { answer: { error: why }, cost: 0, dropped_quotes: 0 };')
  expect(d).not.toMatch(/\breturn\b[^\n]*\n[^\n]*svc_ops_diagnosis_record/)
  // worker v0.86.0 (13 Nov 2026): the same one-model call goes through cascade.ts so that the attempt is kept (pipeline.ai_invocations)
  expect(d).toContain('cascadeFetch(ors.fetch, { service: "ops_diagnosis" }, "https://openrouter.ai/api/v1/chat/completions"')
  expect(d).toContain('layer3_provider_credential_resolve_service')
  expect(d).not.toMatch(/firecrawl|useFc|svc_fc_spend/i)
  expect(fixtures).toContain('W4 ok')
})

test('ops-diagnose job: catalogued, no number in its command, does nothing while ops.ai_diagnosis_on is 0', () => {
  expect(m).toContain("perform cron.schedule('ops-diagnose', '27,57 * * * *', $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'ops_diagnose', 'limit', security.pipeline_num_v1('batch.ops_diagnose', 5)::int)) where security.pipeline_num_v1('ops.ai_diagnosis_on', 0) >= 1 and exists")
  expect(m).toContain("('ops-diagnose', 'Platform upkeep', 61, 'AI diagnosis of low-confidence issues',")
  for (const [k, v] of Object.entries({ 'public.svc_ops_diagnosis_next(integer)': 'adc209ebf9196c613e3dd82fa76fed61', 'public.svc_ops_diagnosis_record(bigint,jsonb,numeric)': '6f1fd77189ea85610a57c6feef16a130',
    'public.svc_enrich_ai_stash_v1(jsonb)': '70a97d7a560571d2de2fecc68ea8ee64' })) { expect(m).toContain(`'${k}'::regprocedure)) <> '${v}'`); expect(run).toContain(`["${k}"]=${v}`) }
  expect(fixtures).toContain('W1 ok')
})

test('enrich_ai (D): the answers are kept first, a failed stash never stops the record', () => {
  const e = mode('enrich_ai')
  const s = e.indexOf('await rpc("svc_enrich_ai_stash_v1", { p_results: noNul(out) }).catch('), r = e.indexOf('await rpc("svc_enrich_ai_record", { p_results: noNul(out) })')
  expect(s).toBeGreaterThan(0); expect(r).toBeGreaterThan(s)
  expect(e).toContain('return j({ ok: true, mode, model, items: out.length, tally, stash, recorded: res,')
})

test('entry reader (C): dropped entries keep the model values; ranges, subject rows and global pages only behind their settings', () => {
  const page = 'China (Gaokao) 488 to 491 | 65% | 70\nUnited States AP Chemistry | Chemistry; 3 or higher\nUnited States AP Physics | Physics; 3 or higher'
  const row = { country_code: 'CN', country_name: 'China', study_level: null, qualification_name: 'Gaokao', min_grade: null, min_value: 489, grade_scale: 'points',
    benchmark_band: null, course_name: null, conditions: { subject_minimums: [], best_n: null, alternatives: [] }, confidence: 0.9, quote: 'China (Gaokao) 488 to 491' }
  const off = entryMatrixParsed({ rows: [row] }, page)
  expect(off.rows).toHaveLength(0); expect(off.dropped[0]).toMatchObject({ reason: 'value_not_in_quote', value: 489, scale: 'points' })
  const on = entryMatrixParsed({ rows: [row] }, page, [], { rangeLower: true })
  expect(on.rows).toHaveLength(1); expect(on.rows[0].min_value).toBe(488)
  const viaLines = entryMatrixParsed({ rows: [row] }, page, Object.assign([], { rangeLower: true }))
  expect(viaLines.rows[0].min_value).toBe(488)
  expect(entryRangeLower(489, '488 to 491 and 480 to 495')).toBeNull()  // two ranges hold it: not decided
  expect(entryRangeLower(500, '488 to 491')).toBeNull()
  const ap = (s) => ({ ...row, country_code: 'US', country_name: 'United States', qualification_name: 'Advanced Placement', min_value: null, grade_scale: 'none', min_grade: '3 or higher',
    quote: `United States AP ${s} | ${s}; 3 or higher` })
  const merged = entrySubjectRows([ap('Chemistry'), ap('Physics'), row])
  expect(merged.merged).toBe(2); expect(merged.rows).toHaveLength(2)
  expect(merged.rows[0].conditions.subject_minimums).toEqual([{ subject: 'United States AP Chemistry', min_grade: '3 or higher' }, { subject: 'United States AP Physics', min_grade: '3 or higher' }])
  expect(merged.rows[0].conditions.subject_quotes).toHaveLength(2); expect(merged.rows[0].row_kind).toBe('subject_prerequisites')
  expect(entrySubjectRows([ap('Chemistry')]).merged).toBe(0)
  const quals = ['international baccalaureate', 'global assessment certificate'], phrases = ['regardless of country']
  expect(entryGlobalQualification('International Baccalaureate | RMIT', 'The IB Diploma is accepted regardless of country of study.', quals, phrases)).toBe('international baccalaureate')
  expect(entryGlobalQualification('International Baccalaureate | RMIT', 'The IB Diploma minimum is 24.', quals, phrases)).toBeNull()  // the page must say it is global
  const man = { status: 'ok', reason: null, heading: 'International Baccalaureate', entries: [], columns: ['Score'], footnotes: [] }
  expect(entryNonCountryShape(man, [])).toContain('no country named')
  expect(entryNonCountryShape({ ...man, global: 'international baccalaureate' }, [])).toBeNull()
  const e = mode('entry_ai')
  expect(e).toContain('stored.lines.rangeLower = Number(ws["reading.entry_range_lower_bound_on"]) >= 1;')
  expect(e).toContain('const subj = Number(ws["reading.entry_subject_rows_on"]) >= 1 ? entrySubjectRows(rows) : { rows, merged: 0 };')
  expect(e).toContain('const globalQ = Number(ws["reading.entry_global_pages_on"]) >= 1')
  // completeness is judged on the rows as read, before any merge; the result still goes to the database (Layer 4) as before
  expect(e.indexOf('const completeness = entryCompleteness(stored.manifest, rows);')).toBeLessThan(e.indexOf('entrySubjectRows(rows)'))
})

test('link search (F): one paid search per query and an earlier answer reused, only with reading.link_search_share_on', () => {
  expect(linkQueryKey('  Bachelor  of NURSING site:u1.example ')).toBe('bachelor of nursing site:u1.example')
  const g = linkSearchGroups([{ course_id: 'a', query: 'Nursing' }, { course_id: 'b', query: 'nursing ' }, { course_id: 'c', query: 'Arts' }])
  expect(g.map((x) => [x.key, x.items.length])).toEqual([['nursing', 2], ['arts', 1]])
  expect(linkSearchShareOn({})).toBe(false); expect(linkSearchShareOn({ 'reading.link_search_share_on': 1 })).toBe(true)
  const l = mode('link_search')
  expect(l).toContain('if (linkSearchShareOn(ws)) {')
  expect(l).toContain('await rpc("svc_course_link_search_prior_v1", { p_queries: groups.map((g) => g.key) })')
  expect((l.match(/useFcWhy\("course_link_search"/g) || []).length).toBe(2)  // once per query when sharing; once per course otherwise (unchanged)
  expect(m).toMatch(/'reading\.link_search_share_on'[\s\S]*?to_jsonb\(0\), 0, 1, 'on\/off'/)
  expect(m).toContain("security.pipeline_num_v1('ops_cost.repeat_search_hours', 24)")
  expect(fixtures).toContain('W2 ok')
})

test('every new behaviour that changes what is proposed or searched ships off', () => {
  for (const k of ['reading.entry_range_lower_bound_on', 'reading.entry_subject_rows_on', 'reading.entry_global_pages_on', 'reading.link_search_share_on'])
    expect(m).toMatch(new RegExp(`'${k.replace(/\./g, '\\.')}'[\\s\\S]*?to_jsonb\\(0\\), 0, 1, 'on/off'`))
  expect(m).toContain("raise exception 'worker requests post-check: a behaviour that changes what is proposed or searched did not ship off'")
  expect(fixtures).toContain('W3 ok')
})
