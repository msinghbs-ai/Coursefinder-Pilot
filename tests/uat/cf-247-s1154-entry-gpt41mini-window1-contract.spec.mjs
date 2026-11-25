// Guards: Platform Admin 25 Nov 2026 18:26 AEDT (gpt-4.1-mini on the whole page for course entry requirements; proposed source-verified criteria approved; Window 1, the 172 unread courses, under a US$0 cap and one scoped on-demand request)
// s1154: the qualification, the route, the input setting, the request and the 172 reads, each through the audited writers' checks and logs; containment proven by post-checks.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261127030000_cf247_s1154_entry_gpt41mini_window1.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')
const CSV = '0345dedc-8c16-44a5-9b79-614a9990ac7f'  // first course of admin p0-aer-activation/2026-11-25-s1-aer-172-course-ids.csv

test('s1154: gpt-4.1-mini is qualified on the measured evidence, after the comparison is complete', () => {
  expect(MIG).toContain("where run_label = 's1151-entry-qualify-openai-v6-2026-11-25' and model_code = 'gpt-4.1-mini'")
  expect(MIG).toContain("if n <> 83 or d <> 83 or v <> 83 then raise exception")
  expect(MIG).toContain("values ('course_entry_requirements', 'gpt-4.1-mini', 'qualified', false, v_ev")
  expect(MIG).toContain('academic recall 95% (of 119)')
  expect(MIG).toContain('Platform Admin (chat, 25 Nov 2026 18:26 AEDT)')
})

test('s1154: whole-page input, route on with a US$0 cap, one request for the 20 providers, the 172 through the entry Read now', () => {
  expect(MIG).toContain("set value = to_jsonb(0), reason = v_reason, updated_at = now() where toolset_key = 'pipeline' and key = 'reading.course_entry_sections_on'")
  expect(MIG).toContain("update pipeline.ai_service_routes set cascade = array['gpt-4.1-mini'], daily_usd_cap = 0, enabled = true")
  expect(MIG).toContain("security.on_demand_close_v1('0de69556-171f-485d-9c81-e4a2b26f7455')")
  expect(MIG).toContain("v_od := security.on_demand_open_v1('claude_session', v_reason, v_prov,")
  expect(MIG).toContain("'firecrawl_credits', 0")
  expect(MIG).toContain("array['openrouter']")
  expect(MIG).toContain("v_job := security.course_entry_read_enqueue_v1(r.course_id, v_pa, v_reason);")
  expect(MIG).toContain(CSV)
  expect((MIG.match(/'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'/g) || []).filter((x) => !x.includes('0de69556') && !x.includes('63ba56cb')).length).toBe(172)
  expect(MIG).toContain("raise exception 'guard: the Window 1 list is not 172 courses at 20 providers'")
})

test('s1154: containment and guardrails are proven before commit; nothing is dropped, scheduled or admitted', () => {
  for (const s of ['post-check: % entry items outside the 172 could be read under an open request', 'post-check: the scheduled reader is not held by the cap',
    'post-check: the entry field is not held by the US$0 cap', 'post-check: course entry reads still send the selection', 'post-check: a qualification job is still active',
    'post-check: more than 140 active cron jobs', 'post-check: manual locks changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
  expect(code).not.toMatch(/cron\.schedule|layer4_review_items\s+set|catalogue\.course_entry_requirements\s+set|insert into catalogue\.|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  expect(MIG).not.toMatch(/deepseek/i)
})
