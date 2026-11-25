// Guards: Global Autonomous PIM design approved Platform Admin 25 Nov 2026 18:42 AEDT (Admin #1097), Master Plan section 6.3 step 1, interface 2 (five separate facts, never one status); G3, manual locks and cron ceiling unchanged.
// s1161: security.field_state_v1 reads applicability, completeness, freshness, source finding, protected hold and the job fact; read only, service role only.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261127130000_cf247_s1161_pim_step1_field_state.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1161: the five facts are separate keys, and the job fact is not part of completeness', () => {
  for (const k of ["'applicability'", "'completeness'", "'freshness'", "'source_finding'", "'protected_hold'", "'processing'"]) expect(code).toContain(k)
  expect(code).toContain("then 'unmeasured' when v_held then 'verified' else 'none'")
  expect(code).toContain("'window_days', null")
})

test('s1161: a manual lock is a flag only; it never changes completeness', () => {
  expect(code).toContain("lk.field in (p_field, 'all')")
  expect(code).not.toMatch(/v_locked\s+then\s+'(none|verified)'/)
})

test('s1161: the source finding comes from the open absence row and only where no value is held', () => {
  expect(code).toContain('a.field = r.absence_field and a.resolved_at is null')
  expect(code).toContain("case when v_held or not v_measured then null")
  expect(code).toContain("coalesce(v_abs.absence_class, 'unknown')")
})

test('s1161: read only, service role only, guards G3 75/48, locks and cron; nothing written, dropped or scheduled', () => {
  expect(code).toContain('revoke all on function security.field_state_v1(text, uuid) from public, anon, authenticated')
  expect(code).toContain('grant execute on function security.field_state_v1(text, uuid) to service_role')
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).not.toMatch(/\b(insert\s+into|update\s+\w|delete\s+from|truncate|cron\.schedule|drop\s+(table|function|column|constraint))\b/i)
  expect(MIG).toContain('-- Replaces: none. Retires: none.')
})
