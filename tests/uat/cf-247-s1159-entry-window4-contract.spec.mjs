// Guards: Platform Admin 26 Nov 2026 03:59 AEDT (closest to admission; reuse stored evidence and qualified readers; spending limits) and 25 Nov 2026 18:26 AEDT (gpt-4.1-mini, whole page); Authority Charter 23 Nov item 2 (Tier 1 universities)
// s1159: Window 4 reads only courses read with no admissible row and never AI-read whose page passes the entry identity rule and the read gate's course page check, shortest stored page first, under a stored-character bound.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128220000_cf247_s1159_entry_window4_gate_checked.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1159: the window is bounded, proven by the gate's own checks, and unread', () => {
  expect(MIG).toContain("and security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')")
  expect(MIG).toContain("security.course_page_check_v1(c.course_id, coalesce(nullif(g.candidates->>'final_url', ''), g.url), coalesce(nullif(g.candidates->>'page_title', ''), g.candidates->>'h1'), g.identity_basis)->>'verdict') is distinct from 'refuse'")
  expect(MIG).toContain('where cum <= 9000000;')
  expect(MIG).toContain("f.reason ~* 'does not state|no quoted|admission rules|superseded|proven course page|correct course page'")
  expect(MIG).toContain("raise exception 'guard: a course entry read is still open; Window 4 opens only on an empty queue'")
  expect(MIG).toContain("if v_n < 60 or v_n > 300 then raise exception")
  expect(MIG).toContain('perform security.course_entry_read_enqueue_v1(r.course_id, v_pa, v_r);')
})

test('s1159: same containment; nothing admitted, scheduled or dropped', () => {
  expect(MIG).toContain("'firecrawl_credits', 0")
  expect(MIG).toContain("array['openrouter']")
  for (const s of ['post-check: % entry items outside Window 4 could be read under an open request', 'post-check: Window 4 is not all queued', 'post-check: the scheduled reader is not held by the cap',
    'post-check: the entry field is not held by the US$0 cap', 'post-check: the number of active cron jobs changed', 'post-check: manual locks changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
  expect(code).not.toMatch(/cron\.schedule|cron\.alter_job|platform_toolset_settings|ai_route_qualifications\s*\(|layer4_review_items\s+set|insert into catalogue\.|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
})
