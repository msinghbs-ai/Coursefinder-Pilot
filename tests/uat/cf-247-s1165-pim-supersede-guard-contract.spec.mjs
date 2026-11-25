// Guards: Global Autonomous PIM step 2 (Master Plan section 6.3; Platform Admin 25 Nov 2026 18:49): no supersession without a verified successor in the same transaction, else HELD:NO_SUCCESSOR; nothing dropped; G2, G3, locks, cron.
// s1165: security.supersede_guard_v1 and the deferred constraint trigger on catalogue.course_fees.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128040000_cf247_s1165_pim_supersede_guard.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1165: the guard needs another active row of the same course and fee type, or an inactive course', () => {
  expect(code).toContain("'NO_SUCCESSOR'")
  expect(code).toContain("a.status = 'active' and a.id is distinct from p_row")
  expect(code).toContain("'course_not_active'")
  expect(code).toContain('grant execute on function security.supersede_guard_v1(uuid, text, uuid) to service_role')
})

test('s1165: one deferred constraint trigger fires only on active to superseded, so a writer may insert its successor in the same transaction', () => {
  expect(code).toContain('create constraint trigger course_fee_supersede_successor')
  expect(code).toContain('deferrable initially deferred')
  expect(code).toContain("when (old.status = 'active' and new.status = 'superseded')")
  expect(code).toContain("raise exception 'HELD:NO_SUCCESSOR")
})

test('s1165: English, intakes and entry removals are not supersession and stay out of this guard', () => {
  expect(code).not.toMatch(/on catalogue\.course_(english_requirements|intakes|entry_requirements)/)
})

test('s1165: nothing dropped, G3 75/48, locks and cron guarded, the smoke reads change no live row', () => {
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).not.toMatch(/\b(delete\s+from|truncate|cron\.schedule|drop\s+(table|function|column|constraint|trigger))\b/i)
  expect(code).not.toMatch(/\bupdate\s+catalogue\./i)
  expect(MIG).toContain('-- Replaces:')
})
