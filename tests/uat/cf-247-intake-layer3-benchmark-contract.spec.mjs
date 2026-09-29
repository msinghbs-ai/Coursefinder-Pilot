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
  const sql = fs.readFileSync('supabase/migrations/20260929200000_cf247_intake_layer3_benchmark.sql', 'utf8')
  const gold = fs.readFileSync('supabase/migrations/20260929201000_cf247_intake_benchmark_gold.sql', 'utf8')
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
  const gold = fs.readFileSync('supabase/migrations/20260929201000_cf247_intake_benchmark_gold.sql', 'utf8')
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
  expect(INTAKE_VALIDATOR_VERSION).toBe('cf247-intake-validation-v1.1.0')
})
