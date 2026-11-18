// Guards: scholarship detail fill (Platform Admin 18 Nov 2026 13:02 and 15:32): the existing reader fills award values and closing dates from the stored official page, no overwrite, no new review kind; a dead lease at the attempt cap never blocks the idle fill.
// CF-247 S652. supabase/migrations-archive/20261118184000_cf247_scholarship_reader_stall_fix.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118184000_cf247_scholarship_reader_stall_fix.sql', 'utf8')

test('the idle fill counts only what the picker can take', () => {
  expect(M).toContain("select pg_temp.cf_edit('security.scholarship_ai_fire_v1()'::regprocedure, '127e679f0a07e2d97814e5d4e94a0b14',")
  expect(M).toContain("where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3;")
  expect(M).toContain("if position('and q.attempts < 3;' in v_src) = 0 then raise exception 'post-check: the due count must follow the picker'; end if;")
})

test('dead leases are settled by an update, and the catch-up runs in an on-demand window with an estimate', () => {
  expect(M).toContain("set state = 'failed', done_at = now(), leased_until = null,")
  expect(M).toContain("v_res := security.on_demand_open_v1('claude_session',")
  expect(M).toContain("null, '{openrouter}');")
  expect(M).toContain("'usd_estimate'")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})

test('no new review kind and no overwrite path: the existing apply path is left as it is', () => {
  expect(M).not.toMatch(/layer4_review_kinds|review_kind\s*=|insert into pipeline\.layer4/i)
  expect(M).not.toMatch(/scholarship_detail_apply_v1\s*\(/)
  expect(M).not.toMatch(/update\s+scholarship\.scholarships/i)
})
