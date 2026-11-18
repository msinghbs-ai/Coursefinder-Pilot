// Guards: destination data sources ingest through the standard Layer 1 schedule (Platform Admin 18 Nov 2026 22:04): the first run is made due on the Layer 1 source, never by a side job; Fair Work stays paused.
// CF-247 S695. supabase/migrations/20261118272000_cf247_destination_first_layer1_run.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118272000_cf247_destination_first_layer1_run.sql', 'utf8')

test('the first run is due on the Layer 1 source, picked up by the standard scheduler; no side job and no direct call', () => {
  expect(M).toContain("set next_verification_at = now(), change_reason = 'First run through the standard Layer 1 schedule (20261118272000, s695)'")
  expect(M).toContain("raise exception 'post-check: Fair Work stays paused';")
  expect(M).not.toMatch(/svc_pilot_submit_nonce|destination_job_run_now_v1|cron\.schedule/)
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})
