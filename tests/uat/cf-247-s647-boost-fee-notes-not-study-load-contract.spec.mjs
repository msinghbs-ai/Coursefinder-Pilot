// Guards: Boost learnings promoted into the reader (Platform Admin 18 Nov 2026 14:29 item 1): a domestic fee note (EFTSL, Commonwealth supported places, a fee calculated on a standard full-time load) is never sent to the model, never counts as a statement for international students and is refused as a study load quote; the pages behind refused readings are read again; newly waiting scholarships are decided by the scope rule every hour
// CF-247 S647 (was S643; renumbered, s643 is held by the PR 4 lane-fold spec). Migration 20261118171000_cf247_boost_study_load_v5_fee_notes, worker coverage-sweep v1.0.17 (boost.ts prompt boost-study-load-v5, selector study-load-windows-v4). The fee notes below are quoted from live refused readings of 18 Nov 2026. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build } from 'esbuild'

const M = fs.readFileSync('supabase/migrations-archive/20261118171000_cf247_boost_study_load_v5_fee_notes.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
let B
test.beforeAll(async () => {
  const out = await build({ entryPoints: ['supabase/functions/coverage-sweep/boost.ts'], bundle: true, format: 'esm', write: false, logLevel: 'silent' })
  B = await import('data:text/javascript;base64,' + Buffer.from(out.outputFiles[0].text).toString('base64'))
})

const FEE1 = 'The indicative annual tuition fee is calculated based on a standard full-time study load which is usually 8 credit points or 6 credit points for certificate programs.'
const FEE2 = 'Your student contribution amount is based on a standard full-time load of 48 credit points (1.0 EFTSL).'
const FEE3 = 'Commonwealth supported places are available for domestic students studying full-time or part-time.'

test('the prompt and the versions name the fee-note rule', () => {
  expect(B.BOOST_STUDY_LOAD_PROMPT_VERSION).toBe('boost-study-load-v5')
  expect(B.BOOST_SELECTOR).toBe('study-load-windows-v6')  // v6 from s721  // v5 from worker v1.0.20 (s661)
  expect(B.BOOST_STUDY_LOAD_SYSTEM).toContain('A fee note never states the course\'s study load')
  expect(B.BOOST_STUDY_LOAD_SYSTEM).toContain('(1.0 EFTSL)')
  for (const x of [FEE1, FEE2, FEE3]) expect(B.isFeeNote(x), x).toBe(true)
  for (const x of ['This course is available full-time or part-time.', 'International students on a student visa must study full-time.', 'Duration: 3 years full-time.']) expect(B.isFeeNote(x), x).toBe(false)
})

test('a fee note is not sent; a page whose study words are all in fee notes sends nothing', () => {
  const onlyFees = `Fees\n${FEE1}\nMore about fees.\n${FEE2}`
  const s1 = B.studyLoadSections(onlyFees, 6000)
  expect(s1.hits).toBeGreaterThan(0)
  expect(s1.text).toBe('')
  expect(s1.selector).toBe('fee_notes_only')
  const mixed = `Course overview. This degree is offered full-time or part-time on campus.\n\nFees. ${FEE1}`
  const s2 = B.studyLoadSections(mixed, 6000)
  expect(s2.text).toContain('offered full-time or part-time')
  expect(s2.text).not.toContain('calculated based on a standard full-time study load')
  expect(B.internationalStudySentences(`International students: ${FEE2}`)).toEqual([])
})

test('a fee note is refused as a quote; a real statement next to it still passes', () => {
  const page = `Overview. This degree is offered full-time or part-time. ${FEE1}`
  const flat = B.boostFlat(page)
  const bad = B.verifyStudyLoad({ study_load: 'full_time', basis: 'general', quote: FEE1, reason: null }, flat, page)
  expect(bad.ok).toBe(false)
  expect(bad.problems).toContain("the quote is a fee note (a fee calculation, EFTSL or CSP), not the course's study load")
  const good = B.verifyStudyLoad({ study_load: 'both', basis: 'general', quote: 'This degree is offered full-time or part-time.', reason: null }, flat, page)
  expect(good.ok).toBe(true)
})

test('the worker skips fee-note-only pages without a model call', () => {
  const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.42"')  // v1.0.38 from s1037  // v1.0.37 from s1029  // v1.0.36 from s1017  // v1.0.35 from s992  // v1.0.34 from s851  // v1.0.25 from s721  // v1.0.19 from s674
  expect(IX).toContain('if (!sec.hits || !sec.text) {  // v1.0.17: a page whose study words are all in fee notes sends nothing, as a page with none')
})

test('migration: route rows follow v5, the pages behind open readings are read again, the scholarship rule runs every hour', () => {
  expect(code).toContain("set prompt_version = 'boost-study-load-v5',")
  expect(code).toContain("where service_code in ('boost_extract', 'boost_extract_benchmark') and prompt_version = 'boost-study-load-v4';")
  expect(code).not.toMatch(/insert into pipeline\.boost_model_qualifications|update pipeline\.boost_model_qualifications/)
  expect(code).toContain("where r.status = 'open' and x.lane = 'study_load' and x.state = 'rejected';")
  expect(code).toContain("set state = 'released', note = 'read again by worker v1.0.17")
  expect(code).toContain("v_res := security.scholarship_scope_auto_decide_v1(r.scholarship_id, true);")
  expect(code).toContain("if security.pipeline_num_v1('scholarship.scope_auto_on', 0) < 1 or v_lim = 0 then")
  expect(code).toContain("select cron.schedule('scholarship-scope-auto', '19 * * * *',")
  expect(code).toContain("security.pipeline_num_v1(''batch.scholarship_scope_auto'', 50)::int")
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
