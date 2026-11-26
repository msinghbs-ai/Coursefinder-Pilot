// Guards: F-OPS.21 (SS-Programme-Control 26 Nov 2026 15:05 AEDT): no synchronous helper count in the screen read; workers and stalls, freshness by country and verified consumer read-back in the background PIM snapshot; G2 existing settings; G3, locks, cron ceiling.
// s1175: security.data_delivery_v1 fallback removed; security.pim_operations_v1 added to security.data_delivery_refresh_v1.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129113000_cf247_s1175_pim_operations_no_sync_fallback.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1175: a missing helper snapshot returns null, never a live count', () => {
  expect(code).toContain("x.helper = %L), ''null''::jsonb)")
  expect(code).toContain('guard: a live helper count is left in the screen read')
})

test('s1175: workers, stalls, freshness by country and consumer read-back come from existing sources and settings', () => {
  expect(code).toContain("security.pipeline_num_v1('plans.auto_stall_hours', 2)")
  expect(code).toContain('from pipeline.data_delivery_job_runs j where j.singleton')
  expect(code).toContain("from pipeline.data_delivery_readings r where r.measure = 'consumer'")
  expect(code).toContain("'freshness_by_country'")
  expect(code).toContain("''operations'', security.pim_operations_v1()")
})

test('s1175: no job, nothing dropped; G3 75/48, no lock removed, cron ceiling', () => {
  expect(code).not.toMatch(/\b(create table|cron\.schedule|truncate|drop\s+(table|function|column|constraint|trigger)|delete\s+from)\b/i)
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(MIG).toMatch(/^-- Replaces:/m)
  expect(MIG).toMatch(/^-- Retires:/m)
})
