// Guards: Wave 2 Track B page reader (Platform Admin 18 Nov 2026 08:19): a deterministic HTML table extractor (no script, no network) feeds the same row pipeline as CSV, XLSX and JSON for format html_table, in the wizard's sample (step 3, AI Auto-Map) and the declarative runner's dry run (step 5), which writes nothing; empty and malformed tables are handled
// CF-247 S613. supabase/functions/_shared/cf247-html-table.js; _shared/cf247-layer1-read.ts (html_table); layer1-ai-induction-mapper 1.2.0; layer1-declarative-runner 1.0.1; src/lib/sample-parse.js; src/Layer1InductionWizard.jsx.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { extractHtmlTables, htmlTableRows, pickHtmlTable, decodeEntities } from '../../supabase/functions/_shared/cf247-html-table.js'
import { parseSample } from '../../src/lib/sample-parse.js'

const read = (p) => fs.readFileSync(p, 'utf8')

test.describe('unit: HTML table extraction', () => {
  test('a table with thead and tbody gives its header row and data rows; entities, inner tags and white space are cleaned', () => {
    const html = `<html><body><h1>PGWP</h1><table><caption>Eligible fields</caption><thead><tr><th>CIP code</th><th>Field of study</th></tr></thead>
      <tbody><tr><td>01.0101</td><td>Agricultural <b>business</b> &amp; management</td></tr>
      <tr><td> 11.0701 </td><td>Computer&nbsp;science<br>(general)</td></tr></tbody></table></body></html>`
    const [t] = extractHtmlTables(html)
    expect(t.caption).toBe('Eligible fields')
    expect(t.header_row_guess).toBe(1)
    expect(t.rows).toEqual([['CIP code', 'Field of study'], ['01.0101', 'Agricultural business & management'], ['11.0701', 'Computer science (general)']])
    const r = htmlTableRows(html, {})
    expect(r.headers).toEqual(['CIP code', 'Field of study'])
    expect(r.arrays).toHaveLength(2)
  })

  test('colspan repeats across columns and rowspan carries down', () => {
    const html = '<table><tr><th>Provider</th><th>Type</th><th>Status</th></tr><tr><td rowspan="2">Alpha College</td><td colspan="2">Registered</td></tr><tr><td>Approved</td><td>Fee cap</td></tr></table>'
    expect(extractHtmlTables(html)[0].rows).toEqual([['Provider', 'Type', 'Status'], ['Alpha College', 'Registered', 'Registered'], ['Alpha College', 'Approved', 'Fee cap']])
  })

  test('several tables (and a nested one) are numbered in the order they open; table_index and header_row choose', () => {
    const html = '<table><tr><td>layout<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table></td></tr></table><table><tr><td>note</td></tr><tr><th>X</th><th>Y</th></tr><tr><td>x1</td><td>y1</td></tr></table>'
    const all = extractHtmlTables(html)
    expect(all.map((t) => t.index)).toEqual([0, 1, 2])
    expect(htmlTableRows(html, { table_index: 1 }).arrays).toEqual([['1', '2']])
    const third = htmlTableRows(html, { table_index: 2 })
    expect(third.headers).toEqual(['X', 'Y'])
    expect(htmlTableRows(html, { table_index: 2, header_row: 1 }).headers).toEqual(['note', 'column_2'])
    expect(() => htmlTableRows(html, { table_index: 7 })).toThrow('table 7 was not found on the page')
  })

  test('empty and malformed tables: no table, an empty table, unclosed cells, rows and tables, stray angle brackets', () => {
    expect(extractHtmlTables('<p>No tables here</p>')).toEqual([])
    expect(() => htmlTableRows('<p>none</p>', {})).toThrow('no table was found on the page')
    expect(extractHtmlTables('<table></table>')[0].rows).toEqual([])
    expect(() => htmlTableRows('<table></table>', {})).toThrow('has no row 1')
    const broken = '<table><tr><th>Code<th>Name<tr><td>A1<td>Alpha < Beta<tr><td>B2<td>Bravo'
    expect(htmlTableRows(broken, {})).toMatchObject({ headers: ['Code', 'Name'], arrays: [['A1', 'Alpha < Beta'], ['B2', 'Bravo']] })
    expect(pickHtmlTable('<table><tr><td>only one cell</td></tr></table>')).toBeNull()
  })

  test('script, style and comments are never read; repeated header rows and empty rows are dropped; duplicate headers are told apart', () => {
    const html = '<script>document.write("<table><tr><td>evil</td></tr></table>")</script><style>td{}</style><!-- <table><tr><td>c</td></tr></table> -->' +
      '<table><tr><th>Name</th><th>Name</th><th></th></tr><tr><td>a</td><td>b</td><td>c</td></tr><tr><th>Name</th><th>Name</th><th></th></tr><tr><td></td><td></td><td></td></tr><tr><td>d</td><td>e</td><td>f</td></tr></table>'
    expect(extractHtmlTables(html)).toHaveLength(1)
    const r = htmlTableRows(html, {})
    expect(r.headers).toEqual(['Name', 'Name (2)', 'column_3'])
    expect(r.arrays).toEqual([['a', 'b', 'c'], ['d', 'e', 'f']])
    expect(decodeEntities('&#39;&#x2019;&unknown; &copy')).toBe("'’&unknown; ©")
  })

  test('integration: the wizard sample reads a saved page with the same code, picking the table with most rows and keeping its index', () => {
    const page = '<!doctype html><html><body><table><tr><th>Menu</th><th>Link</th></tr><tr><td>Home</td><td>/</td></tr></table>' +
      '<table><thead><tr><th>CIP code</th><th>Field</th></tr></thead><tbody>' + Array.from({ length: 30 }, (_, i) => `<tr><td>${String(i).padStart(2, '0')}.0101</td><td>Field ${i}</td></tr>`).join('') + '</tbody></table></body></html>'
    const s = parseSample('pgwp.html', page, 20)
    expect(s).toMatchObject({ columns: ['CIP code', 'Field'], total_rows: 30, table_index: 1, header_row: 1, tables: 2 })
    expect(s.rows).toHaveLength(20)
    expect(parseSample('blank.html', '<p>nothing</p>', 20)).toBeNull()
    expect(parseSample('a.csv', 'a,b\n1,2', 20)).toMatchObject({ columns: ['a', 'b'], total_rows: 1 })
  })
})

test('the reader, mapper, runner and wizard use the extractor for html_table; the dry run writes nothing', () => {
  const reader = read('supabase/functions/_shared/cf247-layer1-read.ts')
  expect(reader).toContain('import { htmlTableRows } from "./cf247-html-table.js";')
  expect(reader).toContain('if (format === "html_table") {')
  const mapper = read('supabase/functions/layer1-ai-induction-mapper/index.ts')
  expect(mapper).toContain('const VERSION = "1.2.0";')
  expect(mapper).toContain('if (!ind.source_url || !format) throw new Error(')
  expect(mapper).toContain('if (connector === "html_pages" && ti >= 0 && ti <= 50) src.table_index = ti;')
  const runner = read('supabase/functions/layer1-declarative-runner/index.ts')
  expect(runner).toContain('html_table: "text/html"')
  expect(runner).toContain('import { extractHtmlTables } from "../_shared/cf247-html-table.js";')
  expect(runner).toContain('tables_on_page: pageTables')
  expect(runner).toContain('"svc_layer1_declarative_stage_v1", { p_run_id: run, p_rows: rows.slice(i, i + cfg.chunk), p_write: false }')
  const html = read('supabase/functions/_shared/cf247-html-table.js')
  expect(html).not.toMatch(/\bfetch\(|eval\(|new Function|import\(/)
  const wizard = read('src/Layer1InductionWizard.jsx')
  expect(wizard).toContain("...(f.sample?.table_index!=null?{source:{table_index:f.sample.table_index,header_row:f.sample.header_row}}:{})")
  expect(wizard).toContain('accept=".csv,.tsv,.txt,.json,.html,.htm,text/csv,application/json,text/html"')
})
