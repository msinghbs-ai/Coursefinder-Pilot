// Guards: Platform Admin 20 Nov 2026 23:07 AEDT (S1-RM-Design s890): Victoria University CRICOS 02475D (Sydney City Centre and Brisbane) is kept with its
// courses and takes the description of CRICOS 00124K through the screen's own held-university writing path, as the Platform Admin, without a manual lock.
// No lifecycle event, archive or re-parenting; G3 and the 7,585 manual locks are checked before and after. A reading opened for writing is admitted
// with its item's text (read_id link), so a held university closes in the UI.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120231000_cf247_s890_vu_02475d_parent_description.sql', 'utf8')
const code = MIG.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')

test('s890: no public object, G3 and locks before and after, nothing deleted', () => {
  expect((MIG.match(/consumer_api_check_v1/g) || []).length).toBeGreaterThanOrEqual(2)
  expect((MIG.match(/pipeline\.manual_locks\) <> 7585/g) || []).length).toBe(2)
  expect(MIG).toMatch(/^-- Replaces:/m); expect(MIG).toMatch(/^-- Retires:/m)
  expect(code).not.toMatch(/create\s+(or replace\s+)?function\s+public\.|create\s+(table|view)\b|\b(drop|delete|truncate)\b/i)
})

test('s890: the decision goes through the screen path for 02475D only, with no lock and no lifecycle change', () => {
  expect(code).toContain("public.admin_layer4_inbox('description_open_held'")
  expect(code).toContain("'choice', 'edit_approve'")
  expect(code).toContain("'set_manual_lock', false")
  expect(code).toContain("p.stable_key = 'provider:cricos:02475d'")
  expect(code).toContain("p.stable_key = 'provider:cricos:00124k'")
  expect(code).not.toMatch(/provider_lifecycle|provider_archive_apply|update\s+catalogue\.(courses|providers)/i)
  expect(code).toContain("raise exception 'post-check: 02475D''s active courses changed'")
  expect(code).toContain("perform set_config('request.jwt.claims', '', true)")
})

test('s890: the held reading is admitted with its item (md5-guarded edit)', () => {
  expect(code).toContain("'c332bdfe60b67b8ce57f6e5e24709fe4'")
  expect(code).toContain("or id = nullif(i.proposed_value->>''read_id'', '''')::uuid) and provider_id = i.entity_id")
})
