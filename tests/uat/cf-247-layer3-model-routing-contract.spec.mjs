import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

// CF-247 Layer 3 model routing (Platform Admin direction 29 Sep 2026 18:30 IST): pure validators and scoring of the
// shared routing contract, and the governance contract of the Edge function and migrations.
async function load() {
  const out = path.join(os.tmpdir(), `routing-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/_shared/cf247-model-routing.ts', '--bundle', '--format=esm', '--platform=neutral', `--outfile=${out}`])
  return import(out)
}
async function loadEnglish() {
  const out = path.join(os.tmpdir(), `english-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/_shared/cf247-english-validation.ts', '--format=esm', `--outfile=${out}`])
  return import(out)
}
const read = (p) => fs.readFileSync(p, 'utf8')

test('English answers are accepted only with a verbatim quote that names the test and every number', async () => {
  const { validateEnglishAnswer } = await loadEnglish()
  const PAGE = 'Entry requirements. International students must have IELTS 6.5 (Academic) with no band below 6.0, or PTE Academic 58. TOEFL iBT 79 is also accepted. Cambridge C1 169.'
  const ok = validateEnglishAnswer({ status: 'stated', rationale: 'x', tests: [
    { test: 'IELTS', overall: 6.5, min_band: 6, quote: 'IELTS 6.5 (Academic) with no band below 6.0' },
    { test: 'PTE', overall: 58, min_band: null, quote: 'PTE Academic 58' },
    { test: 'TOEFL_IBT', overall: 79, min_band: null, quote: 'TOEFL iBT 79 is also accepted' }] }, PAGE)
  expect(ok).toMatchObject({ valid: true, status: 'stated' })
  expect(ok.tests.map((t) => t.test)).toEqual(['IELTS', 'PTE', 'TOEFL_IBT'])
  // a number not written in its own quote, a quote that is not on the page, a quote that does not name the test
  expect(validateEnglishAnswer({ status: 'stated', tests: [{ test: 'IELTS', overall: 7, min_band: null, quote: 'IELTS 6.5 (Academic)' }] }, PAGE).errors).toContain('IELTS:overall_not_in_quote')
  expect(validateEnglishAnswer({ status: 'stated', tests: [{ test: 'IELTS', overall: 6.5, min_band: null, quote: 'IELTS 6.5 overall' }] }, PAGE).errors).toContain('IELTS:quote_not_in_page_text')
  expect(validateEnglishAnswer({ status: 'stated', tests: [{ test: 'PTE', overall: 58, min_band: null, quote: 'or PTE Academic 58' }, { test: 'TOEFL_IBT', overall: 58, min_band: null, quote: 'or PTE Academic 58' }] }, PAGE).errors).toContain('TOEFL_IBT:quote_does_not_name_test')
  // an equivalent score invented for another test is out of range and rejected (seen on the holdout)
  expect(validateEnglishAnswer({ status: 'stated', tests: [{ test: 'PTE', overall: 6, min_band: null, quote: 'or PTE Academic 58' }] }, PAGE).errors).toContain('PTE:overall_out_of_range')
  // IELTS band above overall, band for PTE, duplicates, unknown tests
  expect(validateEnglishAnswer({ status: 'stated', tests: [{ test: 'IELTS', overall: 6, min_band: 6.5, quote: 'IELTS 6.5 (Academic) with no band below 6.0' }] }, PAGE).valid).toBe(false)
  expect(validateEnglishAnswer({ status: 'stated', tests: [{ test: 'PTE', overall: 58, min_band: 50, quote: 'PTE Academic 58' }] }, PAGE).errors).toContain('PTE:min_band_invalid')
  expect(validateEnglishAnswer({ status: 'stated', tests: [{ test: 'CAE', overall: 169, min_band: null, quote: 'Cambridge C1 169' }] }, PAGE).errors).toContain('test_unknown')
  expect(validateEnglishAnswer({ status: 'not_stated', tests: [] }, 'no scores here').valid).toBe(true)
  expect(validateEnglishAnswer({ status: 'not_stated', tests: [{ test: 'IELTS', overall: 6, min_band: null, quote: 'IELTS 6.5 (Academic)' }] }, PAGE).valid).toBe(false)
})

test('numbers are matched as whole tokens (6.0 for 6, never 6 inside 65 or 6.5)', async () => {
  const { numberWritten } = await loadEnglish()
  expect(numberWritten('IELTS 6.0 overall', 6)).toBe(true)
  expect(numberWritten('IELTS 6 overall', 6)).toBe(true)
  expect(numberWritten('IELTS 6.5 overall', 6)).toBe(false)
  expect(numberWritten('PTE 65', 6)).toBe(false)
  expect(numberWritten('PTE 58.', 58)).toBe(true)
})

test('scoring: exact, wrong-admitted, withheld, incomplete and not-stated outcomes', async () => {
  const { scoreIntake, scoreEnglish, scoreTuition } = await load()
  const ok = (admitted, status = 'months') => ({ valid: true, errors: [], status, admitted })
  expect(scoreIntake({ status: 'months', months: [2, 7] }, ok({ months: [2, 7] })).outcome).toBe('exact')
  expect(scoreIntake({ status: 'months', months: [2, 7] }, ok({ months: [2] })).outcome).toBe('incomplete')
  expect(scoreIntake({ status: 'months', months: [2] }, ok({ months: [2, 11] }))).toMatchObject({ outcome: 'wrong_admitted', wrong: [11] })
  expect(scoreIntake({ status: 'not_stated', months: [] }, ok({ months: [3] })).outcome).toBe('wrong_admitted')
  expect(scoreIntake({ status: 'not_stated', months: [] }, ok(null, 'not_stated')).outcome).toBe('exact_not_stated')
  expect(scoreIntake({ status: 'months', months: [2] }, ok(null, 'not_stated')).outcome).toBe('not_stated_on_stated')
  expect(scoreIntake({ status: 'months', months: [2] }, { valid: false, errors: ['x'], status: null, admitted: null }).outcome).toBe('withheld')
  const g = { status: 'stated', tests: [{ test: 'IELTS', overall: 6.5, min_band: 6 }] }
  expect(scoreEnglish(g, ok({ tests: [{ test: 'IELTS', overall: 6.5, min_band: 6 }] }, 'stated')).outcome).toBe('exact')
  expect(scoreEnglish(g, ok({ tests: [{ test: 'IELTS', overall: 6.5, min_band: null }] }, 'stated')).outcome).toBe('incomplete')
  expect(scoreEnglish(g, ok({ tests: [{ test: 'IELTS', overall: 6, min_band: null }] }, 'stated')).outcome).toBe('wrong_admitted')
  expect(scoreEnglish(g, ok({ tests: [{ test: 'IELTS', overall: 6.5, min_band: 6 }, { test: 'PTE', overall: 58, min_band: null }] }, 'stated')).outcome).toBe('wrong_admitted')
  const t = { status: 'admit', amount: 42000, fee_year: 2027 }
  expect(scoreTuition(t, ok({ amount: 42000, fee_year: 2027 }, 'validated')).outcome).toBe('exact')
  expect(scoreTuition(t, ok({ amount: 42000, fee_year: null }, 'validated')).outcome).toBe('incomplete')
  expect(scoreTuition(t, ok({ amount: 42000, fee_year: 2026 }, 'validated')).outcome).toBe('wrong_admitted')
  expect(scoreTuition({ status: 'none' }, ok({ amount: 15000, fee_year: null }, 'validated')).outcome).toBe('wrong_admitted')
  expect(scoreTuition({ status: 'none' }, { valid: true, errors: [], status: 'no_candidate', admitted: null }).outcome).toBe('exact_not_stated')
  expect(scoreTuition({ status: 'none' }, { valid: false, errors: ['x'], status: 'rejected_validation', admitted: null }).outcome).toBe('withheld')
})

test('tuition check replicates the live interpreter and admission gates (basis must be quoted as annual)', async () => {
  const { checkTuition } = await load()
  const profile = { cost_ceiling_usd: 0.05, deterministic_validators: { confidence_min: 0, confidence_max: 1, review_confidence_min: 0.9, allowed_basis: ['annual', 'indicative_annual', 'per_year_explicit'], allowed_currencies: ['AUD', 'NZD'], amount_max: 250000 } }
  const ctx = { identity_match: true, provider_current_tuition: { amount: 24000, currency_code: 'AUD', basis: 'annual_or_indicative_requires_validation', fee_year: null, audience: 'international' } }
  const page = 'Fees International: AUD $24,000 per year. Course fee total AUD $72,000.'
  const cand = { amount: 24000, currency_code: 'AUD', basis: 'annual', fee_year: null, audience: 'international' }
  expect(checkTuition({ candidate_value: cand, confidence: 0.95, rationale: 'r', evidence_quotes: ['International: AUD $24,000 per year'] }, page, ctx, profile, 0.001))
    .toMatchObject({ valid: true, status: 'validated', admitted: { amount: 24000, basis: 'annual', fee_year: null } })
  // a resolved basis without annual wording in the quote is rejected; low confidence is withheld; a different amount is never accepted
  expect(checkTuition({ candidate_value: cand, confidence: 0.95, rationale: 'r', evidence_quotes: ['International: AUD $24,000'] }, page, ctx, profile, 0.001).status).toBe('rejected_validation')
  expect(checkTuition({ candidate_value: cand, confidence: 0.5, rationale: 'r', evidence_quotes: ['International: AUD $24,000 per year'] }, page, ctx, profile, 0.001).status).toBe('low_confidence')
  expect(checkTuition({ candidate_value: { ...cand, amount: 72000 }, confidence: 1, rationale: 'r', evidence_quotes: ['Course fee total AUD $72,000'] }, page, ctx, profile, 0.001).status).toBe('rejected_validation')
  expect(checkTuition({ candidate_value: null, confidence: 0, rationale: 'r', evidence_quotes: [] }, page, ctx, profile, 0.001).status).toBe('no_candidate')
  // an unresolved basis passes the interpreter but is held by the admission gate
  expect(checkTuition({ candidate_value: { ...cand, basis: 'annual_or_indicative_requires_validation' }, confidence: 1, rationale: 'r', evidence_quotes: ['International: AUD $24,000 per year'] }, page, ctx, profile, 0.001).status).toBe('admission_hold')
})

test('the live tuition request is the interpreter request, unchanged; intake and English requests use a strict schema and no seed', async () => {
  const { tuitionRequestBody, intakeRequestBody, englishRequestBody, isPinnedModel } = await load()
  const interp = read('supabase/functions/layer3-work-interpret/index.ts')
  const b = tuitionRequestBody({ model_identifier: 'm/x', max_output_tokens: 900, prompt_system: 'S' }, 'https://u', { identity_match: true }, 'TEXT')
  expect(b).toMatchObject({ model: 'm/x', temperature: 0, seed: 0, max_tokens: 900, provider: { require_parameters: true }, response_format: { type: 'json_object' } })
  expect(b.messages[1].content.startsWith('Task class: provider_current_tuition_validation\n\nGoverned Evidence source: https://u\n\n')).toBe(true)
  for (const line of ['"Task class: provider_current_tuition_validation"', 'Return exactly one JSON object with keys candidate_value, confidence, rationale, evidence_quotes.']) expect(interp).toContain(line)
  for (const f of [intakeRequestBody, englishRequestBody]) {
    const r = f('m/x', 'page', 1200)
    expect(r).toMatchObject({ temperature: 0, provider: { require_parameters: true }, response_format: { type: 'json_schema' } })
    expect(r.response_format.json_schema.strict).toBe(true)
    expect('seed' in r).toBe(false)
    expect('models' in r).toBe(false)
  }
  expect(isPinnedModel('qwen/qwen3-235b-a22b-2507')).toBe(true)
  expect(isPinnedModel('openrouter/auto')).toBe(false)
  expect(isPinnedModel('anthropic/claude-haiku-4.5')).toBe(true)
})

test('Edge function: nonce-only, returned model must equal the pinned id, US$8 qualification cap, credit floor from the register (Decision 252)', () => {
  const fn = read('supabase/functions/layer3-model-routing/index.ts')
  expect(fn).toContain('svc_pilot_consume_nonce')
  expect(fn).toMatch(/QUALIFICATION_CAP_USD = 8\.0/)
  // Decision 252 (4 Oct 2026): the floor and whether it applies come from the toolset register, not a constant
  expect(fn).not.toContain('CREDIT_FLOOR_USD')
  expect(fn).toContain('rpc("svc_layer3_credit_policy", {})')
  expect(fn).toContain('returned_model_mismatch')
  expect(fn).toContain('candidate profile must be paused during qualification')
  expect(fn).toContain('gold set ${body.gold_set} is not frozen or changed since it was frozen')
  expect(fn).not.toMatch(/website_edge_|zoho|wix-|scholarship/i)
  const wf = read('.github/workflows/deploy-edge-functions.yml')
  expect(wf).toContain('[layer3-model-routing]=false')
})

test('migrations: checksum-guarded replacements, nothing activated before the activation migration, no consumer or scholarship objects', () => {
  const dir = 'supabase/migrations-archive'
  const files = fs.readdirSync(dir).filter((f) => /^2026092923[0-4]\d{3}_cf247_l3_/.test(f)).sort()
  expect(files.length).toBeGreaterThanOrEqual(6)
  for (const f of files) {
    const s = read(path.join(dir, f))
    expect(s).not.toMatch(/website_edge_|zoho|wix-|scholarship_(read|sweep|discover|candidates)/i)
    if (!/activat/.test(f)) {
      expect(s).not.toMatch(/cron\.schedule|paused\s*=\s*false|enabled\s*=\s*true/)
    }
  }
  const foundation = read(path.join(dir, '20260929230000_cf247_l3_model_routing_foundation.sql'))
  expect(foundation).toContain("md5(prosrc) from pg_proc where oid='pipeline.svc_pilot_submit_nonce(text,jsonb)'::regprocedure)<>'bab3b602f58ad02a3db0f2a31ed9beab'")
  const fix = read(path.join(dir, '20260929230500_cf247_l3_routing_pages_fix.sql'))
  expect(fix).toContain("'7f4ee1534b7a3468b25f0b667d79f076'")
  const runtime = read(path.join(dir, '20260929231000_cf247_l3_fact_route_runtime.sql'))
  // admission only through the governed writer, write-only-when-empty, differences to Layer 4, snapshots before/after
  expect(runtime).toContain('public.svc_coursefacts_apply_record(')
  expect(runtime).toContain("security.consumer_api_snapshot_v1()")
  expect(runtime).toContain('pipeline.consumer_api_baselines')
  expect(runtime).toContain("'differs from the value already held'")
  expect(runtime).toContain("p_binding_hash is distinct from p.quality_benchmark->>'binding_hash'")
  // activation: cites the direction, checksum-guarded, gated on a passing fresh holdout, one route per task class
  const act = read(path.join(dir, '20260929234500_cf247_l3_activate_routes.sql'))
  expect(act).toContain('Platform Admin direction 29 Sep 2026 18:30 IST (CF-CHG-20260915-247)')
  expect(act).toContain("md5(prosrc)<>'eef1df739175da919f50a66ac2428a7b'")
  expect(act).toContain("digest=pipeline.layer3_holdout_digest(gold_set))<>3")
  expect(act).toContain("coalesce((r.q->>'wrong_admitted')::int,-1)<>0")
  expect(act).toContain("expected exactly one executable profile for %")
  expect(act).toContain("not (p.allowed_task_classes && array['scholarship_page_classification','scholarship_detail_extract'])")
  expect(act).not.toMatch(/delete from pipeline\.layer3_model_profiles/i)
})

test('holdout gold sets: frozen before any model run, disjoint from earlier intake sets, 15+ providers, excerpts for stated cases', () => {
  const gold = read('supabase/migrations-archive/20260929233000_cf247_l3_holdout_gold.sql')
  const rows = [...gold.matchAll(/\(\$x\$(l3r-[a-z]+-h1)\$x\$,\$x\$([a-z_]+)\$x\$,\$x\$([a-z0-9-]+)\$x\$,'([0-9a-f-]{36})','([0-9a-f-]{36})','([0-9a-f]{64})',\$x\$(\{.*?\})\$x\$,(null|\$x\$[\s\S]*?\$x\$),/g)]
  expect(rows.length).toBe(120)
  const bySet = (s) => rows.filter((r) => r[1] === s)
  expect(bySet('l3r-intake-h1').length).toBeGreaterThanOrEqual(40)
  expect(bySet('l3r-english-h1').length).toBeGreaterThanOrEqual(30)
  expect(bySet('l3r-tuition-h1').length).toBeGreaterThanOrEqual(30)
  for (const r of rows) {
    const g = JSON.parse(r[7])
    if (['months', 'stated', 'admit'].includes(g.status)) expect(r[8]).not.toBe('null')
  }
  const freeze = read('supabase/migrations-archive/20260929233500_cf247_l3_holdout_freeze.sql')
  expect(freeze).toContain("a model has already run on a holdout set; freezing now would not be before any model run")
  expect(gold).toContain('intake holdout overlaps an earlier intake gold set')
})
