// Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): a provider held for identity by an earlier reader is offered to the current reader once more on the same stored page; a hold made by the current reader, or for any other rule, stays parked; the evidence signature includes the reader; every later check still applies.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261109181000_cf247_pdesc_identity_reeval.sql'
const M = fs.readFileSync(MIG, 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C = code(M)
const run = fs.readFileSync('tests/fixtures/pdesc-identity-reeval/run.sh', 'utf8')
const scenarios = fs.readFileSync('tests/fixtures/pdesc-identity-reeval/scenarios.sql', 'utf8')
const expected = fs.readFileSync('tests/fixtures/pdesc-identity-reeval/expected.txt', 'utf8').split('\n').filter(Boolean)
const workflow = fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')
const res = (label) => { const l = expected.find((x) => x.startsWith(label + '|')); expect(l, label).toBeTruthy(); return l.slice(label.length + 1) }

test('housekeeping: Replaces and Retires lines, comment and revoke on the new function, nothing dropped, no table or job added, the consumer API is not edited', () => {
  expect(M).toMatch(/^-- Replaces: .+/m)
  expect(M).toMatch(/^-- Retires: nothing/m)
  expect(C).not.toMatch(/\bdrop\s+(function|table|index|trigger)|\bdelete\s+from|\btruncate\b/i)
  expect(C).not.toMatch(/create table|cron\.schedule|cron\.alter_job/i)
  expect(C).toContain("comment on function security.pdesc_reader_behaviour_v1() is '")
  expect(C).toContain('revoke all on function security.pdesc_reader_behaviour_v1() from public, anon, authenticated;')
  const edits = [...C.matchAll(/pg_temp\.edit_all\('([^']+)'/g)].map((m) => m[1])
  expect(edits).toEqual(['security.provider_description_signature_v1(text,text,text)', 'security.provider_description_selection_v1(jsonb)'])
  expect(edits.filter((e) => /website_|zoho_|^api\./.test(e))).toEqual([])
  expect([...C.matchAll(/create or replace function ([a-z_]+\.[a-z_0-9]+)/g)].map((m) => m[1]).filter((n) => !n.startsWith('pg_temp.'))).toEqual(['security.pdesc_reader_behaviour_v1'])
  expect(C).not.toMatch(/(insert\s+into|update)\s+(pipeline\.provider_description_reads|pipeline\.layer4_|catalogue\.providers|pipeline\.ops_remedy)/i)
})

test('the edits are guarded by the live body md5 (read 9 Nov 2026) and the recorded after md5', () => {
  const hdr = [...M.matchAll(/^--   ([a-z0-9_.]+\([^)]*\)) ([0-9a-f]{32}) -> ([0-9a-f]{32})/gm)].map((m) => [m[1], m[2], m[3]])
  expect(hdr.map((h) => h[0])).toEqual(['security.provider_description_signature_v1(text,text,text)', 'security.provider_description_selection_v1(jsonb)'])
  expect(hdr.map((h) => h[1])).toEqual(['b48bbd5b345f2e7b9a1fc6df9958163b', 'c8dd7882a5a6c5b174a829972d475d40'])
  for (const [sig, before, after] of hdr) expect(C, sig).toContain(`'${sig}', '${before}', '${after}'`)
  expect(C).toContain('differs from the definition this change edits')
  expect(C).toContain('must apply exactly once')
  for (const t of ['the changed functions differ from the edited ones', 'the migration changed setting values', 'the second run was not a no-op', 'case "$DB" in g_*)', 'differs from the definition this change edits']) expect(run).toContain(t)
})

test('G2: the identity rules are a setting with label, range, unit, section and used_by; no rule list is written into a function', () => {
  expect(C).toMatch(/\('pipeline', 'pdesc\.identity_reeval_rules', 'Provider descriptions: [^']+',/)
  expect(C).toContain(`'list', '["provider_name_conflict", "provider_name_not_proved", "provider_subunit_source"]'::jsonb, 0, null, 'rules', 1023, 'Provider descriptions', 'security.provider_description_selection_v1',`)
  expect(C).toContain('on conflict (toolset_key, key) do nothing;')
  expect(C).toContain("security.toolset_setting('pipeline','pdesc.identity_reeval_rules')")
  const fn = C.slice(C.indexOf("select pg_temp.edit_all('security.provider_description_selection_v1"))
  expect(fn.match(/'provider_name_(conflict|not_proved)'|'provider_subunit_source'/g) || []).toEqual([])
  expect(res('setting')).toBe('["provider_name_conflict", "provider_name_not_proved", "provider_subunit_source"]|list|rules|Provider descriptions|true|true')
})

test('positive: a hold made by an earlier reader is offered again; the signature includes the reader so a failure recorded for the earlier reader does not block the current one', () => {
  expect(C).toContain("coalesce(security.pdesc_reader_behaviour_v1(),'')")
  expect(res('current_reader')).toBe('provider-description-source-guard-v2')
  expect(res('v1_conflict_offered')).toBe('eligible')
  expect(res('v1_not_proved_offered')).toBe('eligible')
  expect(res('v1_subunit_offered')).toBe('eligible')
  expect(res('unstamped_conflict_offered')).toBe('eligible')
  expect(res('sig_changes_with_reader')).toBe('true|provider-description-source-guard-v2')
  expect(res('sig_stable_within_reader')).toBe('true')
  expect(res('retry_old_signature')).toBe('false')
  expect(res('retry_new_signature')).toBe('true')
  expect(res('v10_over_v9')).toBe('provider-description-source-guard-v10|eligible|unchanged_unsuitable_evidence')
})

test('negative: the current reader\'s hold, other rules, a person\'s rejection, an empty setting and a manual lock stay parked; a re-judged hold is parked again', () => {
  expect(res('no_reader')).toBe('(none)')
  expect(res('v1_only_parked')).toBe('provider-description-source-guard-v1|unchanged_unsuitable_evidence')
  expect(res('v2_conflict_parked')).toBe('unchanged_unsuitable_evidence')
  for (const r of ['v1_verbatim_parked', 'v1_quote_parked', 'v1_not_stated_parked', 'rejected_parked', 'setting_empty_parked', 'judged_again_parked']) expect(res(r), r).toBe('unchanged_unsuitable_evidence')
  expect(res('manual_lock_wins')).toBe('manual_lock')
  expect(res('setting_narrowed')).toBe('eligible|unchanged_unsuitable_evidence')
  // the edits only add the "earlier reader" exception to the two parking branches; the identity proof (worker), the budget and Layer 4 are not touched
  expect(C.match(/and not \(r\.state='held' and v_idr \? r\.rule and coalesce\(r\.checks->'identity'->>'reader_behavior_version',''\) is distinct from coalesce\(v_cur,''\)\)/g)).toHaveLength(2)
  expect(C).not.toMatch(/pdesc\.ai_usd_max|pdesc\.firecrawl_reads_max/)
})

test('the harness runs in the workflow and every printed scenario is in the expected output', () => {
  expect(workflow).toContain('bash tests/fixtures/pdesc-identity-reeval/run.sh')
  expect(workflow).toContain('tests/uat/cf-247-s511-pdesc-identity-reeval-contract.spec.mjs')
  const printed = [...scenarios.matchAll(/select '([a-z0-9_]+)\|'/g)].map((m) => m[1])
  for (const p of new Set(printed)) expect(expected.some((e) => e.startsWith(p + '|')), p).toBe(true)
  expect(scenarios).not.toMatch(/\bcommit\b/i)
  expect(res('grants')).toBe('false|false')
})
