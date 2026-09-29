import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

// CF-247 plan item A3: Layer 3 intake benchmark. Pure validator/scoring functions and the
// no-activation contract of the benchmark function and its migration.
async function load() {
  const out = path.join(os.tmpdir(), `intake-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/_shared/cf247-intake-validation.ts', '--format=esm', `--outfile=${out}`])
  return import(out)
}
const PAGE = 'Bachelor of Example. CRICOS 012345A. Intakes: February and July (international students). Applications close 30 November. Census date 31 March. Updated 3 May 2026.'

test('an answer is accepted only with verbatim quotes that name every month', async () => {
  const { validateIntakeAnswer } = await load()
  expect(validateIntakeAnswer({ status: 'months', months: [2, 7], quotes: ['Intakes: February and July'], rationale: 'x' }, PAGE))
    .toMatchObject({ valid: true, status: 'months', months: [2, 7] })
  // whitespace differences are tolerated; changed characters are not
  expect(validateIntakeAnswer({ status: 'months', months: [2, 7], quotes: ['Intakes:  February and\nJuly'], rationale: 'x' }, PAGE).valid).toBe(true)
  expect(validateIntakeAnswer({ status: 'months', months: [2, 7], quotes: ['Intakes: Feb and July'], rationale: 'x' }, PAGE))
    .toMatchObject({ valid: false, errors: ['quote_not_in_page_text'] })
  // a month not written in the quotes (e.g. the census month) is rejected
  expect(validateIntakeAnswer({ status: 'months', months: [2, 3, 7], quotes: ['Intakes: February and July'], rationale: 'x' }, PAGE))
    .toMatchObject({ valid: false, errors: ['month_not_in_quotes'] })
  expect(validateIntakeAnswer({ status: 'months', months: [], quotes: [], rationale: 'x' }, PAGE).valid).toBe(false)
  expect(validateIntakeAnswer({ status: 'not_stated', months: [], quotes: [], rationale: 'x' }, 'no months here').valid).toBe(true)
  expect(validateIntakeAnswer({ status: 'not_stated', months: [2], quotes: [], rationale: 'x' }, PAGE).valid).toBe(false)
  expect(validateIntakeAnswer({ status: 'maybe', months: [], quotes: [] }, PAGE).valid).toBe(false)
  expect(validateIntakeAnswer({ status: 'months', months: [13], quotes: ['Intakes: February and July'] }, PAGE).errors).toContain('month_out_of_range')
})

test('months written: names, abbreviations, and "may" only when capitalised', async () => {
  const { monthsWritten, monthNamesToNumbers } = await load()
  expect(monthsWritten('Start dates: 24 Feb 2027, 13 Jul 2027, Sept intake')).toEqual([2, 7, 9])
  expect(monthsWritten('you may start in March')).toEqual([3])
  expect(monthsWritten('Intakes in May and November')).toEqual([5, 11])
  expect(monthNamesToNumbers(['July', 'February', 'July', 'Nope'])).toEqual([2, 7])
})

test('scoring: exact set match on stated cases; any month on a not-stated case is an invented intake', async () => {
  const { scoreCase, summarise, passesBar } = await load()
  expect(scoreCase({ status: 'months', months: [2, 7] }, { status: 'months', months: [2, 7] }).exact).toBe(true)
  expect(scoreCase({ status: 'months', months: [2, 7] }, { status: 'months', months: [2] })).toMatchObject({ exact: false, missed: [7] })
  expect(scoreCase({ status: 'months', months: [2] }, { status: 'months', months: [2, 11] })).toMatchObject({ exact: false, invented: [11] })
  expect(scoreCase({ status: 'not_stated', months: [] }, { status: 'months', months: [3] })).toMatchObject({ exact: false, invented: [3], safe_on_not_stated: false })
  // a rejected answer admits nothing: safe on a not-stated case, but never counted as exact
  expect(scoreCase({ status: 'not_stated', months: [] }, { status: null, months: [] })).toMatchObject({ exact: false, safe_on_not_stated: true, abstained: true })
  const rows = [
    ...Array.from({ length: 19 }, () => ({ gold: { status: 'months', months: [2] }, predicted: { status: 'months', months: [2] } })),
    { gold: { status: 'months', months: [2, 7] }, predicted: { status: 'months', months: [2] } },
    { gold: { status: 'not_stated', months: [] }, predicted: { status: 'not_stated', months: [] } },
  ]
  const s = summarise(rows)
  expect(s).toMatchObject({ stated_cases: 20, stated_exact: 19, stated_exact_rate: 0.95, not_stated_with_invented_intakes: 0, precision: 0.95, recall: 0.95 })
  expect(passesBar(s)).toBe(true)
  expect(passesBar(summarise([...rows, { gold: { status: 'not_stated', months: [] }, predicted: { status: 'months', months: [9] } }]))).toBe(false)
})

test('focused evidence keeps intake windows of long pages and whole short pages', async () => {
  const { focusText } = await load()
  expect(focusText('short page', 30000)).toBe('short page')
  const long = 'x '.repeat(40000) + 'Intakes: February and July ' + 'y '.repeat(40000)
  const f = focusText(long, 30000)
  expect(f.length).toBeLessThanOrEqual(30000)
  expect(f).toContain('Intakes: February and July')
})

test('benchmark function and migration activate nothing', () => {
  const fn = fs.readFileSync('supabase/functions/layer3-intake-benchmark/index.ts', 'utf8')
  const sql = fs.readFileSync('supabase/migrations/20260929211000_cf247_intake_layer3_benchmark.sql', 'utf8')
  const gold = fs.readFileSync('supabase/migrations/20260929212000_cf247_intake_benchmark_gold.sql', 'utf8')
  // nonce-only, pinned model, paused profile, json_schema strict, provider routing control only
  expect(fn).toContain('svc_pilot_consume_nonce')
  expect(fn).toContain('intake profile must be paused during benchmark')
  expect(fn).toContain('a pinned, individually named model is required')
  expect(fn).toMatch(/provider: \{ require_parameters: true \}/)
  expect(fn).toContain('strict: true')
  // a single pinned model: no "models" fallback list and no auto router in the request body
  expect(fn).not.toMatch(/[^_]models:\s*\[|"openrouter\/auto"/)
  expect(fn).toMatch(/BUDGET_USD = 3\.0/)
  // no admission, cron, hand-off or consumer function is touched
  for (const s of [fn, sql, gold]) {
    expect(s).not.toMatch(/cron\.schedule|coverage_admission_apply_v1\s*\(|layer3_work_items|website_edge_|zoho|wix-|scholarship_read/i)
  }
  expect(sql).toMatch(/'mistralai\/mistral-small-3\.2-24b-instruct'/)
  expect(sql).toMatch(/array\['provider_intake_validation'\]/)
  expect(sql).toMatch(/false,true,\s*\n\s*jsonb_build_object\('state','pending_intake_benchmark'/)
  // the only replaced live function is guarded by its reviewed checksum
  expect(sql).toContain("md5(prosrc) from pg_proc where oid='pipeline.svc_pilot_submit_nonce(text,jsonb)'::regprocedure)<>'765217baba62e3f81f680305d327e117'")
  // finalise never unpauses or enables the profile
  expect(sql).not.toMatch(/paused\s*=\s*false|enabled\s*=\s*true/)
})

test('gold set: at least 40 cases over at least 15 providers, each months answer backed by an excerpt', () => {
  const gold = fs.readFileSync('supabase/migrations/20260929212000_cf247_intake_benchmark_gold.sql', 'utf8')
  const rows = [...gold.matchAll(/^\s*\('([a-z0-9-]+)','([0-9a-f-]{36})','([0-9a-f]{64})','(months|not_stated)','\{([0-9,]*)\}',(?:\$x\$([\s\S]*?)\$x\$|null),'(l2_[a-z_]+)'/gm)]
  expect(rows.length).toBeGreaterThanOrEqual(40)
  const providers = new Set(rows.map((r) => r[1].split('-')[0]))
  expect(providers.size).toBeGreaterThanOrEqual(15)
  for (const r of rows) {
    if (r[4] === 'months') { expect(r[5].length).toBeGreaterThan(0); expect((r[6] || '').length).toBeGreaterThan(5) }
    else expect(r[5]).toBe('')
  }
  const buckets = new Set(rows.map((r) => r[7]))
  expect(buckets.has('l2_right') && buckets.has('l2_wrong')).toBe(true)
  expect([...buckets].some((b) => b.startsWith('l2_empty'))).toBe(true)
})

test('answers are produced in reading order (rationale, quotes, months, status)', async () => {
  const { INTAKE_RESPONSE_SCHEMA, INTAKE_VALIDATOR_VERSION } = await load()
  expect(INTAKE_RESPONSE_SCHEMA.required).toEqual(['rationale', 'quotes', 'months', 'status'])
  expect(Object.keys(INTAKE_RESPONSE_SCHEMA.properties)).toEqual(['rationale', 'quotes', 'months', 'status'])
  expect(INTAKE_VALIDATOR_VERSION).toBe('cf247-intake-validation-v1.2.0')
})

// ---- requalification (Platform Admin option 1) ----
test('safety rule: narrow whole-course blockers force not_stated; partial restrictions do not', async () => {
  const { intakeSafetyBlockers, applyIntakeSafetyRule, validateIntakeAnswer } = await load()
  const codes = (t) => intakeSafetyBlockers(t).map((b) => b.code)
  expect(codes('Duration 1 year full-time (Available part-time) Not available to student visa holders. Intake/s Check dates')).toEqual(['not_available_to_student_visa_holders'])
  expect(codes('This course is not available to international students. Intakes: February')).toEqual(['course_not_open_to_international'])
  expect(codes('Next start date &times; No current intake This program is not currently accepting new applications.')).toEqual(['no_current_intake'])
  expect(codes('This program has been suspended from September 2024. There are no further intakes of students planned.')).toEqual(['no_current_intake'])
  expect(codes('Notice Not Accepting Enrolments Entry Requirements')).toEqual(['no_current_intake'])
  // partial restrictions and ordinary pages are not blockers
  expect(codes('Online programs are not available to Student visa holders. Start Feb, Jul')).toEqual([])
  expect(codes('Trimester 3 intake is part-time and online only, therefore is not available to International students studying in Australia on a student visa.')).toEqual([])
  expect(codes('French This major is not available for students commencing in 2026.')).toEqual([])
  expect(codes('Applications for 2026 are now closed. The next available intake will commence in Semester 1 2027')).toEqual([])
  expect(codes('Intakes: February and July')).toEqual([])
  // applied after the model: an accepted months answer becomes not_stated; never the reverse
  const page = 'Not available to student visa holders. Starting date Semester 1 - February'
  const v = validateIntakeAnswer({ status: 'months', months: [2], quotes: ['Semester 1 - February'], rationale: 'x' }, page)
  expect(v).toMatchObject({ valid: true, status: 'months' })
  expect(applyIntakeSafetyRule(v, intakeSafetyBlockers(page))).toMatchObject({ status: 'not_stated', months: [], errors: ['safety_rule:not_available_to_student_visa_holders'] })
  const ns = { valid: true, status: 'not_stated', months: [], errors: [] }
  expect(applyIntakeSafetyRule(ns, [])).toBe(ns)
})

test('up to 12 verbatim quotes; "every month except" stays rejected; tuned prompt rules removed', async () => {
  const { validateIntakeAnswer, MAX_QUOTES, INTAKE_SYSTEM_PROMPT } = await load()
  expect(MAX_QUOTES).toBe(12)
  const dates = ['20 July 2026', '3 August 2026', '5 October 2026', '2 November 2026', '4 January 2027', '1 February 2027', '5 April 2027', '3 May 2027', '5 July 2027']
  const page = 'Upcoming intakes ' + dates.join(' ')
  expect(validateIntakeAnswer({ status: 'months', months: [1, 2, 4, 5, 7, 8, 10, 11], quotes: dates, rationale: 'x' }, page).valid).toBe(true)
  expect(validateIntakeAnswer({ status: 'months', months: [7], quotes: Array(13).fill('20 July 2026'), rationale: 'x' }, page).errors).toContain('too_many_quotes')
  const except = 'Intake Dates: Monthly intakes except June and December'
  expect(validateIntakeAnswer({ status: 'months', months: [1, 2, 3, 4, 5, 7, 8, 9, 10, 11], quotes: [except], rationale: 'x' }, except).errors).toContain('month_not_in_quotes')
  expect(INTAKE_SYSTEM_PROMPT).not.toMatch(/glossary|suspended|student visa holders/)
  expect(INTAKE_SYSTEM_PROMPT).toContain('one to twelve short passages')
})

test('requalification migrations: frozen holdout, guarded replacements, nothing activated', () => {
  const sql = fs.readFileSync('supabase/migrations/20260929220000_cf247_intake_requalify.sql', 'utf8')
  const hold = fs.readFileSync('supabase/migrations/20260929221000_cf247_intake_holdout_gold.sql', 'utf8')
  const dev = fs.readFileSync('supabase/migrations/20260929212000_cf247_intake_benchmark_gold.sql', 'utf8')
  const fn = fs.readFileSync('supabase/functions/layer3-intake-benchmark/index.ts', 'utf8')
  for (const s of [sql, hold]) {
    expect(s).not.toMatch(/cron\.schedule|coverage_admission_apply_v1\s*\(|layer3_work_items|website_edge_|zoho|wix-|scholarship_read/i)
    expect(s).not.toMatch(/paused\s*=\s*false|enabled\s*=\s*true/)
  }
  for (const [name, md5] of [['cases_service()', 'e7506c861179148f9a9ce3667a90c484'], ['profile_service()', '4378b41af1c7a3b811f1ab8a006a08d7'],
    ['result_record_service(text,uuid,jsonb)', '53f6629f1d745013d1d5178f7840eb14'], ['finalise_service(text,jsonb,text)', 'e2b68a46f16e9661e6d46dc991165dde']])
    expect(sql).toContain(`oid='public.layer3_intake_benchmark_${name}'::regprocedure)<>'${md5}'`)
  expect(sql).toMatch(/'mistralai\/mistral-medium-3\.1'/)
  expect(sql).toMatch(/false,true,jsonb_build_object\('state','pending_intake_benchmark'/)
  // holdout: frozen with a recorded digest, no overlap with the development set (cases or providers)
  const digest = (hold.match(/Frozen digest \(sha256\): ([0-9a-f]{64})/) || [])[1]
  expect(digest).toBeTruthy()
  expect(hold).toContain(`pipeline.layer3_intake_gold_digest('a3-holdout-1')<>'${digest}'`)
  expect(hold).toContain(`values ('a3-holdout-1', 45, '${digest}'`)
  const row = /^\s*\('([a-z0-9-]+)','([0-9a-f-]{36})','([0-9a-f]{64})','(months|not_stated)','\{([0-9,]*)\}',(?:\$x\$([\s\S]*?)\$x\$|null),'(l2_[a-z_]+)'/gm
  const h = [...hold.matchAll(row)], d = [...dev.matchAll(row)]
  expect(h.length).toBe(45)
  expect(h.filter((r) => r[4] === 'months').length).toBeGreaterThanOrEqual(15)
  expect(h.filter((r) => r[4] === 'not_stated').length).toBeGreaterThanOrEqual(15)
  const devCourses = new Set(d.map((r) => r[2]))
  expect(h.some((r) => devCourses.has(r[2]))).toBe(false)
  expect(new Set(h.map((r) => r[1].split('-')[1])).size).toBeGreaterThanOrEqual(15)
  for (const r of h) if (r[4] === 'months') expect((r[6] || '').length).toBeGreaterThan(5)
  // runs are refused on an unfrozen or changed gold set; the safety rule runs before and after the model
  expect(fn).toContain('is not frozen or has changed since it was frozen')
  expect(fn).toMatch(/const attempts = blockers\.length \? 0/)
  expect(fn).toContain('applyIntakeSafetyRule(validateIntakeAnswer(answer, text), blockers)')
  expect(fn).toMatch(/safety_rules: INTAKE_SAFETY_RULES/)
})
