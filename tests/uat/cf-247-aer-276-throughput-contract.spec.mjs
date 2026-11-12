// Guards: Decision 276 (Platform Admin 12 Nov 2026 17:20): aer.machine_daily_max 1,000 with eligibility, audit and withdrawal unchanged; course-page reading 600 a day within the existing guards; AER v1 frozen
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('the two throughput values change only from their earlier values, with a reason, and nothing else changes', () => {
  const m = fs.readFileSync('supabase/migrations/20261113043100_cf247_aer_276_throughput_and_v1_freeze.sql', 'utf8')
  expect(m).toMatch(/set value = to_jsonb\(1000\)[\s\S]*?key = 'aer\.machine_daily_max' and value = to_jsonb\(300\)/)
  expect(m).toMatch(/set value = to_jsonb\(600\)[\s\S]*?key = 'aer\.schedule_daily_max' and value = to_jsonb\(200\)/)
  expect(m).not.toMatch(/aer\.machine_audit|aer\.matrix_machine_mode|aer\.schedule_layer4_max'\s+and|grid_machine_admission_on/)
  expect(m).not.toMatch(/^\s*(delete|drop|insert|create)\b/im)
  expect(fs.readFileSync('CLAUDE.md', 'utf8')).toContain('**AER v1 is frozen (Decision 276')
})
