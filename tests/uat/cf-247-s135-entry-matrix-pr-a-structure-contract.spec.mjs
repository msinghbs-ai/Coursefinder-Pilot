// Guards: CF-247 AER PR A (Platform Admin 27 Oct 2026 14:35 and the scale decision that followed): a column tie broken only by a one-character word resolves (G1: Sri Lanka, Thailand, UK), a header row printed again inside the table is not a row (P2: Singapore, Foundation equivalencies), and a column of bare numbers with no printed scale holds the page before any AI read (R2: Norway, China Gao Kao, Germany Abitur); every other stored page keeps its manifest and the 25 admitted runs keep their verdicts and identities
// Record: admin docs/platform/aer-v1.1-build-log.md (27 Oct, PR A). Fixtures: tests/fixtures/entry-matrix/rmit-stored/ — the stored pages (s133),
// held-reads-pr-a.json (the last held read of Singapore, Sri Lanka, Thailand and the UK, exported read-only from the run history) and
// complete-25-rows.json (the rows of the 25 runs admitted on 27 Oct, exported read-only). No page is read again.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'
import { entryManifest, entryCompleteness, entryMatrixParsed, entryTables, entryUnscaledColumns, entryNonCountryShape } from '../../supabase/functions/coverage-sweep/entry.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'
const D = 'tests/fixtures/entry-matrix/rmit-stored/'
const page = (slug) => fs.readFileSync(`${D}${slug}.html`, 'utf8')
const INDEX = JSON.parse(fs.readFileSync(`${D}index.json`, 'utf8')).pages
const BEFORE = JSON.parse(fs.readFileSync(`${D}manifests-before-d5.json`, 'utf8')).pages
const HELD = JSON.parse(fs.readFileSync(`${D}held-reads-pr-a.json`, 'utf8')).pages
const C25 = JSON.parse(fs.readFileSync(`${D}complete-25-rows.json`, 'utf8')).pages
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')
const verdict = (slug, rows) => { const h = page(slug), t = entryTables(h, htmlToText), m = entryManifest(h, htmlToText), p = entryMatrixParsed({ rows }, t.text, t.lines); return { m, p, v: entryCompleteness(m, p.rows) } }
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('the held reads are of the stored copies (content hash as recorded)', () => {
  expect(Object.keys(HELD).sort()).toEqual(['singapore', 'sri-lanka', 'thailand', 'united-kingdom'])
  for (const [slug, r] of Object.entries(HELD)) expect(r.content_hash, slug).toBe(INDEX[slug].content_hash)
  for (const [slug, r] of Object.entries(C25)) expect(r.content_hash, slug).toBe(INDEX[slug].content_hash)
})

test('G1: Sri Lanka and Thailand resolve their tied columns and read complete; the UK is fully explained and short by the 2 cells its read left out', () => {
  expect(verdict('sri-lanka', HELD['sri-lanka'].rows).v).toMatchObject({ status: 'complete', expected: 13, matched: 13, unexplained: [], omitted_columns: [] })
  expect(verdict('thailand', HELD.thailand.rows).v).toMatchObject({ status: 'complete', expected: 13, matched: 13, unexplained: [], omitted_columns: [] })
  const uk = verdict('united-kingdom', HELD['united-kingdom'].rows).v
  expect(uk).toMatchObject({ status: 'incomplete', expected: 31, matched: 29, unexplained: [], omitted_columns: [] })
  expect(uk.reason).toBe('2 of 31 published minimums not read')
})

test('G1: a tie that every word cannot break stays not resolved, and a row naming the wrong one of two tied columns is not accepted', () => {
  const rows = HELD.thailand.rows
  // "Matayom" alone names both columns equally, single characters included: still not resolved
  const bare = verdict('thailand', rows.map((x, i) => i === 0 ? { ...x, qualification_name: 'Matayom' } : x)).v
  expect(bare.status).toBe('incomplete')
  expect(bare.unexplained.map(u => u.reason)).toEqual(['qualification_not_resolved'])
  // Matayom 6 named for the Matayom 5 cell resolves to Matayom 6, which does not hold that grade on that line
  const wrong = verdict('thailand', rows.map((x, i) => i === 0 ? { ...x, qualification_name: 'Matayom 6' } : x)).v
  expect(wrong.status).toBe('incomplete')
  expect(wrong.unexplained.map(u => u.reason)).toEqual(['wrong_column'])
})

test('P2: Singapore\'s repeated header row is not a row; 9 minimums; its held read completes; its page text is unchanged', () => {
  const m = entryManifest(page('singapore'), htmlToText)
  expect(m.status).toBe('ok')
  expect(m.entries.length).toBe(9)
  expect(m.entries.some(e => /^Level of study/i.test(e.line))).toBe(false)
  expect(md5(entryTables(page('singapore'), htmlToText).text)).toBe(BEFORE.singapore.text_md5)
  expect(verdict('singapore', HELD.singapore.rows).v).toMatchObject({ status: 'complete', expected: 9, matched: 9 })
})

test('P2: Foundation equivalencies loses its three repeated header rows (24 to 21 entries), keeps its page text, and is still held by D2 before any AI read', () => {
  const m = entryManifest(page('foundation-equivalencies'), htmlToText)
  expect(m.entries.length).toBe(21)
  expect(m.entries.some(e => /\| English Requirement 1 \|/.test(e.line))).toBe(false)
  expect(md5(entryTables(page('foundation-equivalencies'), htmlToText).text)).toBe(BEFORE['foundation-equivalencies'].text_md5)
  const COUNTRIES = JSON.parse(fs.readFileSync('tests/fixtures/entry-matrix/ref-countries.json', 'utf8')).countries
  expect(entryNonCountryShape(m, COUNTRIES)).toBeTruthy()
})

test('R2: Norway, China Gao Kao and Germany Abitur print bare numbers with no scale; no other stored page is flagged', () => {
  const flagged = {}
  for (const slug of Object.keys(INDEX)) { const u = entryUnscaledColumns(entryManifest(page(slug), htmlToText)); if (u.length) flagged[slug] = u }
  expect(flagged).toEqual({
    'china-peoples-republic-of': ['Gao Kao (National College Entrance Examination, NCEE) - Beijing'],
    germany: ['Abitur/Fachhochschulreife'],
    norway: ['Vitnemal fra den videregaende skolen / Vitnemal for videregaende opplaering'],
  })
  // a printed scale clears it, in the column heading or a grading row
  const t = (head, foot = '') => `<h1>Norway</h1><table><tr><th>Level of study</th><th>Australian standard</th><th>${head}</th></tr><tr><td>Diploma</td><td>50%</td><td>3.0</td></tr><tr><td>Bachelor</td><td>65%</td><td>4.0</td></tr>${foot}</table>`
  expect(entryUnscaledColumns(entryManifest(t('Vitnemal'), htmlToText))).toEqual(['Vitnemal'])
  expect(entryUnscaledColumns(entryManifest(t('Vitnemal (out of 6)'), htmlToText))).toEqual([])
  expect(entryUnscaledColumns(entryManifest(t('Vitnemal', '<tr><td colspan="3">Grading scale: 1-6</td></tr>'), htmlToText))).toEqual([])
  // a cell with words or a percentage is not a bare number
  expect(entryUnscaledColumns(entryManifest(t('Vitnemal').replace('<td>3.0</td>', '<td>60%</td>'), htmlToText))).toEqual([])
})

test('R2: the worker holds such a page before any AI read, as "held_unparsed" (terminal), naming the columns', () => {
  const i = w.indexOf('const unscaled = it.completeness_required === true && stored.manifest.status === "ok" && !nonCountry ? entryUnscaledColumns(stored.manifest) : [];')
  expect(i).toBeGreaterThan(0)
  expect(i).toBeLessThan(w.indexOf('const slices = entrySlices(page, Number(it.max_rows) || 400'))
  expect(w).toContain('if (it.completeness_required === true && (stored.manifest.status !== "ok" || nonCountry || unscaled.length)) {')
  expect(w).toContain('`no printed scale: bare numbers in ${unscaled.join("; ")}`')
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(48\.([8-9]|[1-9][0-9])|49\.\d+)"/)
})

test('every page PR A does not target keeps its manifest byte for byte (32 pages)', () => {
  let same = 0
  for (const [slug, b] of Object.entries(BEFORE)) {
    if (['kuwait', 'mexico', 'singapore', 'foundation-equivalencies'].includes(slug)) continue  // D5 (s133) and P2 above
    expect(md5(JSON.stringify(entryManifest(page(slug), htmlToText))), slug).toBe(b.manifest_md5)
    same++
  }
  expect(same).toBe(32)
})

test('the 25 admitted runs stay complete with their own rows, one identity per row; China and Germany are the only ones R2 would hold on a new read', () => {
  let rows = 0
  for (const [slug, r] of Object.entries(C25)) {
    const m = entryManifest(page(slug), htmlToText)
    const rs = r.rows.map(x => ({ ...x, country_name: m.heading, min_value: x.min_value == null ? null : Number(x.min_value), confidence: Number(x.confidence), course_name: null, conditions: {} }))
    const v = verdict(slug, rs)
    expect(v.p.dropped, slug).toEqual([])
    expect(v.v, slug).toMatchObject({ status: 'complete', expected: rs.length, matched: rs.length })
    expect(new Set(r.rows.map(x => x.row_hash)).size, slug).toBe(rs.length)
    rows += rs.length
  }
  expect(Object.keys(C25).length).toBe(25)
  expect(rows).toBe(363)
  expect(Object.keys(C25).filter(s => entryUnscaledColumns(entryManifest(page(s), htmlToText)).length).sort()).toEqual(['china-peoples-republic-of', 'germany'])
})
