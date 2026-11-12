// Guards: Decision 276 AER v2 step 0 (Platform Admin 12 Nov 2026 17:20): a labelled validation set from existing decisions and one coverage definition (a course is covered for an applicant country when the resolver can publish a minimum), read only
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113053100_cf247_aer_v2_step0_labels_and_coverage.sql', 'utf8')

test('the labelled set is a view over decided rows: accepted, left out by Approve except, rejected; machine and person kept apart', () => {
  expect(m).toContain('create or replace view pipeline.aer_labelled_rows_v1 with (security_invoker = true)')
  expect(m).toMatch(/when m\.status_reason like 'excluded by approve except%' then 'left_out'/)
  expect(m).toMatch(/when m\.status_reason like 'quarantined \(rejected\)%' then 'rejected'/)
  expect(m).toMatch(/c0ffee00-0000-4000-8000-000000000150'::uuid then 'machine'/)
  for (const k of ["'country_table'", "'qualification'", "'course_page'"]) expect(m).toContain(k)
})

test('coverage follows the resolver rules (1 course override, 2 course row, 4 provider minimum at the course level or an equivalent), per applicant country from a setting', () => {
  expect(m).toContain('create or replace function security.aer_resolver_coverage_v1(p_countries text[] default null) returns jsonb')
  expect(m).toMatch(/language sql stable security definer/)
  expect(m).toContain("security.toolset_setting('pipeline', 'aer.coverage_countries')")
  expect(m).toContain("security.toolset_setting('pipeline', 'entry.level_equivalents')")
  expect(m).toMatch(/r\.kind = 'override' and r\.audience in \('international', 'all'\)/)
  expect(m).toMatch(/m\.matrix_kind = 'provider_minimum' and m\.min_grade is not null and m\.grade_scale is distinct from 'none'/)
  expect(m).not.toMatch(/^\s*(update|delete|drop|truncate)\b/im)
})
