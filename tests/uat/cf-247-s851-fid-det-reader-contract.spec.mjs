// Guards: S851 deterministic fee, intake and deadline reader (Platform Admin 20 Nov 2026 15:11 AEDT, chat S1-Fees-Intakes): a pure reader with no model, fetch or write; every reading's quote is on the page text; international fees only, with the country currency and a stated basis; calendar months only as intakes; a closing date in the same sentence as its closing words.
// CF-247 s851. Module supabase/functions/coverage-sweep/fid-det-reader.ts, worker mode fid_det_read.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { fidRead, fidUnits, FID_DET_VERSION } from '../../supabase/functions/coverage-sweep/fid-det-reader.ts'

const SRC = fs.readFileSync('supabase/functions/coverage-sweep/fid-det-reader.ts', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const of = (t, cc, k) => fidRead(t, cc).readings.filter((r) => r.kind === k)

test('the module is pure and versioned; the worker mode reads only', () => {
  expect(SRC).not.toMatch(/\bfetch\s*\(|openrouter|firecrawl|Deno\.|supabase|\.rpc\(|\.storage\b|XMLHttpRequest/i)
  expect(FID_DET_VERSION).toBe('fid-det-v1.0')
  expect(IX).toContain('import { fidRead, FID_DET_VERSION } from "./fid-det-reader.ts";')
  expect(IX).toContain('if (mode === "fid_det_read") {')
  const block = IX.slice(IX.indexOf('if (mode === "fid_det_read") {'), IX.indexOf('if (mode === "page_text") {'))
  expect(block).not.toMatch(/\.rpc\(|\.from\("[a-z_]+"\)\.(insert|update|upsert|delete)|openrouter|firecrawl/i)
  expect(block).toContain('.slice(0, 40);  // fixed: bound on one call')
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.42"')  // v1.0.38 from s1037  // v1.0.37 from s1029  // v1.0.36 from s1017  // v1.0.35 from s992
  expect(IX).toContain('// v1.0.34 (20 Nov 2026, CF-247 s851')
})

test('international fee: amount, country currency, basis and the year beside the amount', () => {
  const t = ['International students: A$48,500 per year (2026 indicative annual tuition fee).', 'Domestic students: Commonwealth supported place, $4,500 per year.', 'Application fee: $150.', 'Living costs approximately $29,710 per year.'].join('\n')
  const f = of(t, 'AU', 'fee')
  expect(f).toHaveLength(1)
  expect(f[0]).toMatchObject({ amount: 48500, currency: 'AUD', basis: 'annual', fee_year: 2026 })
  expect(of('Tuition: International students pay CAD $36,000 per year. Application deadline: March 1, 2026.', 'CA', 'fee')[0]).toMatchObject({ amount: 36000, currency: 'CAD', basis: 'annual', fee_year: null })
  expect(of('International tuition: NZ$1,250 per credit.', 'NZ', 'fee')[0]).toMatchObject({ amount: 1250, currency: 'NZD', basis: 'per_unit' })
  expect(of('International students: total course fee $96,000 for the whole course.', 'AU', 'fee')[0]).toMatchObject({ basis: 'course_total' })
  expect(of('International tuition fee: $40,000.', 'AU', 'fee')).toHaveLength(0)   // no basis: not read
})

test('fees: the latest stated year wins; two figures of one basis with no year are ambiguous', () => {
  const nz = 'International tuition fees 2026: NZ$45,000 per year\nInternational tuition fees 2025: NZ$43,000 per year'
  expect(of(nz, 'NZ', 'fee')).toEqual([expect.objectContaining({ amount: 45000, fee_year: 2026 })])
  const two = 'International students (Bachelor) tuition fee: $40,000 per year\nInternational students (Honours) tuition fee: $42,000 per year'
  const r = fidRead(two, 'AU')
  expect(r.readings.filter((x) => x.kind === 'fee')).toHaveLength(0)
  expect(r.ambiguous.join(' ')).toContain('different annual figures')
})

test('intakes: calendar months after a start word; dates and calendars are not intakes; study periods are labels', () => {
  expect(of('Intakes: February and July', 'AU', 'intake')[0]).toMatchObject({ months: ['February', 'July'] })
  expect(of('Program start: September, January.', 'CA', 'intake')[0]).toMatchObject({ months: ['September', 'January'] })
  expect(of('Semester 1 starts 23 February 2026.', 'AU', 'intake')[0]).toMatchObject({ months: [], labels: ['Semester 1'] })
  expect(of('Applications close 30 November 2025 for the February intake.', 'AU', 'intake')).toHaveLength(0)
  expect(of('You may start your application today.', 'AU', 'intake')).toHaveLength(0)
})

test('deadlines: one full date in the closing sentence, an intake hint, rolling statements without a date', () => {
  expect(of('Applications close 30 November 2025 for the February intake.', 'AU', 'deadline')[0]).toMatchObject({ date: '2025-11-30', intake_hint: 'February intake', rolling: false })
  expect(of('Application deadline: March 1, 2026.', 'CA', 'deadline')[0]).toMatchObject({ date: '2026-03-01' })
  expect(of('We accept applications on a rolling basis for admission.', 'NZ', 'deadline')[0]).toMatchObject({ date: null, rolling: true })
  const two = fidRead('Applications close 1 March 2026 or 1 June 2026.', 'AU')
  expect(two.readings.filter((x) => x.kind === 'deadline')).toHaveLength(0)
  expect(two.ambiguous[0]).toContain('2 dates in one line')
})

test('every quote is on the page text word for word', () => {
  const t = 'Fees\nInternational students: A$48,500 per year.\nIntakes: February and July\nApplications close 30 November 2025.'
  const flat = t.replace(/\s+/g, ' ')
  for (const r of fidRead(t, 'AU').readings) expect(flat).toContain(r.quote)
  expect(fidUnits('A. B\nLine two. Line three.')).toEqual(['A. B', 'Line two.', 'Line three.'])
})
