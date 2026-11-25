// Guards: Global Autonomous PIM design approved Platform Admin 25 Nov 2026 18:42 AEDT (Admin #1097), Master Plan section 6.3 step 1, interface 1; G2 (rule is data), G3 (consumer API untouched), manual locks and cron ceiling unchanged.
// s1160: applicability is held in pipeline.field_register and read through security.field_applicable_v1; nothing scheduled, dropped or deleted.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261127040000_cf247_s1160_pim_step1_field_applicability.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1160: the register gains grain, rule, rule data and the absence field name, all additive', () => {
  for (const c of ['entity_grain text', "applicability_rule text not null default 'always'", "applicability_param jsonb not null default '{}'::jsonb", 'absence_field text'])
    expect(code).toContain(c)
  expect(code).toContain("when 'academic_entry' then 'entry_requirements'")
  expect(code).toContain("check (applicability_rule in ('always', 'countries'))")
})

test('s1160: only registered_tuition carries a rule, and its countries are data', () => {
  expect(code).toContain("where field = 'registered_tuition' and applicability_rule = 'always'")
  expect(code).toContain("jsonb_build_array('AU')")
  expect((code.match(/set applicability_rule = 'countries'/g) || []).length).toBe(1)
})

test('s1160: the function checks registration, then a recorded not-applicable absence, then the rule; service role only', () => {
  expect(code).toContain('create or replace function security.field_applicable_v1(p_field text, p_entity uuid)')
  expect(code).toContain("'field_not_registered'")
  expect(code).toContain("a.absence_class = 'not_applicable' and a.resolved_at is null")
  expect(code).toContain("'country_not_covered'")
  expect(code).toContain('revoke all on function security.field_applicable_v1(text, uuid) from public, anon, authenticated')
  expect(code).toContain('grant execute on function security.field_applicable_v1(text, uuid) to service_role')
})

test('s1160: guards G3 75/48, manual locks and active cron before and after; no job, drop or delete', () => {
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(code).toContain("raise exception 'guard: manual locks changed'")
  expect(code).toContain("raise exception 'guard: active cron jobs changed'")
  expect(code).not.toMatch(/cron\.schedule|\bdrop\s+(table|function|column|constraint)|\bdelete\s+from|\btruncate\b/i)
  expect(MIG).toContain('-- Replaces: none. Retires: none.')
})
