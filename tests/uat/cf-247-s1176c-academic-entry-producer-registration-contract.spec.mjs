// Guards: DR-16 Priority 3 item 1 (SS-Programme-Control 27 Nov 2026 00:08 AEDT): academic entry is registered with its automatic producer (reader coverage, s1274 planner step and s1261 scheduled reader), so a missing entry is not diagnosed as a software defect or no_reader; the change was measured before release.
// s1176c: one pipeline.field_register row (academic_entry).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261130061500_cf247_s1176c_academic_entry_producer_registration.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1176c: only the academic_entry register row moves from none to coverage, guarded to exactly one row', () => {
  expect(code).toContain("set reader = 'coverage'")
  expect(code).toContain("where field = 'academic_entry' and reader = 'none'")
  expect(code).toContain('if n <> 1 then raise exception')
  expect(code).not.toMatch(/alter table|drop |constraint|create or replace function/i)
})

test('s1176c: the measured impact is recorded with the change; G3, locks and cron asserted', () => {
  expect(MIG).toMatch(/eligible gaps 155,231 -> 157,603/)
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).toContain('guard: the scheduler changed')
  expect(MIG).toMatch(/^-- Replaces:/m)
  expect(MIG).toMatch(/^-- Retires:/m)
})
