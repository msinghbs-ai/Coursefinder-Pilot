// Guards: CF-247 Track C, entry requirements step A (s112): the matrix reader's admission rules, tested on the Part 1 quotes byte-checked against the raw pages on 25 Oct 2026…
// CF-247 Track C, entry requirements step A (s112): the matrix reader's admission rules, tested on the Part 1 quotes byte-checked
// against the raw pages on 25 Oct 2026 (tests/fixtures/entry-matrix/part1-quotes.json): 17 exact, 6 after whitespace, 2 corrected
// (EIT: no final full stop; NMIT: first letter split in markup), 7 not reachable (not pass/fail cases).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryMatrixParsed, entrySlices, entryMatrixRequest, ENTRY_SCHEMA } from '../../supabase/functions/coverage-sweep/entry.ts'
const fx = JSON.parse(fs.readFileSync('tests/fixtures/entry-matrix/part1-quotes.json', 'utf8')).quotes
const central = fs.readFileSync('supabase/functions/coverage-sweep/central.ts', 'utf8')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const row = (q, x = {}) => ({ country_code: 'IN', country_name: 'India', study_level: null, qualification_name: 'Qualification', min_grade: null, min_value: null,
  grade_scale: 'none', benchmark_band: null, course_name: null, conditions: { subject_minimums: [], best_n: null, alternatives: [] }, confidence: 0.9, quote: q, ...x })

test('byte-check results are the test data: 25 verified, 7 unverified, 19 HTML providers for step A', () => {
  expect(fx.length).toBe(32)
  expect(fx.filter(f => f.verified).length).toBe(25)
  expect(fx.filter(f => f.byte_check === 'corrected').map(f => f.id).sort()).toEqual(['NZ-EIT', 'NZ-NMIT'])
  expect(fx.filter(f => f.html_step_a).length).toBe(19)
  expect(fx.find(f => f.id === 'NZ-EIT').quote.endsWith('International Prospectus')).toBe(true)
})

test('every verified quote is admitted against its page text (markup splits and whitespace tolerated)', () => {
  // ANU's sample was a bare table cell ("70 10.5"): too short to prove anything, so the reader asks for the whole row
  expect(entryMatrixParsed({ rows: [row(fx.find(f => f.id === 'AU-ANU').quote)] }, fx.find(f => f.id === 'AU-ANU').page_text).dropped[0].reason).toBe('quote_too_short')
  for (const f of fx.filter(f => f.verified && f.id !== 'AU-ANU')) {
    const page = `# Entry requirements\n\nIntro text.\n\n${f.page_text}\n\nFooter.`
    const r = entryMatrixParsed({ rows: [row(f.quote)] }, page)
    expect(r.rows.length, f.id).toBe(1)
    const bad = entryMatrixParsed({ rows: [row(f.quote + ' plus words not on the page')] }, page)
    expect(bad.dropped[0]?.reason, f.id).toBe('quote_not_on_page')
  }
  const nmit = fx.find(f => f.id === 'NZ-NMIT')
  expect(nmit.page_text.startsWith('S enior')).toBe(true)
  expect(entryMatrixParsed({ rows: [row(nmit.quote, { min_grade: 'B average', grade_scale: 'letter' })] }, nmit.page_text).rows.length).toBe(1)
})

test('a number needs a scale and must be in the quote; a grade must be in the quote; English tests are not matrix rows', () => {
  const wk = fx.find(f => f.id === 'NZ-WAIKATO'), page = wk.page_text
  expect(entryMatrixParsed({ rows: [row(wk.quote, { min_grade: '75%', min_value: 75, grade_scale: 'percentage' })] }, page).rows.length).toBe(1)
  expect(entryMatrixParsed({ rows: [row(wk.quote, { min_value: 75, grade_scale: 'none' })] }, page).dropped[0].reason).toBe('value_without_scale')
  expect(entryMatrixParsed({ rows: [row(wk.quote, { min_value: 80, grade_scale: 'percentage' })] }, page).dropped[0].reason).toBe('value_not_in_quote')
  expect(entryMatrixParsed({ rows: [row(wk.quote, { min_grade: '85%', grade_scale: 'percentage' })] }, page).dropped[0].reason).toBe('grade_not_in_quote')
  expect(entryMatrixParsed({ rows: [row(wk.quote, { country_code: 'India' })] }, page).dropped[0].reason).toBe('unknown_country')
  const ielts = 'IELTS Academic 6.0 overall with no band below 5.5'
  expect(entryMatrixParsed({ rows: [row(ielts, { qualification_name: 'IELTS Academic' })] }, ielts).dropped[0].reason).toBe('english_test_row')
  // a case-by-case row (SIT China "High school graduates") is kept with no minimum: rendered as case by case, never as a pass (decision 10)
  const sit = fx.find(f => f.id === 'NZ-SIT')
  const k = entryMatrixParsed({ rows: [row(sit.quote, { country_code: 'CN' })] }, sit.page_text).rows[0]
  expect([k.min_grade, k.min_value, k.grade_scale]).toEqual([null, null, 'none'])
})

test('large tables are read in slices with the header repeated; the request is pinned and strict', () => {
  const head = '| Country | Qualification | Minimum |\n|---|---|---|'
  const body = Array.from({ length: 120 }, (_, i) => `| C${i} | Q${i} | ${50 + (i % 40)}% |`).join('\n')
  const s = entrySlices(`Intro\n${head}\n${body}`, 50)
  expect(s.length).toBe(3)
  expect(s[1].startsWith(head)).toBe(true)
  expect(s[2].startsWith(head)).toBe(true)
  const req = entryMatrixRequest('openai/gpt-4.1-mini', { provider: 'P', url: 'https://x', text: 't' })
  expect(req.provider).toEqual({ require_parameters: true })
  expect(req.temperature).toBe(0)
  expect(req.response_format.json_schema.strict).toBe(true)
  expect(ENTRY_SCHEMA.properties.rows.items.required).toContain('quote')
})

test('discovery page type and worker mode', () => {
  expect(central).toContain('"intake_calendar" | "fee_schedule" | "english_policy" | "entry_requirements"')
  expect(central).toContain('k !== "entry_requirements" && !found.some') // no extra targeted map: no new central_find spend
  expect(w).toContain('if (mode === "entry_ai") {')
  expect(w).toContain('if (d1.status === "robots_disallowed") { await frec({ p_status: "robots_disallowed", p_http: http });')
  expect(w).toContain('if (d?.model && !String(d.model).startsWith(it.model)) throw Error(`returned model ${d.model}, not ${it.model}`);  // pinned')
})
