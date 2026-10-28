// Guards: CF-247 AER programme Step B acceptance for Western Sydney and Victoria University (Platform Admin consolidated mandate 28 Oct 2026 23:22, "reader corrections only where a source route's acceptance requires them, structure-driven"; "UTS and WSU remain in scope"): a PDF table of five or more columns gives each proven cell on its own line with its row's first cell; a page's slices are read entry.matrix_slice_concurrency at a time and joined in order; a reply cut while it streamed is named; quote, scale, completeness and identity gates unchanged
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import zlib from 'node:zlib'
import { pdfTables, WIDE_COLUMNS } from '../../supabase/functions/coverage-sweep/pdf.ts'
import { entryNoAnswerWhy } from '../../supabase/functions/coverage-sweep/entry.ts'
const fx = (n) => JSON.parse(zlib.gunzipSync(fs.readFileSync(`tests/fixtures/entry-matrix/pdf/${n}.json.gz`))).pages

test('WSU (7 columns): each level requirement is a whole line with its qualification; the row count is unchanged', () => {
  expect(WIDE_COLUMNS).toBe(5)
  const r = pdfTables(fx('wsu'))
  expect(r.status).toBe('ok')
  expect(r.tables.reduce((a, t) => a + t.rows, 0)).toBe(86)
  const L = r.text.split('\n')
  expect(L).toContain('| Qualification: Argentina | 2 Semester University Foundation Studies: Completion of Argentinean Higher Secondary Schooling (Bachiller or Bachillerato) with an average of 60% |')
  expect(L).toContain('| Qualification: Argentina | 2 Semester Diploma: Successful completion of Bachiller/ Bachillero/ Bachillerato with an average of 75% in the final year |')
  expect(L.filter((l) => l.startsWith('| Qualification: Argentina |')).length).toBe(6)
})

test('narrower tables are given row by row as before', () => {
  for (const [n, cols] of [['vu', 4], ['adelaide', 3], ['curtin', 3], ['federation', 3]]) {
    const r = pdfTables(fx(n))
    expect(r.tables.every((t) => t.columns === cols)).toBe(true)
  }
  const vu = pdfTables(fx('vu')).text.split('\n')
  expect(vu.some((l) => /^\| .*Highest qualification: .* \| VU course: .* \| Level of completion: .*\|/.test(l))).toBe(true)
})

test('worker v0.51.0: slices read at the set concurrency, joined in slice order; a cut reply named; gates unchanged', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const ai = w.slice(w.indexOf('if (mode === "entry_ai") {'), w.indexOf('if (mode === "fee_ai") {'))
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(5[1-9]\.\d+)"/)
  expect(ai).toContain('await pool([...slices.keys()], Math.max(1, Math.min(Number(it.slice_concurrency) || 1, 12)), async (i) => {  // fixed: the setting\'s upper bound (entry.matrix_slice_concurrency)')
  expect(ai).toContain('if (failed) throw failed;')
  expect(ai).toContain('for (const { parsed, nm } of parts) { rows.push(...nm.rows); dropped.push(...parsed.dropped, ...nm.dropped); edition ??= parsed.edition; intake_year ??= parsed.intake_year }')
  expect(ai).toContain('const parsed = entryMatrixParsed(JSON.parse(content), page, stored.lines);')
  expect(ai).toContain('if (it.completeness_required === true && completeness.status !== "complete") {')
  expect(entryNoAnswerWhy({ unreadable: 'TimeoutError: The signal has been aborted' }, 2, 5)).toBe(' (reply unreadable: TimeoutError: The signal has been aborted; slice 2 of 5)')
})
