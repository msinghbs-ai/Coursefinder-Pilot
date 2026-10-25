// Guards: CF-247 S85: non-course pages are refused by setting, existing ones marked and their links set inactive (nothing deleted)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// CF-247 (Platform Admin, 21 Oct 2026 19:18 "Go on with task 3"): never-a-course-page patterns, term dates outside Australia,
// start months by hand for Otago, Calgary and SFU, SFU English page, NZIST names.
const m = fs.readFileSync('supabase/migrations/20261021235000_cf247_page_filter_calendars_nzist.sql', 'utf8')

test('non-course pages are refused by setting, existing ones marked and their links set inactive (nothing deleted)', () => {
  expect(m).toContain("('pipeline', 'pages.not_course_patterns'")
  expect(m).toContain('create or replace function security.not_course_page_v1(p_url text)')
  expect(m).toContain("new.status := 'mismatch'; new.read_status := 'not_course_page';")
  expect(m).toContain("update catalogue.course_links l set status = 'inactive'")
  expect(m).toContain('insert into pipeline.course_page_blocks(course_id, url, reason)')
  expect(m).not.toMatch(/^\s*delete from/im)
})

test('calendar countries come from a setting, not written in', () => {
  expect(m).toContain("('pipeline', 'calendar.countries'")
  expect(m).toContain("s3.key = 'calendar.countries'))")
  expect(m).toContain("'by_hand', v.proposal, 'approved'")
})

test('NZIST records named from NZQA and locked', () => {
  for (const k of ['6012', '6014', '6017', '6024', '6044', '6683']) expect(m).toContain(`('provider:nzqa:${k}',`)
  expect(m).toContain("raise exception 'the six NZIST records are not as expected'")
  expect(m).toMatch(/^-- Replaces: /m)
  expect(m).toMatch(/^-- Retires: /m)
})
