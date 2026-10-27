// Guards: CF-247 AER v1.1 D4 (Platform Admin 27 Oct 2026 05:46): the reader is given the band tables' published cells from the manifest in printed order (repeated values, merged case-by-case cells and printed columns kept); a row whose quoted line publishes no minimum is dropped; the completeness guard still decides
// Record: admin docs/platform/aer-v1.1-build-log.md (D4 triage and design, 27 Oct 06:35). Fixtures: tests/fixtures/entry-matrix/rmit-stored/
// (stored copies, md5-checked) and held-reads-d4.json (the latest held read of each D4 page, from the run history).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryManifest, entryManifestDetail, entryCellList, entryDropNoMinimum, entryCompleteness, entryMatrixParsed, entryMatrixRequest, entryTables, ENTRY_PROMPT, ENTRY_PROMPT_VERSION } from '../../supabase/functions/coverage-sweep/entry.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'
const D = 'tests/fixtures/entry-matrix/rmit-stored/'
const page = (slug) => fs.readFileSync(`${D}${slug}.html`, 'utf8')
const HELD = JSON.parse(fs.readFileSync(`${D}held-reads-d4.json`, 'utf8')).pages
const COUNTRIES = JSON.parse(fs.readFileSync('tests/fixtures/entry-matrix/ref-countries.json', 'utf8')).countries
const NAME = Object.fromEntries(COUNTRIES.map(c => [c.a2, c.name]))
const CC = { denmark: 'DK', colombia: 'CO', indonesia: 'ID', nepal: 'NP', nigeria: 'NG', norway: 'NO', pakistan: 'PK', philippines: 'PH' }
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
// the worker's path for one read: reader checks, the no-minimum filter, then the guard
const run = (slug, rows) => {
  const h = page(slug), t = entryTables(h, htmlToText), d = entryManifestDetail(h, htmlToText)
  const p = entryMatrixParsed({ rows }, t.text, t.lines), nm = entryDropNoMinimum(d.manifest, d.emptyLines, p.rows)
  return { d, p, nm, v: entryCompleteness(d.manifest, nm.rows) }
}
// a read that follows the cell list exactly
const fromCells = (slug) => entryManifest(page(slug), htmlToText).entries.map(e => ({ country_code: CC[slug], country_name: NAME[CC[slug]], study_level: e.level,
  qualification_name: e.header, min_grade: e.cell, min_value: null, grade_scale: 'none', benchmark_band: e.band, course_name: null, conditions: {}, confidence: 0.95, quote: e.line }))
const cells = (slug) => entryManifest(page(slug), htmlToText).entries

test('Denmark: every band row is its own cell, a value repeated from the row above included (22 cells)', () => {
  const c = cells('denmark')
  expect(c.length).toBe(22)
  const stx = c.filter(e => /Studentereksamen/.test(e.header))
  expect(stx.filter(e => e.cell === 'Average of 7').map(e => e.band)).toEqual(['65%', '70%', '75%'])  // the same value on three rows, each its own minimum
  const list = entryCellList(entryManifest(page('denmark'), htmlToText))
  expect(list.split('\n').filter(l => /^\[\d+\]/.test(l)).length).toBe(22)
  expect(list).toContain('| band: 75% | column: Studentereksamen (stx) | cell: Average of 7')
})

test('Colombia, Nepal and Nigeria: the merged case-by-case column is listed on each band row it spans', () => {
  for (const [slug, n] of [['colombia', 9], ['nepal', 6], ['nigeria', 6]]) {
    const cbc = cells(slug).filter(e => /case-by-case/i.test(e.cell))
    expect(cbc.length, slug).toBe(n)
    expect(cbc.every(e => e.band && e.line.startsWith(e.level + ' | ' + e.band + ' |')), slug).toBe(true)
  }
  expect(cells('colombia').filter(e => /case-by-case/i.test(e.cell)).map(e => e.level)).toEqual([...Array(3).fill('Diploma/Associate degrees'), ...Array(6).fill('Bachelor degrees')])
})

test('Indonesia and Norway: each cell carries its printed column', () => {
  const id = cells('indonesia')
  expect(id.length).toBe(25)
  const at50 = id.filter(e => e.band === '50%').map(e => `${e.header.slice(0, 40)} = ${e.cell}`)
  expect(at50).toEqual(['Ijazah - Sekolah Menengah ATAS (Certific = Average of 60%', 'Ijazah - Sekolah Menengah ATAS (Certific = Average of 60%', 'Completion of the first year of a Bachel = CGPA 1.30'])
  expect(new Set(id.filter(e => e.band === '50%').map(e => e.header)).size).toBe(3)  // three printed columns, not one
  expect(id.some(e => /SMA2/.test(e.header) && e.band)).toBe(false)  // SMA2 publishes no band-row minimum
  expect(cells('norway').map(e => e.cell)).toEqual(['1', '2.0', '2.0', '2.5', '3', '3.5', '3.7', '4', '4.2', '4.5', '5.0'])
})

test('a read that follows the cell list passes the guard on every D4 page (the structure supports a complete read)', () => {
  for (const slug of Object.keys(CC)) {
    const r = run(slug, fromCells(slug))
    expect(r.p.dropped, slug).toEqual([])
    expect(r.nm.dropped, slug).toEqual([])
    expect(r.v.status, slug).toBe('complete')
  }
})

test('Pakistan and Philippines: the held reads, replayed, lose only their "Not applicable" rows and are complete', () => {
  for (const [slug, kept] of [['pakistan', 5], ['philippines', 7]]) {
    const rows = HELD[slug].map(x => ({ ...x, country_name: x.country_name || NAME[CC[slug]] }))
    const r = run(slug, rows)
    expect(r.nm.dropped.length, slug).toBe(6)
    expect(r.nm.dropped.every(d => d.reason === 'no_minimum_published' && /^Bachelor degrees \| \d+% \| Not applicable/.test(d.quote)), slug).toBe(true)
    expect(r.v, slug).toMatchObject({ status: 'complete', expected: kept, matched: kept })
  }
})

test('the other held reads, replayed, are still held: nothing that was incomplete now passes without a new read', () => {
  for (const slug of ['denmark', 'colombia', 'indonesia', 'nepal', 'nigeria', 'norway']) {
    const rows = HELD[slug].map(x => ({ ...x, country_name: x.country_name || NAME[CC[slug]] }))
    expect(run(slug, rows).v.status, slug).toBe('incomplete')
  }
})

test('the filter drops only rows on lines that publish nothing; a published line or a page without band tables is untouched', () => {
  const d = entryManifestDetail(page('pakistan'), htmlToText)
  expect(d.emptyLines.length).toBe(6)
  const pub = fromCells('pakistan')
  expect(entryDropNoMinimum(d.manifest, d.emptyLines, pub).dropped).toEqual([])
  const none = entryManifestDetail('<h1>UTS</h1><p>No tables</p>', htmlToText)
  expect(none.emptyLines).toEqual([])
  expect(entryDropNoMinimum(none.manifest, none.emptyLines, [{ quote: 'anything', country_code: 'MY' }]).rows.length).toBe(1)
  // the manifest itself is unchanged by D4 (its fingerprints are checked page by page in s133)
  expect(JSON.stringify(entryManifest(page('pakistan'), htmlToText))).toBe(JSON.stringify(d.manifest))
})

test('the request carries the cell list only when given; the worker gives it to one-slice pages and filters before the guard', () => {
  const m = entryManifest(page('denmark'), htmlToText)
  const withCells = entryMatrixRequest('m', { provider: 'RMIT', url: 'u', text: 'page', cells: entryCellList(m) }).messages[1].content
  expect(withCells).toContain('Published cells of the band table(s), in printed order (one row for each):\n[1] level: Foundation Studies')
  expect(entryMatrixRequest('m', { provider: 'RMIT', url: 'u', text: 'page' }).messages[1].content).not.toContain('Published cells')
  expect(ENTRY_PROMPT_VERSION).toBe('entry-matrix-v0.1.4')
  expect(ENTRY_PROMPT).toContain('When the message lists the published cells of a table, give exactly one row for each listed cell')
  expect(w).toContain('cells: slices.length === 1 ? entryCellList(stored.manifest) : undefined')
  expect(w).toContain('const nm = entryDropNoMinimum(stored.manifest, stored.emptyLines, parsed.rows);')
  expect(w.indexOf('const nm = entryDropNoMinimum(')).toBeLessThan(w.indexOf('const completeness = entryCompleteness(stored.manifest, rows);'))
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.48\.([7-9]|[1-9][0-9])"/)  // v0.48.7 or later (v0.48.8: s135)
})
