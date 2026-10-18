// CF-247 (S65) relink of refused course pages (Platform Admin 18 Oct 2026 22:44 "Lets start on point 5"; choice "A+B, then D (Recommended)").
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const sql = fs.readFileSync('supabase/migrations/20261018150000_cf247_course_relink.sql', 'utf8')

test('candidates come from the address pattern, the stored lists and another course\'s refused page; the reader decides', () => {
  expect(sql).toContain("select replace(v_tpl, '{slug}', r.slug), 'url_pattern', 2")
  expect(sql).toContain("select l.url, 'url_list', 3 from (")
  expect(sql).toContain("select o.url, 'page_swap' src, 1 rk from pipeline.coverage_course_pages o")
  expect(sql).toContain('perform security.course_link_bind_v1(r.course_id, p_provider_id, v_c[1], v_s[1]);')
  expect(sql).toContain("security.pipeline_num_v1('relink.pattern_min_pages', 10)")
  expect(sql).toContain("security.pipeline_num_v1('relink.pattern_min_share', 0.5)")
})

test('D: absent when no candidate or every candidate refused; asked-for searches untouched', () => {
  expect(sql).toContain("'no address from the university''s address pattern or stored lists'")
  expect(sql).toContain("'every candidate address was refused by the reader or did not answer'")
  expect(sql).toContain("where course_id = r.course_id and state = 'queued' and requested_at is null;")
})

test('housekeeping and guards', () => {
  expect(sql).toMatch(/-- Replaces: nothing\n-- Retires: nothing/)
  expect(sql).toContain('comment on table pipeline.course_relink')
  expect(sql.indexOf('insert into pipeline.automation_catalogue')).toBeLessThan(sql.indexOf("select cron.schedule('course-relink'"))
  expect(sql).toContain("$$select security.course_relink_tick_v1(security.pipeline_num_v1('batch.course_relink', 200)::int)$$")
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(sql).not.toMatch(/website_v2_|website_edge_|zoho_edge_|\bapi\./)
})
