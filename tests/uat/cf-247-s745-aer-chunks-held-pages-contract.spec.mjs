// Guards: S745 AER table row chunker regression suite (Platform Admin 19 Nov 2026 05:42 AEDT item 3, session S2-BOOST-AER): on the stored copies of the entry-matrix pages whose reads wait in Layer 4 (36 of the reads held on the D-R3 completeness gate, with every other waiting table page), no printed row is lost, doubled or rebuilt: every row of two or more cells is one row chunk or a header line, every single-cell caption row is carried as context, every quote is a line of the page text the checks read, and the run is deterministic.
// CF-247 S745. Fixtures tests/fixtures/aer-chunks/held (exported read only by aer-entry-inspect.yml, S742; manifest.json gives each page's source, content hash, run and the reader's own counts).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import zlib from 'node:zlib'
import crypto from 'node:crypto'
import { entryChunks, entryChunkCoverage } from '../../supabase/functions/coverage-sweep/entry-chunks.ts'
import { entryTables } from '../../supabase/functions/coverage-sweep/entry.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'

const B = 'tests/fixtures/aer-chunks/held/'
const man = JSON.parse(fs.readFileSync(`${B}manifest.json`, 'utf8')).pages
const quals = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/qualifications.json', 'utf8')).qualifications
const countries = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/country-refs.json', 'utf8'))
const national = JSON.parse(fs.readFileSync('tests/fixtures/aer-chunks/national-qualifications.json', 'utf8'))
const opt = { qualifications: quals, countries, national }
const load = (m) => zlib.gunzipSync(fs.readFileSync(B + m.file)).toString('utf8')

test('the fixtures are the exported stored copies, byte for byte, and cover the held gate reads that have table markup', () => {
  expect(man.length).toBe(48)
  for (const m of man) expect(crypto.createHash('sha256').update(load(m), 'utf8').digest('hex'), m.file).toBe(m.html_sha256)
  expect(man.filter((m) => m.rule === 'gate_incomplete').length).toBe(36)
  expect(man.every((m) => m.run_id && m.source_id && m.url && m.tables >= 1)).toBe(true)
})

for (const m of man) {
  test(`no row lost, doubled or rebuilt: ${m.file}`, () => {
    const html = load(m), et = entryTables(html, htmlToText, true), s = entryChunks(html, htmlToText, opt)
    const cov = entryChunkCoverage(s, et.forms)
    expect(cov.missing, 'a table line is not a row chunk').toEqual([])
    expect(cov.doubled, 'a row chunk appears twice').toEqual([])
    // independent of the chunker's line reading: every row of entryTables' grids
    const quotes = s.chunks.filter((c) => c.kind === 'table_row').map((c) => c.quote)
    // a row is a quote when its printed cells are the quote's cells in order: as printed ("70 | 11"), or with their column header in a table of named numbers
    // ("Program Required Entrance Rank: 70 | Indicative score required: 11"), or after a lead label carried onto the row
    const parts = quotes.map((q) => q.split(' | '))
    const isQuote = (cells) => parts.some((qp) => { const t = qp.slice(qp.length - cells.length); return t.length === cells.length && t.every((x, i) => x === cells[i] || x.endsWith(`: ${cells[i]}`)) })
    const headers = new Set(s.chunks.map((c) => c.header).filter(Boolean))
    const carried = s.chunks.flatMap((c) => [...c.context, c.quote]).join('\n')
    for (const g of et.grids) for (const r of g) {
      const line = r.join(' | ').trim(), cells = r.filter((x) => x).length
      if (cells >= 2) expect(quotes.some((q) => q === line || q.endsWith(` | ${line}`)) || isQuote(r.filter((x) => x)) || headers.has(line), `row lost: ${line.slice(0, 100)}`).toBe(true)
      else if (cells === 1) expect(carried.includes(r.find((x) => x)), `caption lost: ${line.slice(0, 100)}`).toBe(true)
    }
    // every quote is a line of the page text the checks read, never rebuilt
    const lines = new Set(et.text.split('\n').map((l) => l.trim()))
    for (const c of s.chunks) if (c.kind !== 'text_block') expect(lines.has(c.quote), `not on the page text: ${c.quote.slice(0, 100)}`).toBe(true)
    // deterministic
    expect(JSON.stringify(entryChunks(html, htmlToText, opt).chunks)).toBe(JSON.stringify(s.chunks))
  })
}

test('across the held gate reads the chunker yields at least the rows the reader read, so the rows it dropped are each in a chunk of their own', () => {
  let rows = 0, read = 0, lost = 0
  for (const m of man.filter((x) => x.rule === 'gate_incomplete')) {
    const s = entryChunks(load(m), htmlToText, opt); rows += s.tableRows; read += m.read_rows || 0; lost += m.dropped_lost || 0
  }
  // recorded 19 Nov 2026: 36 pages, 1,715 row chunks against 1,727 rows the reader proposed (several rows per printed line on some pages) and 238 printed rows it dropped
  expect(rows).toBeGreaterThanOrEqual(1700)
  expect(read).toBe(1727)
  expect(lost).toBe(238)
})
