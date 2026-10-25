// Guards: CF-247 (S66) relink follow-up: address forms by study level;
// CF-247 (S66) relink follow-up: address forms by study level; paused worker jobs switch on again when work waits.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const sql = fs.readFileSync('supabase/migrations/20261018160000_cf247_relink_levels_and_wake.sql', 'utf8')

test('guarded; every address form with enough pages counts, same study level first; first-rule absents relinked again', () => {
  for (const m of ['f51e31cceffbd15ffc906d01dfb12220', '90379a09e3b89d031add182acc339bca', '99bf9f8c25020375e5c27ce66d0e160c']) expect(sql).toContain(m)
  expect(sql).toContain("having count(*) >= v_min")
  expect(sql).toContain("(fm.form->'levels') @> to_jsonb(r.lvl)")
  expect(sql).toContain("not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%')")
})

test('wake: a paused read or link_search job is switched on again when work waits', () => {
  expect(sql).toContain('(f.next_check_at <= now() or security.worker_mode_waiting_v1(j.mode))')
  expect(sql).toContain("when 'read' then exists (select 1 from pipeline.coverage_course_pages p")
  expect(sql).toContain("when 'link_search' then exists (select 1 from pipeline.course_link_search s")
  expect(sql).toMatch(/-- Replaces: .+\n-- Retires: nothing/)
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
