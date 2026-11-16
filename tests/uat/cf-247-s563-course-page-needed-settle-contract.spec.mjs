// Guards: Course page needed settle rule cpn-settle-v1 (Platform Admin 16 Nov 2026 20:14, quick win A): only entries whose outcome is on record are settled (a confirmed no-page record, or an active official link); no search, no spend, audited, count-only unless applied, and the migration settles nothing itself
// CF-247 S563. Migration 20261116160000_cf247_course_page_needed_settle.
// G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261116160000_cf247_course_page_needed_settle.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('settles only on recorded evidence: active official link -> page_added; confirmed no-page record -> no_page_exists', () => {
  expect(code).toContain("l.link_type = 'official_course' and l.status = 'active') then 'page_added'")
  expect(code).toContain("x.kind = 'no_page' and x.state in ('confirmed', 'confirmed_auto')) then 'no_page_exists'")
  expect(code).toContain("where p_apply and n.course_id = p.course_id and n.state = 'open'")
})

test('bounded by the existing batch setting, Platform Admin only, audited, and the migration only counts', () => {
  expect(code).toContain("security.pipeline_num_v1('layer4.page_needed_convert_batch', 500)")
  expect(code).toContain("raise exception 'Platform Admin role required'")
  expect(code).toContain("'course_page_needed_settle', 'pipeline.course_page_needed'")
  expect(code).toContain('r := security.course_page_needed_settle_v1(null, false);')
  expect(code).not.toMatch(/settle_v1\(\s*[^,]*,\s*true\)/)
})

test('no search, no external call, nothing dropped or deleted', () => {
  expect(code).not.toMatch(/course_link_search|net\.http|firecrawl/i)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
