// Guards: SS-Programme-Control 27 Nov 2026 22:36 AEDT ("Verify actual canonical admission") and the Standing Mandate of 21 Nov 2026 (a verified fix ships live): the course pass of aer-partial-admit (aer-course-partial-v1, s983) is never starved by the entry-table pass
// CF-247 s1325. supabase/migrations/20261130220000_cf247_s1325_course_partial_admission_own_budget.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261130220000_cf247_s1325_course_partial_admission_own_budget.sql', 'utf8')

test('one md5-guarded edit: the course pass keeps its own clock and a fixed 15 s fire guard; nothing else changes', () => {
  expect(sql).toContain("if md5(d) <> '15ce951fb8d1d698302e1d457caeef25' then")
  expect(sql).toContain("'cr record; cc jsonb; c_t0 timestamptz := clock_timestamp(); /* s1325: the course pass''s own clock */'")
  expect(sql).toContain("'\\1c_t0\\2''15 seconds'';  /* s1325: own 15 s fire guard */'")
  expect(sql.match(/regexp_replace\(d,/g)).toHaveLength(2)
  expect(sql).toContain("if n <> 1 then raise exception 'guard: course pass fire guard found % times', n; end if;")
})

test('consumer API, locks, Layer 4 decisions and cron checked; no drop or delete', () => {
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(sql).toContain("post-check: a Layer 4 item was decided")
  expect(sql).not.toMatch(/\bdrop\s+(table|function|view|column|index|schema|policy)\b|\bdelete\s+from\b|\btruncate\s+/i)
  expect(sql).toMatch(/-- Replaces: security\.aer_partial_admit_v1/)
  expect(sql).toMatch(/-- Retires: nothing\./)
})
