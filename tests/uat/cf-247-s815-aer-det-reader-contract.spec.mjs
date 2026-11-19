// Guards: S815 deterministic English and academic entry reader (Platform Admin 20 Nov 2026 10:51 AEDT, Decision 2; Decision 276 kept: shadow readings only, AER v1 frozen, every gate unchanged): a pure reader with no model, fetch or write; every reading's quote is on the page text word for word.
// CF-247 S815. Module supabase/functions/coverage-sweep/aer-det-reader.ts.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { detRead, detUnits, AER_DET_VERSION } from '../../supabase/functions/coverage-sweep/aer-det-reader.ts'

const SRC = fs.readFileSync('supabase/functions/coverage-sweep/aer-det-reader.ts', 'utf8')
const keys = (t) => detRead(t).map((r) => r.key)
const one = (t, k) => detRead(t).find((r) => r.key === k)

test('the module is pure: no model, fetch, storage, database or environment access', () => {
  expect(SRC).not.toMatch(/\bfetch\s*\(|openrouter|firecrawl|Deno\.|supabase|\.rpc\(|\.storage\b|XMLHttpRequest/i)
  expect(AER_DET_VERSION).toBe('aer-det-v1.0')
})

test('English tests: IELTS with band minimum, TOEFL iBT, PTE, OET, CELPIP and Cambridge', () => {
  const t = [
    'English language requirements',
    'IELTS Academic overall score of 6.5 with no individual band below 6.0.',
    'TOEFL iBT: minimum score of 79, with a writing score of 21.',
    'PTE Academic overall 58, no communicative skill below 50.',
    'OET: grade B in each component.',
    'CELPIP General: level 7 in each component.',
    'Cambridge C1 Advanced: 176 overall.',
  ].join('\n')
  expect(one(t, 'ielts').value).toEqual({ overall: 6.5, band_min: 6 })
  expect(one(t, 'toefl_ibt').value).toEqual({ overall: 79 })
  expect(one(t, 'pte').value).toEqual({ overall: 58 })
  expect(one(t, 'oet').value).toEqual({ grade: 'B' })
  expect(one(t, 'celpip').value).toEqual({ level: 7 })
  expect(one(t, 'cambridge').value).toEqual({ score: 176 })
  expect(one(t, 'ielts').strength).toBe('stated_minimum')
})

test('academic entry: ATAR, Year 12, NCEA Level 3, University Entrance, Canadian average, bachelor GPA', () => {
  const t = [
    'The minimum ATAR for this course is 70.',
    'Successful completion of Year 12 or equivalent is required.',
    'NCEA Level 3 with 14 credits in each of three approved subjects.',
    'University Entrance requires NCEA Level 3 literacy and numeracy.',
    'Applicants need an Ontario Secondary School Diploma with an average of 75%.',
    'A bachelor degree with a GPA of 5.0 out of 7 is required.',
  ].join('\n')
  expect(one(t, 'atar').value).toEqual({ atar: 70 })
  expect(one(t, 'year12').value).toEqual({ stated: true })
  expect(one(t, 'ncea_l3').value).toEqual({ credits: 14 })
  expect(one(t, 'university_entrance').value).toEqual({ stated: true })
  expect(one(t, 'ca_secondary').value).toEqual({ average_percent: 75 })
  expect(one(t, 'bachelor_gpa').value).toEqual({ gpa: 5, scale: 7 })
})

test('no reading without a plausible value: out-of-range numbers, years, fees and navigation words give nothing', () => {
  const t = [
    'IELTS preparation courses start in 2026.',
    'IELTS 12.5 is not a score.',
    'TOEFL scores are sent to the university by the test centre.',
    'PTE 25 is below the scale.',
    'ATAR 2026 results are released in December.',
    'ATAR information evening, fee $450.',
    'Apply now for Semester 1, 2027.',
  ].join('\n')
  expect(keys(t)).toEqual([])
})

test('every quote is a substring of the page text, unchanged, and no reading is duplicated', () => {
  const t = 'Entry requirements\n\nYou need IELTS 6.5 overall (no band below 6.0). You also need a minimum ATAR of 75. IELTS 6.5 overall (no band below 6.0).\nYear 12 or equivalent is required.'
  const r = detRead(t)
  expect(r.length).toBeGreaterThan(0)
  for (const x of r) expect(t.includes(x.quote)).toBe(true)
  expect(new Set(r.map((x) => x.key + '|' + x.quote)).size).toBe(r.length)
  expect(detUnits('a\n\n  b  \n')).toEqual(['a', 'b'])
})

test('a long line is cut at sentence ends and never inside a score', () => {
  const long = 'Overview. ' + 'Lorem words here. '.repeat(40) + 'IELTS overall 7.0 is required. ' + 'More words follow. '.repeat(20)
  const r = detRead(long)
  expect(r.map((x) => x.key)).toEqual(['ielts'])
  expect(r[0].quote.length).toBeLessThanOrEqual(320)
  expect(long.includes(r[0].quote)).toBe(true)
  expect(r[0].value.overall).toBe(7)
})
