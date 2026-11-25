// Guards: Platform Admin 25 Nov 2026 14:36 AEDT (the course entry route is switched off once each window is read)
// s1190: Window 4 is closed only when no course entry read is open: route off and its request closed, logged; nothing else changes.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128230000_cf247_s1190_entry_window4_close.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1190: the route is switched off and Window 4 request closed once the window is read', () => {
  expect(MIG).toContain("raise exception 'guard: a course entry read is still open; Window 4 is not finished'")
  expect(MIG).toContain("update pipeline.ai_service_routes set enabled = false, reason = v_r")
  expect(MIG).toContain("reason like 'Platform Admin 26 Nov 2026 03:59 AEDT (closest to admission)%Window 4,%' loop")
  expect(MIG).toContain("raise exception 'post-check: the course entry route is still on'")
})

test('s1190: nothing else changes; nothing is queued, admitted, scheduled or dropped', () => {
  expect(code).not.toMatch(/course_entry_read_enqueue_v1|on_demand_open_v1|platform_toolset_settings|ai_route_qualifications|cron\.schedule|cron\.alter_job|layer4_review_items\s+set|insert into catalogue\.|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  for (const s of ['post-check: the number of active cron jobs changed', 'post-check: manual locks changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
})
