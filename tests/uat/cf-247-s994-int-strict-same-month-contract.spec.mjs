// Guards: CF-247 s994 (session S2-INT, Platform Admin 23 Nov 2026 17:49 AEDT, Decision 271 follow-up): a new Rule B admission needs the stated month to equal the calendar start's month; admitted dates are never changed by it.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261123190000_cf247_s994_int_strict_same_month.sql', 'utf8')
const dq = (tag) => (MIG.match(new RegExp('\\$' + tag + '\\$([\\s\\S]*?)\\$' + tag + '\\$')) || [])[1] || ''
const BEFORE = '5e864efd7758ea2149e28f6566ac466b'

test('the function edit is md5-guarded in both directions and counted', () => {
  expect(MIG).toContain(BEFORE)
  expect(MIG).toMatch(/pg_temp\.edit_counted\('security\.intake_nearest_start_v1\(uuid,uuid,integer,integer,text,jsonb,date,integer,integer\)'/)
  expect(MIG).toContain('array[1, 1]')
  const after = (MIG.match(/body ([0-9a-f]{32}) to /) || [])[1]
  expect(after).toMatch(/^[0-9a-f]{32}$/)
  expect(MIG.split(after).length - 1).toBeGreaterThanOrEqual(3)
})

test('only a start in the stated month is used; the next-month path is gone', () => {
  expect(dq('o1')).toContain('coalesce(v_s1[1], v_s2[1])')
  expect(dq('n1')).toContain("v_cand := v_s1[1]; v_path := 'in_month';")
  expect(dq('n1')).not.toContain('v_s2')
  expect(dq('n1')).not.toContain('next_start')
  expect(dq('n2')).toContain('a start in another month is not used')
})

test('admitted dates are untouched: nothing is updated, withdrawn or deleted, and the dated count is checked', () => {
  expect(MIG).not.toMatch(/update catalogue\.course_intakes|update pipeline\.course_intake_dates|delete from|\bdrop\s+(function|table)/i)
  expect(MIG).toContain("raise exception 'post-check: an admitted start date changed'")
})

test('no new setting, job or schedule; consumer API 75/48 and locks checked; housekeeping lines present', () => {
  expect(MIG).not.toMatch(/platform_toolset_settings|cron\./i)
  expect(MIG).toContain("(v->>'functions')::int <> 75")
  expect(MIG).toContain('pipeline.manual_locks')
  expect(MIG).toMatch(/^-- Replaces: security\.intake_nearest_start_v1/m)
  expect(MIG).toMatch(/^-- Retires: nothing/m)
})
