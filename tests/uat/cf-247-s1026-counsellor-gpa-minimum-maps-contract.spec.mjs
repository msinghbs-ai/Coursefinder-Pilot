// Guards: Platform Admin 24 Nov 2026 07:01 AEDT (S1-RM-Design s1026, REQ-110 follow-up): the Counsellor GPA sort and filter read the country's percentage minimums once per call, not once per course (s1024 took about 21 s live); same rule, so the same courses match; G3 frozen
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124113000_cf247_s1026_counsellor_gpa_minimum_maps.sql', 'utf8')

test('s1026: one map read per call replaces every per-course call in the course list', () => {
  expect(MIG).toContain("'10437508f09e57ccc9f29f048febbbc7'")
  expect(MIG).toContain("v_gpa_maps jsonb:=case when v_gpa_cc is null then null else security.gpa_min_maps_v1(v_gpa_cc,v_gpa_qual) end;")
  expect(MIG).toContain("security.course_gpa_min_percent_v1(numbered.id, numbered.provider_id, v_gpa_cc, v_gpa_qual)',")
  expect(MIG).toMatch(/v_gpa_maps->''provider''->>numbered\.provider_id::text\)::numeric\)', 2\);/)
  expect(MIG).toContain("if d ~ 'course_gpa_min_percent_v1' or d !~ 'v_gpa_maps' then")
})

test('s1026: the maps keep the s1024 rule (percentage only, course rows first, else provider rows) and are checked against it', () => {
  expect((MIG.match(/m\.grade_scale = 'percentage' and m\.min_value between 0 and 100/g) || []).length).toBe(2)
  expect(MIG).toContain("where m.course_id is not null and m.status = 'active'")
  expect(MIG).toContain("where m.course_id is null and m.status = 'active'")
  expect(MIG).toContain('post-check: the maps and the per-course minimum disagree')
})

test('s1026: G3 guarded before and after, locks and cron unchanged, nothing dropped or deleted', () => {
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect((MIG.match(/\(v->>'functions'\)::int <> 75|\(v_api->>'functions'\)::int <> 75/g) || []).length).toBe(2)
  expect(MIG).toContain('post-check: manual locks changed')
  expect(MIG).toContain('revoke all on function security.gpa_min_maps_v1(text, text) from public, anon, authenticated;')
  expect(MIG).not.toMatch(/website_v[23]_|zoho_edge|create or replace function api\.|cron\.(schedule|unschedule|alter_job)|\bdrop (table|function|index|schema|view|trigger)|delete from |truncate /i)
})
