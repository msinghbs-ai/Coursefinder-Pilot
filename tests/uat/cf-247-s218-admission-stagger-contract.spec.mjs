// Guards: Decision 4, scheduler capacity (Platform Admin consolidated decision pack, 2 Nov 2026 10:56)
// CF-247 S218. The three admission writers start apart from each other on the approved minutes; the migration is guarded, reversible and
// changes nothing but the three schedules and their catalogue notes.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261102060000_cf247_admission_schedule_stagger.sql', 'utf8')

test('Decision 4: coverage-admit :x3, coverage-admit-intakes :x5, adapter-overwrite :x9 (approved pattern)', () => {
  expect(sql).toContain(`jobname = 'coverage-admit'), schedule => '3-59/10 * * * *'`)
  expect(sql).toContain(`jobname = 'coverage-admit-intakes'), schedule => '5-59/10 * * * *'`)
  expect(sql).toContain(`jobname = 'adapter-overwrite'), schedule => '9-59/10 * * * *'`)
  // the three start minutes are different from each other
  const mins = [...sql.matchAll(/schedule => '(\d)-59\/10/g)].map((m) => m[1])
  expect(new Set(mins).size).toBe(3)
})

test('Decision 4: the change is guarded against an unexpected starting state and checked afterwards', () => {
  expect(sql).toMatch(/admission schedules differ from the reconciled state[^;]*nothing changed/)
  expect(sql).toContain("Decision 4 post-check: admission schedules")
  expect(sql).toMatch(/-- Rollback: cron\.alter_job back/)
  expect(sql).toMatch(/-- Replaces: /)
  expect(sql).toMatch(/-- Retires: nothing/)
})

test('Decision 4: no command, batch size, time-out, drop or delete is changed', () => {
  expect(sql).not.toMatch(/command\s*=>/i)
  expect(sql).not.toMatch(/\bdrop\b|\bdelete\s+from\b|truncate/i)
  expect(sql).not.toMatch(/statement_timeout|batch\./i)
  expect(sql).not.toMatch(/cron\.schedule\(/)
})
