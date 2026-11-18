// Guards: Course page needed search rule l4-page-needed-search-v1 (Platform Admin 18 Nov 2026 16:10 item 1): open Course page needed items are sent back to the course-link search lane only through the existing Search again decision, under the system automation account, a 404 or unread page first, within the per-course search limit and a batch from settings; a page blocked by the site or disallowed by robots is never searched again by the rule
// CF-247 S654. Migration 20261118190000_cf247_course_page_needed_search_rule. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations-archive/20261118190000_cf247_course_page_needed_search_rule.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name) => { const i = code.indexOf(`create or replace function ${name}(`); return code.slice(i, code.indexOf('$function$;', i)) }

test('only the existing Search again decision, under the system automation account, within the per-course limit', () => {
  const f = fn('security.course_page_needed_search_rule_v1')
  expect(f).toContain("v_res := security.course_page_needed_decide_v1(w.course_id, 'search_again', null,")
  expect(f).toContain("v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';")
  expect(f).toContain("perform set_config('request.jwt.claim.sub', v_sys::text, true);")
  expect(f).toContain("v_max int := security.pipeline_num_v1('layer4.page_needed_search_max', 3)::int;")
  expect(f).toContain('and n.searches_requested < v_max')
  expect(f).not.toMatch(/'add_page'|'no_page'|insert into catalogue\.|update catalogue\.|insert into pipeline\.course_link_search/)
})

test('blocked and robots-disallowed pages are never searched again; 404 and unread pages go first', () => {
  const f = fn('security.course_page_needed_search_rule_v1')
  expect(f).toContain("and coalesce(p.read_status, '-') not in ('blocked', 'robots_disallowed')")
  expect(f).toContain("order by case when p.http_status in (404, 410) then 0 when p.status = 'bound'")
  expect(code).toContain("raise exception 'post-check: a blocked or robots-disallowed page was searched again by the rule';")
})

test('the job runs hourly from settings; the first run must not fail; nothing dropped', () => {
  expect(code).toContain("select cron.schedule('layer4-page-needed-search', '53 * * * *',")
  expect(code).toContain("security.pipeline_num_v1(''layer4.page_needed_search_batch'', 300)::int")
  expect(code).toContain("if security.pipeline_num_v1('layer4.page_needed_search_rule_on', 0) < 1 or v_lim = 0 then")
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
