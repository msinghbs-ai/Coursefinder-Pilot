// Guards: Standing Authority Charter 23 Nov 2026 item 1 (AER v2 proven-structure readers pre-authorised) and Platform Admin 24 Nov 2026 16:15 AEDT ("ACU PDF: implement deterministic layout extraction"); S1-AER-Claude s1071
// s1071: entry-pdf-columns.ts proves an unruled PDF column table (ACU, minimum academic entry requirements by country) from positioned text alone, fails closed, and reads its cells through entry-cells.ts.
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
const fx = JSON.parse(fs.readFileSync('tests/fixtures/entry-matrix/pdf-columns/acu-page2.json', 'utf8'))
const refsRaw = JSON.parse(fs.readFileSync('tests/fixtures/entry-matrix/ref-countries.json', 'utf8'))
const REFS = Array.isArray(refsRaw) ? refsRaw : refsRaw.countries
const QUALS = [{ code: 'IB_DP', aliases: ['international baccalaureate', 'international baccalaureate diploma', 'ib'] }]
const clone = () => JSON.parse(JSON.stringify(fx.pages))

test('ACU page 2: the header proves three level columns and each wrapped cell is one line per row, words as printed', async () => {
  const m = await load('supabase/functions/coverage-sweep/entry-pdf-columns.ts', 'pc1050')
  const { tables, skipped } = m.pdfColumnTableLines(clone(), { minRows: 5 })
  expect(skipped).toEqual([])
  expect(tables).toHaveLength(1)
  expect(tables[0].levels).toEqual(['Bachelor Degree', 'Diplomas Or Tertiary Preparation Program (Health Sciences)', 'Foundation Studies Program'])
  expect(tables[0].rows).toBe(6)
  const L = tables[0].lines
  expect(L).toContain('| Country or Qualification: Afghanistan | Foundation Studies Program: Afghanistan Baccalauria with minimum grade average of 80%. |')
  expect(L).toContain('| Country or Qualification: Afghanistan | Diplomas Or Tertiary Preparation Program (Health Sciences): Afghanistan Baccalauria with minimum grade average of 83%. |')
  expect(L).toContain('| Country or Qualification: European Baccalaureate | Bachelor Degree: Diplome du Baccalaureate European Zeugnis der Europaischen Reifeprufung Diploma di Licenze Liceale Europea, Europees Baccalaureates Diploma with minimum overall grade of 55. |')
  // the "OR" line stays inside its cell; nothing moves between cells
  expect(L.find((l) => l.includes('Afghanistan | Bachelor Degree'))).toContain('foundation program OR Successful completion of one year of study')
  expect(L.filter((l) => l.includes('Algeria |')).length).toBe(3)
})

test('fails closed: an item on no column anchor, a header without level words, or too few rows gives no table', async () => {
  const m = await load('supabase/functions/coverage-sweep/entry-pdf-columns.ts', 'pc1050b')
  const off = clone(); off[0].items.push({ x: 210, y: 463.6, w: 30, h: 10, s: 'stray' })
  expect(m.pdfColumnTableLines(off, { minRows: 5 }).tables).toEqual([])
  expect(m.pdfColumnTableLines(off, { minRows: 5 }).skipped[0].reason).toBe('pdf_columns_item_off_anchor')
  const nolevel = clone(); for (const i of nolevel[0].items) if (i.s === 'BACHELOR DEGREE') i.s = 'COLUMN ONE'
  expect(m.pdfColumnTableLines(nolevel, { minRows: 5 }).skipped[0].reason).toBe('pdf_columns_header_level_unmapped')
  expect(m.pdfColumnTableLines(clone(), { minRows: 50 }).tables).toEqual([])
})

test('the read goes through the cell reader and the admission checks: only printed minimums become rows, pathway cells publish none, nothing is invented', async () => {
  const m = await load('supabase/functions/coverage-sweep/entry-pdf-columns.ts', 'pc1050c'), en = await load('supabase/functions/coverage-sweep/entry.ts', 'en1050')
  const r = m.entryPdfColumnsRead(clone(), REFS, QUALS, {}, { minRows: 5 })
  expect(r).not.toBeNull()
  expect(r.tables.map((t) => t.level_from)).toEqual(['column'])
  for (const x of r.answer.rows) expect(x.conditions.reader).toBe('pdf-columns-v1')
  const lines = new Set(r.text.split('\n'))
  for (const x of r.answer.rows) expect([...lines].some((l) => l.includes(x.quote))).toBe(true)
  const parsed = en.entryMatrixParsed(r.answer, r.text, Object.assign([], { forms: [] }), { qualifications: QUALS, globalTokens: ['all countries'] })
  // cells that print a minimum are read as printed, with the printed scale; a pathway-only cell gives no minimum; qualification rows whose qualification is not in the reference list are dropped, never guessed
  const got = Object.fromEntries(r.answer.rows.filter((x) => x.min_value != null).map((x) => [`${x.min_grade}`, [x.min_value, x.grade_scale]]))
  expect(got['minimum grade average of 83%']).toEqual([83, 'percentage'])
  expect(got['minimum grade average of 80%']).toEqual([80, 'percentage'])
  expect(got['minimum overall grade of 12']).toEqual([12, 'aggregate'])
  expect(r.answer.rows.filter((x) => x.min_value == null && x.grade_scale === 'none').length).toBeGreaterThanOrEqual(4)
  expect(r.dropped.map((d) => d.reason).filter((x) => x !== 'unknown_country')).toEqual([])
  expect(parsed.dropped).toEqual([])
})
