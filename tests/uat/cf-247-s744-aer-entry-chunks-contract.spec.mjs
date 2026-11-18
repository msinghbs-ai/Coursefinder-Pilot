// Guards: S744 AER table row chunker (Platform Admin 19 Nov 2026 05:42 AEDT item 3, session S2-BOOST-AER; Decision 276: an AER v2 record source, no AER v1 reader changed): a dense entry table is split into one chunk per printed row with the headings, header line, row label and cells carried onto it; each chunk's quote is the row exactly as the page text prints it; every row is covered exactly once; nothing is fetched, written or asked of a model.
// CF-247 S744. Module supabase/functions/coverage-sweep/entry-chunks.ts.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryChunks, entryChunksOfText, entryChunkCoverage, entryChunkGroups, entryChunkUser } from '../../supabase/functions/coverage-sweep/entry-chunks.ts'
import { entryTables } from '../../supabase/functions/coverage-sweep/entry.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'

const SRC = fs.readFileSync('supabase/functions/coverage-sweep/entry-chunks.ts', 'utf8')
const page = (f) => fs.readFileSync(`tests/fixtures/entry-matrix/${f}`, 'utf8')
const quals = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/qualifications.json', 'utf8')).qualifications
const countries = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/country-refs.json', 'utf8'))
const national = JSON.parse(fs.readFileSync('tests/fixtures/aer-chunks/national-qualifications.json', 'utf8'))
const opt = { qualifications: quals, countries, national }

test('one chunk per printed table row; the header line is context, not a row; every row covered exactly once', () => {
  for (const f of ['rmit-stored/china-peoples-republic-of.html', 'rmit-stored/foundation-equivalencies.html', 'rmit-band-ladder.html', 'rmit-cambodia.html', 'rmit-canada.html']) {
    const html = page(f), et = entryTables(html, htmlToText, true), s = entryChunks(html, htmlToText, opt)
    const cov = entryChunkCoverage(s, et.forms)
    expect(cov.missing, f).toEqual([])
    expect(cov.doubled, f).toEqual([])
    expect(cov.covered, f).toBe(cov.expected)
    expect(s.tableRows, f).toBe(cov.expected)
    // independent of the chunker's own header rule: rows plus header lines are every row of entryTables' grids
    expect(s.tableRows + s.headerLines, f).toBe(et.grids.reduce((a, g) => a + g.length, 0))
    for (const c of s.chunks.filter((x) => x.kind === 'table_row')) expect(et.forms.some((x) => x.split('\n')[0].trim() === c.quote), `${f}: a header line is a row`).toBe(false)
  }
  const s = entryChunks(page('rmit-stored/foundation-equivalencies.html'), htmlToText, opt)
  // 27 tables, 201 printed rows: 28 header lines (table 24 prints its header row twice; the copy is a header, not a requirement) and 173 requirement rows
  expect(s.tables).toBe(27)
  expect(s.headerLines).toBe(28)
  expect(s.tableRows).toBe(173)
})

test('each quote is the row exactly as the page text the checks read prints it (never rebuilt)', () => {
  // the structured page text the entry-matrix checks read (entryTables with structure forms: a table of named numbers prints "Head: value" cells)
  for (const f of ['rmit-stored/china-peoples-republic-of.html', 'rmit-band-ladder.html', 'rmit-stored/foundation-equivalencies.html']) {
    const html = page(f), text = entryTables(html, htmlToText, true).text, s = entryChunks(html, htmlToText, opt)
    const lines = new Set(text.split('\n').map((l) => l.trim()))
    for (const c of s.chunks) if (c.kind !== 'text_block') expect(lines.has(c.quote), `${f}: ${c.quote.slice(0, 80)}`).toBe(true)
  }
})

test('the headings, the header line and the row label are carried onto each row; a page title with " | " is a heading, never a row', () => {
  const s = entryChunks(page('rmit-stored/china-peoples-republic-of.html'), htmlToText, opt)
  const r = s.chunks.filter((c) => c.kind === 'table_row')
  expect(r.length).toBe(12)
  expect(r.every((c) => c.context.some((h) => h.includes("China, People's Republic of")))).toBe(true)
  expect(r.every((c) => c.header?.startsWith('Level of study | Australian standard | Gao Er'))).toBe(true)
  expect(r[0].label).toBe('Foundation Studies')
  expect(r[0].quote).toBe('Foundation Studies | Not applicable | Minimum average of 60% | Minimum average of 50% | Not applicable')
  expect(r.some((c) => c.quote.startsWith('China | Academic Entry Requirements'))).toBe(false)
  // the country the headings name, when the row label is a level
  expect(r.every((c) => c.country === 'CN')).toBe(true)
  // a blank or merged row label takes the label above it (entryTables' carried cells)
  const b = entryChunks(page('rmit-band-ladder.html'), htmlToText, opt).chunks.filter((c) => c.kind === 'table_row')
  expect(b.filter((c) => c.label === 'Bachelor degrees').length).toBe(6)
})

test('cells keep their column header by position, with the minimum each prints', () => {
  const r = entryChunks(page('rmit-stored/china-peoples-republic-of.html'), htmlToText, opt).chunks.filter((c) => c.kind === 'table_row')[0]
  expect(r.cells.map((c) => c.head)).toEqual(['Level of study', 'Australian standard', 'Gao Er (Senior Middle 2) (Year11)', 'Gao San (Senior Middle 3)(Year 12)', 'Gao Kao (National College Entrance Examination, NCEE) - Beijing'])
  expect(r.cells[1].text).toBe('Not applicable')
  expect(r.cells[4].text).toBe('Not applicable')
  expect(r.cells[2].minimum).toMatchObject({ value: 60, scale: 'percentage' })
  expect(r.cells[3].minimum).toMatchObject({ value: 50, scale: 'percentage' })
  expect(r.cells[1].minimum).toBeNull()
})

test('Markdown tables and labelled lists chunk the same way; prose under a heading is a bounded text block', () => {
  const md = ['# Entry requirements by country', '## Undergraduate', '| Country | Qualification | Minimum |', '| India | CBSE | 65% |', '| Malaysia | STPM | CGPA 3.0 |', '',
    'Argentina: Bachillerato with a 7 average', 'Brazil: Certificado de Ensino Medio', '', 'Applicants are assessed case by case.'].join('\n')
  const s = entryChunksOfText(md, ['| Country | Qualification | Minimum |\n| India | CBSE | 65% |'], [], opt)
  expect(s.tableRows).toBe(2)
  expect(s.headerLines).toBe(1)
  expect(s.listLines).toBe(2)
  expect(s.textBlocks).toBe(1)
  const rows = s.chunks.filter((c) => c.kind === 'table_row')
  expect(rows[0].context).toEqual(['# Entry requirements by country', '## Undergraduate'])
  expect(rows[0].country).toBe('IN')
  expect(s.chunks.find((c) => c.kind === 'list_line')).toMatchObject({ label: 'Argentina', country: 'AR', quote: 'Argentina: Bachillerato with a 7 average' })
})

test('rows are grouped for model calls within one table only, and the request lays out numbered rows to answer one by one', () => {
  const s = entryChunks(page('rmit-stored/foundation-equivalencies.html'), htmlToText, opt)
  const g = entryChunkGroups(s.chunks, 6)
  expect(g.every((x) => x.length <= 6 && new Set(x.map((c) => c.table)).size === 1)).toBe(true)
  expect(g.reduce((a, x) => a + x.length, 0)).toBe(s.chunks.length)
  const u = entryChunkUser('RMIT University', 'https://www.rmit.edu.au/x', g[0])
  expect(u).toContain('Table header: ')
  expect(u).toContain(`[R${g[0][0].n}] ${g[0][0].quote}`)
  expect(u).toContain('answer every row, quoting only within it')
})

test('the module is deterministic and self-contained: no fetch, no write, no model call, no word list of qualifications in code', () => {
  const CODE = SRC.split('\n').filter((l) => !l.trim().startsWith('//')).join('\n')
  expect(CODE).not.toMatch(/fetch\(|rpc\(|storage\.|openrouter|\.from\(|insert |update /i)
  expect(CODE).not.toMatch(/gaokao|cbse|stpm|hkdse|atar/i)
  expect(SRC).toContain('National qualifications (ATAR, Gaokao,')  // named in the header comment only, as the list the caller passes
  const html = page('rmit-band-ladder.html')
  expect(JSON.stringify(entryChunks(html, htmlToText, opt).chunks)).toBe(JSON.stringify(entryChunks(html, htmlToText, opt).chunks))
})
