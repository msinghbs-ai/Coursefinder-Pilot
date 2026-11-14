// Guards: Platform Admin 14 Nov 2026 17:21 (report the benchmark "noting whether any multi-block quotes fail single-block citation checks"): worker v0.94.0 records where each failed quote is found on the page (cited block, adjacent blocks, another block, across blocks elsewhere, not on the page); diagnostic only, no check, verdict or score changes
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { leanText } from '../../supabase/functions/coverage-sweep/lean-input.ts'
import { aerV2Refs, aerV3Blocks, aerV3Verify, aerV3QuoteWhere, aerV3QuoteDiag } from '../../supabase/functions/coverage-sweep/aer-v2.ts'

const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const h = '<main><h2>Entry requirements</h2><p>Applicants need one of the following</p><ul><li>an Indian CBSE Class XII with 75%</li><li>GCE A Levels with 9 points</li></ul><h2>Fees</h2><p>A$40,000 a year</p></main>'
const B = aerV3Blocks(leanText(h), '')
const n = (t) => B.blocks.find((b) => b.text.includes(t)).n

test('a failed quote is located: cited block, adjacent blocks (spans), another block, across blocks elsewhere, or not on the page', () => {
  expect(aerV3QuoteWhere(B, 'an Indian CBSE Class XII with 75%', n('CBSE'))).toBe('cited_block')
  expect(aerV3QuoteWhere(B, 'one of the following an Indian CBSE Class XII', n('CBSE'))).toBe('adjacent_blocks')
  expect(aerV3QuoteWhere(B, 'GCE A Levels with 9 points', n('CBSE'))).toBe('other_block')
  expect(aerV3QuoteWhere(B, 'Fees A$40,000', n('CBSE'))).toBe('page')
  expect(aerV3QuoteWhere(B, 'an ATAR of 99', n('CBSE'))).toBe('not_on_page')
  expect(aerV3QuoteWhere(B, 'ab', n('CBSE'))).toBe('no_quote')
})

test('only records that failed are listed, and the checks are unchanged by the diagnostic', () => {
  const recs = [
    { exact_block: n('CBSE'), exact_quote: 'an Indian CBSE Class XII with 75%', min_grade: '75%', min_value: 75, applicant_country: 'IN', qualification: 'CBSE', qualification_code: null, lead_in_block: null, lead_in_quote: null, support: [] },
    { exact_block: n('CBSE'), exact_quote: 'one of the following an Indian CBSE Class XII with 75%', min_grade: '75%', min_value: 75, applicant_country: 'IN', qualification: 'CBSE', qualification_code: null, lead_in_block: null, lead_in_quote: null, support: [] }]
  const v = aerV3Verify({ records: recs, seen_not_mapped: [] }, B, aerV2Refs(['IN'], []), 300, 3)
  const before = JSON.stringify(v.checks)
  const d = aerV3QuoteDiag(v.records, B, v.checks)
  expect(JSON.stringify(v.checks)).toBe(before)
  expect(d).toEqual([{ record: 1, reasons: ['exact_quote_not_in_block'], exact: 'adjacent_blocks', lead_in: null }])
})

test('worker v0.94.0 stores the diagnostic beside the answer; the verdict and quote_on_page come from the checks as before', () => {
  expect(IX).toContain('quote_diag: aerV3QuoteDiag(v.records, blocks, v.checks) };')
  expect(IX).toContain('ans.error = null; ans.verdict = v.passed > 0 ? "accept" : "no_value"; ans.quote_on_page = v.failed === 0 && v.passed > 0;')
  expect(IX).toMatch(/const WORKER = "coverage-sweep-worker-v0\.94\.0";|\/\/ was v0\.94\.0 \/\/ v0\.94\.0 /)  // current, or kept as "was" by a later worker (v0.95.0, Lean AI 1b-3)
})
