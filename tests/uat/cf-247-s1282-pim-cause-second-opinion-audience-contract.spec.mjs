// Guards: DR-19 slice 3 (SS-Programme-Control 26 Nov 2026 22:32 AEDT): causes kept apart (account refusal, technical failure, insufficient evidence, no source, unproven identity), the existing human-assisted second-opinion step read and never switched on, international audience validity, and the s1277 strategy retained as a recovery policy; no new spend or mechanism
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261130040000_cf247_s1282_pim_cause_second_opinion_audience.sql', 'utf8')

test('s1282: causes come from configuration and evidence classes', () => {
  expect(sql).toContain("e.root_cause_class = 'service_limit' and p_reason ilike e.pattern) then 'account_refusal'")
  expect(sql).toContain("then 'technical_failure' end")
  for (const c of ['identity_unproven', 'no_source', 'insufficient_evidence']) expect(sql).toContain(`'${c}'`)
})

test('s1282: the second opinion is the existing framework, read, never switched on or spent', () => {
  expect(sql).toContain("security.pipeline_num_v1('har.ai_escalate_on', 0) >= 1")
  expect(sql).toContain("p.key = 'har.ai_escalation_model'")
  expect(sql).not.toMatch(/update pipeline\.platform_toolset_settings/i)
  expect(sql).not.toMatch(/openrouter|ai_invocations\s*\(/i)
})

test('s1282: audience validity and the retained policy', () => {
  expect(sql).toContain("'international_held'")
  expect(sql).toContain("'domestic_only'")
  expect(sql).toContain("values ('ai_account_refusal', ")
  expect(sql).toContain("'defer_recheck', false, null, null, 'budget', 'never', 'service_limit'")
})
