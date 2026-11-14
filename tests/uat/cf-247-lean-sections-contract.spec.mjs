// Guards: CF-247 Lean AI Input Phase 1b step 1 (Platform Admin 14 Nov 2026 11:37 and 12:29, admin docs/platform/LEAN-AI-INPUT-PHASE1B-SECTION-SELECTION-DESIGN.md step 1): the high-recall section selector
// (lean-sections-v1) has no block format of its own: it selects from the platform's one [B#] block contract (aer-v2.ts aerV3Blocks, AER_V3_INPUT lean-blocks-v1, built on lean-input.ts leanText lean-md-v1),
// whole tables with their header-carrying rows, the heading path and page data; it is used only by the offline recall check (worker mode lean_sections_eval) on labels independent of the AI
// reader (Layer 4 accepted rows, tested adapters): no AI call, no scraper credit, nothing admitted, no reader's request changed; a page with no selection is never treated as lacking the field.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { BLOCK_INPUT, LEAN_SECTIONS, blockPlain, holds, selectSections } from '../../supabase/functions/coverage-sweep/lean-sections.ts'
import { AER_V3_INPUT, aerV3Blocks } from '../../supabase/functions/coverage-sweep/aer-v2.ts'
import { leanText } from '../../supabase/functions/coverage-sweep/lean-input.ts'

const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261114031500_cf247_lean_sections_eval.sql', 'utf8')
const MIGB = fs.readFileSync('supabase/migrations/20261114051500_cf247_lean_sections_eval_run_b.sql', 'utf8')
const MIGC = fs.readFileSync('supabase/migrations/20261114071500_cf247_lean_selection_shadow.sql', 'utf8')
const SEL = fs.readFileSync('supabase/functions/coverage-sweep/lean-sections.ts', 'utf8')
const filler = '<p>' + 'Graduates work across many industries and roles. '.repeat(12) + '</p>'
const page = `<html><header>Site menu Apply now</header><body><main><h1>Bachelor of Science</h1><p>The Bachelor of Science builds skills in research.</p>` +
  `<div>Duration</div><div>3 years full-time</div><div>Location</div><div>Townsville Bebegu Yumba</div><div>Start dates</div><div>February, July</div>${filler.repeat(60)}` +
  `<h2>Fees</h2><table><thead><tr><th>Year</th><th>Annual fee</th></tr></thead><tbody><tr><td>2026</td><td>A$46,500</td></tr><tr><td>2027</td><td>A$47,990</td></tr></tbody></table><p>* Indicative, per year.</p>` +
  `<h2>Entry requirements</h2><h3>International students</h3><p>A completed secondary qualification equivalent to Year 12 with ATAR 70.</p><ul><li>IELTS 6.5 overall, no band below 6.0</li></ul>` +
  `<h2>How to apply</h2><p>Applications close 30 November 2026.</p><script>var x = "Applications close never";</script></main><footer>Contact us</footer></body></html>`
const blocks = (html, data = 'Duration: 3 years') => aerV3Blocks(leanText(html), data)

test('one [B#] contract: the selector uses the AER v2 blocks (lean-blocks-v1 over lean-md-v1) and defines no block format of its own', () => {
  expect(BLOCK_INPUT).toBe(AER_V3_INPUT)
  expect(AER_V3_INPUT).toBe('lean-blocks-v1')
  expect(SEL).not.toMatch(/export function (leanBlocks|renderBlocks?|blockMap)\b/)
  expect(SEL).not.toMatch(/\[B\$\{/)  // no block line written here
  const ab = blocks(page)
  const sel = selectSections(ab, 'fees')
  expect(sel.input).toBe(ab.input)
  // every selected line is the block's own line, unchanged, with its id and source offset
  const lines = new Set(ab.text.split('\n'))
  for (const l of sel.text.split('\n')) { expect(lines.has(l)).toBe(true); expect(l).toMatch(/^\[B\d+ @(\d+|data)\] /) }
  for (const id of sel.block_ids) expect(sel.text).toContain(`[${id} @`)
  expect(selectSections(blocks(page), 'fees')).toEqual(sel)  // deterministic
})

test('lean-sections-v1: sections, every row of a matching table with its headers, label/value pairs, page data; facts beyond a 24,000-character cut are kept', () => {
  const ab = blocks(page)
  expect(ab.text.length).toBeGreaterThan(24000)
  const fees = selectSections(ab, 'fees')
  expect(fees.selector).toBe(LEAN_SECTIONS)
  expect(fees.text).toContain('## Fees')
  expect(fees.text).toContain('Year: 2026 | Annual fee: A$46,500')
  expect(fees.text).toContain('Year: 2027 | Annual fee: A$47,990')
  expect(fees.text).toContain('* Indicative, per year.')
  expect(fees.text).toContain('@data] Duration: 3 years')  // page data always travels
  expect(fees.chars).toBeLessThan(3000)
  expect(holds(selectSections(ab, 'duration').text, ['3 years full-time'])).toBe(true)
  expect(holds(selectSections(ab, 'campus').text, ['Townsville Bebegu Yumba'])).toBe(true)
  expect(holds(selectSections(ab, 'intakes').text, ['February', 'July'])).toBe(true)
  const entry = selectSections(ab, 'entry_requirements')
  expect(entry.text).toContain('## Entry requirements')
  expect(entry.text).toContain('## International students')
  expect(holds(entry.text, ['ATAR 70'])).toBe(true)
  expect(holds(selectSections(ab, 'english').text, ['IELTS 6.5 overall'])).toBe(true)
  expect(holds(selectSections(ab, 'deadline').text, ['Applications close 30 November 2026'])).toBe(true)
  expect(holds(selectSections(ab, 'deadline').text, ['Applications close never'])).toBe(false)
  // no selection is reported, never acted on
  const none = selectSections(blocks('<main><p>Nothing about the course here.</p></main>', ''), 'english')
  expect(none.no_selection).toBe(true)
})

test('gold matching: flat form, every part needed', () => {
  expect(holds('Start: February, July', ['February', 'July'])).toBe(true)
  expect(holds('Start: February', ['February', 'July'])).toBe(false)
  expect(holds('A$47,990 per year', ['47990'])).toBe(true)
  expect(holds('anything', [])).toBe(false)
})

test('worker mode lean_sections_eval: stored copies only, no AI, no Firecrawl, nothing admitted; no reader uses the selector', () => {
  expect(IX).toMatch(/const WORKER = "coverage-sweep-worker-v0\.89\.0";|\/\/ was v0\.89\.0 \(#1136\) \/\/ v0\.89\.0 \(14 Nov 2026, numbered after #1137/)  // current, or kept as "was" by a later worker (v0.90.0 merges #1128)
  expect(IX).toContain('import { BLOCK_INPUT, LEAN_SECTIONS, SECTION_DEFAULTS, blockPlain, holds, selectSections } from "./lean-sections.ts";')
  expect(IX).toContain('const ab = aerV3Blocks(leanText(raw), di), whole = blockPlain(ab), sel = selectSections(ab, f, SEC_OPT);')
  expect(IX).toContain('const selText = sel.no_selection ? whole : sel.plain;')  // v0.92.0: nothing selected means the page is sent whole (design §3)
  const a = IX.indexOf('if (mode === "lean_sections_eval")'), b = IX.indexOf('if (mode === "central_ai")')
  expect(a).toBeGreaterThan(0)
  const body = IX.slice(a, b)
  expect(body).toContain('svc_lean_sections_eval_next_v1')
  expect(body).toContain('svc_lean_sections_eval_record_v1')
  expect(body).toContain('readEvidenceCopy(c, String(it.storage_path))')
  expect(body).toContain('ai_calls: 0')
  expect(body).not.toMatch(/openrouter|chat\/completions|fcScrape|firecrawl|svc_fc_spend|fetch\(/i)
  // the selector is used by the recall check and (v0.92.0, Phase 1b step 2) by the shadow beside live reads, nowhere else
  expect(IX.split('selectSections(').length - 1).toBe(2)
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

test('recall matcher (v0.91.0): a quote that runs across adjacent blocks is held by the blocks\' words, never broken by the [B#] labels; the reader still gets labelled lines', () => {
  const html = '<main>' + '<p>Intro text for the course page.</p>'.repeat(60) + '<h2>Entry requirements</h2><p>Academic admission requirements may be satisfied through completion of one of the following:</p><ul><li>AQF Diploma or equivalent;</li><li>Undergraduate Certificate</li></ul></main>'
  const ab = blocks(html, '')
  const quote = ['Academic admission requirements may be satisfied through completion of one of the following: AQF Diploma or equivalent; Undergraduate Certificate']
  expect(holds(ab.text, quote)).toBe(false)          // the labelled lines break a cross-block quote (the run phase1b-step1 artefact)
  expect(holds(blockPlain(ab), quote)).toBe(true)
  const sel = selectSections(ab, 'entry_requirements')
  expect(holds(sel.plain, quote)).toBe(true)
  expect(sel.text).toMatch(/^\[B\d+ @\d+\] /m)       // what a reader would be sent keeps its labels
  expect(sel.plain).not.toMatch(/\[B\d+ @/)
})

test('run b migration: run a kept as recorded, its unread cases closed as superseded, the same cases seeded again and held for the release window; nothing deleted', () => {
  expect(MIGB).toMatch(/^-- Replaces: nothing\.$/m)
  expect(MIGB).toMatch(/^-- Retires: nothing\.$/m)
  expect(MIGB).toContain("where run_label = 'phase1b-step1-2026-11-14' and state = 'pending';")
  expect(MIGB).toContain("select security.lean_sections_eval_seed_v1('phase1b-step1b-2026-11-14');")
  expect(MIGB).toContain("set leased_until = now() + interval '10 minutes'")
  expect(MIGB).not.toMatch(/^\s*(drop|truncate|delete)\b/im)
})

test('lean-sections-v2 (Phase 1b step 2): entry requirements under "Assumed knowledge", "Advanced standing" and literacy checks are selected; labels with HTML entities match', () => {
  expect(LEAN_SECTIONS).toBe('lean-sections-v2')
  const pad = '<p>Intro text for the course page.</p>'.repeat(40)
  for (const [h, v] of [['Assumed knowledge', 'Mathematical Methods (Units 3 and 4, C)'], ['Advanced standing', 'Candidates with a cognate bachelor degree get four units of credit'], ['Language, literacy and numeracy', 'Complete an LLND assessment before enrolment'], ['Who can apply', 'Must be 18 years of age or above']]) {
    const ab = blocks(`<main>${pad}<h2>Overview</h2><p>About the course.</p><h2>${h}</h2><p>${v}</p><h2>Careers</h2><p>Jobs.</p></main>`, '')
    const sel = selectSections(ab, 'entry_requirements')
    expect(holds(sel.plain, [v]), h).toBe(true)
    expect(holds(sel.plain, ['Jobs.']), h).toBe(false)
  }
  expect(holds('To enter FNS40222 – Certificate IV in Accounting', ['To enter FNS40222 &#8211; Certificate IV'])).toBe(true)
  expect(holds('Fees & charges', ['Fees &amp; charges'])).toBe(true)
  const sel = selectSections(blocks('<main><h2>Careers</h2><p>Jobs.</p></main>', ''), 'entry_requirements')
  expect(sel.no_selection).toBe(true)
  expect(['likely', 'unknown', 'no_signal', 'not_measured']).toContain(sel.signal)
})

test('Phase 1b step 2 shadow: the enrich read records what the selector would send beside what is sent; the request is unchanged; bounded and switchable by settings', () => {
  const enrich = IX.slice(IX.indexOf('if (mode === "enrich_ai")'), IX.indexOf('if (mode === "scholarship_inspect")'))
  expect(enrich).toContain('const SEL_SHADOW = wsOn("reading.selection_shadow_on", 1), SEL_MAX = wsNum("reading.selection_shadow_max_chars", 200000);')
  expect(enrich).toContain('const big = SEL_SHADOW && lean.text.length > SEL_MAX, t1 = Date.now(), ab = SEL_SHADOW && !big ? aerV3Blocks(lean, di) : null, blocksMs = Date.now() - t1;')
  // the selection goes only into the observation row: its text is hashed, never placed in a request
  const shadow = enrich.slice(enrich.indexOf('const shadowSel = async'), enrich.indexOf('const readStored ='))
  expect(shadow).toContain('sel_sha256: await sha256Hex(s.text)')
  expect(shadow).not.toMatch(/cascadeFetch|messages|content:\s*s\.|chat\/completions/)
  expect(enrich.match(/shadowSel\(/g)?.length).toBe(1)  // one call, in observeReads
  expect(enrich).not.toMatch(/sel\.(text|plain)\b[^\n]*(cascadeFetch|messages)/)
  // the selector's sizes come from settings, the same for the recall check and the shadow
  expect(IX).toContain('const SEC_OPT = { section_max_chars: wsNum("reading.section_max_chars", SECTION_DEFAULTS.section_max_chars),')
  expect(MIGC).toMatch(/^-- Replaces: public\.svc_ai_input_observe_v1\(jsonb\) \(same name; replaced only from the definition it was written against, md5 3f6d4ed98c8055bdbd18adae4e09edf0\)\.$/m)
  expect(MIGC).toMatch(/^-- Retires: nothing\.$/m)
  expect(MIGC).toContain("if md5(pg_get_functiondef('public.svc_ai_input_observe_v1(jsonb)'::regprocedure)) <> '3f6d4ed98c8055bdbd18adae4e09edf0' then")
  for (const k of ['reading.selection_shadow_on', 'reading.section_max_chars', 'reading.section_neighbour_chars', 'reading.section_intro_blocks', 'reading.selection_shadow_max_chars']) expect(MIGC).toContain(`('pipeline', '${k}',`)
  expect(MIGC).toContain("select security.lean_sections_eval_seed_v1('phase1b-step1c-2026-11-14');")
  expect(MIGC).toContain("count(*) filter (where j.preflight_full in ('likely', 'unknown') and j.preflight_selection = 'no_signal')")
  expect(MIGC).not.toMatch(/^\s*(drop|truncate)\b/im)
})
