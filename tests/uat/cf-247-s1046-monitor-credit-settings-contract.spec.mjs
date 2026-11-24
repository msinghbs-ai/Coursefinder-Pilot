// Guards: Platform Admin 24 Nov 2026 15:10 AEDT (approved: firecrawl.monitor_credits_per_url 6 and firecrawl.monitor_weekly_credits 160, so every Firecrawl Monitor target runs without pausing)
// s1046: the two settings change as the Settings writer changes them (range check, reason, one logged event each) and the watchlist still fits the cap.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124233000_cf247_s1046_monitor_credit_settings.sql', 'utf8')

test('s1046: credits per page 6 and weekly cap 160, range-checked, with a reason and a logged event each; no target held for budget', () => {
  expect(MIG).toContain("('monitor_credits_per_url', 6::numeric), ('monitor_weekly_credits', 160::numeric)")
  expect(MIG).toContain('(s.min_value is null or r.v >= s.min_value) and (s.max_value is null or r.v <= s.max_value)')
  expect(MIG).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
  expect(MIG).toContain("'approved_by', 'Platform Admin (chat, 24 Nov 2026 15:10 AEDT)'")
  expect(MIG).toContain("if (v_plan->>'held_budget')::int <> 0 or (v_plan->>'est_week_credits')::numeric > 160 then raise exception")
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)|delete from|truncate |cron\.schedule/i)
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
