// Guards: CF-247 Lean AI Input Phase 1b step 1 (Platform Admin 14 Nov 2026 11:37, approving admin docs/platform/LEAN-AI-INPUT-PHASE1B-SECTION-SELECTION-DESIGN.md step 1): the deterministic,
// header-preserving block converter (lean-blocks-v1: numbered [B#] blocks with source offsets and heading paths, tables whole with their header rows) and the high-recall section selector
// (lean-sections-v1) used only by the offline recall check (worker mode lean_sections_eval) on labels independent of the AI reader (Layer 4 accepted rows, tested adapters): no AI call, no
// Firecrawl, nothing admitted, no reader's request changed; a page with no selection is never treated as lacking the field.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { LEAN_BLOCKS, LEAN_SECTIONS, blockMap, holds, leanBlocks, renderBlock, renderBlocks, selectSections } from '../../supabase/functions/coverage-sweep/lean-sections.ts'

const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261114031500_cf247_lean_sections_eval.sql', 'utf8')
const filler = '<p>' + 'Graduates work across many industries and roles. '.repeat(12) + '</p>'
const page = `<html><header>Site menu Apply now</header><body><h1>Bachelor of Science</h1><p>The Bachelor of Science builds skills in research.</p>` +
  `<dl><dt>Duration</dt><dd>3 years full-time</dd><dt>Campus</dt><dd>Townsville Bebegu Yumba</dd><dt>Start</dt><dd>February, July</dd></dl>${filler.repeat(60)}` +
  `<h2>Fees</h2><table><caption>International fees</caption><thead><tr><th>Year</th><th>Annual fee</th></tr></thead><tbody><tr><td>2027</td><td>A$47,990</td></tr></tbody></table><p>* Indicative, per year.</p>` +
  `<h2>Entry requirements</h2><h3>International students</h3><p>A completed secondary qualification equivalent to Year 12 with ATAR 70.</p><ul><li>IELTS 6.5 overall, no band below 6.0</li></ul>` +
  `<h2>How to apply</h2><p>Applications close 30 November 2026.</p><script>var x = "Applications close never";</script><footer>Contact us</footer></body></html>`

test('lean-blocks-v1: numbered [B#] blocks in page order with offsets into the stored page and heading paths; tables whole with caption and header row; chrome and scripts left out', () => {
  const lb = leanBlocks(page)
  expect(lb.converter).toBe(LEAN_BLOCKS)
  expect(LEAN_BLOCKS).toBe('lean-blocks-v1')
  lb.blocks.forEach((b, i) => { expect(b.id).toBe(`B${i + 1}`); expect(b.src_end).toBeGreaterThan(b.src_start) })
  const t = lb.blocks.find((b) => b.kind === 'table')
  expect(t.table.header).toEqual(['Year', 'Annual fee'])
  expect(t.table.caption).toBe('International fees')
  expect(t.text).toBe('Table: International fees\n| Year | Annual fee |\n| --- | --- |\n| 2027 | A$47,990 |')
  expect(page.slice(t.src_start, t.src_start + 6)).toBe('<table')
  expect(page.slice(t.src_end - 8, t.src_end)).toBe('</table>')
  const ielts = lb.blocks.find((b) => /IELTS/.test(b.text))
  expect(ielts.path).toEqual(['Bachelor of Science', 'Entry requirements', 'International students'])
  expect(renderBlock(ielts)).toMatch(/^\[B\d+ @\d+-\d+\] - IELTS 6\.5 overall/)
  expect(lb.blocks.some((b) => /Site menu|Contact us|Applications close never/.test(b.text))).toBe(false)
  const map = blockMap(lb.blocks)
  expect(map[ielts.id]).toEqual({ kind: 'item', level: 0, src_start: ielts.src_start, src_end: ielts.src_end, path: ielts.path })
  expect(leanBlocks(page)).toEqual(lb)  // deterministic
})

test('lean-sections-v1: a field takes its whole section, whole tables with header rows, label/value pairs, the heading path; facts far beyond a 24,000-character cut are kept', () => {
  const lb = leanBlocks(page)
  expect(lb.chars).toBeGreaterThan(24000)
  const fees = selectSections(lb, 'fees')
  expect(fees.selector).toBe(LEAN_SECTIONS)
  expect(fees.text).toContain('| Year | Annual fee |')
  expect(fees.text).toContain('| 2027 | A$47,990 |')
  expect(fees.text).toContain('* Indicative, per year.')
  expect(holds(fees.text, ['47990'])).toBe(true)
  expect(fees.chars).toBeLessThan(2000)
  expect(holds(selectSections(lb, 'duration').text, ['3 years full-time'])).toBe(true)
  expect(holds(selectSections(lb, 'campus').text, ['Townsville Bebegu Yumba'])).toBe(true)
  expect(holds(selectSections(lb, 'intakes').text, ['February', 'July'])).toBe(true)
  const entry = selectSections(lb, 'entry_requirements')
  expect(entry.text).toContain('## Entry requirements')
  expect(entry.text).toContain('### International students')
  expect(holds(entry.text, ['ATAR 70'])).toBe(true)
  expect(holds(selectSections(lb, 'english').text, ['IELTS 6.5 overall'])).toBe(true)
  expect(holds(selectSections(lb, 'deadline').text, ['Applications close 30 November 2026'])).toBe(true)
  // every selected line is a whole block of the page, with its id and offsets
  for (const line of entry.text.split('\n').filter((l) => l.startsWith('[B'))) expect(line).toMatch(/^\[B\d+ @\d+-\d+\] /)
  // no selection is reported, never acted on
  const none = selectSections(leanBlocks('<p>Nothing about the course here.</p>'), 'english')
  expect(none.no_selection).toBe(true)
})

test('gold matching: flat form, every part needed', () => {
  expect(holds('Start: February, July', ['February', 'July'])).toBe(true)
  expect(holds('Start: February', ['February', 'July'])).toBe(false)
  expect(holds('A$47,990 per year', ['47990'])).toBe(true)
  expect(holds('anything', [])).toBe(false)
})

test('worker mode lean_sections_eval: stored copies only, no AI, no Firecrawl, nothing admitted; no reader uses the selector', () => {
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v0.89.0";')
  expect(IX).toContain('import { LEAN_BLOCKS, LEAN_SECTIONS, holds, leanBlocks, renderBlocks, selectSections } from "./lean-sections.ts";')
  const a = IX.indexOf('if (mode === "lean_sections_eval")'), b = IX.indexOf('if (mode === "central_ai")')
  expect(a).toBeGreaterThan(0)
  const body = IX.slice(a, b)
  expect(body).toContain('svc_lean_sections_eval_next_v1')
  expect(body).toContain('svc_lean_sections_eval_record_v1')
  expect(body).toContain('readEvidenceCopy(c, String(it.storage_path))')
  expect(body).toContain('ai_calls: 0')
  expect(body).not.toMatch(/openrouter|chat\/completions|fcScrape|firecrawl|svc_fc_spend|fetch\(/i)
  // the selector is used only by the recall check
  expect(IX.split('selectSections(').length - 1).toBe(1)
})

test('the migration: independent labels only, settings for switch, batch and sample, catalogued job, read-only report; nothing dropped', () => {
  expect(MIG).toMatch(/^-- Replaces: nothing\.$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\.$/m)
  expect(MIG).toContain("comment on table pipeline.lean_section_eval_cases is 'CF-247 Lean AI Input Phase 1b step 1")
  expect(MIG).toContain("gold_source        text not null check (gold_source in ('aer_accepted', 'adapter'))")
  expect(MIG).toContain("where l.source_kind = 'course_page' and l.label = 'accepted'")
  for (const k of ['reading.lean_sections_eval_on', 'batch.lean_sections_eval', 'reading.lean_sections_eval_sample']) expect(MIG).toContain(`('pipeline', '${k}',`)
  expect(MIG).toContain("perform cron.schedule('lean-sections-eval', '*/5 * * * *', 'select security.lean_sections_eval_fire_v1()');")
  expect(MIG).toContain("('lean-sections-eval', 'Course pages', 42,")
  expect(MIG).toContain("grant execute on function public.svc_lean_sections_eval_next_v1(int) to service_role;")
  expect(MIG).toContain("grant execute on function public.svc_lean_sections_eval_record_v1(jsonb) to service_role;")
  expect(MIG).toContain("'ai_calls', 0, 'firecrawl_credits', 0")
  expect(MIG).not.toMatch(/^\s*(drop|truncate|delete)\b/im)
  expect(MIG).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
})
