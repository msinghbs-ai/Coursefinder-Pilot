// Guards: CF-247 R2 (v2.15.350; throughput record section 3.3, O10 approved 24 Oct 2026): daily picked-courses cap and per-course stop.
// CF-247 R2 (v2.15.350; throughput record section 3.3, O10 approved 24 Oct 2026): daily picked-courses cap and per-course stop.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261024013000_cf247_r2_daily_cap_course_stop.sql', 'utf8')

test('settings: search.daily_picked_cap 100 [10–2,000] and search.stop_per_course_after 6 [3–20], in Course page search', () => {
  expect(m).toMatch(/'search\.daily_picked_cap', .*'100'::jsonb, '10', '2000', 'courses a day', \d+, 'Course page search'/)
  expect(m).toMatch(/'search\.stop_per_course_after', .*'6'::jsonb, '3', '20', 'wrong pages', \d+, 'Course page search'/)
})

test('picker: counts today\'s picks (UTC day), holds everything but a person\'s running task at the cap, skips courses with too many wrong pages', () => {
  expect(m).toMatch(/pg_temp\.edit_n\('public\.svc_course_link_search_next\(integer\)', '[0-9a-f]{32}'/)
  expect(m).toContain("select v_daycap - count(*) into v_room from pipeline.course_link_search where sent_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC');")
  expect(m).toContain('if v_room > 0 then v_lim := least(v_lim, v_room); end if;')
  expect(m).toContain('and (v_room > 0 or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id)))  -- R2: the daily cap')
  expect(m).toContain('(select count(distinct r.url) from pipeline.page_rejections r where r.course_id = s.course_id) < v_course_stop')
  // the university-wide stop stays behind it, untouched
  expect(m).not.toContain("search_stop_after'")
})

test('stall cause names the cap; nothing else changes', () => {
  expect(m).toMatch(/pg_temp\.edit_n\('security\.link_search_block_v1\(uuid,uuid\[\]\)', '[0-9a-f]{32}'/)
  expect(m).toContain("'code', 'daily_cap'")
  expect(m).not.toMatch(/update pipeline\.(course_link_search_settings|firecrawl_targets|platform_toolset_settings)/)
  expect(m).toMatch(/-- Replaces: .*\n-- Retires: nothing/)
})
