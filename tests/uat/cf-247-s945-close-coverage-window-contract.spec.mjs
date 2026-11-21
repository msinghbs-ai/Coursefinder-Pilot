// Guards: CF-247 s945 (Pilot CLAUDE.md on-demand rule; s903 follow-up, 21 Nov 2026): the coverage unlock on-demand window ad97c846 is closed with security.on_demand_close_v1 once it has run, idempotently, with its use kept and reported
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261121235000_cf247_s945_close_coverage_window_ad97c846.sql', 'utf8')

test('the window is closed through on_demand_close_v1, only while it is open, and keeps its report', () => {
  expect(MIG).toContain("v_id constant uuid := 'ad97c846-4c3b-447f-b2c7-18b14caa9daa'")
  expect(MIG).toContain("if v_state = 'open' then r := security.on_demand_close_v1(v_id);")
  expect(MIG).toContain("'post-check: the window is not closed'")
  expect(MIG).toContain("'post-check: the window has no report of its use'")
  expect(MIG).not.toMatch(/\bdrop\s+(table|function|view)\b|\bdelete\s+from\b|cron\.schedule\(/i)
})
