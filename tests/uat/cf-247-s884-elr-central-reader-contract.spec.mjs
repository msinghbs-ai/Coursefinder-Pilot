// Guards: CF-247 s884 (session S1-ELR-Central, Platform Admin 20 Nov 2026 22:07 AEDT): elr-central-v1.0 reads a stored central English page deterministically by study-level tier (undergraduate, postgraduate coursework, research, VET and diploma), keeps PTE decimals and verbatim quotes, gives a value to a tier only when the line, row or heading names it (or says all courses), leaves conflicting values out, and reports regulated disciplines instead of using them as a default
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { centralRead, tiersOf, disciplineOf, ELR_CENTRAL_VERSION } from '../../supabase/functions/coverage-sweep/elr-central-reader.ts'

const SRC = fs.readFileSync('supabase/functions/coverage-sweep/elr-central-reader.ts', 'utf8')
const WORKER = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const PAGE = ['# English language requirements', '## Undergraduate',
  'IELTS Academic: 6.5 overall with no band below 6.0. TOEFL iBT: 79 overall with writing 21.', 'PTE Academic: 58.5 overall, no communicative skill below 50.',
  '## Postgraduate coursework', 'IELTS 6.5 overall (no band below 6.0); PTE Academic 64 overall',
  '## Higher degree by research', 'IELTS 7.0 overall with no band below 6.5.',
  '## Vocational education (VET) and diplomas', 'IELTS 5.5 overall, no band below 5.0.',
  '## Nursing and midwifery', 'IELTS 7.0 overall with 7.0 in each band.', 'Foundation program: IELTS 5.0 overall.'].join('\n')
const code = (t, tier) => (centralRead(t).defaults[tier] || []).map((r) => [r.test_code, r.overall_score])

test('the module is pure: no model, fetch, storage, database or environment access', () => {
  expect(SRC).not.toMatch(/\bfetch\s*\(|openrouter|firecrawl|Deno\.|supabase|\.rpc\(|\.storage\b/i)
  expect(ELR_CENTRAL_VERSION).toBe('elr-central-v1.0')
})

test('each tier gets its own value under its own heading; decimals and quotes are kept', () => {
  const r = centralRead(PAGE)
  expect(code(PAGE, 'undergraduate')).toEqual([['IELTS', 6.5], ['TOEFL_IBT', 79], ['PTE', 58.5]])
  expect(code(PAGE, 'postgraduate')).toEqual([['IELTS', 6.5], ['PTE', 64]])
  expect(code(PAGE, 'research')).toEqual([['IELTS', 7]])
  expect(code(PAGE, 'vet')).toEqual([['IELTS', 5.5]])
  expect(r.defaults.undergraduate[0].component_scores).toEqual({ reading: 6, writing: 6, speaking: 6, listening: 6 })
  for (const t of Object.values(r.defaults)) for (const q of t) expect(PAGE).toContain(q.quote)
})

test('regulated disciplines are reported, never a tier default; pathway lines are ignored', () => {
  const r = centralRead(PAGE)
  expect(r.discipline_higher.map((d) => d.discipline)).toEqual(['nursing'])
  expect(code(PAGE, 'vet')).not.toContainEqual(['IELTS', 5])
  expect(disciplineOf('Bachelor of Laws')).toBe('law')
  expect(disciplineOf('Master of Teaching (Secondary)')).toBe('education')
  expect(disciplineOf('Vocational education and training')).toBe(null)
})

test('strict tiers: a line naming two tiers is split; "all courses" means undergraduate and postgraduate only; a line with no tier gives nothing', () => {
  const two = 'IELTS 6.0 overall for undergraduate courses and 6.5 overall for postgraduate coursework.'
  expect(code(two, 'undergraduate')).toEqual([['IELTS', 6]])
  expect(code(two, 'postgraduate')).toEqual([['IELTS', 6.5]])
  const all = 'All courses require IELTS 6.5 overall with no band below 6.0.'
  expect(Object.keys(centralRead(all).defaults).sort()).toEqual(['postgraduate', 'undergraduate'])
  expect(centralRead('IELTS 6.5 overall with no band below 6.0.').defaults).toEqual({})
  expect(tiersOf('Graduate Diploma')).toEqual(['postgraduate'])
  expect(tiersOf('Doctor of Philosophy')).toEqual(['research'])
  expect(tiersOf('Advanced Diploma')).toEqual(['vet'])
})

test('two values of one test for one tier are a conflict and the test is left out', () => {
  const t = ['## Undergraduate', 'IELTS 6.0 overall.', 'IELTS 6.5 overall.', 'PTE Academic 50 overall.'].join('\n')
  const r = centralRead(t)
  expect(r.conflicts).toEqual([{ tier: 'undergraduate', test_code: 'IELTS', values: [6, 6.5] }])
  expect(code(t, 'undergraduate')).toEqual([['PTE', 50]])
})

test('a test table is read row by row with the row line as the quote', () => {
  const t = ['| Level | IELTS | TOEFL iBT | PTE Academic |', '|---|---|---|---|', '| Undergraduate | 6.5 | 79 | 58 |', '| Postgraduate | 7.0 | 94 | 65 |'].join('\n')
  expect(code(t, 'undergraduate')).toEqual([['IELTS', 6.5], ['TOEFL_IBT', 79], ['PTE', 58]])
  expect(code(t, 'postgraduate')).toEqual([['IELTS', 7], ['TOEFL_IBT', 94], ['PTE', 65]])
  expect(centralRead(t).defaults.postgraduate[0].quote).toBe('| Postgraduate | 7.0 | 94 | 65 |')
})

test('the worker mode elr_central_read is read only and answers with the extractor version', () => {
  const at = WORKER.indexOf('if (mode === "elr_central_read") {')
  expect(at).toBeGreaterThan(0)
  const block = WORKER.slice(at, WORKER.indexOf('if (mode === "page_text") {', at))
  expect(block).toContain('reading: centralRead(text)')
  expect(block).toContain('extractor: ELR_CENTRAL_VERSION')
  expect(block).not.toMatch(/\.rpc\(|\.insert\(|\.update\(|\.upsert\(|openrouter|firecrawl/i)
})
