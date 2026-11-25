// Guards: Platform Admin 25 Nov 2026 14:36 AEDT (guardrail: daily spend well inside US$5.00; route off after each window)
// s1156 (applied live first through db-apply-migration.yml; its applied text is kept in supabase/migration-history/applied/ by the history sync, s782): Window 2 is held when its spend runs far above the estimate: the course entry route is switched off and its request closed, logged; nothing else changes.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migration-history/applied/20261127050000_cf247_s1156_entry_window2_spend_hold.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1156: the route is switched off and Window 2 request closed, each with its reason', () => {
  expect(MIG).toContain("update pipeline.ai_service_routes set enabled = false, reason = v_r")
  expect(MIG).toContain("reason like 'Platform Admin 25 Nov 2026 14:36 and 18:26 AEDT: Window 2,%' loop")
  expect(MIG).toContain("perform security.on_demand_close_v1(r.id)")
  expect(MIG).toContain("raise exception 'post-check: the course entry route is still on'")
})

test('s1156: nothing else changes; nothing is queued, admitted, scheduled or dropped', () => {
  expect(code).not.toMatch(/course_entry_read_enqueue_v1|on_demand_open_v1|platform_toolset_settings|ai_route_qualifications|cron\.schedule|cron\.alter_job|layer4_review_items|insert into catalogue\.|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  for (const s of ['post-check: the number of active cron jobs changed', 'post-check: manual locks changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
})
