// Guards: SS-Programme-Control 26 Nov 2026 15:09 AEDT, P0 item 3 (lean-md-v3 live check), and the standing cron limit: the recall job switched on by s1197 is off again once its case is recorded
// s1198: lean-sections-eval switched off after the s1197 case; guarded on the case being recorded; nothing else changes.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129131500_cf247_s1198_lean_check_off.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1198: the recall job is switched off only once the s1197 case is recorded', () => {
  expect(MIG).toContain("raise exception 'guard: the s1197 case is not recorded yet'")
  expect(MIG).toContain("perform cron.alter_job(job_id := v_job, active := false);")
  expect(MIG).toContain("raise exception 'post-check: lean-sections-eval is still on'")
})

test('s1198: no AI, route, admission, setting or new job, and nothing dropped', () => {
  expect(code).not.toMatch(/ai_service_routes|on_demand_open|layer4_review_items|course_entry_requirements|platform_toolset_settings|cron\.schedule|\bdelete from\b|truncate |active := true/i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
})
