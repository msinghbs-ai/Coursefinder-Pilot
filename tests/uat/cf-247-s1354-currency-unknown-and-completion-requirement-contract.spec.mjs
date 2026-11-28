// Guards: SS-Programme-Control PC-20261128-1729-DELIVERY-VERIFY (28 Nov 2026): no provider-default currency on contradictory or unknown evidence; a completion requirement is not an entry requirement
// CF-247 s1354. supabase/functions/coverage-sweep/extract.ts (currencyFor, fee), adapters.ts, scholarship.ts (scholarshipValue), course-entry.ts
// (entryCompletionRequirement, courseEntrySliceRows), index.ts (worker v1.0.64). GB and IE are compatibility fixtures only: no provider there is read.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { currencyFor, fee } from '../../supabase/functions/coverage-sweep/extract.ts'
import { scholarshipValue } from '../../supabase/functions/coverage-sweep/scholarship.ts'
import { courseEntrySliceRows, entryCompletionRequirement } from '../../supabase/functions/coverage-sweep/course-entry.ts'

const AU_PAGE = 'International students. Indicative annual tuition fee 2027: A$42,500 per year. CRICOS 012345A.'

test('the fee reader has a currency only for AU, NZ and CA; any other or unknown country reads no amount', () => {
  expect(currencyFor('AU')).toBe('AUD')
  expect(currencyFor('NZ')).toBe('NZD')
  expect(currencyFor('CA')).toBe('CAD')
  expect(currencyFor('au')).toBe('AUD')
  for (const c of ['GB', 'IE', 'US', '', null, undefined]) expect(currencyFor(c)).toBeNull()
  for (const c of ['GB', 'IE', null]) {
    const r = fee(AU_PAGE, currencyFor(c))
    expect(r).toMatchObject({ value: null, safe: false, rejection_reason: 'currency_unknown', currency: null })
  }
  // AU unchanged
  expect(fee(AU_PAGE, currencyFor('AU'))).toMatchObject({ value: 42500, safe: true })
  expect(fee(AU_PAGE)).toMatchObject({ value: 42500, safe: true })
})

test('a scholarship with no known currency, or a "$" amount for a non-dollar provider, is never a fixed AUD value', () => {
  expect(scholarshipValue('A one-off award of $10,000 paid in the first year.', '', null)).toMatchObject({ type: 'ambiguous', foreign_currency: true, currency_unknown: true })
  expect(scholarshipValue('The ASEAN $10,000 Award is worth $10,000.', 'ASEAN $10,000 Award', null)?.type).not.toBe('fixed_amount')
  expect(scholarshipValue('A one-off award of $10,000 paid in the first year.', '', 'GBP')).toMatchObject({ type: 'ambiguous', foreign_currency: true })
  expect(scholarshipValue('A one-off award of $10,000 paid in the first year.', '', 'EUR')).toMatchObject({ type: 'ambiguous', foreign_currency: true })
  // percentages need no currency; AU, NZ and CA unchanged
  expect(scholarshipValue('Recipients receive 20% off tuition fees each year.', '', null)).toMatchObject({ type: 'percentage', percentage: 20 })
  expect(scholarshipValue('A one-off award of $10,000 paid in the first year.')).toMatchObject({ type: 'fixed_amount', amount: 10000, currency: 'AUD' })
  expect(scholarshipValue('The award is valued at NZ$5,000 per year.', '', 'NZD')).toMatchObject({ type: 'fixed_amount', amount: 5000, currency: 'NZD' })
  expect(scholarshipValue('The award is valued at C$8,000 per year.', '', 'CAD')).toMatchObject({ type: 'fixed_amount', amount: 8000, currency: 'CAD' })
})

test('the worker never substitutes AUD for a missing scholarship or adapter currency', () => {
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(ix).not.toContain('it.currency || "AUD"')
  expect(ix.split('it.currency || null)').length - 1).toBe(3)
  expect(ix).toContain('const WORKER = "coverage-sweep-worker-v1.0.66"')
  const ad = fs.readFileSync('supabase/functions/coverage-sweep/adapters.ts', 'utf8')
  expect(ad).toContain('pFee <= 500000 && currencyFor(course.country) ? {')
})

const MURDOCH = 'All students will undertake at least 450 hours of approved work experience, plus complete a report outlining the experience gained, in order to complete the requirements of the degree.'

test('a condition of completing the course is dropped as completion_requirement (negative fixture, Murdoch 030196A)', () => {
  expect(entryCompletionRequirement(MURDOCH, 'Work experience')).toBe(true)
  expect(entryCompletionRequirement('Students must complete 80 days of professional placement as part of the degree.')).toBe(true)
  expect(entryCompletionRequirement('Students undertake a 12-week industry placement to graduate.')).toBe(true)
  // entry conditions stay
  for (const q of ['Applicants must have at least two years of relevant work experience.', 'A folio is required as part of your application.',
    'Applicants will be selected on the basis of an interview, which forms part of the course selection process.',
    'International Baccalaureate (IB) Diploma score of 27 or higher', 'Selection rank of 80, which can be met by: ATAR of 80 (adjusted or unadjusted)',
    'One successful Semester study at AQF 7', 'You must pass a police check before you start your first placement during the course.'])
    expect(entryCompletionRequirement(q)).toBe(false)
  const page = `Admission requirements. International Baccalaureate (IB) Diploma score of 27 or higher. Work experience. ${MURDOCH}`
  const out = courseEntrySliceRows({ rows: [
    { kind: 'minimum_grade', audience: 'international', description: 'IB Diploma 27', quote: 'International Baccalaureate (IB) Diploma score of 27 or higher', min_entry_score: null, min_entry_score_basis: null, benchmark_band: null, min_grade: '27', confidence: 0.9 },
    { kind: 'portfolio_interview', audience: 'all', description: 'Work experience and report', quote: MURDOCH, min_entry_score: null, min_entry_score_basis: null, benchmark_band: null, min_grade: null, confidence: 0.8 },
  ] }, page)
  expect(out.rows.map((r) => r.kind)).toEqual(['minimum_grade'])
  expect(out.dropped).toEqual([{ reason: 'completion_requirement', kind: 'portfolio_interview', quote: MURDOCH }])
})
