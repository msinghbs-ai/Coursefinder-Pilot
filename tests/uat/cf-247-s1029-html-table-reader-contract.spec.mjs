// Guards: Standing Authority Charter 23 Nov 2026 item 1 (AER v2 HTML_TABLE proven-structure readers pre-authorised) and Platform Admin 24 Nov 2026 05:33 AEDT ("$0 deterministic cell-to-row adapter for proven PDF_TABLE / HTML_TABLE grids"); S2-RM-Design AER v2 Batch 1 (s1029): a stored HTML entry table is read without the model only when its markup proves a worded header, a country or qualification first column and a named study level, and the read fails closed otherwise
// s1029: entry-html-table.ts turns each proven HTML table into the PDF cell reader's lines (entry-cells.ts), so every row goes through entryMatrixParsed like the other deterministic readers.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import zlib from 'node:zlib'
import { execFileSync } from 'node:child_process'

async function load(file, name) {
  const out = path.join(os.tmpdir(), `${name}-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', [file, '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}
const page = (f) => zlib.gunzipSync(fs.readFileSync(`tests/fixtures/entry-matrix/html-table/${f}.html.gz`)).toString('utf8')
const refsRaw = JSON.parse(fs.readFileSync('tests/fixtures/entry-matrix/ref-countries.json', 'utf8'))
const REFS = Array.isArray(refsRaw) ? refsRaw : refsRaw.countries
const QUALS = [{ code: 'GCE_A', aliases: ['gce a level', 'gce a levels', 'a level', 'a levels'] }, { code: 'IB_DP', aliases: ['international baccalaureate', 'international baccalaureate diploma', 'ib'] },
  { code: 'CIE', aliases: ['cambridge international examinations', 'cambridge international'] }, { code: 'AP', aliases: ['advanced placement', 'advanced placement international diploma'] }]
// the study-level words of security.entry_level_map_v1 (live 24 Nov 2026): a level the reader names must be one the database maps
const LEVEL_MAP = /phd|doctor|master|postgrad|graduate diploma|graduate certificate|associate degree|bachelor|degree|undergrad|advanced diploma|diploma|foundation|pathway|certificate/i

test('Lincoln University: the degree table is read cell by cell with its level from the heading; the tables with no level heading are skipped, never guessed', async () => {
  const ht = await load('supabase/functions/coverage-sweep/entry-html-table.ts', 'ht1029'), en = await load('supabase/functions/coverage-sweep/entry.ts', 'en1029')
  const r = ht.entryHtmlTableRead(page('lincoln'), REFS, QUALS, {}, { minRows: 5 })
  expect(r).not.toBeNull()
  expect(r.tables.map((t) => [t.index, t.level_from])).toEqual([[0, 'heading']])
  expect(r.tables[0].levels[0]).toMatch(LEVEL_MAP)
  expect(r.skipped.map((s) => s.reason)).toEqual(['html_table_level_unmapped', 'html_table_level_unmapped'])
  expect(r.answer.rows.length).toBeGreaterThanOrEqual(40)
  const lines = new Set(r.text.split('\n'))
  for (const x of r.answer.rows) {
    expect(x.conditions.reader).toBe('html-table-v1')
    // every quote is the start of one proven cell line ("| Country: Australia | <level>: ... |")
    expect([...lines].some((l) => l.startsWith(`| ${x.quote}`) || l.includes(x.quote))).toBe(true)
  }
  const parsed = en.entryMatrixParsed(r.answer, r.text, Object.assign([], { forms: [] }), { qualifications: QUALS, globalTokens: ['all countries'] })
  expect(parsed.dropped).toEqual([])
  expect(parsed.rows.length + (parsed.qualification_rows || []).length).toBe(r.answer.rows.length)
  // an "All countries" row is read by its qualification (qualification-first), not dropped as an unknown country
  expect((parsed.qualification_rows || []).map((q) => q.qualification_code)).toContain('IB_DP')
  const ib = r.answer.rows.find((x) => /International Baccalaureate/.test(x.qualification_name))
  expect(ib.min_value).toBe(24)
  // the cells it cannot name stay named drops, so the read is not called complete
  expect(r.dropped.map((d) => d.reason)).toEqual(['unknown_country', 'unknown_country'])
  expect(ht.entryHtmlTableCompleteness(r).status).toBe('incomplete')
})

test('Yoobee and KBS: study levels from the column headers; every proven cell gives a row, and the read is complete', async () => {
  const ht = await load('supabase/functions/coverage-sweep/entry-html-table.ts', 'ht1029b'), en = await load('supabase/functions/coverage-sweep/entry.ts', 'en1029b')
  for (const [f, minRows, minWithValue] of [['yoobee', 90, 1], ['kbs', 95, 40]]) {
    const r = ht.entryHtmlTableRead(page(f), REFS, QUALS, {}, { minRows: 5 })
    expect(r, f).not.toBeNull()
    expect(r.tables.every((t) => t.level_from === 'column' && t.levels.every((l) => LEVEL_MAP.test(l))), f).toBe(true)
    expect(r.answer.rows.length, f).toBeGreaterThanOrEqual(minRows)
    expect(r.answer.rows.filter((x) => x.min_value != null).length, f).toBeGreaterThanOrEqual(minWithValue)
    expect(ht.entryHtmlTableCompleteness(r).status, f).toBe('complete')
    const parsed = en.entryMatrixParsed(r.answer, r.text, Object.assign([], { forms: [] }), { qualifications: QUALS, globalTokens: ['all countries'] })
    expect(parsed.dropped, f).toEqual([])
  }
})

test('fails closed: per-country tables with no header row, a numeric header, a row wider than its header and an unnamed level are not read', async () => {
  const ht = await load('supabase/functions/coverage-sweep/entry-html-table.ts', 'ht1029c')
  // University of Wollongong prints one small table per country with no header row (an accordion shape this reader does not prove)
  expect(ht.entryHtmlTableRead(page('uow'), REFS, QUALS, {}, { minRows: 5 })).toBeNull()
  const rows = (n, w) => Array.from({ length: n }, (_, i) => `<tr>${Array.from({ length: w }, (_, j) => `<td>${j === 0 ? ['India', 'China', 'Kenya', 'Ghana', 'Nepal', 'Chile'][i % 6] : 'Year 12 with 70%'}</td>`).join('')}</tr>`).join('')
  const table = (head, body) => `<h2>Undergraduate entry</h2><table><thead><tr>${head.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${body}</tbody></table>`
  expect(ht.htmlTableLines(table(['Country', 'Requirement'], rows(6, 2))).tables.length).toBe(1)
  expect(ht.htmlTableLines(table(['Country', '2026'], rows(6, 2))).skipped[0].reason).toBe('html_table_no_worded_header')
  expect(ht.htmlTableLines(table(['Country', 'Requirement'], rows(6, 3))).skipped[0].reason).toBe('html_table_row_wider_than_header')
  expect(ht.htmlTableLines(table(['Programme', 'Requirement'], rows(6, 2))).skipped[0].reason).toBe('html_table_first_column_not_country_or_qualification')
  expect(ht.htmlTableLines(table(['Country', 'Requirement'], rows(3, 2))).skipped[0].reason).toBe('html_table_too_few_rows')
  const noLevel = `<h2>Entry by country</h2><table><thead><tr><th>Country</th><th>Requirement</th></tr></thead><tbody>${rows(6, 2)}</tbody></table>`
  expect(ht.htmlTableLines(noLevel).skipped[0].reason).toBe('html_table_level_unmapped')
})


test('s1041 NZ: country headings prove two-row and three-column headerless HTML grids without AI', async () => {
  const ht = await load('supabase/functions/coverage-sweep/entry-html-table.ts', 'ht1041')
  // Representative structures from the official Wintec and Otago Polytechnic country sections.
  const wintec = '<h2>Argentina</h2><table><tbody>' +
    '<tr><td>Certificate (level 4)</td><td>Título de Técnico Auxiliar</td></tr>' +
    '<tr><td>Diploma (level 5)</td><td>Título de Bachiller/Bachillerato</td></tr>' +
    '<tr><td>Degree level</td><td>One year of successful undergraduate-level study at a recognised tertiary institution</td></tr>' +
    '</tbody></table>'
  const otago = '<h3>Australia</h3><table><tbody>' +
    '<tr><td>NCEA Level 2</td><td>Certificate/Diploma Level</td><td>Successful completion of Year 12</td></tr>' +
    '<tr><td>NCEA Level 3</td><td>Degree Level</td><td>Successful completion of Year 12, AND ATAR score of 65 or above</td></tr>' +
    '</tbody></table>'
  for (const [html, country, n] of [[wintec, 'AR', 3], [otago, 'AU', 2]]) {
    const r = ht.entryHtmlTableRead(html, REFS, QUALS, {}, { minRows: 5 })
    expect(r).not.toBeNull()
    expect(r.tables).toHaveLength(1)
    expect(r.tables[0].level_from).toBe('row')
    expect(r.answer.rows).toHaveLength(n)
    expect(r.answer.rows.every((x) => x.country_code === country && x.conditions.reader === 'html-table-v1')).toBe(true)
    expect(ht.entryHtmlTableCompleteness(r).status).toBe('complete')
  }
})

test('s1041 NZ: fail closed on prose countries, unknown headings, absent row levels and single-row tables', async () => {
  const ht = await load('supabase/functions/coverage-sweep/entry-html-table.ts', 'ht1041-negative')
  const rows = '<table><tr><td>Diploma level</td><td>Year 12</td></tr><tr><td>Degree level</td><td>ATAR of 75</td></tr></table>'
  expect(ht.entryHtmlTableRead('<h2>Entry requirements for Argentina</h2>' + rows, REFS, QUALS)).toBeNull()
  expect(ht.entryHtmlTableRead('<h2>Unknownland</h2>' + rows, REFS, QUALS)).toBeNull()
  expect(ht.entryHtmlTableRead('<h2>Australia</h2><table><tr><td>Entry</td><td>Year 12</td></tr><tr><td>Degree level</td><td>ATAR of 75</td></tr></table>', REFS, QUALS)).toBeNull()
  expect(ht.entryHtmlTableRead('<h2>Australia</h2><table><tr><td>Degree level</td><td>ATAR of 75</td></tr></table>', REFS, QUALS)).toBeNull()
})

test('the worker reads a proven HTML table in its own branch and leaves every other path as it was; the lease takes stored HTML', async () => {
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(ix).toContain('import { ENTRY_HTML_TABLE_READER, entryHtmlTableCompleteness, entryHtmlTableRead } from "./entry-html-table.ts";')
  expect(ix).toContain('const WORKER = "coverage-sweep-worker-v1.0.38";')
  expect(ix).toContain('rawHtmlOf.set(path, t);  // s1029')
  // the branch runs after the page's parse options and before any model slice; it records and returns, so a page it does not prove goes on unchanged
  const at = ix.indexOf('const htmlRead = '), parse = ix.indexOf('const parseOpts = { countryAliases:'), slices = ix.indexOf('const slices = entrySlices(page,')
  expect(at > parse && at < slices).toBe(true)
  expect(ix).toContain('Number(ws["reading.entry_html_table_reader_on"]) >= 1')
  expect(ix).toContain('const hp = entryMatrixParsed(htmlRead.answer, htmlRead.text,')
  expect(ix).toContain('if (it.completeness_required === true && hc.status !== "complete") {')
  // the held path for a page no deterministic reader proves is untouched (s1017)
  expect(ix).toContain('if (!cellRead && !gridRead && !ruledRead && (it.det_only === true || !it.model)) {')
  const mig = fs.readFileSync('supabase/migrations/20261124140000_cf247_s1029_aer_html_table_reader.sql', 'utf8')
  expect(mig).toMatch(/^-- Replaces: /m)
  expect(mig).toMatch(/^-- Retires: /m)
  expect(mig).toContain("md5(pg_get_functiondef('public.svc_entry_matrix_next(integer)'::regprocedure)) <> '51f11c9ed46f2333f325d4a0821062c2'")
  expect(mig).toContain("or (e0.mime_type ~* 'html' and security.pipeline_num_v1('reading.entry_html_table_reader_on', 1) >= 1)")
  for (const k of ['reading.entry_html_table_reader_on', 'reading.entry_html_table_min_rows']) expect(mig).toContain(`'${k}'`)
  // the Batch 1 re-read goes through the logged Platform Admin path, which supersedes only proposed rows and pending items
  expect(mig).toContain('public.admin_entry_matrix_reread(array[')
  expect(mig).toContain("raise exception 'post-check: an active entry row changed'")
})
