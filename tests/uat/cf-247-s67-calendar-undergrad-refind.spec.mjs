// CF-247 (S67) 19 Oct 2026: calendar intakes for universities' undergraduate courses; re-find a provider's pages on its current website.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const sql = fs.readFileSync('supabase/migrations/20261019010000_cf247_calendar_undergrad_and_refind.sql', 'utf8')

test('calendar: universities only at the study levels in calendar.university_levels (undergraduate), guarded edit', () => {
  expect(sql).toContain("'9d39783597ebdedddf0e59dddec61bbb'")
  expect(sql).toContain('["bachelor", "bachelor_honours", "associate_degree", "diploma", "advanced_diploma"]')
  expect(sql).toContain("and (not cal.uni or exists (select 1 from ref.study_levels sl where sl.id = c.study_level_id and sl.code in (select jsonb_array_elements_text(s2.value)")
})

test('re-find: old page kept until a new one passes, put back when none does; Adelaide started', () => {
  expect(sql).toContain("'9a8ddb7f000d5ccca6f2fc5311728bed'")
  expect(sql).toContain("or exists (select 1 from pipeline.page_refind r where r.course_id = pipeline.coverage_course_pages.course_id and r.state = ''open'');")
  expect(sql).toContain("update pipeline.page_refind r set state = 'kept_old'")
  expect(sql).toContain("select security.page_refind_start_v1(p.id, 'adelaide.edu.au'")
  expect(sql).toMatch(/-- Replaces: .+/)
  expect(sql).toContain('comment on table pipeline.page_refind')
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(sql).not.toMatch(/website_v2_|website_edge_|zoho_edge_|\bapi\./)
})
