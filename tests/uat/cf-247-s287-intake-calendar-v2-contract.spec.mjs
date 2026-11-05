// Guards: Platform Admin decision 5 Nov 2026 (intake recovery and process accountability) §1, §2, §7: the existing central-page calendar reader extended (calendar-v2): dated starts with their meaning, deadlines with who they apply to, scope, every value proven on the page, findings fed back, stored documents re-read with the dated parser first.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { CALENDAR_PARSER_DATES, CALENDAR_PROMPT, CALENDAR_READER, calendarAiParsed, calendarAiRequest, calendarSafe, calendarSlices } from '../../supabase/functions/coverage-sweep/calendar.ts'

const Y = new Date().getUTCFullYear() + 1
const page = [`# Key dates ${Y}`, `| Date | Event |`, `| 22 February ${Y} | Autumn session teaching begins |`, `| 15 February ${Y} | Orientation week |`,
  `| 1 December ${Y - 1} | International applications close for Autumn session |`, `## Spring`, `| 6 September | Spring session begins |`, `Main campus academic calendar`].join('\n')
const answer = { scope: 'main_teaching', scope_quote: 'Main campus academic calendar', periods: [
  { period: 'Autumn session', start: { year: Y, month: 2, day: 22, quote: `22 February ${Y} | Autumn session teaching begins` }, start_meaning: 'teaching_start', year_quote: '', end: null,
    application_deadlines: [{ year: Y - 1, month: 12, day: 1, quote: `1 December ${Y - 1} | International applications close for Autumn session`, applies_to: 'international' }] },
  { period: 'Orientation', start: { year: Y, month: 2, day: 15, quote: `15 February ${Y} | Orientation week` }, start_meaning: 'orientation', year_quote: '', end: null, application_deadlines: [] },
  { period: 'Spring session', start: { year: Y, month: 9, day: 6, quote: '6 September | Spring session begins' }, start_meaning: 'teaching_start', year_quote: `# Key dates ${Y}`, end: null, application_deadlines: [] },
  { period: 'Winter school', start: { year: Y, month: 7, day: 1, quote: `1 July ${Y} | Winter school begins` }, start_meaning: 'teaching_start', year_quote: '', end: null, application_deadlines: [] },
  { period: 'Summer term', start: { year: Y, month: 11, day: 30, quote: '6 September | Spring session begins' }, start_meaning: 'teaching_start', year_quote: '', end: null, application_deadlines: [] }] }

test('every value must be on the page: dated teaching starts kept, orientation never a commencement, unproven values become findings', () => {
  const p = calendarAiParsed([answer], page, `ai:gpt-4.1-mini:${CALENDAR_READER}`)
  expect(p.parser).toBe('ai:gpt-4.1-mini:calendar-v2.1'); expect(p.reader).toBe('calendar-v2.1'); expect(p.scope).toBe('main_teaching')
  const autumn = p.periods.find(x => x.period === 'autumn session')
  expect(autumn.starts).toEqual([{ year: Y, month: 2, day: 22, date: `${Y}-02-22`, quote: `22 February ${Y} | Autumn session teaching begins`, year_basis: 'quote', meaning: 'teaching_start' }])
  expect(autumn.deadlines).toEqual([{ year: Y - 1, month: 12, day: 1, date: `${Y - 1}-12-01`, quote: `1 December ${Y - 1} | International applications close for Autumn session`, year_basis: 'quote', applies_to: 'international', rolling: false }])
  // the year printed only in the heading: kept with that heading as its evidence
  expect(p.periods.find(x => x.period === 'spring session').starts[0]).toMatchObject({ year: Y, date: `${Y}-09-06`, year_quote: `# Key dates ${Y}`, year_basis: 'heading' })
  expect(p.periods.find(x => x.period === 'orientation')).toBeUndefined()
  expect(p.periods.find(x => x.period === 'winter school')).toBeUndefined()   // quote not on the page
  expect(p.periods.find(x => x.period === 'summer term')).toBeUndefined()     // month not in its quote
  expect(p.findings.map(f => f.code).sort()).toEqual(['month_not_in_quote', 'not_a_teaching_start', 'quote_not_on_page'])
})

test('a year in neither the quote nor an enclosing section is never assumed; scope, missing deadlines and next year are findings', () => {
  const page = ['# Key dates', '| 6 September | Spring session begins |', 'Main campus academic calendar'].join('\n')   // calendar-v2.1: no section year on this page
  const a = { scope: 'offshore_campus', scope_quote: 'Main campus academic calendar', periods: [{ period: 'Term 1', start: { year: Y, month: 9, day: 6, quote: '6 September | Spring session begins' }, start_meaning: 'teaching_start', year_quote: 'not on the page', end: null, application_deadlines: [] }] }
  const p = calendarAiParsed([a], page, 'ai:m:calendar-v2', true)
  expect(p.periods[0].starts[0]).toMatchObject({ year: null, date: null, month: 9 })
  expect(p.scope).toBe('offshore_campus')
  expect(p.findings.map(f => f.code).sort()).toEqual(['document_longer_than_read', 'next_year_missing', 'no_deadline', 'not_main_calendar', 'year_not_printed'])
})

test('long documents are read whole in slices up to the setting; the dated parser stands alone only when safe', () => {
  const text = Array.from({ length: 300 }, (_, i) => `line ${i} ${'x'.repeat(90)}`).join('\n')
  const all = calendarSlices(text, 10000, 10); expect(all.cut).toBe(false); expect(all.slices.join('')).toBe(text)
  const some = calendarSlices(text, 10000, 2); expect(some.cut).toBe(true); expect(some.slices).toHaveLength(2)
  const today = new Date(`${Y - 1}-11-05T00:00:00Z`)
  expect(calendarSafe({ periods: [{ starts: [{ year: Y, date: `${Y}-02-22` }] }] }, true, today).safe).toBe(true)
  expect(calendarSafe({ periods: [{ starts: [{ year: Y, date: `${Y}-02-22` }] }] }, false, today).safe).toBe(false)
  expect(calendarSafe({ periods: [{ starts: [{ year: Y - 2, date: `${Y - 2}-02-22` }, { year: null, date: null }] }] }, true, today)).toEqual({ safe: false, reason: 'the dated parser found no current or future dated teaching start' })
  expect(CALENDAR_PARSER_DATES).toBe('provider-policy-calendar-dates-v2')
})

test('the request: pinned model, strict schema with meaning, scope and who a deadline applies to, earlier findings as notes', () => {
  const r = calendarAiRequest('openai/gpt-4.1-mini', { provider: 'UNSW Sydney', url: 'https://www.unsw.edu.au/key-dates', text: 'x', notes: '- year_not_printed: start of term 4', slice: '1 of 2' }, 4000)
  expect(r.model).toBe('openai/gpt-4.1-mini'); expect(r.provider).toEqual({ require_parameters: true }); expect(r.temperature).toBe(0); expect(r.max_tokens).toBe(4000)
  const sc = r.response_format.json_schema; expect(sc.strict).toBe(true)
  expect(sc.schema.properties.scope.enum).toEqual(['main_teaching', 'offshore_campus', 'college_or_residence', 'study_abroad_inbound', 'pathway_or_foundation', 'research_only', 'other'])
  expect(sc.schema.properties.periods.items.properties.start_meaning.enum).toEqual(['teaching_start', 'orientation', 'enrolment', 'other'])
  expect(r.messages[0].content).toContain('Never infer, calculate or move a date to another year')
  expect(r.messages[0].content).toContain('year_not_printed: start of term 4')
  expect(r.messages[1].content).toContain('Part: 1 of 2')
  expect(CALENDAR_PROMPT).toContain('orientation for orientation or O-week')
})

test('the worker: calendars read by calendar-v2 in the existing central_ai mode, English pages as before; mode calendar_reread reads stored documents with the dated parser first and no Firecrawl', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const ai = w.slice(w.indexOf('if (mode === "central_ai") {'), w.indexOf('if (mode === "calendar_reread") {'))
  expect(ai).toContain('if (it.kind === "intake_calendar") {')
  expect(ai).toContain('calendarAiParsed(answers, md, `ai:${it.model_code}:${CALENDAR_READER}`, cut)')
  expect(ai).toContain('wsNum("reading.calendar_slice_chars", 24000), wsNum("reading.calendar_max_slices", 4)')
  expect(ai).toContain('centralAiRequest(it.model, it.kind,')   // English policy unchanged
  const rr = w.slice(w.indexOf('if (mode === "calendar_reread") {'), w.indexOf('// v0.47.0 (CF-247 Track C'))
  expect(rr).toContain('rpc("svc_calendar_reread_next_v2"'); expect(rr).toContain('p_reader: CALENDAR_READER'); expect(rr).toContain('{ ...calendarStarts(md), parser: CALENDAR_PARSER_DATES }')
  expect(rr).toContain('p_send_to_ai: !safe.safe'); expect(rr).not.toMatch(/firecrawl|useFc/i); expect(rr).toContain('paid_reads: 0')
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.59\.(7|8|9)"/)
})

test('the migration: the decided settings, every guarded edit by md5, the jobs, and the fixture runs in CI', () => {
  const m = fs.readFileSync('supabase/migrations/20261105020000_cf247_intake_calendar_v2.sql', 'utf8')
  expect(m).toMatch(/'intake_dates\.month_unique_match'[\s\S]{0,900}'number', to_jsonb\(1\), 0, 1, 'on\/off'/)           // decision §3: approved
  expect(m).toMatch(/'central\.auto_approve_calendar_dates'[\s\S]{0,700}'number', to_jsonb\(0\), 0, 1, 'on\/off'/)        // never switched on by itself
  for (const [sig, md5] of [['security.intake_dates_apply_v1(integer,uuid[])', 'd47fbe685ae62287264a1909c988e9d6'], ['security.intake_ui_selection_v1(text,integer)', 'a61e8114a65bc5e13007b8ff1d262976'],
    ['security.run_now_cohort_create_v1(text,uuid,text,text)', '410db5ca480e038e32d12c16f66eefa9'], ['public.svc_central_ai_next(integer)', 'fc8273f89031a309311d5e247f453fea'],
    ['public.svc_central_ai_record(bigint,jsonb,numeric,text)', '2f386c25a249d5c8edfb557a3fbc3d84'], ['security.policy_auto_approve_v1()', '12cce3d801e7c4b75e021430357fcca2']]) expect(m).toContain(`'${sig}', '${md5}'`)
  expect(m).toContain("select cron.schedule('calendar-reread', '13 * * * *',"); expect(m).toContain("select cron.schedule('process-results', '53 * * * *',")
  expect(m).toContain("and (r.kind <> 'intake_calendar' or fact_source_id is not distinct from r.fact_source_id)")
  const wf = fs.readFileSync('.github/workflows/intake-run-validate-test.yml', 'utf8')
  expect(wf).toContain('bash tests/fixtures/intake-calendar-v2/run.sh')
  expect(wf).toContain('bash tests/fixtures/intake-calendar-v2/browser.sh')   // the #872 browser workflow again on plan v3
  expect(fs.readFileSync('tests/fixtures/intake-calendar-v2/run.sh', 'utf8')).toContain('Refusing a remote database')
})
