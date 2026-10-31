// Guards: StudySearch SS-004 follow-up (Platform Admin mandate 1 Nov 2026 08:57; admin 2026-10-31-studysearch-transformation.md §33): the health check and the weekly scorecard call the run-outcome classifier only for runs reported failed with "job canceled", so the scheduled-job section keeps its former run time and every other status passes through unchanged.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261101020000_cf247_ss004_health_runtime.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('md5-guarded edits from the v2.15.387 definitions; nothing dropped; consumer API untouched', () => {
  expect(m).toContain("select pg_temp.edit_once('security.platform_health_check_v1(boolean)', '43f5ba0f68140ccafe4a2d46fe0cf4ad', '964db44f6fbcf2cf4c6e6463f4860b40', array[")
  expect(m).toContain("select pg_temp.edit_once('security.ops_scorecard_v1(date,jsonb)', '18dcf612e1572f51797fb80853f0dbe3', '100bd14801534ae6a1ce947b0cb1876b', array[")
  expect(m).toMatch(/^-- Replaces: security\.platform_health_check_v1, security\.ops_scorecard_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(code(m)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|function\s+api\./)
})

test('every call of the classifier is behind the "job canceled" guard', () => {
  const calls = m.split('$n$').filter((_, i) => i % 2 === 1).join('\n')
  const n = (calls.match(/security\.cron_run_outcome_v1\(/g) || []).length
  const guarded = (calls.match(/case when d0?\.status='failed' and d0?\.return_message='job canceled' then security\.cron_run_outcome_v1\(/g) || []).length
  expect(n).toBe(3)
  expect(guarded).toBe(3)
})
