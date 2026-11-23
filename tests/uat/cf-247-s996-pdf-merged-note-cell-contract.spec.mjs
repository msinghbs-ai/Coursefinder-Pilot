// Guards: AER v2 proven-structure PDF_TABLE reader (Decision 276 clarified, Standing Authority Charter 23 Nov 2026): a cell merged across columns (a full-width note) is read as a note
// line only when no vertical rule runs at any column edge it crosses; it is never a cell under a column header (never a minimum); a vertical rule keeps failing closed (s996, University of Auckland).
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
const NOTE = /No direct entry for secondary qualifications/

test('University of Auckland A-I and J-Z are read; the merged note is a note line, never a cell', async () => {
  const r = await load('supabase/functions/coverage-sweep/pdf.ts', 'pdf996')
  for (const [f, notes] of [['auckland_ai', 8], ['auckland_jz', 4]]) {
    const x = r.pdfTables(pages(f))
    expect(x.status, `${f}: ${x.reason}`).toBe('ok')
    const lines = x.text.split('\n')
    const noteLines = lines.filter((l) => NOTE.test(l))
    expect(noteLines.length).toBe(notes)
    // every line that mentions the note is a "§ Note:" line; no table row (a line starting "|") carries it
    for (const l of noteLines) expect(l.startsWith('§ Note: ')).toBe(true)
    expect(lines.filter((l) => l.startsWith('|') && NOTE.test(l))).toEqual([])
  }
})

test('a vertical rule at a crossed edge still holds the document (fail closed)', async () => {
  const r = await load('supabase/functions/coverage-sweep/pdf.ts', 'pdf996b')
  const ps = pages('auckland_jz')
  const pg = ps[1], note = pg.items.find((i) => i.s === 'for secondary qualifications')
  // a rule through the note's row band at an inner column edge (x 313.0 is a column edge of this table)
  pg.rules.push({ o: 'v', x: 313.0, a: note.y - 8, b: note.y + 12 })
  const x = r.pdfTables(ps)
  expect(x.status).toBe('unparsed')
  expect(x.reason).toMatch(/crosses a column edge|merged cell/)
})

test('documents without a merged cell are read exactly as before', async () => {
  const r = await load('supabase/functions/coverage-sweep/pdf.ts', 'pdf996c')
  for (const f of ['vu', 'wsu', 'adelaide', 'curtin', 'federation']) expect(r.pdfTables(pages(f)).status).toBe('ok')
  for (const f of ['unsw', 'sydney', 'uq', 'mq_ug']) expect(r.pdfTables(pages(f)).status).toBe('unparsed')
})
