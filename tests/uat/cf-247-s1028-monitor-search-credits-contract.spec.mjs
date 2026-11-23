// Guards: Platform Admin 24 Nov 2026 09:06 AEDT (UI-UX plan v1.2 slice 8: the Firecrawl Monitor week counts what Firecrawl charges, so the 150-credit cap pauses only real overspend)
// s1028: a completed search check counts 2 credits per 10 results; a page check counts firecrawl.monitor_credits_per_url per page.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124123000_cf247_s1028_monitor_search_credits.sql', 'utf8')

test('s1028: search checks at the search price, page checks per page from the G2 setting; md5-style guard; nothing else changes', () => {
  expect(MIG).toContain("m.monitor_id = p->>'monitor_id' and m.target_type = 'search')")
  expect(MIG).toContain("then 2 * ceil(coalesce((p->'summary'->>'totalPages')::numeric, 0) / 10.0)")
  expect(MIG).toContain("* security.monitor_setting_v1('monitor_credits_per_url', 5) end;")
  expect(MIG).toContain("raise exception 'guard: public.svc_monitor_event_v1 is not the s1027 definition'")
  expect((MIG.match(/CREATE OR REPLACE FUNCTION/g) || []).length).toBe(1)
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)|delete from|truncate /i)
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
