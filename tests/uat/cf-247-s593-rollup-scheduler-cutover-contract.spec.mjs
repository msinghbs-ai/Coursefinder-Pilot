// Guards: Consolidation PR 1 cutover (Platform Admin 17 Nov 2026 23:07; Cron dispatchers rule 15 Nov 2026 22:36): the 25 group A rollup targets go live and their 25 legacy jobs are switched off in the same transaction, only while a 24-hour shadow covered the same minutes as the legacy starts with no failed or refused run and every legacy job still carries its registered command and schedule; layer2-onboarding-snapshot stays on its own job; nothing is dropped (the unschedule waits for the paste file after the retention window)
// CF-247 S593. Migration 20261118010000_cf247_rollup_scheduler_cutover. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118010000_cf247_rollup_scheduler_cutover.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const gate = code.slice(code.indexOf('-- the gate') >= 0 ? code.indexOf('if exists (select 1 from pipeline.rollup_targets') : 0, code.indexOf('for v_t in select t.target_code'))

test('the gate needs a full 24-hour shadow with the same minutes as the legacy starts, no failed run and untouched legacy jobs', () => {
  expect(code).toContain("v_from timestamptz := now() - interval '24 hours'; -- fixed:")
  expect(gate).toContain("raise exception 'gate: a rollup target is already live; this cutover runs once'")
  expect(gate).toContain("raise exception 'gate: the shadow history does not cover 24 hours'")
  expect(gate).toContain("status in ('failed', 'refused')")
  expect(gate).toContain('abs(coalesce(s.due_minutes, 0) - coalesce(l.starts, 0)) > 1')
  expect(gate).toContain('j.active and md5(j.command) = t.call_md5 and j.schedule = t.schedule')
  expect(gate).toContain("if v_n <> 25 then raise exception 'gate:")
})

test('the targets go live and the legacy jobs are switched off together, logged and marked retiring', () => {
  const cut = code.slice(code.indexOf('for v_t in select t.target_code'), code.indexOf('end $cut$;'))
  expect(cut).toContain('perform cron.alter_job(v_t.jobid, active => false);')
  expect(cut).toContain("update pipeline.rollup_targets set mode = 'live'")
  expect(cut).toContain("values ('scheduler', 'dispatcher_cutover', v_t.legacy_job,")
  expect(cut).toContain("set status = 'retiring', replaced_by = 'rollup-scheduler (pipeline.rollup_targets, mode live)'")
  expect(cut).toContain("security.pipeline_num_v1('hygiene.retire_after_days', 14)")
  expect(code).toContain("where jobname = 'layer2-onboarding-snapshot' and active")
  expect(code).toContain("where jobname = 'rollup-scheduler' and active")
  // nothing is dropped or unscheduled by the migration
  expect(code).not.toMatch(/cron\.unschedule|\bdrop\s|\bdelete\s+from\b|\btruncate\b/i)
})
