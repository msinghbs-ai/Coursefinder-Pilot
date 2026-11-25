// Guards: Platform Admin decision 26 Nov 2026 06:57 AEDT (option 2) and 08:19 AEDT (evaluate the remaining identity-held cohorts automatically under the approved rule); 25 Nov 18:26 AEDT (gpt-4.1-mini, whole page)
// s1193: Window 5 reads only never-AI-read courses whose page passes the proven sibling page, shortest stored page first, under a stored-character bound and the usual containment.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129020000_cf247_s1193_entry_window5_sibling_proven.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1193: the window is the approved rule, bounded and unread', () => {
  expect(MIG).toContain("and coalesce((security.entry_sibling_identity_v1(c.course_id, g.url)->>'ok')::boolean, false))) z")
  expect(MIG).toContain('where cum <= 9000000;')
  expect(MIG).toContain("if v_n < 150 or v_n > 500 then raise exception")
  expect(MIG).toContain("raise exception 'guard: a course entry read is still open; Window 5 opens only on an empty queue'")
  expect(MIG).toContain('perform security.course_entry_read_enqueue_v1(r.course_id, v_pa, v_r);')
})

test('s1193: same containment; nothing admitted, scheduled or dropped', () => {
  expect(MIG).toContain("'firecrawl_credits', 0")
  expect(MIG).toContain("array['openrouter']")
  for (const s of ['post-check: % entry items outside Window 5 could be read under an open request', 'post-check: Window 5 is not all queued', 'post-check: the scheduled reader is not held by the cap',
    'post-check: the entry field is not held by the US$0 cap', 'post-check: the number of active cron jobs changed', 'post-check: manual locks changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
  expect(code).not.toMatch(/cron\.schedule|cron\.alter_job|platform_toolset_settings|ai_route_qualifications\s*\(|layer4_review_items\s+set|insert into catalogue\.|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
})
