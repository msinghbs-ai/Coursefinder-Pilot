// Guards: CF-247 s1372, PC-20261128-INSTITUTIONAL-PARALLEL-READINESS and PC-20261128-2251/2319 (exact page scope for qualified container PDF reads, no unchanged repeat) and Standing Authority Charter 23 Nov 2026 item 1 (AER v2 proven-structure PDF readers pre-authorised): an untitled prospectus held at a marketing page is read on the pages that prove an entry table, continued while the same reader proves the run, and stays held when a held page touches a run
// s1372: entry-pdf-scope.ts entryProvenPageRuns. Documents are composed from the stored real-page fixtures (Federation, Curtin, VU, Macquarie, Sydney) and a prose page,
// in the shape of the three held container reads (Newcastle, UNSW College, NZSE: held at an early marketing page, no "Table X" title).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import zlib from 'node:zlib'
import { pdfTables } from '../../supabase/functions/coverage-sweep/pdf.ts'
import { entryProvenPageRuns, entryTablePageScope } from '../../supabase/functions/coverage-sweep/entry-pdf-scope.ts'

const fx = (n) => JSON.parse(zlib.gunzipSync(fs.readFileSync(`tests/fixtures/entry-matrix/pdf/${n}.json.gz`))).pages
const at = (ps, from) => ps.map((p, k) => ({ ...p, p: from + k }))
const prose = (p) => ({ p, width: 595, height: 842, rules: [], items: [{ x: 50, y: 700, w: 400, h: 10, s: 'Welcome to our university, a great place to begin your journey.' }] })
const read = (f) => fs.readFileSync(f, 'utf8')

test('a prospectus held at its first marketing page is read on its entry table pages; the text equals the table read alone', () => {
  const fed = fx('federation'), held = fx('mq_ug')[0], heldLater = fx('sydney')[0]
  const doc = [...at([held], 1), prose(2), ...at(fed, 3), prose(9), ...at([heldLater], 10)]
  expect(pdfTables(doc).status).toBe('unparsed')
  expect(entryTablePageScope(doc)).toBeNull()  // no "Table X - Academic Entry Requirements" title: s1253 finds nothing
  const pr = entryProvenPageRuns(doc, pdfTables)
  expect(pr.runs).toEqual([{ first: 3, last: 8 }])
  expect(pr.pages).toEqual([3, 4, 5, 6, 7, 8])
  expect(pr.held_left_out).toEqual([1, 10])
  expect(pr.left_out).toEqual([1, 2, 9, 10])
  const together = pdfTables(doc.filter((q) => pr.pages.includes(q.p)))
  expect(together.status).toBe('ok')
  // Federation's continuation pages (no header of their own) are read under page 3's header, exactly as the table read alone
  expect(together.text).toBe(pdfTables(fed).text)
})

test('two entry tables apart are two runs, each continued only while the reader proves it', () => {
  const doc = [prose(1), ...at(fx('curtin'), 2), prose(7), ...at(fx('vu'), 8)]
  const pr = entryProvenPageRuns(doc, pdfTables)
  expect(pr.runs).toEqual([{ first: 2, last: 6 }, { first: 8, last: 13 }])
  expect(pr.held_left_out).toEqual([])
})

test('fail closed: a held page touching a run, or no entry table at all, selects nothing', () => {
  const fed = fx('federation'), held = fx('mq_ug')[0], heldTable = fx('sydney')[0]
  expect(entryProvenPageRuns([...at([held], 1), ...at(fed, 2)], pdfTables)).toBeNull()       // held page before the table
  expect(entryProvenPageRuns([...at(fed, 1), ...at([heldTable], 7)], pdfTables)).toBeNull()  // a held ruled page after it (the rest of a table?)
  expect(entryProvenPageRuns([...at([held], 1), prose(2)], pdfTables)).toBeNull()            // no entry table
  // every stored real fixture the reader holds stays held (UQ, Macquarie, UNSW, Sydney: misaligned or unruled tables); none is read on a part of itself
  for (const n of ['uq', 'mq_ug', 'unsw', 'sydney']) expect(entryProvenPageRuns(fx(n), pdfTables)).toBeNull()
})

test('the worker tries it only after the whole read and the s1253 scope held, uses only a scope the same reader proves, and names the pages left out', () => {
  const idx = read('supabase/functions/coverage-sweep/index.ts')
  const s1253 = idx.indexOf('if (t.status !== "ok") { const sc = entryTablePageScope(pages);'), s1372 = idx.indexOf('if (t.status !== "ok") { const pr = entryProvenPageRuns(pages, pdfTables);')
  expect(s1253).toBeGreaterThan(0)
  expect(s1372).toBeGreaterThan(s1253)
  expect(idx).toContain('if (pr && pr.pages.length < pages.length) { const sp = pages.filter((q) => pr.pages.includes(q.p)), st = pdfTables(sp); if (st.status === "ok") { pages = sp;')
  expect(idx).toContain('held pages left out: ${pr.held_left_out.join(",") || "none"}')
  // entry_inspect (read only) shows the selection and what the reader makes of it, for qualification on the stored copies before any read
  const exp = read('supabase/functions/coverage-sweep/entry-pdf-export.ts')
  expect(exp).toContain('const pr = w.status === "ok" ? null : entryProvenPageRuns(pg, pdfTables)')
  expect(exp).toContain('proven_runs: pr ?')
  // a page selection only: no fetch, no model, no write in the scope module; the container's reader modules are unchanged in behaviour
  const sc = read('supabase/functions/coverage-sweep/entry-pdf-scope.ts')
  expect(sc).not.toMatch(/fetch\(|\.rpc\(|openrouter|upload\(/i)
  expect(sc).toMatch(/^import type \{ PdfPage \} from "\.\/pdf\.ts";$/m)
})
