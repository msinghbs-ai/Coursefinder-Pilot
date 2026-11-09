// Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): a register-fact profile is not declined for the catalogue's own course labels (Employment Skills Programmes, Non AQF Award); outcome, award and ranking claims are still refused; a city that lost a character is not stated; a machine-text hold made under another text rule is looked at again once, only through the existing registry tier and machine admission.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261109180000_cf247_pdesc_registry_label_words.sql'
const M = fs.readFileSync(MIG, 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C = code(M)
const run = fs.readFileSync('tests/fixtures/pdesc-registry-labels/run.sh', 'utf8')
const scenarios = fs.readFileSync('tests/fixtures/pdesc-registry-labels/scenarios.sql', 'utf8')
const expected = fs.readFileSync('tests/fixtures/pdesc-registry-labels/expected.txt', 'utf8').split('\n').filter(Boolean)
const workflow = fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')
const res = (label) => { const l = expected.find((x) => x.startsWith(label + '|')); expect(l, label).toBeTruthy(); return l.slice(label.length + 1) }

test('housekeeping: Replaces and Retires lines, comments and revokes on the new function, nothing dropped, no table, job or setting added', () => {
  expect(M).toMatch(/^-- Replaces: .+/m)
  expect(M).toMatch(/^-- Retires: nothing/m)
  expect(C).not.toMatch(/\bdrop\s+(function|table|index|trigger)|\bdelete\s+from|\btruncate\b/i)
  expect(C).not.toMatch(/create table|cron\.schedule|cron\.alter_job/i)
  expect(C).not.toMatch(/(insert\s+into|update)\s+pipeline\.platform_toolset_settings/i)
  expect(C).toContain("comment on function security.pdesc_text_rule_fingerprint_v1() is '")
  expect(C).toContain('revoke all on function security.pdesc_text_rule_fingerprint_v1() from public, anon, authenticated;')
  const edits = [...C.matchAll(/pg_temp\.edit_all\('([^']+)'/g)].map((m) => m[1])
  expect(edits).toEqual(['security.provider_description_registry_profile_v1(uuid)', 'security.provider_description_registry_tier_v1()'])
  expect(edits.filter((e) => /website_|zoho_|^api\./.test(e))).toEqual([]) // G3: the consumer API is neither edited nor created
  expect([...C.matchAll(/create or replace function ([a-z_]+\.[a-z_0-9]+)/g)].map((m) => m[1]).filter((n) => !n.startsWith('pg_temp.'))).toEqual(['security.pdesc_text_rule_fingerprint_v1'])
})

test('the edits are guarded by the live body md5 (read 9 Nov 2026) and the recorded after md5', () => {
  const hdr = [...M.matchAll(/^--   ([a-z0-9_.]+\([^)]*\)) ([0-9a-f]{32}) -> ([0-9a-f]{32})/gm)].map((m) => [m[1], m[2], m[3]])
  expect(hdr.map((h) => h[0])).toEqual(['security.provider_description_registry_profile_v1(uuid)', 'security.provider_description_registry_tier_v1()'])
  expect(hdr.map((h) => h[1])).toEqual(['53f35748344bb1bc74b621979724e1b5', '1f9cbb77a59ab392a2e59b6aff317adb'])
  for (const [sig, before, after] of hdr) expect(C, sig).toContain(`'${sig}', '${before}', '${after}'`)
  expect(C).toContain('select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure')
  expect(C).toContain('differs from the definition this change edits')
  expect(C).toContain('must apply exactly once')
  for (const t of ['the changed functions differ from the edited ones', 'the migration changed a setting', 'the second run was not a no-op', 'case "$DB" in g_*)', 'differs from the definition this change edits']) expect(run).toContain(t)
})

test('the profile returns the labels it printed with its fixed wording, and only the profile does (provider-written tiers pass no codes)', () => {
  expect(C).toContain("'codes', jsonb_build_array(s2, reg.registration_code) || to_jsonb(coalesce(v_levels, '{}'::text[])) || to_jsonb(coalesce(v_fields, '{}'::text[]))")
  // the text rule is not edited: the exemption is the existing ignore-listed-codes step, so no word list, number or rule branch is loosened
  expect(M).not.toMatch(/pg_temp\.edit_all\('security\.pdesc_machine_text_check/)
  expect(res('gate_old_codes')).toBe('false|refused_word:employment')
  expect(res('gate_new_codes')).toBe('true|')
  expect(res('profile_codes')).toBe('Non AQF Award ; Employment Skills Programmes')
  expect(res('profile_ok')).toContain('Its listed courses are at Non AQF Award levels, in fields including Employment Skills Programmes.')
})

test('negative: outcome, employability, award and ranking claims, and the word outside the label, are still refused; provider-written tiers are unchanged', () => {
  expect(res('neg_outcome')).toBe('false|refused_word:employment')
  expect(res('neg_employability')).toBe('false|refused_word:employability')
  expect(res('neg_award')).toBe('false|refused_word:award')
  expect(res('neg_ranking')).toBe('false|refused_word:ranked')
  expect(res('neg_label_alone_lower')).toBe('false|refused_word:employment')
  expect(res('neg_stored_tier')).toBe('machine_text_refused_word')
  expect(res('label_whole')).toBe('true|true|')
  expect(res('label_plus_claim')).toBe('true|false|refused_word:ranked')
})

test('a city that lost a character is not stated as a place; a real macron is kept', () => {
  expect(C).toContain("position('?' in v_city) > 0 or position(chr(65533) in v_city) > 0")
  expect(res('city_question')).toContain('is a university in Victoria, Australia.')
  expect(res('city_replacement')).toContain('is a university in Victoria, Australia.')
  expect(res('city_macron_kept')).toContain('is a university in Whangārei, Victoria, Australia.')
})

test('re-evaluation: a hold made under another text rule is looked at again once, through the existing tier and machine admission only', () => {
  expect(C).toContain('not (h.rule like \'machine_declined_machine_text%\' and h.checks->>\'text_rule\' is distinct from v_fp)')
  expect(C).toContain("lr.rule like 'machine_declined_machine_text%' and lr.checks->>'tier' = 'registry_factual' and lr.checks->>'text_rule' is distinct from v_fp")
  expect(C).toContain("'tier_hold', true, 'text_rule', v_fp")
  // no description, read or Layer 4 item is written by the migration itself
  expect(C).not.toMatch(/(insert\s+into|update)\s+(pipeline\.provider_description_reads|pipeline\.layer4_|catalogue\.providers)/i)
  expect(res('reeval_before')).toBe('(none)|0')
  expect(res('reeval_run')).toBe('{"on": true, "held": 0, "errors": 0, "admitted": 1}')
  expect(res('reeval_admitted')).toBe('true|1')
  expect(res('reeval_audit')).toBe('registry_factual|pdesc-machine-v1|admitted|true')
  expect(res('reeval_again')).toBe('{"on": true, "held": 0, "errors": 0, "admitted": 0}')
  // a hold that is still refused is stamped with the current rule and waits; a changed rule looks at it once more
  expect(res('stale_run')).toContain('"held": 1')
  expect(res('stamped')).toBe('1|1')
  expect(res('current_again')).toBe('{"on": true, "held": 0, "errors": 0, "admitted": 0}|2')
  expect(res('rule_changed')).toBe('{"on": true, "held": 0, "errors": 0, "admitted": 1}|true')
  expect(res('fingerprint_grants')).toBe('false|false')
})

test('the harness runs in the workflow and every printed scenario is in the expected output', () => {
  expect(workflow).toContain('bash tests/fixtures/pdesc-registry-labels/run.sh')
  expect(workflow).toContain('tests/uat/cf-247-s510-pdesc-registry-label-words-contract.spec.mjs')
  const printed = [...scenarios.matchAll(/select '([a-z0-9_]+)\|'/g)].map((m) => m[1])
  for (const p of new Set(printed)) expect(expected.some((e) => e.startsWith(p + '|')), p).toBe(true)
  expect(scenarios).not.toMatch(/\bcommit\b/i)
})
