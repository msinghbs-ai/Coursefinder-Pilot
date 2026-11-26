// Guards: SS-Programme-Control 27 Nov 2026 00:08 AEDT items 3 to 5 (s1287): starved and often-deferred rollup targets run first in their own due ticks, and the layer2-onboarding-snapshot dispatcher cutover is finished byte for byte with its cron job switched off, not dropped.
// CF-247 S1287 (and S1289, data-delivery priority 9). supabase/migrations/20261130064500_cf247_s1287_dispatcher_starvation_and_l2_snapshot_cutover.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261130064500_cf247_s1287_dispatcher_starvation_and_l2_snapshot_cutover.sql', 'utf8')
const code = M.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')

test('the starved targets move ahead of the every-minute group; course-field-readiness stays behind it', () => {
  expect(code).toContain("when 'ops-cost-guard' then 3 when 'coursefinder-data-quality-overview-refresh' then 3 when 'course-field-readiness' then 11 else 4 end")
  expect(code).toContain("raise exception 'guard: a target priority is not as read on 27 Nov 2026'")
  expect(code).not.toMatch(/create or replace function/i)
})

test('the cutover is byte for byte, switches the cron job off and marks it retiring', () => {
  expect(code).toContain('t.call_md5 = md5(j.command) and t.call_md5 = md5(t.call_sql) and t.schedule = j.schedule')
  expect(code).toContain('perform cron.alter_job(r.jobid, active => false);')
  expect(code).toContain("set mode = 'live', enabled = true, last_due_at = date_trunc('minute', now())")
  expect(code).toContain("set status = 'retiring', replaced_by = 'rollup-scheduler (pipeline.rollup_targets, group A, mode live)'")
  expect(code).not.toMatch(/cron\.unschedule|\bdrop\s+(table|function|view|schema)|\bdelete\s+from/i)
})

test('consumer API, cron ceiling and manual locks are checked after the change', () => {
  expect(code).toContain("raise exception 'post-check: consumer API moved: %'")
  expect(code).toContain("raise exception 'post-check: active cron jobs above 140'")
  expect(code).toContain("raise exception 'post-check: manual locks changed'")
})

test('s1289: data-delivery runs ahead of the every-minute group, behind the starved targets', () => {
  const m = fs.readFileSync('supabase/migrations/20261130080000_cf247_s1289_data_delivery_first_in_tick.sql', 'utf8').split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
  expect(m).toContain('set priority = 9,')
  expect(m).toContain("raise exception 'guard: another target already holds priority 6 to 9'")
  expect(m).not.toMatch(/create or replace function|cron\.unschedule|\bdelete\s+from/i)
})
