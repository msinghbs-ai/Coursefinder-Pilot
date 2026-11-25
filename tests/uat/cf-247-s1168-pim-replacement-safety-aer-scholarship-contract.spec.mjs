// Guards: PIM step 2 extended (Platform Admin 25 Nov 2026 23:12 AEDT): no AER, description or Scholarship supersession without a verified successor (HELD:NO_SUCCESSOR), including the s871 regression; G2, G3, locks, cron.
// s1168: pipeline.supersede_guard_scope, security.supersede_successor_v1, three deferred constraint triggers, and the held verdict in security.aer_det_reread_v1.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128070000_cf247_s1168_pim_replacement_safety_aer_scholarship.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1168: Layer 4 entry and description reads, scholarship reviews and active entry rows need a successor at commit', () => {
  for (const t of ['layer4_supersede_successor', 'scholarship_review_supersede_successor', 'course_entry_supersede_successor']) expect(code).toContain(`create constraint trigger ${t}`)
  expect((code.match(/deferrable initially deferred/g) || []).length).toBe(3)
  expect(code).toContain("raise exception 'HELD:NO_SUCCESSOR")
  for (const c of ['course_entry_first_read', 'course_description_first_read', 'provider_description']) expect(code).toContain(`('layer4', '${c}'`)
})

test('s1168: a successor is a newer pending read, a value held, or an entity no longer active; an old approval alone is not a successor', () => {
  expect(code).toContain("o.id <> i.id and o.status = 'pending'")
  expect(code).toContain("'value_held'")
  expect(code).toContain("'entity_not_active'")
  expect(code).not.toMatch(/o\.status in \('pending', 'approved'/)
})

test('s1168: the s871 reread holds a read with no successor instead of superseding it; md5 guarded', () => {
  expect(code).toContain("'7a79bb260028ea1943a20240c5a42037'")
  expect(code).toContain("then ''held_no_successor''")
})

test('s1168: scope is data; nothing dropped or deleted; G3 75/48, locks and cron guarded', () => {
  expect(code).toContain('create table if not exists pipeline.supersede_guard_scope')
  expect(code).toContain('comment on table pipeline.supersede_guard_scope')
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).not.toMatch(/\b(delete\s+from|truncate|cron\.schedule|drop\s+(table|function|column|constraint|trigger))\b/i)
  expect(MIG).toContain('-- Replaces:')
})
