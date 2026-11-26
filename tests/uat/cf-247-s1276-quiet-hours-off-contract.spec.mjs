// Guards: Platform Admin via SS-Programme-Control 26 Nov 2026 21:01 AEDT (permanent 24x7 autonomous production operation: the s1213 daytime quiet hours removed through their audited setting; no job, limit or cap changed)
// s1276: pipeline.quiet_hours.enabled goes from 1 to 0 with its reason; the five jobs run all day; nothing else changes.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129235000_cf247_s1276_quiet_hours_off_continuous_operation.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1276: only the quiet-hours switch changes, 1 to 0, with its reason and an audit event', () => {
  expect(code).toContain("set value = to_jsonb(0), reason = v_reason, updated_at = now()")
  expect(code).toContain("where toolset_key = 'pipeline' and key = 'quiet_hours.enabled';")
  expect(code.match(/update pipeline\.platform_toolset_settings/g).length).toBe(1)
  expect(code).toContain('insert into pipeline.admin_control_events')
  expect(code).toContain("if security.pipeline_num_v1('quiet_hours.enabled', -1) <> 1 then raise exception")
})

test('s1276: no job, route, cap or consumer change; nothing dropped; cron, locks and the five jobs checked after', () => {
  expect(code).not.toMatch(/cron\.schedule|cron\.alter_job|cron\.unschedule|ai_service_routes|create table |\bdelete from\b|truncate |website_v2_/i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
  for (const s of ['post-check: active cron jobs changed', 'post-check: manual locks changed', 'is still held by quiet hours', 'post-check: consumer API moved']) expect(MIG).toContain(s)
})
