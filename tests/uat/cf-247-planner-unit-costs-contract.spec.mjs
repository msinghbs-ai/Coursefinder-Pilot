// Guards: Platform Admin 10 Nov 2026 19:47 "Restore autonomous operation" (IQ-00355): the hourly automatic enrichment planner must not time out because security.enrich_unit_costs_v1 scans every usage row through a per-row function; the figures it returns must not change.
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261110200000_cf247_planner_unit_costs.sql', 'utf8')
const R = fs.readFileSync('supabase/held/planner_unit_costs_forward_recovery.sql', 'utf8')
const BEFORE = 'f10198f02de958119baefd490931c258'
const AFTER = '00d1b42bc96af737982c3ba77a384036'

test('the migration follows the house pattern: header, one md5-guarded body replacement, nothing dropped, no setting changed', () => {
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
  expect(M).toContain('security.enrich_unit_costs_v1()')
  expect(M).toContain(BEFORE)
  expect(M).toContain(AFTER)
  expect(R).toContain(BEFORE)
  expect(R).toContain(AFTER)
  expect(M).toContain('supabase/held/planner_unit_costs_forward_recovery.sql')
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(M).not.toMatch(/\balter\s+table\b/i)
  expect(M).not.toMatch(/platform_toolset_settings/)
})

test('the usage window is summed per purpose and provider before the purpose group is applied, and the 30-day window stays marked fixed', () => {
  expect(M).toMatch(/group by x\.purpose, x\.provider_id/)
  expect(M).toMatch(/security\.fc_purpose_group_v1\(a\.purpose\)/)
  expect(M).not.toMatch(/fc_purpose_group_v1\(x\.purpose\)/)
  expect(M).toContain('-- fixed: estimate window')
})

test('the seven figures and their sources are unchanged', () => {
  for (const k of ['site_credits', 'search_credits_per_course', 'adapter_credits', 'scholarship_credits', 'enrich_usd_per_item', 'adapter_usd', 'scholarship_usd']) {
    expect(M, k).toContain(`'${k}'`)
    expect(R, k).toContain(`'${k}'`)
  }
  // the per-course search figure divides by the number of usage rows: summed rows keep that count
  expect(M).toMatch(/sum\(units\) \/ nullif\(sum\(n\), 0\) from u where purpose = 'course_link_search'/)
})
