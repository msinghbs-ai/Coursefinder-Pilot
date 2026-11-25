// Guards: Platform Admin 26 Nov 2026 03:59 AEDT (closest to admission; reuse stored evidence and qualified readers; spending limits) and 25 Nov 2026 18:26 AEDT (gpt-4.1-mini, whole page); Authority Charter 23 Nov item 2 (Tier 1 universities)
// s1158: Window 3 reads only identity-proven university courses read with no admissible row and never AI-read, shortest stored page first, under a stored-character bound.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261128210000_cf247_s1158_entry_window3_universities.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1158: the window is bounded, proven, unread and university-only', () => {
  expect(MIG).toContain("pt.code = 'university'")
  expect(MIG).toContain("security.coverage_identity_allowed(c.provider_id, c.ib, 'entry_requirements')) z")
  expect(MIG).toContain('where cum <= 9000000;')
  expect(MIG).toContain("f.reason ~* 'does not state|no quoted|admission rules|superseded'")
  expect(MIG).toContain("raise exception 'guard: a course entry read is still open; Window 3 opens only on an empty queue'")
  expect(MIG).toContain("if v_n < 200 or v_n > 700 then raise exception")
  expect(MIG).toContain('perform security.course_entry_read_enqueue_v1(r.course_id, v_pa, v_r);')
})

test('s1158: same containment; nothing admitted, scheduled or dropped', () => {
  expect(MIG).toContain("'firecrawl_credits', 0")
  expect(MIG).toContain("array['openrouter']")
  for (const s of ['post-check: % entry items outside Window 3 could be read under an open request', 'post-check: Window 3 is not all queued', 'post-check: the scheduled reader is not held by the cap',
    'post-check: the entry field is not held by the US$0 cap', 'post-check: the number of active cron jobs changed', 'post-check: manual locks changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
  expect(code).not.toMatch(/cron\.schedule|cron\.alter_job|platform_toolset_settings|ai_route_qualifications\s*\(|layer4_review_items\s+set|insert into catalogue\.|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
})
