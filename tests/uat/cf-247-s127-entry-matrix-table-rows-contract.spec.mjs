// Guards: CF-247 AER v1.1 (Platform Admin 26 Oct 2026 21:45 "RMIT first … prove the pattern"): band-ladder table rows are read and quote-checked whole, a merged or blank row label carried down; a page read again only by the Platform Admin, earlier result kept
// Record: admin docs/platform/aer-v1.1-build-log.md. First runs dropped 21 of 22 RMIT rows as quote_not_on_page because the level is
// named once for a group of rows. Fixture: tests/fixtures/entry-matrix/rmit-band-ladder.html (reconstructed from the live page).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryPageText, entryMatrixParsed, ENTRY_PROMPT, ENTRY_PROMPT_VERSION, ENTRY_TABLE_BASIS } from '../../supabase/functions/coverage-sweep/entry.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'
const html = fs.readFileSync('tests/fixtures/entry-matrix/rmit-band-ladder.html', 'utf8')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const m = fs.readFileSync('supabase/migrations/20261026008000_cf247_entry_matrix_reread.sql', 'utf8')
const row = (q, x = {}) => ({ country_code: 'BD', country_name: 'Bangladesh', study_level: 'Bachelor degrees', qualification_name: 'Higher School Certificate (HSC)',
  min_grade: 'Minimum CGPA of 4.2', min_value: 4.2, grade_scale: 'gpa', benchmark_band: '70%', course_name: null,
  conditions: { subject_minimums: [], best_n: null, alternatives: [] }, confidence: 0.95, quote: q, ...x })

test('each table row is one line; a blank or merged level cell takes the label above it', () => {
  const t = entryPageText(html, htmlToText)
  const lines = t.split('\n').map(s => s.trim())
  expect(lines).toContain('Bachelor degrees | 70% | Not applicable | Minimum CGPA of 4.2')
  expect(lines).toContain('Diploma/Associate degrees | 60% | Not applicable | Minimum CGPA of 3.9')  // &nbsp; counts as blank
  expect(lines).toContain('Level of study | Australian standard | Secondary School Certificate (SSC) | Higher School Certificate (HSC)')
  // rowspan written as merged cells gives the same rows
  expect(lines).toContain('Diploma/Associate degrees | 55% | Minimum CGPA of 3.7')
  // colspan repeats the cell across its columns
  expect(lines.some(l => l.startsWith('Note | Note | '))).toBe(true)
  // a label is never carried into another table, and a row with nothing else in it takes no label
  expect(lines).toContain('| Not carried from the table above')
  expect(lines.filter(l => /^Bachelor degrees \| /.test(l)).length).toBe(6)
  expect(lines.some(l => /^Bachelor degrees \| \| \|/.test(l))).toBe(false)
  // the page outside tables is unchanged
  expect(t).toContain('Academic entry requirements for students who have completed studies in Bangladesh.')
})

test('the whole-row quote is admitted against the row text and was not against plain text; an invented row is still dropped', () => {
  const q = 'Bachelor degrees | 70% | Not applicable | Minimum CGPA of 4.2'
  expect(entryMatrixParsed({ rows: [row(q)] }, htmlToText(html)).dropped[0].reason).toBe('quote_not_on_page')  // the 26 Oct failure
  expect(entryMatrixParsed({ rows: [row(q)] }, entryPageText(html, htmlToText)).rows.length).toBe(1)
  expect(entryMatrixParsed({ rows: [row('Bachelor degrees 70% Not applicable Minimum CGPA of 4.2')] }, entryPageText(html, htmlToText)).rows.length).toBe(1)
  // a grade from another row of the group is not on this row
  expect(entryMatrixParsed({ rows: [row('Bachelor degrees | 70% | Not applicable | Minimum CGPA of 4.4', { min_grade: 'Minimum CGPA of 4.4', min_value: 4.4 })] },
    entryPageText(html, htmlToText)).dropped[0].reason).toBe('quote_not_on_page')
  // a label is carried only inside its own table: the second table's level never meets the third table's row
  expect(entryMatrixParsed({ rows: [row('Diploma/Associate degrees | Not carried from the table above', { min_grade: null, min_value: null, grade_scale: 'none' })] },
    entryPageText(html, htmlToText)).dropped[0].reason).toBe('quote_not_on_page')
})

test('the worker reads stored HTML through the row text, says so, and the prompt describes the lines', () => {
  expect(w).toContain('const tb = entryTables(t, htmlToText, nameNumbers), md = entryManifestDetail(t, htmlToText); return { text: tb.text, lines: tb.lines, manifest: md.manifest, emptyLines: md.emptyLines, named: tb.named }')  // v0.50.1 (s145): numeric tables named, off under the completeness guard  // v0.48.7 (s134) adds the lines that publish nothing  // v0.48.2 (s128) and v0.48.3 (s129) keep the same row text
  expect(w).toContain('page_basis: ENTRY_TABLE_BASIS')
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(48\.[1-9]|49\.\d+|5\d\.\d+)"/)
  expect(ENTRY_TABLE_BASIS).toBe('table-rows-v1')
  expect(ENTRY_PROMPT_VERSION).toMatch(/^entry-matrix-v0\.1\.[1-9]$/)
  expect(ENTRY_PROMPT).toContain('Each table row on the page is given as one line with its cells separated by " | "')
})

test('read again: Platform Admin only, reason and log; proposed rows and pending items only; earlier result kept; nothing deleted', () => {
  expect(m).toContain("if current_user <> 'postgres' and (auth.uid() is null or security.current_role_rank() < 6) then raise exception 'Platform Admin required'")
  expect(m).toContain("if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'reason required'")
  expect(m).toContain("where run_id = r.id and status = 'proposed';")
  expect(m).toContain("where id = r.review_item_id and status = 'pending';")
  expect(m).toContain("where source_id = any(p_source_ids) and state = 'done' for update")
  expect(m).toContain('previous_results = previous_results || jsonb_build_array(')
  expect(m).toContain("add column if not exists previous_results jsonb not null default '[]'::jsonb")
  expect(m).toContain("values ('entry_matrix', 'reread', 'pipeline.entry_matrix_runs',")
  // rows superseded before the item, so the item's trigger has no proposed rows left to quarantine
  expect(m.indexOf("update catalogue.provider_entry_matrix set status = 'superseded'")).toBeLessThan(m.indexOf("update pipeline.layer4_review_items set status = 'superseded'"))
  expect(m).not.toMatch(/status = 'active'/)
  expect(m).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
  expect(m).toContain('grant execute on function public.admin_entry_matrix_reread(uuid[], text) to authenticated;')
})
