// Guards: StudySearch decision D3 / SS-008 (Platform Admin 31 Oct 2026 13:30, logical retirement; admin 2026-10-31-studysearch-transformation.md §14, §27): Rule 4 (low agreement, page wins) stays inactive, is marked retiring in the component register with its replacement and retire-after date, cannot be executed by an app role, and nothing is dropped or deleted
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261031060000_cf247_d3_rule4_retired.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('logical retirement: catalogue says retired; job and function marked retiring with replacement and date from the setting', () => {
  expect(m).toContain("set description = 'RETIRED (Platform Admin 31 Oct 2026, StudySearch decision D3: logical retirement;")
  expect(m).toContain("set status = 'retiring', replaced_by = 'Layer 4 review")
  expect(m).toContain("retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int")
  expect(m).toContain("('function', 'security.l4_rule_low_agreement_v1', 'L4 admit', 'Admission'")
  expect(m).toContain('-- Retires: job l4-rule-low-agreement and security.l4_rule_low_agreement_v1')
})

test('admissions stay off: the job must already be inactive, stays inactive, and no app role can run the function', () => {
  expect(m).toContain("raise exception 'D3: the Rule 4 job must already be inactive'")
  expect(m).toContain("raise exception 'D3 post-check: the job is active'")
  expect(m).toContain('revoke all on function security.l4_rule_low_agreement_v1() from public, anon, authenticated, service_role;')
  expect(code(m)).not.toMatch(/cron\.(schedule|alter_job|unschedule)/)
})

test('nothing deleted or dropped; history kept; consumer API untouched', () => {
  const c = code(m)
  expect(c).not.toMatch(/\b(drop|delete|truncate)\b/i)
  expect(c).not.toMatch(/uni_adapters|layer4_review_items|website_v2_|zoho_|function\s+api\./)
})
