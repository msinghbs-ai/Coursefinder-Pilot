// Guards: Platform Admin 24 Nov 2026 07:01 AEDT (S1-RM-Design s1024, REQ-110 follow-up, answer "Percentage-only"): an optional GPA sort and "meets minimum" filter on the Counsellor course list reads percentage-scale minimums only; CBSE Class X grade points are never compared with course minimums; G3 frozen
// s1024: the course list changes in place from its md5-checked definitions, each insertion exactly once; absent arguments leave the list as before.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124103000_cf247_s1024_counsellor_gpa_sort_filter.sql', 'utf8')

test('s1024: only percentage-scale minimums are compared, course rows before provider rows', () => {
  expect((MIG.match(/m\.grade_scale = 'percentage' and m\.min_value between 0 and 100/g) || []).length).toBe(2)
  expect(MIG).toContain('where m.course_id = p_course and m.status = \'active\'')
  expect(MIG).toContain('where m.course_id is null and m.provider_id = coalesce(p_provider')
  expect(MIG).not.toMatch(/grade_scale\s*(=|in)\s*\(?'(gpa|points|letter|aggregate|rank)'/)
})

test('s1024: a student result converts only from a listed scale at a published point; CBSE Class X is not listed', () => {
  expect(MIG).toContain("'lookups.gpa_comparable_scales'")
  expect(MIG).toMatch(/'list', '\[\]'::jsonb/)
  expect(MIG).toContain("s.value ? v_code")
  expect(MIG).toContain('v_val between g.raw_min_value and coalesce(g.raw_max_value, g.raw_min_value)')
  expect(MIG).toContain(`security.gpa_student_percent_v1('{"gpa_country":"IN","gpa_scale_code":"CBSE_X_GP10","gpa_value":"9"}') is not null`)
})

test('s1024: the course list is changed in place from pinned definitions, and absent arguments keep the old path', () => {
  expect(MIG).toContain("'cd2d1610e25ca4fca3cefc33f77b4dc3'")
  expect(MIG).toContain("'22eb2f5e78def853193e672808628e69'")
  expect(MIG).toContain("expected exactly one")
  expect(MIG).toContain("and nullif(p_args->>''gpa_country'','''') is null  -- s1024")
  expect(MIG).toContain("v_intake_year is null and v_test is null and v_gpa_cc is null then")
  expect(MIG).toContain("v_gpa_cc is null or not v_gpa_meets or v_gpa_pct is null or security.course_gpa_min_percent_v1(c.id, c.provider_id, v_gpa_cc, v_gpa_qual) <= v_gpa_pct")
  expect(MIG).toContain("case when v_sort=''gpa'' and v_dir=''asc''")
  expect(MIG).toContain("''gpa_minimums'',case when v_gpa_cc is null then null")
})

test('s1024: G3 guarded before and after, locks and cron unchanged, helpers not open to anon, nothing dropped or deleted', () => {
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect((MIG.match(/\(v->>'functions'\)::int <> 75|\(v_api->>'functions'\)::int <> 75/g) || []).length).toBe(2)
  expect(MIG).toContain('post-check: manual locks changed')
  expect(MIG).toContain('post-check: the number of active cron jobs changed')
  expect(MIG).toContain('revoke all on function security.course_gpa_min_percent_v1(uuid, uuid, text, text) from public, anon, authenticated;')
  expect(MIG).not.toMatch(/website_v[23]_|zoho_edge|create or replace function api\.|cron\.(schedule|unschedule|alter_job)|\bdrop (table|function|index|schema|view|trigger)|delete from |truncate /i)
})
