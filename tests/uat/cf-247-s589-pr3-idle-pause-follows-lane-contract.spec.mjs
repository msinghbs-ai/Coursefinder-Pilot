// Guards: consolidation PR 3 cutover preparation (Platform Admin 17 Nov 2026 22:45): the flag-recheck idle pause and its release act on a live coverage lane, never by switching the legacy cron row back on; a retiring job is never switched on (UR-07); shadow dispatches while the legacy job is off are recorded deferred
// CF-247 S589. Migration 20261118001000_cf247_pr3_idle_pause_follows_lane.sql (md5-guarded edits of security.flag_jobs_v1, security.flag_requeue_v1, security.coverage_lane_run_v1).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261118001000_cf247_pr3_idle_pause_follows_lane.sql', 'utf8')

test('a live lane is held and released on the lane; a retiring job is never switched on', () => {
  expect(mig).toContain("create or replace function security.job_switch_v1(p_jobid bigint, p_job text, p_on boolean)")
  expect(mig).toContain("update pipeline.field_execution_registry r set enabled = coalesce(p_on, false), updated_at = now()")
  expect(mig).toContain("cr.status in ('retiring', 'retired')) then\n    return 'left off: retiring';")
  expect(mig).toContain("create or replace function security.job_switched_on_v1(p_jobid bigint, p_job text)")
  expect(mig).toMatch(/revoke all on function security\.job_switch_v1\(bigint, text, boolean\) from public, anon, authenticated;/)
})

test('flag-recheck and the flag release use the switch, guarded by the live body md5 of each function', () => {
  expect(mig).toContain("'30be1ecbedad83271a31d81d8e77c46e'")
  expect(mig).toContain("'b25306d3229537b6f0e942d5693e5b49'")
  expect(mig).toContain("'6c9a778785ff4ab5f04ece8bd0c49978'")
  expect(mig).toContain("perform security.job_switch_v1(j.jobid, j.jobname, false);")
  expect(mig).toContain("perform security.job_switch_v1(v_jobid, f.entity_key, true);")
  expect(mig).toContain("if v_c <> 1 then raise exception")
  expect(mig).toContain("after the edit is not the expected body")
})

test('shadow counts only minutes the legacy job was switched on; no lane goes live here', () => {
  expect(mig).toContain("if v_r.mode = 'shadow' and not exists (select 1 from cron.job c where c.jobname = v_r.legacy_job and c.active) then")
  expect(mig).toContain("'deferred', 'legacy job switched off: not due in shadow'")
  expect(mig).toContain("raise exception 'post-check: no lane may be live before the cutover'")
  expect(mig).toMatch(/-- Replaces: .+\n-- Retires: nothing\./)
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(mig).not.toMatch(/cron\.(schedule|unschedule)\s*\(/)
})
