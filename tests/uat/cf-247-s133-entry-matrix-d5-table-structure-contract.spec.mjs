// Guards: CF-247 AER v1.1 D5 (Platform Admin 27 Oct 2026 05:46): the source-table manifest recognises a footnote row whatever its width, reads a row whose trailing cells were left out as blank only when no merged cell spans them, and still fails a malformed table; complete tables keep their manifests and verdicts
// Record: admin docs/platform/aer-v1.1-build-log.md. Fixtures: tests/fixtures/entry-matrix/rmit-stored/ — the stored copies of all 36 RMIT
// pages (title, h1 and table markup via entry_inspect, each md5-checked against the database), their pre-D5 manifest fingerprints, and the
// proposed rows of the 12 runs complete under the guard.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'
import { entryManifest, entryCompleteness, entryMatrixParsed, entryTables, entryNonCountryShape } from '../../supabase/functions/coverage-sweep/entry.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'
const D = 'tests/fixtures/entry-matrix/rmit-stored/'
const page = (slug) => fs.readFileSync(`${D}${slug}.html`, 'utf8')
const INDEX = JSON.parse(fs.readFileSync(`${D}index.json`, 'utf8')).pages
const BEFORE = JSON.parse(fs.readFileSync(`${D}manifests-before-d5.json`, 'utf8')).pages
const COMPLETE = JSON.parse(fs.readFileSync(`${D}complete-runs-rows.json`, 'utf8')).pages
const COUNTRIES = JSON.parse(fs.readFileSync('tests/fixtures/entry-matrix/ref-countries.json', 'utf8')).countries
const NAME = Object.fromEntries(COUNTRIES.map(c => [c.a2, c.name]))
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')
const verdict = (slug, rows) => { const h = page(slug), t = entryTables(h, htmlToText), m = entryManifest(h, htmlToText), p = entryMatrixParsed({ rows }, t.text, t.lines); return { m, p, v: entryCompleteness(m, p.rows) } }
const rowsFor = (m, cc, map = (x) => x) => m.entries.map(e => map({ country_code: cc, country_name: NAME[cc], study_level: e.level, qualification_name: e.header,
  min_grade: e.cell, min_value: null, grade_scale: 'none', benchmark_band: e.band, course_name: null, conditions: {}, confidence: 0.95, quote: e.line }))

test('the fixtures are the stored copies: 36 pages, each md5 as recorded from the database', () => {
  expect(Object.keys(INDEX).length).toBe(36)
  for (const [slug, p] of Object.entries(INDEX)) expect(md5(page(slug)), slug).toBe(p.html_md5)
})

test('Kuwait: the footnote row (one cell spanning the columns) is a footnote; the table reads 11 minimums', () => {
  const m = entryManifest(page('kuwait'), htmlToText)
  expect(m.status).toBe('ok')
  expect(m.entries.length).toBe(11)
  expect(m.footnotes.length).toBe(1)
  expect(m.footnotes[0]).toMatch(/^Grading \/ Calculation System \| Overall average percentage in all academic subject/)
  expect(m.entries.filter(e => e.band).map(e => e.band)).toEqual(['50%', '55%', '60%', '65%', '70%', '75%', '80%', '85%', '90%'])
  expect(entryNonCountryShape(m, COUNTRIES)).toBeNull()
})

test('Mexico: the 80% row left its trailing cell out (no merged cell spans it); it publishes nothing there; 6 minimums as printed', () => {
  const m = entryManifest(page('mexico'), htmlToText)
  expect(m.status).toBe('ok')
  expect(m.entries.map(e => `${e.level}|${e.band ?? ''}|${e.cell.slice(0, 30)}`)).toEqual([
    'Foundation Studies||6', 'University Pathways Fast Track||8',
    'Diploma/Associate degrees|50%|7', 'Diploma/Associate degrees|55%|7.5', 'Diploma/Associate degrees|60%|8',
    'Bachelor degrees|65%|Assessed on a case-by-case bas'])
  // the page text the reader and the quote check see is unchanged: the short row is still printed as the source has it
  expect(entryTables(page('mexico'), htmlToText).text).toContain('Bachelor degrees | 80% | Not applicable\n')
})

test('a short row under a merged cell, a wider data row and a band table with no rows still fail', () => {
  const t = (rows) => `<h1>Kuwait</h1><table><tr><th>Level of study</th><th>Australian standard</th><th>A</th><th>B</th></tr>${rows}</table>`
  // B spans two rows from the 50% row, then the 55% row stops before A: the carry cannot reach B, so the row is not understood
  const underMerged = t('<tr><td>Diploma</td><td>50%</td><td>60%</td><td rowspan="3">Case by case</td></tr><tr><td>Diploma</td><td>55%</td></tr><tr><td>Diploma</td><td>60%</td><td>70%</td></tr>')
  expect(entryManifest(underMerged, htmlToText)).toMatchObject({ status: 'unparsed' })
  expect(entryManifest(underMerged, htmlToText).reason).toMatch(/^a short row under a merged cell: Diploma \| 55%/)
  expect(entryManifest(t('<tr><td>Diploma</td><td>50%</td><td>60%</td><td>70%</td><td>80%</td></tr>'), htmlToText).reason).toMatch(/^a row has 5 cells, the header 4/)
  // a band table with no data rows
  expect(entryManifest(t(''), htmlToText).reason).toBe('a band table has no rows')
  // a short row with no merged cell above is read with blank trailing cells when its band cell reads as a band
  expect(entryManifest(t('<tr><td>Diploma</td><td>50%</td><td>60%</td><td>70%</td></tr><tr><td>Diploma</td><td>55%</td><td>65%</td></tr>'), htmlToText)).toMatchObject({ status: 'ok' })
  // a cell missing in the middle shifts a grade into the band column (as a browser shows it): not understood
  expect(entryManifest(t('<tr><td>Diploma</td><td>50%</td><td>60%</td><td>70%</td></tr><tr><td>Diploma</td><td>Average of 65%</td></tr>'), htmlToText).reason).toMatch(/^a short row whose band cell does not read as a band/)
  // with no full row to compare, a short row is not understood (fail closed)
  expect(entryManifest(t('<tr><td>Diploma</td><td>50%</td><td>60%</td></tr>'), htmlToText).status).toBe('unparsed')
})

test('on the D5 pages a short read, an omitted column, an omitted band or an under-count cannot pass', () => {
  const km = entryManifest(page('kuwait'), htmlToText), kr = rowsFor(km, 'KW')
  expect(verdict('kuwait', kr).v).toMatchObject({ status: 'complete', expected: 11, matched: 11 })
  expect(verdict('kuwait', kr.filter(x => x.benchmark_band !== '80%')).v.status).toBe('incomplete')  // one band row left out
  expect(verdict('kuwait', kr.map(x => x.benchmark_band === '80%' ? { ...x, benchmark_band: null } : x)).p.dropped.map(d => d.reason)).toEqual(['band_missing'])
  expect(verdict('kuwait', kr.filter(x => x.benchmark_band)).v.status).toBe('incomplete')  // Foundation and Fast Track left out
  const mm = entryManifest(page('mexico'), htmlToText), mr = rowsFor(mm, 'MX')
  expect(verdict('mexico', mr).v).toMatchObject({ status: 'complete', expected: 6, matched: 6 })
  const noCase = verdict('mexico', mr.filter(x => !/case-by-case/.test(x.min_grade)))
  expect(noCase.v.status).toBe('incomplete')  // the case-by-case column left out
  expect(noCase.v.omitted_columns.length).toBe(1)
  // the footnote is never a minimum
  const foot = verdict('kuwait', [...kr, { ...kr[0], study_level: 'Grading / Calculation System', min_grade: 'Overall average percentage', quote: km.footnotes[0] }])
  expect(foot.p.dropped.length).toBe(1)  // refused before the guard: never proposed
  expect(foot.p.rows.some(x => /Grading/.test(x.study_level))).toBe(false)
  // and a footnote row that passed the earlier checks would be a row the manifest cannot explain
  expect(entryCompleteness(km, [...verdict('kuwait', kr).p.rows, { ...verdict('kuwait', kr).p.rows[0], study_level: 'Grading / Calculation System', quote: km.footnotes[0] }]).status).toBe('incomplete')
})

test('every other stored page keeps its manifest and page text byte for byte (34 pages)', () => {
  let same = 0
  for (const [slug, b] of Object.entries(BEFORE)) {
    const h = page(slug), m = entryManifest(h, htmlToText)
    if (slug === 'kuwait' || slug === 'mexico') { expect(b.status, slug).toBe('unparsed'); expect(m.status, slug).toBe('ok'); continue }
    expect(md5(JSON.stringify(m)), slug).toBe(b.manifest_md5)
    expect(md5(entryTables(h, htmlToText).text), slug).toBe(b.text_md5)
    same++
  }
  expect(same).toBe(34)
})

test('the 12 runs complete under the guard stay complete with their own proposed rows, one identity per row (no re-read)', () => {
  let rows = 0
  for (const [slug, rs] of Object.entries(COMPLETE)) {
    const r = verdict(slug, rs.map(x => ({ ...x, country_name: NAME[x.country_code], min_value: x.min_value == null ? null : Number(x.min_value), confidence: Number(x.confidence) })))
    expect(r.p.dropped, slug).toEqual([])
    expect(r.v, slug).toMatchObject({ status: 'complete', expected: rs.length, matched: rs.length })
    expect(new Set(rs.map(x => x.row_hash)).size, slug).toBe(rs.length)
    rows += rs.length
  }
  expect(Object.keys(COMPLETE).length).toBe(12)
  expect(rows).toBe(189)
  // D1 unchanged: Hong Kong's Foundation and Fast Track rows carry no band
  expect(COMPLETE['hong-kong-sar-of-the-peoples-republic-of-china'].filter(x => /Foundation|Fast Track/.test(x.study_level)).map(x => x.benchmark_band)).toEqual([null, null])
})

test('D2 unchanged: the three non-country pages are still held before any AI read', () => {
  for (const slug of ['foundation-equivalencies', 'international-baccalaureate', 'global-assessment-certificate'])
    expect(entryNonCountryShape(entryManifest(page(slug), htmlToText), COUNTRIES), slug).toBeTruthy()
})
