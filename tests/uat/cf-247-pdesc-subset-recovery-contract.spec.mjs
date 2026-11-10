// Guards: Platform Admin decision 10 Nov 2026 19:47 (F-PDESC.01-.05): source contract over migration 20261110210000 (sentence-subset recovery of machine-declined provider readings), its forward recovery and its fixture wiring. Behaviour against real SQL is the isolated PostgreSQL run tests/fixtures/pdesc-subset-recovery/run.sh.
// G1, G2, G3, G4 and housekeeping are guarded centrally (s42, s32, s57, s120); they are not asserted again here.
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261110210000_cf247_pdesc_sentence_subset_recovery.sql', 'utf8')
const R = fs.readFileSync('supabase/held/pdesc_sentence_subset_recovery_forward_recovery.sql', 'utf8')
const WF = fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')
const SQL = M.split('\n').filter(l => !/^\s*--/.test(l)).join('\n')

test('the migration follows the house pattern: md5-guarded edits, one new read-only function, nothing dropped, held forward recovery', () => {
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
  for (const h of ['dedf28930cc7a12ad31570dec0d2f334', 'ed205f4b6dbdaf1a27b1bdf39479a276', '15b2f9882e77d7fcf0a8a4be2b6df18f', '575bded841d3ceca0afc9bdf13bf4d82', '4a37300325d9da37ba26c92a0eda8279', 'e0fea4e1e736f97b5a7172ecb981501a', '5f2d1a514ffcb45582888a2f455c63b8']) expect(M, h).toContain(h)
  expect(M).toContain("raise exception 'live % differs from the definition this change edits")
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(SQL).not.toMatch(/insert into pipeline\.platform_toolset_settings|update pipeline\.platform_toolset_settings/i)
  expect(R).toContain('dedf28930cc7a12ad31570dec0d2f334')
  expect(R).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(M).toContain('supabase/held/pdesc_sentence_subset_recovery_forward_recovery.sql')
})

test('the recovery is subtractive: it drops sentences, reruns the same checks, admits through the existing admission under the machine rule, and calls no AI or crawler', () => {
  expect(M).toContain('provider_description_subset_v1')
  expect(M).toContain("'subset_of_reading'")
  expect(M).toContain('pdesc-machine-v1')
  expect(SQL).toContain('provider_description_validate_v1')
  expect(SQL).toContain('provider_description_machine_gate_v1')
  expect(SQL).not.toMatch(/firecrawl|openrouter|svc_provider_description_reserve/i)
  for (const code of ['every_sentence_refused', 'no_sentence_to_leave_out', 'name_not_in_remaining_quotes']) expect(M, code).toContain(code)
  // consumer API (G3): none of it is named
  expect(SQL).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
})

test('the fixture is wired into the provider-description workflow and covers the recovery and the attempts rules', () => {
  expect(WF).toContain('bash tests/fixtures/pdesc-subset-recovery/run.sh')
  expect(WF).toContain('tests/uat/cf-247-pdesc-subset-recovery-contract.spec.mjs')
  const exp = fs.readFileSync('tests/fixtures/pdesc-subset-recovery/expected.txt', 'utf8')
  for (const k of ['monash_description|true|approved', 'attempt_budget_refused|1|queued/0/ai_budget_refused', 'attempt_fetch_failed|true|1|queued/1/retry', 'attempt_not_found|true|1|held/2/no_about_page']) expect(exp, k).toContain(k)
})
