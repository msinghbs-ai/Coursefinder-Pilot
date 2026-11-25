// Guards: Platform Admin 25 Nov 2026 08:16 AEDT (P0 AER preprocessing, Admin #1063: the existing meaningful-content section selector in entryRead; one preprocessing mechanism for scheduled and on-demand reads; recall against source evidence and earlier answers; model qualification through the existing register; no new engine, reader, scheduler, queue or pipeline)
// s1125: course entry reads send the selected entry-requirement sections (course-entry.ts courseEntryInput over lean-sections-v3), the qualification harness reads the same input on named candidate models, judged on the stored page (lean-qualify.ts entryJudge).
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
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const PASTE = fs.readFileSync('tests/fixtures/paste/PASTE-20261125-s1125-lean-harness-entry-labels.sql', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261126190000_cf247_s1125_entry_sections_first_qualify.sql', 'utf8')

// a course page as providers publish it: navigation, a long overview, then the entry requirements with a table and its footnote
const PAGE = `<html><body><nav><a href="/">Home</a> <a href="/study">Study</a> Apply now Entry requirements ATAR</nav>
<main><h1>Bachelor of Nursing</h1>
<h2>Overview</h2>${'<p>Our nursing graduates work across hospitals, clinics and the community. You will learn in simulation labs with modern equipment and experienced teachers.</p>'.repeat(30)}
<h2>Career outcomes</h2><p>Registered nurse, community health nurse, mental health nurse.</p>
<h2>Entry requirements</h2>
<p>Applicants must have completed an Australian Year 12 qualification or equivalent.</p>
<table><tr><th>Qualification</th><th>Minimum</th></tr><tr><td>Australian Year 12</td><td>ATAR 70.00*</td></tr><tr><td>Diploma of Nursing (HLT54121)</td><td>Completed</td></tr></table>
<p>* International applicants must also complete an interview.</p>
<h2>Fees</h2><p>Indicative annual fee AUD 38,000.</p>
</main><footer>Copyright</footer></body></html>`

test('s1125: the selector picks the entry section, its table and footnote, and the read sends only that', async () => {
  const lean = await load('supabase/functions/coverage-sweep/lean-input.ts', 'li1125')
  const aer = await load('supabase/functions/coverage-sweep/aer-v2.ts', 'av1125')
  const sec = await load('supabase/functions/coverage-sweep/lean-sections.ts', 'ls1125')
  const ce = await load('supabase/functions/coverage-sweep/course-entry.ts', 'ce1125')
  const ab = aer.aerV3Blocks(lean.leanText(PAGE), null), s = sec.selectSections(ab, 'entry_requirements')
  const sel = { selector: s.selector, blocks: s.blocks, chars: s.chars, plain: s.plain, no_selection: s.no_selection, signal: String(s.signal) }
  const whole = PAGE.replace(/<[^>]+>/g, ' ')
  const r = ce.courseEntryInput(whole, sel, { on: true, ofBlocks: ab.blocks.length })
  expect(r.input).toMatchObject({ basis: 'course-entry-sections-v1', sent: 'sections', why: null, selector: 'lean-sections-v5' })  // s1135: the selector's current version
  for (const q of ['Australian Year 12 qualification or equivalent', 'ATAR 70.00', 'Diploma of Nursing (HLT54121)', 'International applicants must also complete an interview']) expect(r.text, q).toContain(q)
  expect(r.text).not.toContain('simulation labs')  // the overview is not sent
  expect(r.input.sent_chars).toBeLessThan(r.input.page_chars / 4)
})

test('s1125: the whole page is sent when the switch is off, nothing is selected, the signal is not likely, or the selection is not smaller', async () => {
  const ce = await load('supabase/functions/coverage-sweep/course-entry.ts', 'ce1125b')
  const whole = 'x'.repeat(5000), sel = (o) => ({ selector: 'lean-sections-v3', blocks: 3, chars: 100, plain: 'Entry requirements: ATAR 70', no_selection: false, signal: 'likely', ...o })
  expect(ce.courseEntryInput(whole, sel(), { on: false }).input).toMatchObject({ sent: 'whole', why: 'sections_off' })
  expect(ce.courseEntryInput(whole, null, { on: true }).input).toMatchObject({ sent: 'whole', why: 'not_selected' })
  expect(ce.courseEntryInput(whole, sel({ no_selection: true }), { on: true }).input).toMatchObject({ sent: 'whole', why: 'no_selection' })
  expect(ce.courseEntryInput(whole, sel({ signal: 'unknown' }), { on: true }).input).toMatchObject({ sent: 'whole', why: 'signal_unknown' })
  expect(ce.courseEntryInput('short', sel({ plain: 'a much longer selected text than the page' }), { on: true }).input).toMatchObject({ sent: 'whole', why: 'not_smaller' })
  const ok = ce.courseEntryInput(whole, sel(), { on: true })
  expect(ok.text).toBe('Entry requirements: ATAR 70')
  expect(ok.input).toMatchObject({ sent: 'sections', page_chars: 5000, sent_chars: 27 })
})

test('s1125: the judge checks each label row against the stored page first, then quote, kind, audience and score', async () => {
  const m = await load('supabase/functions/coverage-sweep/lean-qualify.ts', 'lq1125')
  const page = 'Applicants must have completed an Australian Year 12 qualification or equivalent. Australian Year 12 ATAR 70.00. International applicants must also complete an interview.'
  const gold = [
    { quote: 'Applicants must have completed an Australian Year 12 qualification or equivalent', kind: 'prior_qualification', audience: 'all' },
    { quote: 'Australian Year 12 ATAR 70.00', kind: 'minimum_grade', audience: 'domestic', min_entry_score: 70 },
    { quote: 'International applicants must also complete an interview', kind: 'portfolio_interview', audience: 'international' },
    { quote: 'A portfolio of three works is required', kind: 'portfolio_interview' },  // an earlier answer whose words are not on the page: not a label
  ]
  const rows = [
    { kind: 'prior_qualification', audience: 'all', quote: 'Applicants must have completed an Australian Year 12 qualification or equivalent.' },
    { kind: 'minimum_grade', audience: 'domestic', min_entry_score: 70, quote: 'Australian Year 12 ATAR 70.00' },
    { kind: 'general_note', audience: 'all', quote: 'Something else the page states about entry' },
  ]
  const j = m.entryJudge(rows, gold, page)
  expect(j).toMatchObject({ gold: 4, gold_on_page: 3, found: 2, kind_same: 2, audience_same: 2, score_compared: 1, score_same: 1, rows: 3, extra: 1 })
  expect(j.missed).toEqual(['International applicants must also complete an interview'])
  expect(m.entryQuoteMatch('ATAR 70', 'ATAR 70.00 or equivalent')).toBe(false)  // too short to identify a requirement
})

test('s1125: one input function for every course entry read and for its qualification', () => {
  const read = IX.slice(IX.indexOf('const entryRead = async (pg: any, raw: string, items: any[]) => {'), IX.indexOf('// v0.54.0 (W32): a failed read records its cost'))
  expect(read).toContain('ein = entryInputOf(raw, di, text);')
  expect(read).toContain('const plan = courseEntryPlan(ein.text, { pageChars: chars,')
  expect(read).toContain('value: { rows, dropped, coverage: m.coverage, input: ein.input }')
  expect(read).toContain('...courseEntrySliceRows(ans.a, s.text, quoteOpts)')  // quotes checked on the text sent
  expect(IX).toContain('const on = wsOn("reading.course_entry_sections_on", 0);')
  expect(IX).toContain('const ab = aerV3Blocks(lean, di), s = selectSections(ab, "entry_requirements", SEC_OPT);')
  const q = IX.slice(IX.indexOf('if (f === "entry_requirements") {'), IX.indexOf('return;\n          }', IX.indexOf('if (f === "entry_requirements") {')))
  expect(q).toContain('const ein = entryInputOf(raw, di, whole)')
  expect(q).toContain('courseEntryRequest(it.model, courseEntryUser(')
  expect(q).toContain('service: "course_entry_requirements", source: "lean_qualify"')
  expect(q).toContain('entryJudge(m.rows, goldRows, whole)')
  expect(q).not.toMatch(/svc_enrich_entry|enrich_entry_record|layer4|course_entry_requirements\s+set|admit/i)  // nothing is admitted
})

test('s1125: the migration seeds the existing harnesses, keeps the route off and the holds, and switches nothing on', () => {
  expect(MIG).toContain("'reading.course_entry_sections_on', 'Course entry requirements: send the selected sections'")
  // the two CHECK constraints are widened by the Platform Admin's paste file (a migration never drops), which then starts the run once
  expect(PASTE).toContain("check (gold_source in ('aer_accepted', 'adapter', 'ai_earlier', 'cohort_size'))")
  expect(PASTE).toContain("check (field in ('fees', 'intakes', 'entry_requirements'))")
  expect(PASTE).toContain("raise exception 'stop: a harness CHECK constraint is not the definition read on 25 Nov 2026'")
  expect(PASTE).toContain('select security.lean_entry_qualify_start_v1() as started;')
  expect(MIG).toContain("create or replace function security.lean_entry_qualify_start_v1() returns jsonb")
  expect(MIG).toContain("pg_get_constraintdef(oid) like '%entry_requirements%'")
  expect(MIG).toContain("if exists (select 1 from pipeline.lean_qualify_cases where run_label = 's1125-entry-qualify-2026-11-25') then")
  // the deploy's own refusal rule, now also in the pre-flight, finds nothing in the migration
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  expect(fs.readFileSync('scripts/ci/migration-preflight.mjs', 'utf8')).toContain("/^alter table .* drop /i.test(l)")
  expect(MIG).toContain("if md5(pg_get_functiondef('public.svc_lean_qualify_next_v1(integer)'::regprocedure)) <> 'b0274eab6c8fbf0061854305a7623cf2' then")
  expect(MIG).toContain("or (c.field = 'entry_requirements' and v_ent_ok and exists (select 1 from pipeline.ai_model_catalogue mc where mc.code = c.model_code and mc.status = 'allowed')))")
  expect(MIG).toContain("v_ent_ok := coalesce((v_ent->'key'->>'held')::boolean, true) = false")
  expect(MIG).toContain("security.pipeline_num_v1('reading.lean_qualify_ceiling_usd', 0)")  // the existing hard ceiling
  expect(MIG).toContain("v_od := security.on_demand_open_v1('claude_session', v_reason, v_prov,")
  expect(MIG).toContain("raise exception 'post-check: the course entry route was switched on'")
  expect(MIG.replace(/--.*$/gm, '')).not.toMatch(/update pipeline\.ai_service_routes|ai_route_qualifications|insert into catalogue\.|update catalogue\.|layer4_review_items\s+set|cron\.schedule|\bdelete from\b|truncate /i)
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: more than 140 active cron jobs']) expect(MIG).toContain(s)
})
