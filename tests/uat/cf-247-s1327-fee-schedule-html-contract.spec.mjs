// Guards: Platform Admin / SS-Programme-Control 28 Nov 2026 06:54 AEDT (scoped Batch 08 exception for UNE and TAFE Queensland only: the existing Decision 162 fee schedule worker reads their two official HTML schedules; sources registered and qualified through Decision 162; whole-of-course totals parked)
// CF-247 s1327. supabase/functions/fee-schedule-etl/index.ts, html-rows.ts; supabase/migrations/20261130223000_cf247_s1327_fee_schedule_une_tafeqld.sql; scripts/fee-schedule-run.mjs; .github/workflows/fee-schedule-run.yml
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { transformSync } from 'esbuild'

const w = fs.readFileSync('supabase/functions/fee-schedule-etl/index.ts', 'utf8')
const sql = fs.readFileSync('supabase/migrations/20261130223000_cf247_s1327_fee_schedule_une_tafeqld.sql', 'utf8')
const wf = fs.readFileSync('.github/workflows/fee-schedule-run.yml', 'utf8')
const { htmlRows } = await import('data:text/javascript;base64,' + Buffer.from(transformSync(fs.readFileSync('supabase/functions/fee-schedule-etl/html-rows.ts', 'utf8'), { loader: 'ts', format: 'esm' }).code).toString('base64'))

test('only the two scoped HTML schedules are registered, each read only from the table its header rule names', () => {
  expect(w).toContain('const VERSION = "fee-schedule-etl-v0.9.1";')
  expect(w.match(/format: "html"/g)).toHaveLength(2)
  expect(w).toContain('une_2027: { provider_cricos: "00003G", fee_year: 2027, basis: "annual", format: "html", header: /\\bCRICOS\\b.*\\bFee\\b/i, bareAmounts: true,')
  expect(w).toContain('tafeqld_he_2027: { provider_cricos: "03020E", fee_year: 2027, basis: "annual", format: "html", header: /Cost \\(annual indicative\\)/i,')
  expect(w).toContain('if (isHtml && d.numPages === 0) throw Error("no table with the schedule\'s header was found; nothing read");')
  expect(w).toContain('contentType: isHtml ? "text/html" : "application/pdf"')
})

test('the HTML reader keeps the PDF row rule: whole-of-course tables are never read, footnote marks dropped, bare amounts signed only when wholly an amount', () => {
  const page = '<table><tr><th>Course Name</th><th>CRICOS Code</th><th>Cost (total)</th></tr><tr><td>Certificate III in X</td><td>110034H</td><td>$6,600</td></tr></table>'
    + '<table><tr><th>Course</th><th>CRICOS Code</th><th>Cost (annual indicative)</th></tr><tr><td>Associate Degree in Civil Engineering</td><td>065567A</td><td>$27,600</td></tr></table>'
  expect(htmlRows(page, /Cost \(annual indicative\)/i, false)).toEqual({ tables: 2, tablesRead: 1, rows: ['Associate Degree in Civil Engineering | 065567A | $27,600'] })
  const une = '<table><tr><th>Courses</th><th>Intakes</th><th>CRICOS</th><th>Fee</th></tr><tr><td><a href="#">Bachelor of Laws</a></td><td>1 &amp; 2 &amp; 3</td><td>052146G</td><td>37,152*</td></tr></table>'
  expect(htmlRows(une, /\bCRICOS\b.*\bFee\b/i, true).rows).toEqual(['Bachelor of Laws | 1 & 2 & 3 | 052146G | $37,152'])
})

test('rows can be limited to codes checked one by one; the rest are parked, never applied', () => {
  expect(w).toContain('const parsed = only ? { rows: parsedAll.rows.filter((r) => only.has(r.course_cricos)), rejected: parsedAll.rejected } : parsedAll;')
  expect(w).toContain('if (parsed.rows.length < (only ? 1 : 10)) throw Error("too few rows parsed; apply refused");')
  expect(wf).toContain('workflow_dispatch:')
  expect(wf).not.toMatch(/^  (push|schedule|pull_request):/m)   // the only trigger is workflow_dispatch (the input named schedule is a schedule key)
})

test('two sources registered and qualified through Decision 162 only; the apply keeps every check; evidence typed text/html', () => {
  expect(sql).toContain("'Decision-162-fee-schedule'")
  expect(sql).toContain("approved 28 Nov 2026 06:54 (Platform Admin scoped exception, s1327)")
  expect(sql).toContain("in ('00003G', '03020E')")
  expect(sql).toContain("if md5(d) <> 'd5bc73e93f83c950e5a37130a0488fd2' then")
  expect(sql).toContain("case when p_storage_path ~* ''\\.html?$'' then ''text/html'' else ''application/pdf'' end /* s1327 */")
  expect(sql).not.toMatch(/\bdrop\s+(table|function|view|column|index|schema|policy)\b|\bdelete\s+from\b|\btruncate\s+|create table|alter table/i)
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
})
