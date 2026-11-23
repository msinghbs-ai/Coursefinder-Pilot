// Guards: Platform Admin 24 Nov 2026 05:33 AEDT (S1-RM-Design s1017: $0 deterministic cell-to-row reader for proven ruled PDF course grids, AER v2 proven structure, Standing Authority Charter 23 Nov 2026 item 1; while the entry_matrices route has no qualified model, stored PDFs are read only by deterministic readers and never sent to a model)
// s1017: entry-ruled-grid.ts turns a proven ruled course-by-qualification table (University of Auckland) into grid cells read by entry-grid.ts; it fails closed on anything it cannot tie to one course and one column.
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
const pages = (f) => JSON.parse(zlib.gunzipSync(fs.readFileSync(`tests/fixtures/entry-matrix/pdf/${f}.json.gz`))).pages
const refsRaw = JSON.parse(fs.readFileSync('tests/fixtures/entry-matrix/ref-countries.json', 'utf8'))
const REFS = Array.isArray(refsRaw) ? refsRaw : refsRaw.countries
const QUALS = [{ code: 'GCE_A', aliases: ['gce a level', 'gce a levels', 'a level', 'a levels'] }, { code: 'IB_DP', aliases: ['international baccalaureate', 'international baccalaureate diploma', 'ib'] },
  { code: 'AP', aliases: ['advanced placement', 'ap exams'] }]
const HEADINGS = ['CRICOS=fact', 'ATAR=fact', 'Tertiary Admission Rank=fact', 'HKDSE=HK', 'Gao Kao=CN', 'GaoKao=CN', 'SAT=US', 'USA=US', 'Additional programme entry=fact']

test('University of Auckland A-I and J-Z are read cell by cell without the model; every row quotes a proven cell', async () => {
  const rg = await load('supabase/functions/coverage-sweep/entry-ruled-grid.ts', 'rg1017'), eg = await load('supabase/functions/coverage-sweep/entry-grid.ts', 'eg1017')
  for (const [f, minRows, skipped] of [['auckland_ai', 140, 1], ['auckland_jz', 220, 0]]) {
    const r = rg.ruledGridFromPages(pages(f))
    expect(r.reason, f).toBeNull()
    expect(r.skipped.length, `${f}: a piece with no course column is skipped, never guessed`).toBe(skipped)
    const g = eg.entryGridRead(r.tables, REFS, QUALS, eg.entryGridHeadingList(HEADINGS), {})
    expect(g.answer.rows.length, f).toBeGreaterThanOrEqual(minRows)
    expect(g.columns.filter((c) => c.kind === 'unknown').map((c) => c.head), f).toEqual([])
    const text = r.tables.flatMap((t) => t.cells.map((c) => `| ${t.labelHead}: ${c.label} | ${c.head}: ${c.value} |`)).join('\n')
    for (const row of g.answer.rows) {
      expect(text.includes(row.quote), row.quote).toBe(true)
      expect(row.qualification_name).not.toMatch(/^Additional programme entry/)
      expect(row.conditions.reader).toBe('pdf-grid-v1')
      expect(row.conditions.place.page).toBeGreaterThan(0)
    }
    // a course's cells stay in its own row: no course has two values under one heading
    const seen = new Map()
    for (const t of r.tables) for (const c of t.cells) { const k = `${c.section}|${c.label}|${c.head}`; expect(seen.has(k) && seen.get(k) !== c.value, k).toBe(false); seen.set(k, c.value) }
  }
})

test('tables of other shapes are not read as course grids (cell reader, aligned grid and held PDFs keep their path)', async () => {
  const rg = await load('supabase/functions/coverage-sweep/entry-ruled-grid.ts', 'rg1017b')
  for (const f of ['wsu', 'vu', 'adelaide', 'curtin', 'federation', 'unsw', 'sydney', 'uq', 'mq_ug']) expect(rg.ruledGridFromPages(pages(f)).tables, f).toEqual([])
})

test('it fails closed: a course with two values under one heading, or a row with no course, refuses the whole table', async () => {
  const rg = await load('supabase/functions/coverage-sweep/entry-ruled-grid.ts', 'rg1017c')
  const head = '| Programme | Alpha Board | Beta Board | Gamma Board |\n| --- | --- | --- | --- |\n§ Science\n'
  const ok = Array.from({ length: 6 }, (_, i) => `| Science | Programme: Bachelor of Course ${i} | Alpha Board: 7${i} | Beta Board: 8${i} | Gamma Board: 9${i} |`).join('\n')
  expect(rg.ruledGridTables(head + ok).reason).toBeNull()
  expect(rg.ruledGridTables(head + ok + '\n| Science | Programme: Bachelor of Course 1 | Alpha Board: 99 |').reason).toMatch(/two values/)
  expect(rg.ruledGridTables(head + ok + '\n| Science | Alpha Board: 50 |').reason).toMatch(/no Programme cell/)
  expect(rg.ruledGridTables(head + ok + '\n| Science | Programme: Bachelor of X | Delta: 5 |').reason).toMatch(/names no column/)
  expect(rg.ruledGridTables('| Country | Alpha |\n| --- | --- |\n| Country: A | Alpha: 1 |').tables).toEqual([])
})

test('the worker reads with no model only through a deterministic reader, and the database leases only stored PDFs while there is no model', () => {
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(ix).toContain('import { ENTRY_RULED_GRID_READER, ruledGridFromPages } from "./entry-ruled-grid.ts";')
  expect(ix).toContain('if (!cellRead && !gridRead && !ruledRead && (it.det_only === true || !it.model)) {')
  expect(ix).toContain('if (!cellRead && !gridRead && !ruledRead) await pool([...slices.keys()],')
  expect(ix).toContain('reading.entry_ruled_grid_reader_on')
  const mig = fs.readFileSync('supabase/migrations/20261124060000_cf247_s1017_ruled_grid_reader_det_only_lease.sql', 'utf8')
  expect(mig).toContain("e0.mime_type = 'application/pdf'")
  expect(mig).toContain("'model', case when v_det then null else v_model end")
  expect(mig).toContain("md5(pg_get_functiondef('public.svc_entry_matrix_next(integer)'::regprocedure)) <> 'edc670b607489b5b4a372ddc83c73f9f'")
  expect(mig).toContain('post-check: manual locks changed')
  expect(mig).toMatch(/^-- Replaces: /m)
  expect(mig).not.toMatch(/website_v2|zoho_edge|cron\.(schedule|unschedule|alter_job)|\bdrop (table|function|index|schema|view|trigger)|delete from |truncate /i)
})
