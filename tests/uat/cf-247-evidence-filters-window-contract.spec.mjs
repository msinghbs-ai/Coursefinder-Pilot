import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('migration 1860 widens the Evidence filter snapshot window to 150 minutes to cover the 2-hourly refresh, guarded on the live definition', () => {
  const m = fs.readFileSync('supabase/migrations/20261006001860_cf247_evidence_filters_snapshot_window.sql', 'utf8')
  expect(m).toContain('2c6ad61f540b3335c2d8a4fadc8f92a6')
  expect(m).toContain("security.admin_evidence_filter_options()")
  expect(m).toContain("interval ''150 minutes''")
  expect(m).toContain("raise exception 'expected snippet not found exactly once'")
  expect(m).not.toMatch(/\b(drop|truncate|cascade)\b/i)
})
