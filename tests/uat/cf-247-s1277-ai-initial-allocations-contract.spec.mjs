// Guards: Platform Admin via SS-Programme-Control 26 Nov 2026 21:43 AEDT, confirmed in session (initial AI allocations: academic entry US$5 a day, platform AI ceiling US$10 a day; Firecrawl unchanged)
// s1277: only the course entry route cap (US$1.00 -> US$5.00) and budgets.ai_daily_ceiling_usd (5 -> 10) change, each guarded and audited.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261130000000_cf247_s1277_ai_initial_allocations.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1277: the entry cap and the platform AI ceiling change, guarded on their current values, with reasons and audit events', () => {
  expect(code).toContain('update pipeline.ai_service_routes set daily_usd_cap = 5.00, reason = v_reason, changed_at = now()')
  expect(code).toContain("set value = to_jsonb(10), reason = v_reason, updated_at = now()")
  expect(code).toContain("where toolset_key = 'pipeline' and key = 'budgets.ai_daily_ceiling_usd';")
  expect(code).toContain("daily_usd_cap = 1.00 and cascade = array['gpt-4.1-mini']")
  expect(code).toContain("security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', -1) <> 5")
  expect(code.match(/update pipeline\.ai_service_routes/g).length).toBe(1)
  expect(code.match(/update pipeline\.platform_toolset_settings/g).length).toBe(1)
  expect(code.match(/insert into pipeline\.admin_control_events/g).length).toBe(2)
})

test('s1277: no model, qualification, job, Firecrawl or consumer change; nothing dropped', () => {
  expect(code).not.toMatch(/cascade\s*=\s*array\[[^\]]*\]\s*,|ai_route_qualifications\s+set|insert into pipeline\.ai_route_qualifications|firecrawl|cron\.schedule|cron\.alter_job|\bdelete from\b|truncate |website_v2_/i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
  for (const s of ['post-check: active cron jobs changed', 'post-check: manual locks changed', 'post-check: consumer API moved']) expect(MIG).toContain(s)
})
