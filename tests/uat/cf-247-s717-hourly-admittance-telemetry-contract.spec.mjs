// Guards: hourly admittance telemetry (Platform Admin 19 Nov 2026 06:57): one read-only query (no write, no new table or function) gives the 27 columns of the Google Sheet Hourly_Admittance_Telemetry in Drive Monitoring, with the Melbourne time first, coverage from admin_coverage_telemetry_v1, Layer 4 admitted/held/rejected for courses, providers, scholarships, AER and destination data, and job health. (Numbered s717: s719 was already used by LIN 19/198 in Pilot #1343.)
// CF-247 S717. scripts/telemetry/hourly-admittance.sql (run hourly by the scheduled task "Hourly admittance telemetry").
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const Q = fs.readFileSync('scripts/telemetry/hourly-admittance.sql', 'utf8')
const code = Q.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
const COLUMNS = ['snapshot_aedt', 'snapshot_utc', 'courses_admitted', 'courses_held', 'courses_rejected', 'providers_admitted', 'providers_held', 'providers_rejected',
  'scholarships_admitted', 'scholarships_held', 'scholarships_rejected', 'aer_admitted', 'aer_held', 'aer_rejected', 'destination_admitted', 'destination_held',
  'destination_rejected', 'coverage_courses', 'coverage_fields_n', 'coverage_courses_all_n', 'coverage_courses_zero', 'coverage_mean_fields_admitted',
  'coverage_tracked_fields', 'jobs_active', 'jobs_off', 'job_runs_1h_succeeded', 'job_runs_1h_failed']

test('read only, inside one read-only transaction with a time limit', () => {
  expect(code).toContain('begin transaction read only;')
  expect(code).toContain("set local statement_timeout = '20s';")
  expect(code).not.toMatch(/\b(insert|update|delete|truncate|drop|alter|create)\b/i)
})

test('the 27 sheet columns, in order, Melbourne time first', () => {
  const found = [...code.matchAll(/ as ([a-z0-9_]+)(?=,|;|\s*$)/gm)].map(m => m[1])
  expect(found).toEqual(COLUMNS)
  expect(code).toContain("to_char(now() at time zone 'Australia/Melbourne', 'YYYY-MM-DD HH24:MI') as snapshot_aedt")
})

test('reads coverage telemetry, Layer 4, scholarships, AER, destination and job health', () => {
  expect(code).toContain("public.admin_coverage_telemetry_v1('{}'::jsonb)")
  expect(code).toContain('from pipeline.layer4_review_items')
  expect(code).toContain('from scholarship.scholarships')
  expect(code).toContain('from catalogue.course_entry_requirements')
  expect(code).toContain('from destination.locality_metrics')
  expect(code).toContain('from cron.job_run_details')
})
