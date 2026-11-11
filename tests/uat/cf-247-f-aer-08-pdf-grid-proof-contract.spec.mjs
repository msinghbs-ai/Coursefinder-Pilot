// Guards: F-AER.08 aligned grid proof, fail closed: a course-by-qualification PDF table without drawn row rules is accepted only when every value sits in one headed column and one labelled course row (Platform Admin 11 Nov 2026 decision 1)
// The stored copies (tests/fixtures/entry-matrix/pdf, the same sha256 as the live sources) of UNSW, Sydney and UQ are held today by ruled-cells-v1
// ("columns of text with no drawn rules"). pdf-grid.ts proves them by alignment; each figure below was checked against the printed row.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import zlib from 'node:zlib'
import { execFileSync } from 'node:child_process'

async function load(file, name) {
  const out = path.join(os.tmpdir(), `${name}-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', [file, '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`])
  return import(out)
}
const pages = (f) => JSON.parse(zlib.gunzipSync(fs.readFileSync(`tests/fixtures/entry-matrix/pdf/${f}.json.gz`))).pages
const cell = (t, label, head) => t.cells.find((c) => c.label === label && c.head === head)?.value

test('UNSW, Sydney and UQ prove by alignment; the counts are every printed course row', async () => {
  const g = await load('supabase/functions/coverage-sweep/pdf-grid.ts', 'grid')
  const u = g.pdfGrids2(pages('unsw')), s = g.pdfGrids2(pages('sydney')), q = g.pdfGrids2(pages('uq'))
  expect([u.status, s.status, q.status]).toEqual(['ok', 'ok', 'ok'])
  expect(u.tables.map((t) => [t.page, t.rows, t.heads.length])).toEqual([[1, 65, 35]])
  expect(s.tables.map((t) => [t.page, t.rows, t.heads.length])).toEqual([[1, 17, 31], [2, 31, 31], [3, 22, 31], [4, 19, 31]])
  expect(q.tables.map((t) => [t.page, t.rows, t.heads.length])).toEqual([[3, 54, 31]])
  // the ruled reader still holds them (nothing changes for any other document)
  const r = await load('supabase/functions/coverage-sweep/pdf.ts', 'pdf')
  for (const f of ['unsw', 'sydney', 'uq']) expect(r.pdfTables(pages(f)).status).toBe('unparsed')
})

test('values sit under their own heading and course (checked against the printed rows)', async () => {
  const g = await load('supabase/functions/coverage-sweep/pdf-grid.ts', 'grid2')
  const u = g.pdfGridPage(pages('unsw')[0])
  const eng = 'B Engineering (Hons) (Materials Science and Engineering)'  // a label printed over two lines around its values
  expect([cell(u, eng, 'INT ATAR'), cell(u, eng, 'Gao Kao'), cell(u, eng, 'IB'), cell(u, eng, 'German Abitur'), cell(u, eng, 'Switzerland (FMC)')]).toEqual(['80', '72', '30', '2.5', '56'])
  expect([cell(u, 'B Science', 'INT ATAR'), cell(u, 'B Science', 'India AISSCE'), cell(u, 'B Science', 'Europe (EB)')]).toEqual(['78', '75', '67.5'])
  const s2 = g.pdfGridPage(pages('sydney')[1])
  const ed = 'B Education (Health and Physical Education)^'
  // a cell wrapped over three lines is one cell
  expect([cell(s2, ed, 'CRICOS'), cell(s2, ed, 'English - IELTS Academic'), cell(s2, ed, 'English - TOEFL iBT'), cell(s2, ed, 'IB Diploma')]).toEqual(['103483H', '7.5 (8.0-L/S, 7.0-R/W)', '105 (27-L/S, 25-W, 23-R)', '29'])
  const s1 = g.pdfGridPage(pages('sydney')[0])
  // rotated headings: the narrow USFP column is its own column (its values are not folded into SAT)
  expect([cell(s1, 'B Economics', 'USA - SAT (out of 1600)'), cell(s1, 'B Economics', 'USFP GPA/USFP English'), cell(s1, 'B Economics', 'Vietnam - High School Graduation Certificate')]).toEqual(['1300', '7.3/C+', '8.5'])
  const q = g.pdfGridPage(pages('uq')[2])
  expect([cell(q, 'Bachelor of Science', 'Australian Tertiary Admission Rank (ATAR)'), cell(q, 'Bachelor of Science', 'Chinese GaoKao'), cell(q, 'Bachelor of Science', 'India CISCE and CBSE')]).toEqual(['80', '72', '70'])
  // every cell keeps its page and coordinates
  expect(q.cells.every((c) => c.page === 3 && c.x > 0 && c.y > 0)).toBe(true)
})

test('fails closed: a value off its columns, two values in one cell, or a heading that cannot be placed holds the page', async () => {
  const g = await load('supabase/functions/coverage-sweep/pdf-grid.ts', 'grid3')
  const base = pages('unsw')[0]
  const row = base.items.find((i) => i.s === 'B Science')
  const vals = base.items.filter((i) => Math.abs(i.y - row.y) < 1 && i.x > 270)
  // a value moved between two columns
  const moved = { ...base, items: base.items.map((i) => (i === vals[3] ? { ...i, x: (vals[3].x + vals[4].x) / 2 } : i)) }
  expect(() => g.pdfGridPage(moved)).toThrow(/column|values/)
  // a second value printed in a cell
  const extra = { ...base, items: [...base.items, { ...vals[5], x: vals[5].x + vals[5].w + 12, s: '99' }] }
  expect(() => g.pdfGridPage(extra)).toThrow()
  // a heading removed
  const hd = base.items.find((i) => i.s === 'HKDSE')
  expect(() => g.pdfGridPage({ ...base, items: base.items.filter((i) => i !== hd) })).toThrow(/no heading/)
  // a page of prose has no grid
  expect(g.pdfGridPage({ ...base, items: base.items.filter((i) => !g.GRID_VALUE.test(i.s.trim())) })).toBeNull()
})
