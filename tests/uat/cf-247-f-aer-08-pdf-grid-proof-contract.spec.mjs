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

// step 2: grid cells become requirement rows, each checked by the parser exactly as a model's answer
const refs = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/country-refs.json', 'utf8'))
const Q = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/qualifications.json', 'utf8'))
const LIST = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/grid-heading-list.json', 'utf8'))  // the proposed reading.entry_grid_headings
async function gridRows(f) {
  const g = await load('supabase/functions/coverage-sweep/pdf-grid.ts', `g-${f}`)
  const r = await load('supabase/functions/coverage-sweep/entry-grid.ts', `r-${f}`)
  const e = await load('supabase/functions/coverage-sweep/entry.ts', `e-${f}`)
  const grid = g.pdfGrids2(pages(f))
  const aliases = e.entryCountryAliases(['UK=GB'])
  const read = r.entryGridRead(grid.tables, refs, Q.qualifications, r.entryGridHeadingList(LIST), aliases)
  const parsed = e.entryMatrixParsed(read.answer, grid.text, Object.assign([], { forms: [] }), { countryAliases: aliases, qualifications: Q.qualifications, globalTokens: Q.global_tokens })
  return { read, parsed }
}

test('every printed minimum becomes one row for one course and one country or qualification; only N/A cells give none', async () => {
  const counts = {}
  for (const f of ['unsw', 'sydney', 'uq']) {
    const { read, parsed } = await gridRows(f)
    counts[f] = [parsed.rows.length, parsed.qualification_rows.length]
    expect(parsed.dropped).toEqual([])  // the parser keeps every row (quote on the page, value in the quote, scale)
    expect(read.dropped.every((d) => d.reason === 'no_minimum_published')).toBe(true)
    expect(read.columns.filter((c) => c.kind === 'unknown')).toEqual([])
    for (const x of parsed.rows) { expect(x.course_name).toBeTruthy(); expect(x.country_code).toMatch(/^[A-Z]{2}$/) }
  }
  expect(counts).toEqual({ unsw: [1932, 260], sydney: [1780, 178], uq: [1214, 162] })  // 12 Nov 2026: the ATAR column is a course fact (the course record holds the ATAR), not an AU row
})

test('headings: boards, international qualifications, governed fallbacks and course facts', async () => {
  const { read } = await gridRows('unsw')
  const col = (h) => read.columns.filter((c) => c.head === h || c.head.startsWith(h)).map((c) => `${c.kind}:${c.country || c.qualification || ''}`)
  expect(col('India AISSCE')).toEqual(['board:IN'])
  expect(col('IB')).toEqual(['qualification:IB_DP'])
  expect(col('GCE AL')).toEqual(['qualification:GCE_A', 'qualification:NCUK_IFY'])  // "GCE AL or NCUK": one row for each
  expect(col('Europe (EB)')).toEqual(['qualification:EB'])  // governed list EB=@EB
  expect(col('Gao Kao')).toEqual(['board:CN'])               // governed list
  expect(col('UFS GPA')).toEqual(['fact:'])                  // the university's own foundation program: not a country or recognised qualification
  const s = await gridRows('sydney')
  expect(s.read.columns.filter((c) => c.kind === 'fact').map((c) => c.head)).toContain('CRICOS')
})

test('values keep their printed words; a number only when the cell is one number', async () => {
  const r = await load('supabase/functions/coverage-sweep/entry-grid.ts', 'v')
  expect(r.entryGridValue('75%', 'China - Gaokao')).toEqual({ grade: '75%', value: 75, scale: 'percentage' })
  expect(r.entryGridValue('3.4', 'British Columbia GPA')).toEqual({ grade: '3.4', value: 3.4, scale: 'gpa' })
  expect(r.entryGridValue('80', 'INT ATAR')).toEqual({ grade: '80', value: 80, scale: 'rank' })
  expect(r.entryGridValue('A2', 'Malaysia - UEC')).toEqual({ grade: 'A2', value: null, scale: 'letter' })
  expect(r.entryGridValue('14/14', 'GCE 3/4 A Levels')).toEqual({ grade: '14/14', value: null, scale: 'none' })
  expect(r.entryGridValue('3..6', 'Gao Kao')).toEqual({ grade: '3..6', value: null, scale: 'none' })  // a misprint is never read as a number
  expect(r.entryGridValue('N/A', 'IB')).toBeNull()
})
