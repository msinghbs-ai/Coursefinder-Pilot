// Guards: Platform Admin decision D11, 27 Nov 2026 (retain pauses and reconcile, s1291): jobs 87, 378 and 108 stay switched off; the register records each hold with its decision, owner, replacement and spend, and no cron row changes.
// CF-247 S1291. supabase/migrations/20261130091500_cf247_s1291_paused_jobs_held_register.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261130091500_cf247_s1291_paused_jobs_held_register.sql', 'utf8').split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')

test('the holds are recorded in the register and as control events, never by switching a job', () => {
  expect(code).toContain("update pipeline.component_register c set note = h.note")
  expect(code).toContain("'hold_recorded'")
  expect(code).toContain("raise exception 'post-check: a cron row changed'")
  expect(code).not.toMatch(/cron\.alter_job|cron\.schedule\(|cron\.unschedule|status = 'retiring'|\bdelete\s+from/i)
})
