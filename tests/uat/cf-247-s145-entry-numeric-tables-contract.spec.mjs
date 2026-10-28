// Guards: CF-247 AER programme reader correction for an approved source route (Platform Admin consolidated mandate 28 Oct 2026 23:22, "reader corrections only where a source route's acceptance requires them, structure-driven"): an HTML table whose data cells are all bare numbers names each cell by its column header so its rows can be quoted whole (ANU rank-to-score pages, UWA score-to-ATAR tables); worded tables, completeness-guarded providers and every gate unchanged
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryTables, entryMatrixParsed, NAMED_NOTE } from '../../supabase/functions/coverage-sweep/entry.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'

const anu = fs.readFileSync('tests/fixtures/entry-matrix/numeric/anu-india-aissc.html', 'utf8')

test('ANU (stored page): each rank row says what its numbers are, and only when asked', () => {
  const t = entryTables(anu, htmlToText, true)
  expect(t.named).toBe(1)
  expect(t.text).toContain('Program Required Entrance Rank | Indicative score required')
  expect(t.text).toContain('Program Required Entrance Rank: 80 | Indicative score required: 14.0')
  expect(t.text).toContain('Program Required Entrance Rank: 99 | Indicative score required: 20.0')
  const off = entryTables(anu, htmlToText)
  expect(off.named).toBe(0)
  expect(off.text).toContain('\n80 | 14.0\n')
})

test('a whole named line passes the quote gates; a bare cell still does not', () => {
  const page = entryTables(anu, htmlToText, true).text
  const row = (quote) => ({ country_code: 'IN', country_name: 'India', study_level: 'Bachelor', qualification_name: 'All India Senior School Certificate', min_grade: '14.0', min_value: 14, grade_scale: 'points', benchmark_band: 'rank 80', course_name: null, conditions: {}, confidence: 0.95, quote })
  const ok = entryMatrixParsed({ rows: [row('Program Required Entrance Rank: 80 | Indicative score required: 14.0')] }, page)
  expect(ok.dropped).toEqual([])
  expect(ok.rows.length).toBe(1)  // the band and the score are both on the quoted line
  const other = entryMatrixParsed({ rows: [{ ...row('Program Required Entrance Rank: 80 | Indicative score required: 14.0'), benchmark_band: 'rank 90' }] }, page)
  expect(other.dropped[0].reason).toBe('band_not_in_quote')  // a band not printed on the line is still refused
  expect(entryMatrixParsed({ rows: [row('80 | 14.0')] }, page).dropped[0].reason).toBe('quote_too_short')
})

test('worded tables are unchanged; a header that is itself a number is not a header', () => {
  const html = (rows) => `<table>${rows.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join('')}</tr>`).join('')}</table>`
  const worded = entryTables(html([['Qualification', 'Minimum'], ['CBSE', '75%'], ['State Boards', 'Minimum average of 80%']]), htmlToText, true)
  expect(worded.named).toBe(0)
  expect(worded.text).toContain('CBSE | 75%')
  const noHeader = entryTables(html([['70', '10.5'], ['80', '14.0'], ['82', '14.5']]), htmlToText, true)
  expect(noHeader.named).toBe(0)
})

test('worker: named only outside the completeness guard, and the read is told so', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('const stored = await storedText(it.storage_path, it.mime, Number(it.pdf_max_pages) || 40, it.completeness_required !== true), page = stored.text;')
  expect(w).toContain('note: stored.pdf ? PDF_NOTE : stored.named ? NAMED_NOTE : undefined }')
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(50\.([1-9]|\d{2,})|5[1-9]\.\d+)"/)
  expect(NAMED_NOTE).toMatch(/quote the whole line/)
})
