// Guards: F-AER.10 reusable reader fixes (Platform Admin mandate 12 Nov 2026 09:23: "Fix UWA's 8 missing quotation values, 41 incorrect band values and 2 identity conflicts at the reader level ... Continue repairing UTS, CSU, Curtin, Wollongong and VU using reusable reader improvements")
// The cases are the production reads of 12 Nov 2026 (v0.72.1): each row keeps what the page prints and nothing else; a fix never invents a number or a country.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

async function entry() {
  const out = path.join(os.tmpdir(), `entry-f10-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/entry.ts', '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`])
  return import(out)
}
const row = (x) => ({ country_code: 'CN', country_name: 'China', study_level: null, qualification_name: 'Year 12', min_grade: null, min_value: null, grade_scale: 'none',
  benchmark_band: null, course_name: null, conditions: {}, confidence: 1, quote: '', ...x })

test('a heading + cell quote is proven by its parts, in order and close together; parts far apart or out of order are not', async () => {
  const e = await entry()
  // Charles Sturt: the country is an accordion heading, the cell follows after other text
  const page = 'Nepal\nShow details\nEntry Requirements\nHigher Secondary Education Certificate with a grade average of 65%\nSri Lanka\nEntry Requirements\nGCE A Levels'
  const q = 'Nepal Entry Requirements Higher Secondary Education Certificate with a grade average of 65%'
  const r = row({ country_code: 'NP', qualification_name: 'Higher Secondary Education Certificate', min_grade: 'grade average of 65%', min_value: 65, grade_scale: 'percentage', quote: q })
  expect(e.entryMatrixParsed({ rows: [r] }, page).dropped.map((d) => d.reason)).toEqual(['quote_not_on_page'])
  const ok = e.entryMatrixParsed({ rows: [r] }, page, [], { quoteParts: { window: 600 } })
  expect(ok.rows.length).toBe(1)
  expect(ok.rows[0].conditions.quote_proof).toBe('parts')
  // Federation: "COUNTRY: Uganda | Undergraduate Entry: ..." where COUNTRY and Undergraduate Entry are column headings printed on the page
  const fed = 'COUNTRY\nUndergraduate Entry\nUganda\nSuccessful completion of the Cambridge Overseas Higher School Certificate with minimum 3 passes in principal subjects'
  const fq = 'COUNTRY: Uganda | Undergraduate Entry: Successful completion of the Cambridge Overseas Higher School Certificate with minimum 3 passes in principal subjects'
  expect(e.entryMatrixParsed({ rows: [row({ country_code: 'UG', qualification_name: 'COHSC', min_grade: 'minimum 3 passes in principal subjects', quote: fq })] }, fed, [], { quoteParts: { window: 600 } }).rows.length).toBe(1)
  // parts out of order, or further apart than the window, prove nothing
  const far = 'Higher Secondary Education Certificate with a grade average of 65%\n' + 'x'.repeat(2000) + '\nNepal Entry Requirements'
  expect(e.entryMatrixParsed({ rows: [r] }, far, [], { quoteParts: { window: 600 } }).dropped.map((d) => d.reason)).toEqual(['quote_not_on_page'])
  const apart = 'Nepal\n' + 'y'.repeat(900) + '\nEntry Requirements Higher Secondary Education Certificate with a grade average of 65%'
  expect(e.entryMatrixParsed({ rows: [r] }, apart, [], { quoteParts: { window: 600 } }).dropped.map((d) => d.reason)).toEqual(['quote_not_on_page'])
})

test('a band given with its rank label keeps the printed number only; a band name is never cut (UWA)', async () => {
  const e = await entry()
  const W = ['ATAR', 'rank', 'selection rank', 'entrance rank']
  expect(e.entryBandNumber('ATAR equivalent: 98', W)).toBe('98')
  expect(e.entryBandNumber('ATAR 80', W)).toBe('80')
  expect(e.entryBandNumber('Rank / ATAR: 95', W)).toBe('95')
  expect(e.entryBandNumber('B2', W)).toBe('B2')
  expect(e.entryBandNumber('Band 3', W)).toBe('Band 3')
  expect(e.entryBandNumber('ATAR equivalent: 98', [])).toBe('ATAR equivalent: 98')
  const page = 'Indian School Certificate Average | ATAR Equivalent\n75 | 85'
  const r = row({ country_code: 'IN', qualification_name: 'Indian School Certificate (CISCE)', min_grade: '75', min_value: 75, grade_scale: 'percentage',
    benchmark_band: 'ATAR Equivalent: 85', quote: 'Indian School Certificate Average: 75 | ATAR Equivalent: 85' })
  const p = e.entryMatrixParsed({ rows: [r] }, page, [], { bandLabelWords: W, quoteParts: { window: 600 } })
  expect(p.rows.map((x) => x.benchmark_band)).toEqual(['85'])
})

test('a printed range keeps its lower bound, never an invented midpoint; a count with no scale keeps its printed grade only (UWA, Federation)', async () => {
  const e = await entry()
  const page = 'Gaokao score | ATAR\n488 to 491 | 65% | 70'
  const r = row({ qualification_name: 'Gaokao', min_grade: '488 to 491', min_value: 489.5, grade_scale: 'points', quote: '488 to 491 | 65% | 70' })
  expect(e.entryMatrixParsed({ rows: [r] }, page).dropped.map((d) => d.reason)).toEqual(['value_not_in_quote'])
  expect(e.entryMatrixParsed({ rows: [r] }, page, [], { rangeLower: true }).rows.map((x) => x.min_value)).toEqual([488])
  const up = 'Uganda: Cambridge Overseas Higher School Certificate with minimum 2 passes in principal subjects'
  const c = row({ country_code: 'UG', qualification_name: 'COHSC', min_grade: 'minimum 2 passes in principal subjects', min_value: 2, grade_scale: 'none', quote: up })
  expect(e.entryMatrixParsed({ rows: [c] }, up).dropped.map((d) => d.reason)).toEqual(['value_without_scale'])
  const kept = e.entryMatrixParsed({ rows: [c] }, up, [], { nullValue: true }).rows
  expect(kept.map((x) => [x.min_value, x.min_grade])).toEqual([[null, 'minimum 2 passes in principal subjects']])
})

test('a country\'s own framework names the country of a row that gives none, only when one framework is named (Wollongong AQF)', async () => {
  const e = await entry()
  const map = e.entryQualificationCountries(['AQF=AU', 'NCEA=NZ', 'bad'])
  expect(map).toEqual({ aqf: 'AU', ncea: 'NZ' })
  expect(e.entryQualificationCountry("AQF bachelor's degree", map)).toBe('AU')
  expect(e.entryQualificationCountry('AQF or NCEA', map)).toBe(null)
  expect(e.entryQualificationCountry('Bachelor degree', map)).toBe(null)
  const page = "AQF bachelor's degree | 50% | 50% | 60% | 65%"
  const r = row({ country_code: '', country_name: '', qualification_name: "AQF bachelor's degree", min_grade: '50%', min_value: 50, grade_scale: 'percentage', quote: page })
  expect(e.entryMatrixParsed({ rows: [r] }, page).dropped.map((d) => d.reason)).toEqual(['unknown_country'])
  const p = e.entryMatrixParsed({ rows: [r] }, page, [], { qualificationCountries: map })
  expect(p.rows.map((x) => [x.country_code, x.conditions.country_from_qualification])).toEqual([['AU', "AQF bachelor's degree"]])
})

test('every fix is a setting; the switches built for these cases are switched on with a reason; nothing is dropped', () => {
  const m = fs.readFileSync('supabase/migrations/20261113003100_cf247_aer_reader_fixes.sql', 'utf8')
  for (const k of ['reading.entry_quote_parts_on', 'reading.entry_quote_window_chars', 'reading.entry_band_label_words', 'reading.entry_qualification_countries']) expect(m).toContain(`'${k}'`)
  for (const k of ['reading.entry_range_lower_bound_on', 'reading.entry_subject_rows_on', 'reading.entry_value_null_on'])
    expect(m).toMatch(new RegExp(`reason = 'Platform Admin mandate 12 Nov 2026 09:23[^']*'\\n where toolset_key = 'pipeline' and key = '${k.replace(/\./g, '\\.')}'`))
  expect(m).toContain("('GCE_O', 'GCE Ordinary Level'")
  expect(m).toContain("('BTEC_NED', 'Pearson BTEC'")
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(ix).toContain('const WORKER = "coverage-sweep-worker-v0.74.0"')
  expect(ix).toMatch(/Number\(ws\["reading\.entry_quote_parts_on"\]\) >= 1 \? \{ quoteParts: \{ window: Number\(ws\["reading\.entry_quote_window_chars"\]\)/)
  expect(ix).toContain('qualificationCountries: entryQualificationCountries(ws["reading.entry_qualification_countries"])')
})
