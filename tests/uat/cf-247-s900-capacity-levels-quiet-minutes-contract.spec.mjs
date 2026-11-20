// Guards: CF-247 s900 (Platform Admin 21 Nov 2026 07:48, chat S1-Coverage-Unlock-UI-Notes; IQ-00510 and IQ-00445): the pilot database alert
// levels are 8,192 / 9,216 / 10,240 MiB, coverage-reconcile runs at :09 and scholarship-coverage-classify at :40 with their commands unchanged,
// the active job count is unchanged, and nothing is dropped, deleted, unscheduled or shortened in retention
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261121090000_cf247_s900_capacity_levels_and_quiet_minutes.sql', 'utf8')

test('IQ-00510: the pilot alert levels move to 8,192 / 9,216 / 10,240 MiB, logged with the levels before', () => {
  expect(MIG).toContain('set database_warn_bytes     = 8192::bigint * 1048576,')
  expect(MIG).toContain('database_high_bytes     = 9216::bigint * 1048576,')
  expect(MIG).toContain('database_critical_bytes = 10240::bigint * 1048576,')
  expect(MIG).toContain("where environment = 'pilot';")
  expect(MIG).toContain("values ('capacity', 'policy_update', 'pipeline.platform_capacity_policy',")
  expect(MIG).toContain("raise exception 'post-check: the pilot critical level was not set';")
  // retention is not touched
  expect(MIG).not.toMatch(/observation_retention_days\s*=|retention_days'\s*,|keep_days'\s*,/)
})

test('IQ-00445: the two jobs keep their commands and move to :09 and :40; the active count is unchanged', () => {
  expect(MIG).toContain("where jobname = 'coverage-reconcile' and command = 'select security.coverage_reconcile_v1()'")
  expect(MIG).toContain("where jobname = 'scholarship-coverage-classify' and command = 'select security.scholarship_coverage_classify_v1()'")
  expect(MIG).toContain("perform cron.alter_job(v_rec, schedule => '9 * * * *');")
  expect(MIG).toContain("perform cron.alter_job(v_cls, schedule => '40 * * * *');")
  expect(MIG).toContain("raise exception 'post-check: the active job count changed';")
  expect(MIG).toContain("raise exception 'post-check: a catalogue row still names the old minute';")
  expect(MIG).not.toMatch(/cron\.schedule\(|cron\.unschedule|^\s*(drop|delete|truncate|vacuum)\b/im)
})

test('housekeeping lines are present', () => {
  expect(MIG).toMatch(/^-- Replaces: .+$/m)
  expect(MIG).toMatch(/^-- Retires: .+$/m)
})
