// Guards: PIM step 5 first slice (Platform Admin 25 Nov 2026 23:12 AEDT; Master Plan 6.2 interface 2): the refresh window is a setting (G2) with a per-field override; freshness only for a held value; failed sources keep their value; snapshot only; G3, locks, cron ceiling.
// s1170: pipeline pim.refresh_days, field_register.refresh_days, freshness in security.field_state_entity_v1, security.pim_refresh_v1 in the Data Delivery snapshot.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128100000_cf247_s1170_pim_refresh_window_source_findings.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1170: the refresh window is a labelled setting with a range and unit, and a field may override it', () => {
  expect(code).toContain("'pipeline', 'pim.refresh_days'")
  expect(code).toContain("'number', '365'::jsonb, 30, 730, 'days'")
  expect(code).toContain('add column if not exists refresh_days integer')
  expect(code).toContain("coalesce(r.refresh_days, security.pipeline_num_v1('pim.refresh_days', 365)::int)".replace(/'/g, "''"))
})

test('s1170: freshness is given only for a held value, as inside or past', () => {
  expect(code).toContain("if s->>''completeness'' in (''verified'', ''partial'') then")
  expect(code).toContain("then ''inside'' else ''past'' end")
})

test('s1170: refresh due and source outcomes are counted in the background snapshot; nothing is removed', () => {
  expect(code).toContain("''refresh'', security.pim_refresh_v1()")
  for (const o of ['not_read', 'http_error', 'fetch_failed', 'blocked', 'robots_disallowed']) expect(code).toContain(`'${o}'`)
  expect(code).not.toMatch(/\b(update|delete from)\s+(catalogue|pipeline)\.(courses|coverage_course_pages|field_enrich_items|course_)/i)
})

test('s1170: nothing dropped; G3 75/48, no lock removed, cron ceiling', () => {
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).toContain("guard: active cron jobs above the ceiling of 140")
  expect(code).not.toMatch(/\b(truncate|cron\.schedule|drop\s+(table|function|column|constraint|trigger))\b/i)
  expect(MIG).toContain('-- Replaces:')
})
