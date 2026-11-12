// Guards: Decision 276 amendment 2 (Platform Admin 12 Nov 2026 17:20): table completeness is measured independently against the stored source document, not from the AI reader's own list of what it missed
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

async function wsu() {
  const { pdfTables } = await load('supabase/functions/coverage-sweep/pdf.ts', 'c-pdf')
  const cells = await load('supabase/functions/coverage-sweep/entry-cells.ts', 'c-cells')
  const c = await load('supabase/functions/coverage-sweep/aer-completeness.ts', 'c-comp')
  const t = pdfTables(JSON.parse(zlib.gunzipSync(fs.readFileSync('tests/fixtures/entry-matrix/pdf/wsu.json.gz'))).pages)
  const read = cells.entryCellRead(t.text, refs, Q.qualifications, { UK: 'GB' })
  return { t, rows: read.answer.rows, c }
}

test('a complete read: every country a table row names is recorded (WSU, 72 countries)', async () => {
  const { t, rows, c } = await wsu()
  const r = c.tableCompleteness(t.text, rows, refs, { UK: 'GB' })
  expect(r.method).toBe('table-row-countries-v1')
  expect(r.missing).toEqual([])
  expect(r.complete).toBe(true)
  expect(r.printed.length).toBeGreaterThanOrEqual(60)
})

test('a read that skips a country is incomplete whatever the reader reports: the country is named from the page alone', async () => {
  const { t, rows, c } = await wsu()
  const r = c.tableCompleteness(t.text, rows.filter((x) => x.country_code !== 'NP' && x.country_code !== 'DE'), refs, { UK: 'GB' })
  expect(r.missing).toEqual(['DE', 'NP'])
  expect(r.complete).toBe(false)
})

test('row labels: a label names one country or none; a board after the country keeps the country; prose lines are not rows', async () => {
  const { c } = await wsu()
  const idx = (await load('supabase/functions/coverage-sweep/entry-cells.ts', 'c-cells2')).entryCellCountryIndex(refs)
  expect(c.labelCountry('Nepal', idx)).toBe('NP')
  expect(c.labelCountry('India CBSE', idx)).toBe('IN')
  expect(c.labelCountry('International Baccalaureate', idx)).toBe(null)
  expect(c.tableRowLabels('Students from Nepal may apply.\n| Country: Nepal | UG: 70% |\n| Ghana | 60% |')).toEqual(['Nepal', 'Ghana'])
})
