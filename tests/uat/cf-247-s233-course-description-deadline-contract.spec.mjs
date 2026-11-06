// Guards: Platform Admin direction 3 Nov 2026 09:32 (platform-led enrichment) and Admin #382 P0 deadline semantics, 6 Nov 2026: course description and application deadline enriched by the platform
// Acceptance report item 1 (admin docs/platform/nz-enrichment-brief/2026-11-03-platform-enrichment-control-autonomy-acceptance-report.md): course
// description and application deadline are fields of the existing Enrich fields engine (enrich_fields_v1, field_enrich_items, worker mode
// enrich_ai, the standing gap queue, enrichment plans): the stored course page first, quote-backed, Layer 4 for a provider's first descriptions,
// existing AI and Firecrawl budgets. The behaviour runs on isolated fixtures by tests/fixtures/course-text/run.sh (scratch PostgreSQL; the eight
// live functions the migration edits and six it reads against are loaded from their live text and checked against the live md5s); this spec
// holds the contract, the worker's pure functions and the fixture coverage.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { COURSE_TEXT_ANSWER_KEY, COURSE_TEXT_FIELDS, COURSE_TEXT_SYSTEM, courseTextAnswer, courseTextAnswerLimit, courseTextDeadlines, courseTextLengthNote, courseTextPage,
  courseTextRequest, courseTextResults, courseTextSchema, courseTextUser } from '../../supabase/functions/coverage-sweep/course-text.ts'

const MIG = 'supabase/migrations/20261103110000_cf247_course_description_deadline_fields.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/course-text'
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1); return m.slice(a, m.indexOf(']], array[', a) + 20) }

// live md5 before (re-read 3 Nov 2026 11:26 AEDT) and after the edit
const EDITS = {
  'security.enrich_fields_v1()': ['0efc2f55d0f1e285225be7a10a28f4c1', '80ee183b324c196b4c9559cec6e3360f'],
  'public.svc_enrich_ai_record(jsonb)': ['264ab812e37f4c1877bdafbdb43147b1', 'ae1ced1c1f1fd092afe885cfc37be0b4'],
  'security.field_gap_queue_tick_v1()': ['d909e54d6b6de0f8d2893fbb2d8553bd', '387f8edbe3363ea52317e024d96f2369'],
  'public.admin_enrich_fields(text,jsonb)': ['349584fc0e9b605e1067cbbd488e435a', '476062fa6437a4266ab6716fad0021c4'],
  'security.field_stalled_v1()': ['702dc1da52bd7272c913ad287b7c8b06', 'a964f1dcf244909453835b1ceda4e3b6'],
  'security.enrich_coverage_snapshot_v1()': ['1f94cdee31ec466dc0e83e30728c5596', '242b178c5d924ec359f2f10b796925f0'],
  'security.layer4_review_decide_impl(uuid,text,text,jsonb)': ['073889b7c5319019b25212ce08705a37', '55353f1903c97b268255c8c1e4f5ca6f'],
  'security.layer4_inbox_items_v1()': ['c31b009df674a4a6ff531f00b99a9a45', 'a56bc3313e02ac0611deb5657da95ce0'],
}

test('the two fields join the existing Enrich fields engine: list, items, standing queue, record, coverage (md5-guarded edits only)', () => {
  for (const [sig, [before, after]] of Object.entries(EDITS)) {
    const e = edit(sig)
    expect(e).toContain(`'${before}', '${after}'`)
    expect(run).toContain(`["${sig}"]=${before}`)  // the fixture loads the same live text
  }
  expect(edit('security.enrich_fields_v1()')).toContain("('description', 'Course description', 'course', array['ai_stored', 'scraper'], 11)")
  expect(edit('security.enrich_fields_v1()')).toContain("('deadline', 'Application deadline', 'course', array['ai_stored', 'scraper'], 12)")
  expect(edit('public.svc_enrich_ai_record(jsonb)')).toContain("elsif i.field in ('description', 'deadline') then")
  expect(edit('security.field_gap_queue_tick_v1()')).toContain('security.enrich_course_text_gaps_v1(v_fields)')
  expect(edit('public.admin_enrich_fields(text,jsonb)')).toContain("when 'deadline' then security.enrich_deadline_missing_v1(c.id) else false end")
  expect(edit('security.field_stalled_v1()')).toContain("'p_address', 'description', 'deadline'")
  // the starting source rule is the stored page only; the register says a reader exists
  expect(code).toContain("('ALL', 'description', array['ai_stored']")
  expect(code).toContain("('ALL', 'deadline', array['ai_stored']")
  expect(code).toMatch(/update pipeline\.field_register set reader = 'enrich'[\s\S]+where field in \('description', 'deadline'\) and reader = 'none';/)
  // no new engine, job or screen
  expect(code).not.toMatch(/cron\.schedule|insert into pipeline\.automation_catalogue|create table/i)
})

test("standing queue: stored page only, the queue's own rules, a daily cap per field that is a setting", () => {
  const g = m.slice(m.indexOf('create or replace function security.enrich_course_text_gaps_v1'), m.indexOf("comment on function security.enrich_course_text_gaps_v1"))
  expect(g).toContain("security.pipeline_num_v1('enrich.course_text_items_per_day', 500)")
  expect(g).toContain("coalesce((j.args->>'standing')::boolean, false)")
  expect(g).toContain("g.status in ('bound', 'ambiguous')")
  expect(g).toContain('security.enrich_item_held_v1(m.cid, f)')
  expect(g).toContain('security.provider_hidden_v1')
  expect(g).toContain("not in ('queued', 'waiting', 'ai', 'leased', 'review')")
  expect(g).toContain('limit v_room')
})

test("description admission: provider description rules, held never cut, Layer 4 for a provider's first descriptions", () => {
  const chk = m.slice(m.indexOf('create or replace function security.course_description_check_v1'), m.indexOf('comment on function security.course_description_check_v1'))
  for (const rule of ['not_stated', 'sentence_count', 'quote_not_on_page', 'unsupported_marketing', 'unsupported_claim', 'incomplete_sentence', 'unsupported_sentence', 'length', 'duplicate_other_course']) expect(chk).toContain(`'${rule}'`)
  for (const k of ['pdesc.superlatives', 'pdesc.claim_words', 'pdesc.support_min_share', 'pdesc.duplicate_share', 'enrich.course_description_max_chars']) expect(chk).toContain(k)
  expect(chk).not.toMatch(/left\(v_text|substr\(v_text/)  // never cut
  const rec = m.slice(m.indexOf('create or replace function security.enrich_course_text_record_v1'), m.indexOf('comment on function security.enrich_course_text_record_v1'))
  expect(rec).toContain('if i.evidence_id is distinct from g.evidence_id then')  // only the course's own bound page
  expect(rec).toContain("security.coverage_identity_allowed(g.provider_id, g.identity_basis, i.field)")
  expect(rec).toContain("'course_description_first_read'")
  expect(rec).toContain("'Course description read from the course''s own page. This is one of the provider''s first course descriptions, so a person approves it as read or rejects it.'")
  expect(rec).toContain('security.course_description_trusted_v1(v_pid)')
  expect(rec).toContain("'held_first_admission:")
  expect(rec).toMatch(/update catalogue\.courses set description = v_text, updated_at = now\(\) where id = i\.course_id and nullif\(btrim\(description\), ''\) is null;/)
  expect(edit('security.layer4_review_decide_impl(uuid,text,text,jsonb)')).toContain('security.layer4_course_description_apply_v1(v_actor,v_item.id,v_final,trim(p_reason))')
  expect(edit('security.layer4_inbox_items_v1()')).toContain("r.field_code = 'course_description_first_read' then 'provider_description'")
  const ap = m.slice(m.indexOf('create or replace function security.layer4_course_description_apply_v1'), m.indexOf('comment on function security.layer4_course_description_apply_v1'))
  expect(ap).toContain('if p_value is distinct from i.proposed_value then raise exception')  // approved as read, never edited
})

test('deadline admission: explicit dates in the quote, tied to an intake, never inferred, never over a held deadline', () => {
  const rec = m.slice(m.indexOf('create or replace function security.enrich_course_text_record_v1'), m.indexOf('comment on function security.enrich_course_text_record_v1'))
  for (const why of ['quote_not_on_page', 'no_full_date', 'date_not_in_quote', 'not_tied_to_one_intake', 'intake_not_matched', 'conflicting_dates', 'outside_intake_window']) expect(rec).toContain(`'${why}'`)
  expect(rec).toContain("update catalogue.course_intakes set application_deadline = v_date where id = it.id and application_deadline is null;")
  expect(rec).toContain("security.pipeline_num_v1('intake_dates.deadline_max_days_before', 366)")
  expect(rec).toContain("'the page says applications are rolling (no date to hold)'")
  // Admin #382 P0 (6 Nov 2026): extend the existing deadline guard, never a
  // second admissions mechanism or a duplicate spec. Real cases run through
  // svc_enrich_ai_record in the existing PostgreSQL fixture.
  const semantics = fs.readFileSync('supabase/migrations/20261106450000_cf247_deadline_closing_semantics.sql', 'utf8')
  expect(semantics).toContain('f01e9be83e58c9c48c33e5fde4de05d9')
  expect(semantics).toContain('2357306ca969fb7b299021bac3b6f3fa')
  expect(semantics).toContain('regexp_split_to_table')
  expect(semantics).toContain('regexp_matches(c.t, p.full_date')
  for (const quote of ['Start date 02 Nov 2026', 'Intakes 15 February 2027', 'Start Dates 12 October 2026']) expect(fixtures).toContain(quote)
  expect(fixtures).toContain("reason = 'held: date_not_in_quote'")
  expect(run).toContain('20261106450000_cf247_deadline_closing_semantics.sql')

})

test('worker v0.59.4: one call per course on the stored page, the central model, quotes checked, nothing fetched', () => {
  // the v0.59.4 note stays in the version chain once a later worker is released ("// was v0.59.4 // ...")
  expect(worker).toMatch(/(?:const WORKER = "coverage-sweep-worker-v0\.59\.4"; |\n\/\/ was v0\.59\.4 )\/\/ v0\.59\.4 \(3 Nov 2026, CF-247 Workstream C/)
  expect(worker).toContain('// was v0.59.3 // v0.59.3 (3 Nov 2026, CF-247 Workstream F, hidden failures')
  const t = worker.slice(worker.indexOf('const textRead = async'), worker.indexOf('const entryCall = async'))
  // v0.59.9: the one call is askText(user, fields); the first user message is unchanged
  expect(t).toContain('courseTextRequest(model, user, w, maxTokens)')
  expect(t).toContain('courseTextUser(pg.provider, pg.title, want, page, length)')
  expect(t).toContain('courseTextPage(raw, PAGE_CHARS)')
  expect(t).toContain('returned model ${d.model}, not ${model}')
  expect(t).not.toMatch(/firecrawl|useFc|readSch|fetch\(p\.|fetch\(u/i)
  expect(worker).toContain('const textIt = (pg.items || []).filter((x: any) => (COURSE_TEXT_FIELDS as readonly string[]).includes(String(x.field)));')
  expect(worker).toContain('try { await textRead(pg, raw, textIt) } catch (e) { fail(textIt.map((x: any) => Number(x.item_id)), e) }')
  expect(COURSE_TEXT_FIELDS).toEqual(['description', 'deadline'])
})

test('course-text.ts: schema per field asked, quotes on the page, dates never made up, cut answers held', () => {
  expect(Object.keys(courseTextSchema(['description']).properties)).toEqual(['description'])
  expect(Object.keys(courseTextSchema(['deadline']).properties)).toEqual(['deadlines'])
  expect(courseTextSchema(['description', 'deadline']).required).toEqual(['description', 'deadlines'])
  const req = courseTextRequest('openai/gpt-4.1-mini', 'u', ['description'], 1500)
  expect(req.provider).toEqual({ require_parameters: true }); expect(req.temperature).toBe(0); expect(req.max_tokens).toBe(1500)
  expect(COURSE_TEXT_SYSTEM).toContain('never work out a date from a start date or a term, and never assume a year')
  expect(courseTextUser('Uni', 'BSc', ['description', 'deadline'], 'TEXT', { min_sentences: 1, max_sentences: 4, max_chars: 700 }))
    .toBe('Provider: Uni\nCourse: BSc\nFields: description, deadlines\nDescription length: 1 to 4 sentences, at most 700 characters in all (the sentences, not the quotes).\n\nPage text:\nTEXT')
  expect(courseTextLengthNote({})).toBe('')
  expect(courseTextAnswerLimit({ [COURSE_TEXT_ANSWER_KEY]: 3000 })).toBe(3000); expect(courseTextAnswerLimit({})).toBe(1500)
  const html = '<html><nav>Menu Apply now</nav><main><h1>Bachelor of Nursing</h1><p>The Bachelor of Nursing prepares students for registered nurse practice in hospital and community settings.</p>' +
    '<p>Applications for the February 2027 intake close 30 November 2026.</p>' + 'x'.repeat(1600) + '</main><footer>Best university</footer></html>'
  const page = courseTextPage(html, 16000)
  expect(page).not.toContain('Menu Apply now'); expect(page).not.toContain('Best university')
  const a = { description: { about_course: true, sentences: [
      { text: 'The course prepares students for registered nurse practice.', quote: 'The Bachelor of Nursing prepares students for registered nurse practice in hospital and community settings.' },
      { text: 'It is ranked first.', quote: 'Ranked first in Australia for nursing graduates.' }] },
    deadlines: [{ intake: 'February 2027 intake', kind: 'date', date: '2026-11-30', quote: 'Applications for the February 2027 intake close 30 November 2026.' },
                { intake: null, kind: 'date', date: '30 Nov', quote: 'close 30 November' }] }
  const out = courseTextResults(a, page, [{ item_id: 1, field: 'description' }, { item_id: 2, field: 'deadline' }], { model: 'm', worker: 'w', cost: 0.002 })
  expect(out[0].value.sentences.map((s) => s.on_page)).toEqual([true, false])
  expect(out[0].reason).toBe("a sentence's quote is not on the page"); expect(out[0].cost).toBe(0.001)
  expect(out[1].value.deadlines[0]).toEqual({ intake: 'February 2027 intake', kind: 'date', date: '2026-11-30', quote: 'Applications for the February 2027 intake close 30 November 2026.', on_page: true })
  expect(out[1].value.deadlines[1].date).toBeNull()  // not YYYY-MM-DD: never completed here
  expect(courseTextDeadlines({ deadlines: [] }, page)).toEqual([])
  expect(courseTextResults({ description: { about_course: false, sentences: [] } }, page, [{ item_id: 3, field: 'description' }], { model: 'm', worker: 'w', cost: 0 })[0].reason).toBe('the page does not state it')
  const cut = courseTextAnswer({ choices: [{ finish_reason: 'length', message: { content: '{"descr' } }], usage: { cost: 0.003 } }, 1500)
  expect(cut).toEqual({ ok: false, cost: 0.003, error: 'held_partial: output_truncated: course_text reached reading.answer_tokens.course_text (1500)' })
  expect(courseTextAnswer({ choices: [{ message: { content: '{"deadlines":[]}' } }] }, 1500)).toEqual({ ok: true, a: { deadlines: [] }, cost: 0 })
})

test('fixtures cover every case, on the live definitions, with the migration applied twice', () => {
  expect(run).toContain('migrations/20261103110000_cf247_course_description_deadline_fields.sql')
  expect(run).toContain("grep -c ': applied' <<<\"$OUT\")\" = 8")
  expect(run).toContain("grep -c 'already applied' <<<\"$OUT2\")\" = 8")
  for (const c of ['1a', '1e', '2a', '2c', '3b', '3d', '4a', '4b', '4c', '4d', '4e', '4f', '4g', '4h', '4i', '5a', '5c', '5d', '5e', '5f', '5g', '5h', '5i', '5j', '5l', '5m',
                   '6a', '6b', '6c', '6d', '6e', '6f', '6g', '6h', '6i', '6k', '6l', '6q', '6r', '7a', '8a', '8b']) expect(fixtures).toContain(`pg_temp.ok('${c} `)
  for (const f of fs.readdirSync(`${FX}/live`)) expect(fs.readFileSync(`${FX}/live/${f}`, 'utf8')).toMatch(/^CREATE OR REPLACE FUNCTION /)
})

test('operator screens: Enrich fields shows the values read; Layer 4 labels a course description', () => {
  const ef = fs.readFileSync('src/EnrichFields.jsx', 'utf8'), l4 = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8'), cc = fs.readFileSync('src/course-coverage.jsx', 'utf8')
  expect(ef).toContain("if(i.field==='description')return v.text||(v.sentences||[]).map(s=>s.text).join(' ')||'—'")
  expect(ef).toContain("if(i.field==='deadline')return (v.deadlines||[])")
  expect(l4).toContain("label={d.field_code==='course_description_first_read'?'Course description':k.label}")
  expect(cc).toContain("description:{label:'Course description',layer:'Enrich fields (AI reads the stored course page; Layer 4 first)'}")
})
