// Guards: Admin #1028 (Platform Admin 24 Nov 2026 23:49 AEDT, each AER chat owns its providers' source recovery and extraction) and Standing Authority Charter 23 Nov 2026 item 1 (AER v2 proven-structure PDF readers pre-authorised)
// s1105: entry-pdf-columns.ts proves the country-header PDF layout (CQUniversity "Country Specific Academic Requirements": Country | Qualification | Diploma | Undergraduate), fails closed, leaves out a foreign award printed under another country, and entry-cells.ts reads "per cent" as a percentage
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

async function load(file, name) {
  const out = path.join(os.tmpdir(), `${name}-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', [file, '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}
const fx = JSON.parse(fs.readFileSync('tests/fixtures/entry-matrix/pdf-columns/cqu-country-specific-pages.json', 'utf8'))
const refsRaw = JSON.parse(fs.readFileSync('tests/fixtures/entry-matrix/ref-countries.json', 'utf8'))
const REFS = Array.isArray(refsRaw) ? refsRaw : refsRaw.countries
const pages = () => fx.pages.map((p) => ({ p: p.p, width: p.width, height: p.height, rules: [], items: p.items.map(([x, y, w, s]) => ({ x, y, w, h: 10, s })) }))

test('CQU country table: the header proves two level columns, a country carries over its qualification rows, cells keep their words', async () => {
  const m = await load('supabase/functions/coverage-sweep/entry-pdf-columns.ts', 'pc1105')
  const { tables, skipped } = m.pdfCountryColumnTableLines(pages(), { minRows: 5 })
  expect(tables).toHaveLength(1)
  expect(tables[0].levels).toEqual(['Diploma', 'Undergraduate'])
  const L = tables[0].lines
  expect(L).toContain('| Country or Qualification: China - Gao San (Senior Three) | Diploma: Grade average of 65 per cent in academic subjects |')
  // a second qualification of the same country is its own row, the country carried forward
  expect(L.some((l) => l.includes('China - Gao Kao (National College Entrance Examination) | Diploma: Assessed on a case'))).toBe(true)
  // a cell's text that runs on in a second item of the same line is one cell
  expect(L.find((l) => l.includes('United States of America') && l.includes('Undergraduate:'))).toContain('with a minimum GPA 2.5 and a SAT 1 composite score of 1050')
  // the province score table after the heading is no part of the country table, and the page number in the foot margin is not a cell
  expect(L.join('\n')).not.toMatch(/Beijing|Henan|GAO KAO MINIMUM/)
  // UK awards printed under China with no country of their own are left out and listed
  expect(L.join('\n')).not.toMatch(/SQA|BTEC/)
  expect(skipped.map((s) => s.reason)).toEqual(['pdf_columns_foreign_award_row', 'pdf_columns_foreign_award_row'])
})

test('CQU country table: the cell reader reads per cent as a percentage and drops pathway-only cells', async () => {
  const m = await load('supabase/functions/coverage-sweep/entry-pdf-columns.ts', 'pc1105b')
  const r = m.entryPdfColumnsRead(pages(), REFS, [], {}, { minRows: 5 })
  expect(r).not.toBeNull()
  const china = r.answer.rows.filter((x) => x.country_code === 'CN')
  expect(china.map((x) => [x.study_level, x.min_value, x.grade_scale])).toEqual([['Diploma', 65, 'percentage'], ['Undergraduate', 70, 'percentage']])
  const india = r.answer.rows.find((x) => x.country_code === 'IN' && x.study_level === 'Undergraduate')
  expect(india.min_value).toBe(60); expect(india.grade_scale).toBe('percentage')
  expect(r.dropped.some((d) => d.reason === 'no_minimum_published' && d.country === 'CA')).toBe(true)
})

test('fails closed: an item left of the first column, or a header with no level words, gives no table', async () => {
  const m = await load('supabase/functions/coverage-sweep/entry-pdf-columns.ts', 'pc1105c')
  const off = pages(); off[0].items.push({ x: 20, y: 600, w: 10, h: 10, s: 'stray' })
  expect(m.pdfCountryColumnTableLines(off, { minRows: 5 }).tables).toEqual([])
  expect(m.pdfCountryColumnTableLines(off, { minRows: 5 }).skipped[0].reason).toBe('pdf_columns_item_off_anchor')
  const bad = pages(); bad[0].items.find((i) => i.s === 'Undergraduate').s = 'Column Three'
  expect(m.pdfCountryColumnTableLines(bad, { minRows: 5 }).skipped[0].reason).toBe('pdf_columns_header_level_unmapped')
})
