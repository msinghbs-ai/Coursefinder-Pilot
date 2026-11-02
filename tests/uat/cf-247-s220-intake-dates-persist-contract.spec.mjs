// Guards: Intake year/date/deadline persistence (Platform Admin 2 Nov 2026 11:10)
// §2 "Prioritise persistence of intake year, actual start date and application deadline where the existing calendar reader already extracts
// those values"; 11:18 "demonstrate actual dates flowing from stored evidence through catalogue, search projection and consumer API".
// The parser (coverage-sweep policy.ts calendarStarts, calendar-dates-v1) keeps the day, year and "applications close" rows it used to drop;
// the migration applies them from the approved calendar to month intakes (off by default) and stops a re-admission from blanking them.
// The behaviour runs on isolated fixtures by tests/fixtures/intake-dates/run.sh (scratch PostgreSQL; the E16 fixture database for the live
// page check and search projection, the admission write and the intake guards rebuilt from this repository and checked against the live
// md5s, the migration applied twice, then fixtures.sql); this spec runs the parser and holds the contract and the fixture coverage.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const MIG = 'supabase/migrations/20261102080000_cf247_intake_dates_persist.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/intake-dates'
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const before = fs.readFileSync(`${FX}/before.mjs`, 'utf8')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); return m.slice(a, m.indexOf('\n$function$;', a)) }
const plan = fn('security.intake_dates_plan_v1')
const apply = fn('security.intake_dates_apply_v1')
const periods = fn('security.calendar_dated_periods_v1')

async function policyParser() {
  const out = path.join(os.tmpdir(), `policy-s220-${process.pid}.mjs`)
  execFileSync('npx', ['esbuild', 'supabase/functions/coverage-sweep/policy.ts', '--format=esm', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}

test('the parser keeps the printed day, year and deadline; months, years and quotes are exactly as before', async () => {
  const { calendarStarts, CALENDAR_DATES, POLICY_PARSER } = await policyParser()
  expect(CALENDAR_DATES).toBe('calendar-dates-v1')
  expect(POLICY_PARSER).toBe('provider-policy-v0.2.5')  // the approved proposals keep their parser key
  const cal = calendarStarts('## 2027 key dates\n| Date | Event |\n|---|---|\n| 1 March 2027 | Semester 1 starts |\n| 30 November 2026 | Applications close for Semester 1 |\n| 26 July 2027 | Semester 2 begins |\n| 10 June 2027 | Semester 1 exams |\n| Semester 2 applications close | Rolling, until places are filled |\n| 13 July 2027 | Semester 1 supplementary exams start |')
  const s1 = cal.periods.find((p) => p.period === 'semester 1'), s2 = cal.periods.find((p) => p.period === 'semester 2')
  expect(cal.dates).toBe('calendar-dates-v1')
  // exact date and year kept
  expect(s1.starts).toEqual([{ year: 2027, month: 3, day: 1, date: '2027-03-01', quote: '1 March 2027 | Semester 1 starts' }])
  // an "applications close" row becomes a deadline, with its own printed year
  expect(s1.deadlines).toEqual([{ year: 2026, month: 11, day: 30, date: '2026-11-30', quote: '30 November 2026 | Applications close for Semester 1', rolling: false }])
  // rolling wording is kept as text, never a date
  expect(s2.deadlines).toEqual([])
  expect(s2.deadline_rolling).toEqual(['Semester 2 applications close | Rolling, until places are filled'])
  // an exams row keeps giving its month (unchanged) but is never a start date
  expect(s1.months).toEqual([3, 7])
  expect(s1.starts.some((x) => x.month === 7)).toBe(false)
  // month-only stays month-only: a day with no printed year has no year and no date; an impossible day has no date
  const curtin = calendarStarts('## Semesters\n| Session | Key dates |\n|---|---|\n| Semester 1 |\n| Start date | Monday 16 February |\n| Semester 2 |\n| Start date | Monday 20 July |')
  expect(curtin.periods.map((p) => `${p.period}:${p.months.join(',')}`)).toEqual(['semester 1:2', 'semester 2:7'])
  expect(curtin.periods[0].starts).toEqual([{ year: null, month: 2, day: 16, date: null, quote: 'Start date | Monday 16 February' }])
  expect(calendarStarts('## Key dates 2027\n- Semester 1 begins 31 February 2027').periods[0].starts[0].date).toBeNull()
  // the heading's year counts as printed (as the months parser already used it)
  expect(calendarStarts('## Key dates 2027\n- Trimester 2 begins Monday 5 July').periods[0].starts[0].date).toBe('2027-07-05')
  // a day range: the year counts, the day does not (live: "Term 1 | 18 – 20 January 2027 | 25 January 2027")
  expect(calendarStarts('| Period | Starts |\n|---|---|\n| Term 1 begins | 18 – 20 January 2027 |').periods[0].starts[0]).toMatchObject({ year: 2027, month: 1, day: null, date: null })
  // a deadline-only period adds no start month
  expect(calendarStarts('## 2027\n- Term 4 applications close 1 August 2027').periods).toEqual([])
})

test('the admission write is edited only from its live md5 and checked after; the fixture run rebuilds it and the guards from the repository', () => {
  expect(m).toContain("select pg_temp.edit_once('security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)', '8674165fa03b97ca15c3bc82923b1288', 'c2cbc9ab616a77487d447991f33daaeb'")
  expect(code).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(code).toContain("raise exception '% after the edit has md5 %, expected %'")
  expect(run).toContain('"8674165fa03b97ca15c3bc82923b1288 44e23d4abc1d36cdbb85407287a87e5f d0490f3707199988e87b5f37ca5e7342"')
  expect(run).toContain('"04fa25d82c373de08767d5573d4caabc 5b45bbf1e39d9098d5f23de729418b2d"')  // the live search projection (after E16)
  expect(run).toContain('"4263b5ad2369e87c99674f9159d672f8"')  // the live API month helper
  expect(run).toContain("grep -c 'already applied' | grep -qx 1")
  for (const f of ['20261001173000_cf247_country_admission_rules', '20261023026000_cf247_fee_floor', '20261024004000_cf247_r1_backoff_ledger_identity',
    '20261015040000_cf247_intake_duplicates_and_ca_regions', '20260930120000_cf247_crud_manual_first', '20261001170000_cf247_course_links_and_applicants']) expect(before).toContain(f)
  // a write without a year keeps the held year, date and deadline; an older year never replaces a later one
  expect(m).toContain('do update set intake_year = case when excluded.intake_year is null or excluded.intake_year < ci.intake_year then ci.intake_year else excluded.intake_year end,')
  expect(m).toContain('application_deadline = case when excluded.intake_year > ci.intake_year then null else ci.application_deadline end,')
})

test('the dates come from the approved calendar only, as printed: stored quotes for calendars approved before calendar-dates-v1', () => {
  expect(periods).toContain("p.kind = 'intake_calendar' and p.status = 'approved'")
  expect(periods).toContain('order by p.decided_at desc nulls last, p.created_at desc limit 1')  // the calendar enrich_parse_intake_periods_v1 uses
  expect(periods).toContain("per.e->'starts'), ('deadline', per.e->'deadlines')")
  expect(periods).toContain("where not (per.e ? 'starts')")
  expect(periods).toContain("coalesce(nullif(z.d[5], '')::int, (regexp_match(z.q, '\\m(20\\d\\d)\\M'))[1]::int) y")  // the year printed in the same quote only
  expect(periods).toContain("where per.e->'months' @> to_jsonb(q.m)")  // only a month the person approved
  expect(periods).toContain('case when a.y is not null and a.d between 1 and')  // a date only with a printed day and year
  expect(periods).toContain("case when z.q !~ '\\m\\d{1,2}(st|nd|rd|th)?\\s*[–—-]\\s*\\d{1,2}(st|nd|rd|th)?\\s+[A-Za-z]' then coalesce(z.d[1], z.d[4])::int end d")
  expect(periods).toContain("q !~* '\\m(exams?|examinations?|supplementary|census|results|holidays?|break|recess|graduation|enrolment|withdraw\\w*)\\M'")
})

test('the plan keeps every guard: E16 page check, refused pages, locks, holds, only empty columns, never another year', () => {
  expect(plan).toContain('if security.page_refused_v1(r.course_id, v_url) then')
  expect(plan).toContain("v_chk := security.course_page_check_v1(r.course_id, v_url, null, null);\n    if v_chk->>'verdict' is distinct from 'pass' then")
  expect(plan).toContain("k.field in ('intakes', 'intake')")
  expect(plan).toContain('if security.course_held_v1(r.course_id) then')
  expect(plan).toContain('and (r.intake_year is null or s.year = r.intake_year);')  // a row with a year is never moved (past intakes stay history)
  expect(plan).toContain('(s.on_date >= v_today or')  // the next start on or after today
  expect(plan).toContain('v_start := case when cardinality(v_starts) = 1 then v_starts[1] end;')  // two start days: year only
  expect(plan).toContain("security.pipeline_num_v1('intake_dates.deadline_max_days_before', 366)")
  expect(plan).toContain('new_year := case when r.intake_year is null then v_year end;')
  expect(plan).toContain('new_start := case when r.start_date is null then v_start end;')
  expect(plan).toContain('new_deadline := case when r.application_deadline is null then new_deadline end;')
  expect(apply).toContain('set intake_year = coalesce(i.intake_year, p.new_year), start_date = coalesce(i.start_date, p.new_start),')
})

test('the re-apply is governed, idempotent, batched and off by default; nothing is switched on or changed by the migration', () => {
  expect(apply).toContain("coalesce((security.toolset_setting('pipeline', 'intake_dates.apply_enabled') #>> '{}')::boolean, false)")
  expect(apply).toContain("if not v_on then return jsonb_build_object('enabled', false, 'filled', 0); end if;")
  expect(m).toMatch(/\('pipeline', 'intake_dates\.apply_enabled', 'Intake dates: on',\n[^\n]*\n  to_jsonb\(false\)/)
  expect(plan).toContain("security.pipeline_num_v1('batch.intake_dates_apply', 200)")
  expect(plan).toContain('-- each row once for each approved calendar')
  expect(m).toContain("perform cron.alter_job((select jobid from cron.job where jobname = 'intake-dates-apply'), active := false);")
  expect(m).toContain("raise exception 'intake dates post-check: the setting must be off'")
  expect(m).toContain("raise exception 'intake dates post-check: the job must be paused'")
  const outside = code.replace(/\$function\$[\s\S]*?\$function\$/g, '').replace(/\$[on]\$[\s\S]*?\$[on]\$/g, '')
  expect(outside).not.toMatch(/\b(update|delete)\s+(catalogue|search)\./)
  expect(outside).not.toMatch(/^\s*(drop|truncate)\b/im)
})

test('the consumer API reads the same three fields through the existing projection: a value change, not a shape change', () => {
  // projection: catalogue.course_intakes -> search.course_documents.intake_options (live after E16, md5 checked by run.sh)
  const proj = fs.readFileSync('supabase/migrations/20261016010000_cf247_api_data_fixes.sql', 'utf8')
  expect(proj).toContain("jsonb_build_object('year',i.intake_year,'label',i.intake_label,'start_date',i.start_date,'application_deadline',i.application_deadline,'campus_id',i.campus_id)")
  // consumer API: api.website_v2_course_item builds intakes[] from intake_options; the fixtures run this exact expression (live md5 8f2a0ac9...)
  const api = fs.readFileSync('supabase/migrations/20261010006800_cf247_r4_published_gate.sql', 'utf8')
  const expr = "jsonb_agg(distinct jsonb_build_object('label', i->>'label', 'month', api.website_v2_label_month(i->>'label'), 'year', i->'year',\n                  'start_date', i->'start_date', 'application_deadline', i->'application_deadline'))\n                 from jsonb_array_elements(coalesce(d.intake_options,'[]'::jsonb)) i where nullif(i->>'label','') is not null), '[]'::jsonb)"
  expect(api).toContain(expr)
  expect(fixtures).toContain(expr)
  expect(fixtures).toContain("intake_options=s.intake_options,\n      earliest_intake_date=s.earliest_intake_date,\n      has_intake=(jsonb_array_length(s.intake_options)>0)")
  expect(proj).toContain("intake_options=s.intake_options,\n      earliest_intake_date=s.earliest_intake_date,\n      has_intake=(jsonb_array_length(s.intake_options)>0),")
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|function api\./)
})

test('the fixtures cover every case, from the stored reading to the consumer API intake objects', () => {
  for (const p of ['PASS stored readings: dated starts, deadlines, rolling text, month-only', 'PASS off by default', 'PASS exact date and year kept',
    'PASS month-only stays month-only', 'PASS rolling deadline marked', 'PASS an "applications close" row becomes a deadline', 'PASS a past-year intake is not overwritten',
    'PASS manual lock respected', 'PASS a refused page is not used', 'PASS backfill from stored readings', 'PASS the backfill is idempotent',
    'PASS chain: stored reading -> intake row -> search projection -> consumer API']) expect(fixtures).toContain(`raise notice '${p}';`)
  expect(fixtures).toContain(":'cal'::jsonb")  // the real parser's reading of calendar.md
  expect(run).toContain('CAL=$(node tests/fixtures/intake-dates/parse.mjs)')
  expect(fixtures).toContain("'page not proved to be the course''s own (E16 %'")
  expect(fixtures).toContain("'API: rolling deadline is null, never text in a date field'")
  expect(fixtures).toContain("'API: the same five keys'")
  expect(fs.readFileSync(`${FX}/calendar.md`, 'utf8')).toContain('| Semester 2 applications close | Rolling, until places are filled |')
})
