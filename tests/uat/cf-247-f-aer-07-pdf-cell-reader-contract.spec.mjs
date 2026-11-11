// Guards: F-AER.07 PDF cell reader: a ruled PDF entry table is read cell by cell, recognising the country, education board, international qualification, study level, scale and minimum (Platform Admin 11 Nov 2026 16:20; qualification-first decision 11 Nov 2026 item 5)
// Production 11 Nov 2026: WSU's Entry Qualifications PDF (stored copy 92aadee2..., the fixture wsu.json.gz) was read by the model with 25 rows dropped, so its Layer 4 item
// could only be rejected. The cell reader (worker v0.71.0, entry-cells.ts) reads the same table with nothing dropped; its rows go through the parser's checks unchanged.
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
const refs = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/country-refs.json', 'utf8'))
const Q = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/qualifications.json', 'utf8'))
const pages = JSON.parse(zlib.gunzipSync(fs.readFileSync('tests/fixtures/entry-matrix/pdf/wsu.json.gz'))).pages

async function wsu() {
  const { pdfTables } = await load('supabase/functions/coverage-sweep/pdf.ts', 'pdf')
  const cells = await load('supabase/functions/coverage-sweep/entry-cells.ts', 'cells')
  const entry = await load('supabase/functions/coverage-sweep/entry.ts', 'entry')
  const t = pdfTables(pages)
  const aliases = entry.entryCountryAliases(['UK=GB', 'GB-SCT=GB', 'GB-ENG=GB'])
  const read = cells.entryCellRead(t.text, refs, Q.qualifications, aliases)
  const parsed = read && entry.entryMatrixParsed(read.answer, t.text, Object.assign([], { forms: t.forms }), { countryAliases: aliases, qualifications: Q.qualifications, globalTokens: Q.global_tokens })
  return { t, read, parsed, cells }
}

test('WSU: every cell is read; nothing the page prints is dropped', async () => {
  const { read, parsed } = await wsu()
  expect(read).not.toBeNull()
  expect(read.stats.cells).toBe(456)
  expect(read.levels).toEqual(['3 Semester University Foundation Studies', '2 Semester University Foundation Studies', '3 Semester Diploma', '2 Semester Diploma', 'Undergraduate Degree', 'Postgraduate Degree'])
  // the only cells with no row are the page's own "Not applicable" (GAC 3, IB 1), kept as no_minimum_published (ignored by the D-R3 gate setting)
  expect(read.dropped.map((d) => d.reason)).toEqual(['no_minimum_published', 'no_minimum_published', 'no_minimum_published', 'no_minimum_published'])
  expect(parsed.dropped).toEqual([])
  expect(parsed.rows.length).toBe(461)
  expect(new Set(parsed.rows.map((r) => r.country_code)).size).toBe(72)
  // every kept quote is at most 300 characters and every value is printed in its quote (the gate's flag rule)
  for (const r of parsed.rows) {
    expect(r.quote.length).toBeLessThanOrEqual(300)
    if (r.min_value != null) expect(r.quote).toContain(String(r.min_value).replace(/\.0$/, ''))
    if (r.min_grade) expect(r.quote).toContain(r.min_grade)
  }
})

test('education boards: one row per board that prints its own minimum (Nepal, China, Indonesia)', async () => {
  const { parsed } = await wsu()
  const at = (cc, level) => parsed.rows.filter((r) => r.country_code === cc && r.study_level === level)
  const np = at('NP', 'Undergraduate Degree')
  expect(np.map((r) => [r.qualification_name, r.min_value, r.grade_scale])).toEqual([
    ['Nepalese Higher Secondary Certificate', 80, 'percentage'], ['Nepalese Education Board Year 12', 2.9, 'gpa'], ['Nepalese Proficiency Certificate (10+3)', 75, 'percentage']])
  expect(np[0].conditions.alternatives.length).toBe(2)
  expect(at('CN', '3 Semester Diploma').map((r) => r.min_value)).toEqual([60, 65])
  // one qualification printed with two minimums ("SMA3 75% or GPA 7.5") is one row with an equivalent minimum, never two rows of one identity
  const id = at('ID', 'Undergraduate Degree')
  expect(id.map((r) => [r.qualification_name, r.min_value, r.grade_scale])).toEqual([['SMA3', 75, 'percentage']])
  expect(id[0].conditions.equivalent_minimums).toEqual([{ min_grade: 'GPA 7.5', min_value: 7.5, grade_scale: 'gpa' }])
})

test('a board that names its country is that country, with the board kept (India: State Boards, CBSE, ISC)', async () => {
  const { parsed } = await wsu()
  const ug = parsed.rows.filter((r) => r.country_code === 'IN' && r.study_level === 'Undergraduate Degree')
  expect(ug.map((r) => [r.qualification_name, r.min_value, r.grade_scale])).toEqual([
    ['Indian Higher Secondary School Certificate (State Boards)', 70, 'percentage'], ['All India School Certificate (CBSE)', 6, 'gpa'], ['Indian School Certificate (ISC)', 6, 'gpa']])
  expect(ug.every((r) => !!r.conditions.education_board)).toBe(true)
  // postgraduate entry names a degree, not the school board
  // the same postgraduate requirement under each board is one row listing the boards
  const pg = parsed.rows.filter((r) => r.country_code === 'IN' && r.study_level === 'Postgraduate Degree')
  expect(pg.length).toBe(1)
  expect(pg[0].qualification_name).toMatch(/Bachelor degree/)
  expect(pg[0].conditions.education_boards).toEqual(['Indian Higher Secondary School Certificate (State Boards)', 'All India School Certificate (CBSE)', 'Indian School Certificate (ISC)'])
  // no two rows share the identity the D-R3 gate checks (country, study level, qualification)
  const ids = parsed.rows.map((r) => [r.country_code, r.study_level, r.qualification_name].join('|'))
  expect(new Set(ids).size).toBe(ids.length)
})

test('international qualifications are kept by identity, never as a country (GAC, IB Certificate)', async () => {
  const { parsed } = await wsu()
  const q = parsed.qualification_rows.map((r) => [r.qualification_code, r.study_level, r.min_value, r.grade_scale])
  expect(q).toEqual([
    ['GAC', '3 Semester Diploma', null, 'none'], ['GAC', '2 Semester Diploma', 2, 'gpa'], ['GAC', 'Undergraduate Degree', 2.3, 'gpa'],
    ['IB_COURSES', '3 Semester University Foundation Studies', null, 'none'], ['IB_COURSES', '2 Semester University Foundation Studies', null, 'none'],
    ['IB_COURSES', '3 Semester Diploma', 22, 'points'], ['IB_COURSES', '2 Semester Diploma', 23, 'points'], ['IB_COURSES', 'Undergraduate Degree', 24, 'points']])
  expect(parsed.rows.some((r) => /GAC|Baccalaureate Certificate/.test(r.country_name))).toBe(false)
  // the page says nothing about every country, so applicability is unresolved (never inferred)
  expect(parsed.qualification_rows.every((r) => r.applicability === 'unresolved')).toBe(true)
})

test('scales and minimums as printed: ranges and directions keep their words, letters have no number', async () => {
  const { parsed } = await wsu()
  const one = (cc, level) => parsed.rows.find((r) => r.country_code === cc && r.study_level === level)
  expect([one('DE', '3 Semester Diploma').min_grade, one('DE', '3 Semester Diploma').min_value]).toEqual(['a grade of 4.6 to 5.0', null])
  expect([one('DE', 'Undergraduate Degree').min_grade, one('DE', 'Undergraduate Degree').min_value]).toEqual(['a grade of 4.0 or less', 4])
  expect([one('NG', '3 Semester Diploma').min_value, one('NG', '3 Semester Diploma').grade_scale]).toEqual([null, 'none'])
  expect([one('FR', 'Undergraduate Degree').min_value, one('FR', 'Undergraduate Degree').grade_scale]).toEqual([10.5, 'aggregate'])
  expect([one('GB', 'Undergraduate Degree').min_value, one('GB', 'Undergraduate Degree').grade_scale]).toEqual([6, 'points'])
  expect([one('PH', '3 Semester University Foundation Studies').min_value, one('PH', '3 Semester University Foundation Studies').grade_scale]).toEqual([null, 'letter'])
  expect(one('AU', 'Undergraduate Degree').grade_scale).toBe('rank')
})

test('only a country-by-level grid is read by cells; any other shape goes to the model', async () => {
  const { cells } = await wsu()
  expect(cells.entryCellRead('| A | B |\n| A: x | B: 70% |', refs, Q.qualifications)).toBeNull()
  const vu = (await load('supabase/functions/coverage-sweep/pdf.ts', 'pdf2')).pdfTables(JSON.parse(zlib.gunzipSync(fs.readFileSync('tests/fixtures/entry-matrix/pdf/vu.json.gz'))).pages)
  expect(cells.entryCellRead(vu.text, refs, Q.qualifications)).toBeNull()  // VU prints four requirement columns per row, not one line per cell
  // a label naming two countries is not guessed
  const idx = cells.entryCellCountryIndex(refs)
  expect(cells.entryCellLabel('India and Nepal Certificate', idx, Q.qualifications).kind).toBe('unknown')
  expect(cells.entryCellLabel('Cambridge International A Level', idx, Q.qualifications)).toMatchObject({ kind: 'qualification', qualification: 'CAIE_AL' })
})

test('worker and migration: switch and shape limits are settings; the recovery panel fix edits the live definition only', () => {
  const idx = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(idx).toContain('const WORKER = "coverage-sweep-worker-v0.71.0"')
  expect(idx).toMatch(/Number\(ws\["reading\.entry_cell_reader_on"\]\) >= 1/)
  expect(idx).toContain('ws["reading.entry_cell_min_levels"]')
  expect(idx).toContain('ws["reading.entry_cell_min_lines"]')
  const m1 = fs.readFileSync('supabase/migrations/20261112163100_cf247_aer_pdf_cell_reader.sql', 'utf8')
  expect(m1).toContain("'caf0e61bfcf983fb421638afd3aea795'")
  expect(m1).toContain('null::uuid new_item_id into v_sup')
})
