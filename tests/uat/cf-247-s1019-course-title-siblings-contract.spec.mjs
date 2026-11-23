// Guards: Platform Admin 24 Nov 2026 06:45 AEDT (IR-027: same-title course siblings, no merge; the AER relink lists every sibling on one Layer 4 card for a person; nothing in catalogue.* changed; G3 frozen; nothing dropped)
// s1019: pipeline.course_title_siblings_v groups each provider's active same-title courses with CRICOS code and status, duration, study load,
// publication and lock; readable by postgres and service_role only.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124070000_cf247_s1019_course_title_siblings.sql', 'utf8')

test('s1019: the sibling view groups active same-title courses per provider with what a person needs to choose', () => {
  expect(MIG).toContain('create view pipeline.course_title_siblings_v as')
  expect(MIG).toContain("where c.lifecycle_status = 'active'")
  expect(MIG).toContain('group by c.provider_id, lower(btrim(c.canonical_title))')
  expect(MIG).toContain('having count(*) > 1;')
  for (const k of ["'cricos_code'", "'cricos_status'", "'duration_value'", "'study_load'", "'publication_status'", "'locked'"]) expect(MIG).toContain(k)
  expect(MIG).toContain('comment on view pipeline.course_title_siblings_v is')
})

test('s1019: nothing is merged; only the service roles read it; G3, locks and cron checked', () => {
  const sql = MIG.replace(/on commit drop/g, '').replace(/^--.*$/gm, '')
  expect(sql).not.toMatch(/\b(update|delete|insert|truncate|drop)\s+/i)
  expect(MIG).toContain('revoke all on pipeline.course_title_siblings_v from public, anon, authenticated;')
  expect(MIG).toContain('grant select on pipeline.course_title_siblings_v to service_role;')
  for (const s of ['guard: the consumer API is not at its baseline before this change', 'post-check: the consumer API moved', 'post-check: manual locks changed',
    'post-check: the number of active cron jobs changed', 'post-check: the UQ Bachelor of Pharmacy (Honours) group (IR-027) is missing']) expect(MIG).toContain(s)
})
