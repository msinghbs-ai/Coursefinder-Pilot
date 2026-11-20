// Guards: CF-247 s841 (session S1-ELR, Platform Admin 20 Nov 2026 15:10 and 15:21 AEDT): elr-det-v1.0 is a pure, deterministic English language requirement reader (IELTS, TOEFL iBT, PTE Academic, OET, CELPIP, Cambridge C1/C2) with no model, fetch or write; every reading's quote is on the page text word for word; flattened table lines are skipped, never cross-assigned; academic entry is not read
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { elrRead, elrCollapsed, elrAgree, ELR_DET_VERSION } from '../../supabase/functions/coverage-sweep/elr-det-reader.ts'

const SRC = fs.readFileSync('supabase/functions/coverage-sweep/elr-det-reader.ts', 'utf8')
const WORKER = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const one = (t, k) => elrRead(t).find((r) => r.key === k)
const all4 = (v) => ({ reading: v, writing: v, speaking: v, listening: v })

test('the module is pure and English only: no model, fetch, storage, database or environment access, no academic entry keys', () => {
  expect(SRC).not.toMatch(/\bfetch\s*\(|openrouter|firecrawl|Deno\.|supabase|\.rpc\(|\.storage\b|XMLHttpRequest/i)
  expect(ELR_DET_VERSION).toBe('elr-det-v1.0')
  expect(SRC).not.toMatch(/"(atar|year12|ncea_l3|university_entrance|ca_secondary|bachelor_gpa)"/)
})

test('IELTS: overall with a band floor, and named skill minimums', () => {
  expect(one('IELTS Academic overall score of 6.5 with no individual band below 6.0.', 'ielts').value).toEqual({ overall: 6.5, components: all4(6) })
  expect(one('International English Language Testing System (IELTS): 7.0 overall, Reading 6.5, Writing 6.5, Speaking 7.0, Listening 7.0', 'ielts').value)
    .toEqual({ overall: 7, components: { reading: 6.5, writing: 6.5, speaking: 7, listening: 7 } })
  expect(one('Duolingo English Test 115, LANGUAGECERT 70, IELTS 6.5 overall (no band less than 6.0)', 'ielts').value).toEqual({ overall: 6.5, components: all4(6) })
})

test('TOEFL iBT, PTE Academic (decimals kept), OET, CELPIP and Cambridge C1 and C2, by acronym or spelled-out name', () => {
  expect(one('TOEFL iBT: minimum total score of 79, with a writing score of 21 and reading 13.', 'toefl_ibt').value).toEqual({ overall: 79, components: { reading: 13, writing: 21 } })
  expect(one('Test of English as a Foreign Language internet-based test (TOEFL iBT) 90 overall, minimum 20 in each section', 'toefl_ibt').value).toEqual({ overall: 90, components: all4(20) })
  expect(one('PTE Academic overall 58.5, no communicative skill below 50.', 'pte').value).toEqual({ overall: 58.5, components: all4(50) })
  expect(one('Pearson Test of English (Academic): 65 with no score below 58', 'pte').value).toEqual({ overall: 65, components: all4(58) })
  expect(one('OET: grade B in each component.', 'oet').value).toEqual({ grade: 'B' })
  expect(one('OET minimum 350 in each sub-test', 'oet').value).toEqual({ components: all4(350) })
  expect(one('CELPIP General: level 7 in each component.', 'celpip').value).toEqual({ overall: 7, components: all4(7) })
  expect(one('Cambridge C1 Advanced: 176 overall, with no less than 169 in each skill.', 'cambridge').value).toEqual({ overall: 176, components: all4(169), level: 'C1' })
  expect(one('C2 Proficiency 185 overall', 'cambridge').value).toEqual({ overall: 185, level: 'C2' })
  expect(one('IELTS Academic overall score of 6.5 with no individual band below 6.0.', 'ielts').strength).toBe('stated_minimum')
})

test('a flattened table line of several programmes, or one test with two values on a line, is skipped', () => {
  expect(elrRead('Bachelor of Arts IELTS 6.5 Bachelor of Nursing IELTS 7.0')).toEqual([])
  expect(elrRead('Undergraduate IELTS 6.0; postgraduate IELTS 6.5 overall')).toEqual([])
  expect(elrCollapsed('Bachelor of Arts IELTS 6.5 Bachelor of Nursing IELTS 7.0')).toBe(true)
  // one programme's row with one value per test is read, each test from its own words only
  const row = elrRead('IELTS 6.5 | TOEFL 79 | PTE 58 | Duolingo 115')
  expect(row.map((r) => [r.key, r.value.overall])).toEqual([['ielts', 6.5], ['toefl_ibt', 79], ['pte', 58]])
  expect(row.every((r) => r.strength === 'mentioned' && r.flags.includes('no_minimum'))).toBe(true)
})

test('no reading without a plausible value; pathway words are flagged; a requirement heading makes a bare list a stated requirement', () => {
  expect(elrRead('IELTS preparation courses start in 2026.')).toEqual([])
  expect(elrRead('TOEFL scores are sent to the university by the test centre.')).toEqual([])
  expect(elrRead('IELTS 12.5 is not a score.')).toEqual([])
  expect(one('Students with IELTS 5.5 may enter our Foundation program first.', 'ielts').flags).toContain('pathway')
  const t = ['English language requirements', 'IELTS (Academic) 6.5', 'TOEFL iBT 79', 'Fees', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'PTE 58'].join('\n')
  const rs = elrRead(t)
  expect(one(t, 'ielts').strength).toBe('stated_minimum')
  expect(one(t, 'ielts').flags).toEqual(['section'])
  expect(one(t, 'pte').strength).toBe('mentioned')
  expect(rs.every((r) => t.includes(r.quote))).toBe(true)
})

test('agreement: two different values of a test on one page disagree', () => {
  const rs = elrRead('IELTS 6.5 overall is required for most courses.\nNursing requires IELTS 7.0 overall.')
  expect(elrAgree(rs, 'ielts')).toBe(false)
  expect(elrAgree(elrRead('IELTS 6.5 overall.\nApplicants need IELTS 6.5 overall.'), 'ielts')).toBe(true)
})

test('the worker mode elr_det_read is read only and answers with the extractor version', () => {
  const at = WORKER.indexOf('if (mode === "elr_det_read") {')
  expect(at).toBeGreaterThan(0)
  const block = WORKER.slice(at, WORKER.indexOf('if (mode === "page_text") {', at))
  expect(block).toContain('elrRead(text)')
  expect(block).toContain('extractor: ELR_DET_VERSION')
  expect(block).not.toMatch(/\.rpc\(|\.insert\(|\.update\(|\.upsert\(|openrouter|firecrawl/i)
})
