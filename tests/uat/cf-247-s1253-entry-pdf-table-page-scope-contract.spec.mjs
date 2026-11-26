// Guards: Admin #1191 (S2-AER stored AER evidence inspection and shared PDF reader recovery, 26 Nov 2026 18:14 AEDT, Operating Model v1.26) and Standing Authority Charter 23 Nov 2026 item 1 (AER v2 proven-structure PDF readers pre-authorised; v1 essential correctness only)
// s1253: entry-pdf-scope.ts keeps the pages that carry a PDF's academic entry tables (Le Cordon Bleu Tables A and B, pages 15 to 32 of 34) and leaves out text pages and Table C; the worker uses it only
// when the whole-document read already holds and only when the same proven reader proves the scoped pages; entry_inspect (read only) takes a page range, bounded link targets and a scope check.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

async function load(file, name) {
  const out = path.join(os.tmpdir(), `${name}-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', [file, '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}
const fx = JSON.parse(fs.readFileSync('tests/fixtures/entry-matrix/pdf-scope/lcb-policy-pages.json', 'utf8'))
const rules = [{ o: 'h', y: 100, a: 0, b: 500 }, { o: 'v', x: 100, a: 0, b: 500 }]
const pages = () => fx.pages.map((p) => ({ p: p.p, width: p.width, height: p.height, rules, items: p.items.map(([x, y, w, s]) => ({ x, y, w, h: 10, s })) }))
const read = (f) => fs.readFileSync(f, 'utf8')

test('the stored LCB policy: Tables A and B (pages 15 to 32) are the scope; text pages, Table C and the page after it are not', async () => {
  const m = await load('supabase/functions/coverage-sweep/entry-pdf-scope.ts', 'pscope1253')
  expect(fx.pdf_pages).toBe(34)
  const sc = m.entryTablePageScope(pages())
  expect(sc.first).toBe(15)
  expect(sc.last).toBe(32)
  // each table keeps its own title, so Table A (international qualifications) and Table B (country of education) stay two tables
  expect(sc.titles.map((t) => t.page)).toEqual([15, 16])
  expect(sc.titles[0].title).toMatch(/^Table A .*International Qualifications/)
  expect(sc.titles[1].title).toMatch(/^Table B .*by Country of Education/)
})

test('a continuation page that draws no table ends the scope; a document with no entry table title has no scope', async () => {
  const m = await load('supabase/functions/coverage-sweep/entry-pdf-scope.ts', 'pscope1253b')
  const ps = pages().map((p) => (p.p === 17 ? { ...p, rules: [] } : p))
  expect(m.entryTablePageScope(ps)).toMatchObject({ first: 15, last: 16 })
  expect(m.entryTablePageScope(pages().filter((p) => p.p < 15 || p.p > 16))).toBeNull()
  expect(m.entryTablePageScope(pages().filter((p) => p.p === 33))).toBeNull()
})

test('the worker applies the scope only to a held read and only when the same reader proves it; entry_inspect stays read only and bounded', () => {
  const idx = read('supabase/functions/coverage-sweep/index.ts')
  expect(idx).toMatch(/if \(t\.status !== "ok"\) \{ const sc = entryTablePageScope\(pages\);/)
  expect(idx).toMatch(/st = pdfTables\(sp\); if \(st\.status === "ok"\) \{ pages = sp;/)
  expect(idx).toContain('const WORKER = "coverage-sweep-worker-v1.0.49"')
  const ins = idx.slice(idx.indexOf('if (mode === "entry_inspect")'), idx.indexOf('if (mode === "entry_ai")'))
  expect(ins).toContain('slice(0, 12);  // fixed: diagnostic batch cap')
  expect(ins).toContain('slice(0, 40) : undefined;  // fixed: diagnostic bound')
  expect(ins).not.toMatch(/\.rpc\(|upload\(|svc_entry_matrix_record|fetch\(/)  // no write, no fetch, no model
  const exp = read('supabase/functions/coverage-sweep/entry-pdf-export.ts')
  expect(exp).toMatch(/opt\.scopeCheck/)
})

test('the inspection script and workflow select stored sources by id with bounds and leave the permissions unchanged', () => {
  const s = read('scripts/aer-entry-inspect.mjs'), w = read('.github/workflows/aer-entry-inspect.yml')
  expect(s).toMatch(/pick\.length > 12/)
  expect(s).toMatch(/uuid|[0-9a-f]\{8\}/i)
  expect(w).toMatch(/source_ids:/)
  expect(w).toMatch(/IN_SOURCES/)
  expect(w).not.toMatch(/\$\{\{\s*(inputs|github\.event\.inputs)\.[a-z_]+\s*\}\}[^\n]*node scripts/)  // inputs reach the script through env, not the command line
})
