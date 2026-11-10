// Guards: Platform Admin directive 10 Nov 2026 14:02 (scale the course-description machine admission by removing avoidable declines and holds, without weakening identity proof, source evidence, manual locks or rejection memory; accurate flow accounting in the EXISTING Data Delivery stages): source contract over migration 20261110180000, its forward recovery, the screen, the mock and the workflow. The behaviour is proved by the PostgreSQL fixture tests/fixtures/cdesc-throughput/run.sh (run in CI by course-descriptions-test.yml) and by the browser specs of the panel.
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261110180000_cf247_cdesc_decline_throughput.sql', 'utf8')
const R = fs.readFileSync('supabase/held/cdesc_decline_throughput_forward_recovery.sql', 'utf8')
const UI = fs.readFileSync('src/DataDelivery.jsx', 'utf8')
const WF = fs.readFileSync('.github/workflows/course-descriptions-test.yml', 'utf8')
const EDITS = [
  ['security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)', '3bb5d62b5e86cd7c76707171e02a3ae5', '6e65745a7863f0dae97a743821475eb0'],
  ['security.course_description_machine_check_v1(uuid)', '3e0fe24d762e7fc4348865ea09499690', '4c321730269064b42ff9ac10a114336b'],
  ['security.enrich_course_text_record_v1(bigint,jsonb)', 'c52c1969a80f2d3db1d81a4e46a49cd9', '82e93b8b73d1f13ac3fd62dbb59264f9'],
  ['security.course_description_promote_held_v1(uuid)', '1c990fb9c93b1841195160a0e9a712ae', '2f46bf63e50726d67bdd9d7cf74e915a'],
  ['security.enrich_course_text_gaps_v1(text[])', '5352bc7ea7bbf3ef00bd616f2897f2f4', '66d9dad4eb0d743b804097b1bf9d38d2'],
  ['security.course_description_machine_run_v1()', '452e3ae1ed2ab196865e2905ad2801e1', 'faa6dab1bfeef3464ba86fac11b34766'],
  ['security.data_delivery_cdesc_stages_v1()', 'd2a913a4d294f71fadf949bff6786f94', 'bf7c8c712273ae99b885e748ff58b998'],
]

test('the migration follows the house pattern: header, seven guarded edits, new read-only helpers, nothing dropped, no existing setting changed', () => {
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
  for (const [sig, before, after] of EDITS) {
    expect(M, sig).toContain(sig)
    expect(M, sig).toContain(before)
    expect(M, sig).toContain(after)
    expect(R, `${sig} (recovery)`).toContain(before)
  }
  expect(M).toContain('supabase/held/cdesc_decline_throughput_forward_recovery.sql')
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(M).not.toMatch(/\balter\s+table\b/i)
  expect(M).not.toContain('@@MD5_')
  // the only top-level write to a setting is the insert of the two new lists, and it never overwrites an existing value
  expect(M).not.toMatch(/^\s*update\s+pipeline\.platform_toolset_settings/im)
  expect(M).toMatch(/on conflict[^;]*do nothing/i)
  expect(M).toContain("'enrich.course_description_learner_words'")
  expect(M).toContain("'enrich.course_description_supported_words'")
  expect(M).toContain('must apply exactly once')
  expect(M).toContain('differs from the definition this change edits')
})

test('the protections stay: the review-first setting is not read or changed, the margin test and the identity proof are kept, a duplicate is never admitted', () => {
  expect(M).not.toMatch(/(update|insert into)[^;]*enrich\.course_description_review_first/i)
  expect(M).not.toMatch(/(?<!--.*)pipeline_num_v1\('enrich\.course_description_review_first', 0\) >= 1/)   // nothing branches on it: only the post-check proves it is still on
  expect(M).toContain("raise exception 'post-check: review_first must be untouched'")
  expect(M).toContain("g.score - g.runner_up < 0.1")          // the margin stays; only a code proof with a unique page is exempt
  expect(M).toContain("g.basis = 'ai_match'")                   // an AI match is still declined for margin
  expect(M).toContain("g2.course_id <> g.course_id")            // a CRICOS-code page shared by another course is still thin
  expect(M).toContain('cdesc_parked_other_v1(o.id)')            // only an older, not otherwise parked twin blocks: the oldest goes on to the duplicate rules
  // the recheck makes no AI call and spends nothing
  const rc = M.slice(M.indexOf('create or replace function security.cdesc_recheck_held_v1'), M.indexOf('comment on function security.cdesc_recheck_held_v1'))
  expect(rc.length).toBeGreaterThan(500)
  expect(rc).not.toMatch(/openrouter|http_post|net\.http|ai_cost|reserve/i)
  expect(rc).toContain('enrich_course_text_record_v1')
})

test('QA conditions: a currency code is never a paper code, leading the way still refuses, the learner quote must speak to the reader, a shared page is found by its normalised address or evidence, wording at three providers is not tie-broken', () => {
  expect(M).toContain("(a|the)\\s+teams?")                                   // only the verb senses of leading are set aside
  expect(M).not.toMatch(/leading\\s\+\(to\|into\|towards\?\|a\|an\|the/)       // a|an|the are no longer in the alternation
  expect(M).toContain("\\m(aud|usd|nzd|eur|gbp|cad|sgd|cny|jpy|inr|hkd|chf)\\s?[0-9]")
  expect(M).toContain("\\m(papers?|courses?|units?|subjects?|modules?)\\M")
  expect(M).toContain("v_q !~ '\\myou(r|rs|rself)?\\M'")
  expect(M).toContain("regexp_replace(regexp_replace(g2.url, '[?#].*$', ''), '/+$', '')")
  expect(M).toContain('g2.evidence_id = g.evidence_id')
  expect(M).toContain('select count(distinct c3.provider_id) >= 3 into v_many')
  expect(M).toContain('v_many or ((o.created_at, o.id) < (i.created_at, i.id)')
  // the header says only what the code does about word-form figures
  expect(M).toContain('a figure written as a word (for example "three years") is not caught by the shared figures rule')
  expect(M).not.toContain('Durations, hours,\n--      weeks, counts of anything else, prices')
})

test('the forward recovery restores the seven live bodies and is guarded by the md5 of what is live', () => {
  expect(R).toContain('5352bc7ea7bbf3ef00bd616f2897f2f4')
  expect(R).toContain('66d9dad4eb0d743b804097b1bf9d38d2')
  expect(R).not.toMatch(/^\s*drop\b/im)
  expect((R.match(/CREATE OR REPLACE FUNCTION/g) || []).length).toBe(7)
})

test('Data Delivery: one additive key "flow" on the existing course stages, read only and cheap; the screen draws it inside the existing box; a missing key is Not measured', () => {
  expect(M).toContain("'flow', security.data_delivery_cdesc_flow_v1(),")
  const fn = M.slice(M.indexOf('create or replace function security.data_delivery_cdesc_flow_v1'), M.indexOf('comment on function security.data_delivery_cdesc_flow_v1'))
  expect(fn).not.toMatch(/\b(insert|delete|truncate)\b|\bupdate\s+[a-z]/i)
  expect(fn).toContain("'known', false, 'reason', 'The flow counts could not be read: ' || sqlerrm")
  for (const k of ["'eligible'", "'gain'", "'declined_by_cause'", "'held_by_cause'", "'reads'", "'run'", "'blocker'"]) expect(fn, k).toContain(k)
  expect(M).toContain('revoke all on function security.data_delivery_cdesc_flow_v1() from public, anon, authenticated;')
  expect(UI).toContain('<Flow fl={st.flow}/>')
  expect(UI).toContain('data-dd-flow="unknown"')
  expect(UI).toContain('if(fl==null)return')
  expect(UI).toContain('fl.declined_by_cause==null?null:')   // a missing list is Not measured, never 0
  expect((UI.match(/export default function/g) || []).length).toBe(1)
  expect(UI).toContain('data-dd-stages="known"')              // the existing box is still the one box
})

test('CI runs the fixture and this contract', () => {
  expect(WF).toContain('bash tests/fixtures/cdesc-throughput/run.sh')
  expect(WF).toContain('tests/fixtures/cdesc-throughput/**')
  expect(WF).toContain('tests/uat/cf-247-cdesc-decline-throughput-contract.spec.mjs')
  expect(fs.existsSync('tests/fixtures/cdesc-throughput/scenarios_outcomes.sql')).toBe(true)
  expect(fs.existsSync('tests/fixtures/cdesc-throughput/scenarios_flow.sql')).toBe(true)
})
