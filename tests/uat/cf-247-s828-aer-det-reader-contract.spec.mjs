// Guards: S828, S829, S832, S834 and s1009 (Platform Admin 23 Nov 2026 15:52 AEDT: no maximum read as a minimum; the quote carries its value; no overall average taken from one subject's mark) deterministic academic entry reader (Platform Admin 20 Nov 2026 10:51 AEDT Decision 2 and 15:08 AEDT: AER and English are separate; Decision 276 kept): a pure reader with no model, fetch or write; every reading's quote is on the page text word for word; no English test is ever read here.
// CF-247 S828 (reader), S829 (precision), S832 (collapsed-row guard) and S834 (academic only, aer-det-v1.3). Module supabase/functions/coverage-sweep/aer-det-reader.ts.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { detRead, detUnits, detCollapsed, detUncovered, AER_DET_VERSION } from '../../supabase/functions/coverage-sweep/aer-det-reader.ts'

const SRC = fs.readFileSync('supabase/functions/coverage-sweep/aer-det-reader.ts', 'utf8')
const keys = (t) => detRead(t).map((r) => r.key)
const one = (t, k) => detRead(t).find((r) => r.key === k)

test('the module is pure: no model, fetch, storage, database or environment access', () => {
  expect(SRC).not.toMatch(/\bfetch\s*\(|openrouter|firecrawl|Deno\.|supabase|\.rpc\(|\.storage\b|XMLHttpRequest/i)
  expect(AER_DET_VERSION).toBe('aer-det-v1.4')
})

test('academic only: no English test is read, whatever the wording, and an academic value is never taken from an English sentence', () => {
  const t = [
    'IELTS Academic overall score of 6.5 with no individual band below 6.0.',
    'TOEFL iBT: minimum score of 79.', 'PTE Academic overall 58.', 'OET: grade B in each component.', 'CELPIP General: level 7.', 'Cambridge C1 Advanced: 176 overall.',
    'International English Language Testing System 6.5 and Pearson Test of English 58.',
  ].join('\n')
  expect(keys(t)).toEqual([])
  for (const x of ['ielts', 'toefl_ibt', 'pte', 'oet', 'celpip', 'cambridge']) expect(SRC).not.toMatch(new RegExp('key: "' + x + '"'))
  expect(keys('Year 12 with an IELTS 6.5 overall')).toEqual([])
  expect(keys('IELTS 5.5 Academic (no lower than 5.0 in any subtest). Applicants need NCEA Level 3 and University Entrance.')).not.toContain('ncea_l3')
})

test('academic entry: ATAR, Year 12, NCEA Level 3, University Entrance, Canadian average, bachelor GPA', () => {
  const t = [
    'The minimum ATAR for this course is 70.',
    'Successful completion of Year 12 with a study score of at least 25 in English is required.',
    'NCEA Level 3 with 14 credits in each of three approved subjects.',
    'University Entrance requires 14 credits in each of three subjects and 10 literacy credits.',
    'Applicants need an Ontario Secondary School Diploma with an average of 75%.',
    'A bachelor degree with a GPA of 5.0 out of 7 is required.',
  ].join('\n')
  expect(one(t, 'atar').value).toEqual({ atar: 70, basis: 'ATAR' })
  expect(one(t, 'year12').value).toEqual({ value: 25, basis: 'score' })
  expect(one(t, 'ncea_l3').value).toEqual({ credits: 14, basis: 'credits' })
  expect(one(t, 'university_entrance').value).toEqual({ credits: 14, basis: 'credits' })
  expect(one(t, 'ca_secondary').value).toEqual({ average_percent: 75 })
  expect(one(t, 'bachelor_gpa').value).toEqual({ gpa: 5, scale: 7 })
})

test('s834 new rules: IB Diploma points, A-level grades and an Indian board average, each with its own quote', () => {
  const t = [
    'International Baccalaureate Diploma with a minimum of 30 points including three higher level subjects.',
    'GCE A-levels with grades AAB, including Mathematics.',
    'Applicants with CBSE or ISC must have an average of 75% in their Year 12 results.',
  ].join('\n')
  expect(one(t, 'ib').value).toEqual({ points: 30, basis: 'points' })
  expect(one(t, 'alevel').value).toEqual({ grades: 'AAB' })
  expect(one(t, 'india_board').value).toEqual({ average_percent: 75 })
  for (const x of detRead(t)) expect(t.includes(x.quote)).toBe(true)
  expect(keys('IB Diploma accepted.')).toEqual([])
  expect(keys('A-levels or equivalent are accepted.')).not.toContain('alevel')
})

test('s834 the credit count is never the level number: "42 level 3 credits" reads 42, "level 3 credits" alone gives nothing', () => {
  expect(one('University Entrance approved subjects You must also gain a total of 42 level 3 credits which are from three subjects', 'university_entrance').value.credits).toBe(42)
  expect(keys('University Entrance requires level 3 credits in approved subjects')).not.toContain('university_entrance')
  expect(one('NCEA Level 3 comprised of 60 credits at NCEA Level 3 or above and 20 credits at NCEA Level 2', 'ncea_l3').value.credits).toBe(60)
})

test('s834 Year 12 needs a stated threshold: boilerplate, units and a bare mention give nothing; a score, mark, percentage or a grade with "or higher" gives a value', () => {
  expect(keys('Prerequisites for admission may be specified in terms of levels of achievement in particular Year 12 subjects.')).toEqual([])
  expect(keys('Completed an Australian Year 12 qualification or equivalent.')).toEqual([])
  expect(keys('VCE Units 3 and 4 in English')).toEqual([])
  expect(one('VCE or equivalent score of at least 30 in English (EAL)', 'year12').value.value).toBe(30)
  expect(one('Year 12 with a minimum of 65% in Mathematics', 'year12').value.value).toBe(65)
  expect(one('Year 12 English at grade C or higher', 'year12').value.grade).toBe('C')
})

test('no reading without a plausible value: out-of-range numbers, years, fees and navigation words give nothing', () => {
  const t = ['ATAR 2026 results are released in December.', 'ATAR information evening, fee $450.', 'Apply now for Semester 1, 2027.', 'NCEA Level 3 is accepted.'].join('\n')
  expect(keys(t)).toEqual([])
})

test('every quote is a substring of the page text, unchanged, and no reading is duplicated', () => {
  const t = 'Entry requirements\n\nYou need a minimum ATAR of 75. You also need a minimum ATAR of 75.\nYear 12 with a score of 60 is required.'
  const r = detRead(t)
  expect(r.length).toBeGreaterThan(0)
  for (const x of r) expect(t.includes(x.quote)).toBe(true)
  expect(new Set(r.map((x) => x.key + '|' + x.quote)).size).toBe(r.length)
  expect(detUnits('a\n\n  b  \n')).toEqual(['a', 'b'])
})

test('a long line is cut at sentence ends and never inside a score', () => {
  const long = 'Overview. ' + 'Lorem words here. '.repeat(40) + 'A minimum ATAR of 70.5 is required. ' + 'More words follow. '.repeat(20)
  const r = detRead(long)
  expect(r.map((x) => x.key)).toEqual(['atar'])
  expect(r[0].quote.length).toBeLessThanOrEqual(320)
  expect(long.includes(r[0].quote)).toBe(true)
  expect(r[0].value.atar).toBe(70.5)
})

test('s832 collapsed rows (kept in v1.3): a flattened table line is skipped, and a value is never taken across another qualification', () => {
  const two = 'Bachelor of Business Year 12 with a score of 60 Bachelor of Commerce Year 12 with a score of 70'
  expect(detCollapsed(two)).toBe(true)
  expect(detRead(two)).toEqual([])
  const tab = 'ATAR 70 | NCEA Level 3 | University Entrance'
  expect(detCollapsed(tab)).toBe(true)
  expect(detRead(tab)).toEqual([])
  expect(keys('Ontario Secondary School Diploma with NCUK 112 points; foundation average 75%')).not.toContain('ca_secondary')
  const r = one('NCEA Level 3 with 60 credits at Level 3 and University Entrance.', 'ncea_l3')
  expect(r.quote).not.toMatch(/University Entrance/)
})

test('s834 other requirements: a prerequisite, portfolio or interview line the reader does not read is carried as uncovered, never an English line', () => {
  const t = 'A minimum ATAR of 70 is required.\nPrerequisite: Mathematics Methods units 3 and 4.\nApplicants must submit a portfolio.\nIELTS 6.5 overall; no interview needed for English.'
  const u = detUncovered(t, detRead(t))
  expect(u).toEqual(['Prerequisite: Mathematics Methods units 3 and 4.', 'Applicants must submit a portfolio.'])
  expect(detUncovered('A minimum ATAR of 70 is required.', detRead('A minimum ATAR of 70 is required.'))).toEqual([])
})

test('s1009 (aer-det-v1.4): a maximum or "up to" figure is never a minimum; an overall average is not taken from one subject\'s mark; the quote carries the value', () => {
  expect(keys('*Up to a maximum international ATAR of 99.95 applies to this offer.')).toEqual([])
  expect(keys('Applicants may receive up to 5 ATAR adjustment points; the maximum ATAR is 99.95.')).toEqual([])
  expect(keys('Senior School Certificate awarded by CBSE Senior Secondary 65% in English.')).not.toContain('india_board')
  expect(one('Guaranteed ATAR: 57.70', 'atar').value.atar).toBe(57.7)
  expect(one('CBSE Senior School Certificate with an overall average of 65%.', 'india_board').value.average_percent).toBe(65)
  expect(one('International Baccalaureate Diploma with a minimum of 28 points.', 'ib').value.points).toBe(28)
  expect(one('International Baccalaureate Diploma with a minimum of 28 points.', 'ib').quote).toContain('28 points')  // v1.3 cut this quote to "International"
  for (const r of detRead('The minimum ATAR for this course is 70.\nInternational Baccalaureate Diploma with a minimum of 28 points.')) {
    const v = Object.entries(r.value).filter(([k, x]) => k !== 'basis' && (typeof x === 'number' || typeof x === 'string')).map(([, x]) => String(x))
    expect(v.some((x) => r.quote.includes(x))).toBe(true)
  }
})
