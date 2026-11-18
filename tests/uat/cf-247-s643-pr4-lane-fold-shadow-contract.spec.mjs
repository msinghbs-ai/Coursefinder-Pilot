// Guards: Pilot CLAUDE.md "Cron dispatchers" (Platform Admin 15 Nov 2026 22:36) for consolidation PR 4 (Platform Admin 18 Nov 2026 14:24, chat S1-Build): page-text and the 7 single-mode coverage-sweep jobs are registered byte for byte on coverage-lane-dispatch, and settings-backup-daily on rollup-scheduler, in shadow only; the legacy jobs keep running; coverage-read, coverage-read-2 and the Boost jobs stay on their own jobs; no cron job is added, changed or switched off.
// The live rolled-back dry run (label live-dry-run) runs the migration's pre- and post-checks against production; these checks keep the rules in the file.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const m = fs.readFileSync(migrationPath('20261118170000_cf247_pr4_lane_fold_shadow.sql'), 'utf8')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const lanes = ['coverage-discover', 'coverage-discover-2', 'coverage-ai-match', 'central-find', 'logo-find', 'ops-diagnose', 'scholarship-listing', 'page-text']

test('shadow only: the 8 lanes and the rollup target are copied from cron.job byte for byte, with the md5 guard, and start in shadow', () => {
  expect(m).toMatch(/^-- Replaces: nothing/m); expect(m).toMatch(/^-- Retires: nothing/m)
  expect(c).toContain("select j.jobname, 'worker_lane', j.jobname, j.command, md5(j.command), j.schedule, 50, 'shadow',")
  expect(c).toContain(`where j.active and j.jobname in (${lanes.map((l) => `'${l}'`).join(', ')})`)
  expect(c).toContain("select j.jobname, j.jobname, j.command, md5(j.command), j.schedule, 'A', 50, true, 'shadow',")
  expect(c).toContain("where j.active and j.jobname = 'settings-backup-daily'")
  expect(c).toContain("if v_n <> 8 then raise exception 'post-check: % of 8 coverage lanes match their live legacy job'")
  expect(c).toContain("raise exception 'post-check: a PR 4 target is live (this change is shadow only)'")
})

test('no cron job is added, changed or switched off, and nothing is dropped or deleted', () => {
  expect(c).not.toMatch(/cron\.(schedule|unschedule|alter_job)\s*\(/)
  expect(c).not.toMatch(/\b(drop|truncate)\b|\bdelete from\b/i)
  expect(c).not.toMatch(/insert into pipeline\.automation_catalogue/)
  expect(c).not.toMatch(/create or replace function|create or replace procedure/)
  expect(c).toContain("raise exception 'post-check: a legacy job was switched off (this change is shadow only)'")
  // the register keeps the jobs active and notes the shadow
  expect(c).toContain("update pipeline.component_register r")
  expect(c).not.toMatch(/status\s*=\s*'retiring'/)
})

test('jobs kept on their own are refused, and a job already held by a dispatcher stops the change', () => {
  expect(c).toContain("r.legacy_job in ('coverage-read', 'coverage-read-2', 'boost-extract', 'boost-fields', 'boost-benchmark')")
  expect(c).toContain("raise exception 'pre-check: one of the 9 jobs is already held by a dispatcher'")
  expect(c).toContain("raise exception 'pre-check: the 9 jobs must be on, catalogued and registered active'")
})
