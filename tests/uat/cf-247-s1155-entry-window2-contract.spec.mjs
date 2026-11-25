// Guards: Platform Admin 25 Nov 2026 14:36 AEDT (Decision 3: Window 2 for the 267 waiting items only after Window 1 finishes cleanly, same containment, route off after) and 18:26 AEDT (gpt-4.1-mini, whole page)
// s1155: Window 1 is closed (route off, its request closed) only when its 172 items are all resolved; Window 2 opens for exactly the reconciled 267 at 22 providers.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261127040000_cf247_s1155_entry_window1_close_window2.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1155: Window 1 closes only when finished; Window 2 is exactly the reconciled queue', () => {
  expect(MIG).toContain("if exists (select 1 from s1155_w1 where state in ('queued', 'waiting', 'ai', 'leased')) then raise exception 'guard: Window 1 is not finished'; end if;")
  expect(MIG).toContain("(select count(distinct provider_id) from s1155_w2) <> 22")
  expect(MIG).toContain("update pipeline.ai_service_routes set enabled = false, reason = v_r1")
  expect(MIG).toContain('perform security.on_demand_close_v1(r.id); v_closed := v_closed + 1;')
  expect(MIG).toContain("v_od := security.on_demand_open_v1('claude_session', v_r2, v_prov,")
  expect(MIG).toContain("'firecrawl_credits', 0")
})

test('s1155: containment and guardrails are proven before commit; nothing queued, admitted, scheduled or dropped', () => {
  for (const s of ['post-check: % entry items outside the 267 could be read under an open request', 'post-check: the scheduled reader is not held by the cap',
    'post-check: the entry field is not held by the US$0 cap', 'post-check: the number of active cron jobs changed', 'post-check: manual locks changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
  expect(code).not.toMatch(/course_entry_read_enqueue_v1|cron\.schedule|cron\.alter_job|layer4_review_items\s+set|insert into catalogue\.|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
})
