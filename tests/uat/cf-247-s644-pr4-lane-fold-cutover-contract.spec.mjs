// Guards: Pilot CLAUDE.md "Cron dispatchers" (Platform Admin 15 Nov 2026 22:36) for the consolidation PR 4 cutover (Platform Admin 18 Nov 2026 14:24, chat S1-Build; early cutover authorised by the Platform Admin 19 Nov 2026 07:47, checked on today's completed settings-backup-daily and rollup-scheduler runs): after a shadow whose minute coverage is clean, the 8 coverage lanes and settings-backup-daily go live and their 9 legacy jobs are switched off and marked retiring in the same transaction; nothing is unscheduled or dropped by the migration (the unschedule waits for the admin paste file after the retention window).
// The live rolled-back dry run (label live-dry-run) runs the gate against production; these checks keep the rules in the file.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const m = fs.readFileSync(migrationPath('20261119095000_cf247_pr4_lane_fold_cutover.sql'), 'utf8')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the gate: once only, the shadow of 20261118170000 checked on today\'s runs, minute coverage, md5 and schedule unchanged, no person-paused job', () => {
  expect(m).toMatch(/^-- Replaces: the 9 legacy cron jobs/m); expect(m).toMatch(/^-- Retires: those 9 jobs/m)
  expect(c).toContain("raise exception 'gate: a PR 4 target is already live; this cutover runs once'")
  expect(c).toContain("if v_from is null or v_from > timestamptz '2026-11-18 15:00:00+11' then")
  expect(c).toContain("raise exception 'gate: today''s settings-backup-daily start has not succeeded with a shadow_due rollup run for its minute'")
  expect(c).toContain("raise exception 'gate: the latest finished rollup-scheduler tick did not succeed'")
  expect(m).toMatch(/^-- Early cutover \(Platform Admin 19 Nov 2026 07:47 AEDT, chat S1-Build\)/m)
  expect(c).toContain("x.status in ('shadow_due', 'deferred')")
  expect(c).toContain("where z.uncovered > 1 or z.refused > 0 or z.legacy_minutes = 0;")
  expect(c).toContain("raise exception 'gate: settings-backup-daily shadow does not cover its % legacy start(s)'")
  expect(c).toContain("raise exception 'gate: % of 8 legacy jobs still carry the registered command and schedule'")
  expect(c).toContain("f.reason_code = 'idle_paused' and f.state = 'raised'")
})

test('the cutover: targets live and legacy jobs off in one transaction, logged, retiring; nothing unscheduled or dropped', () => {
  expect(c.match(/perform cron\.alter_job\(r\.jobid, active => false\);/g).length).toBe(2)
  expect(c).not.toMatch(/cron\.(schedule|unschedule)\s*\(/)
  expect(c).not.toMatch(/\b(drop|truncate)\b|\bdelete from\b/i)
  expect(c.match(/'dispatcher_cutover'/g).length).toBe(2)
  expect(c.match(/set status = 'retiring'/g).length).toBe(2)
  expect(c).toContain("retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int")
  expect(c).toContain("raise exception 'post-check: a legacy job is still switched on'")
  expect(c).toContain("raise exception 'post-check: not all 9 legacy jobs are retiring'")
})
