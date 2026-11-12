// Guards: Decision 276 AER v2 step 0 (design v0.3 §3.8: Coverage & completeness computes academic_entry from admitted records, by the resolver's rules)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('academic_entry counts courses with a published minimum (resolver rules 1, 2, 4) beside academic options; the build is edited only where guarded', () => {
  const m = fs.readFileSync('supabase/migrations/20261113093100_cf247_aer_coverage_screen.sql', 'utf8')
  expect(m).toContain("'2f6a9a8314281004d9fa4253527a5488'")
  expect(m).toContain('create temp table _aer_cov on commit drop as select x.course_id from security.aer_covered_courses_v1() x;')
  expect(m).toContain('or exists(select 1 from _aer_cov x where x.course_id=c.course_id)) academic')
  expect(m).toMatch(/r\.kind = 'override' and r\.audience in \('international', 'all'\)/)
  expect(m).toMatch(/m\.matrix_kind = 'provider_minimum' and m\.min_grade is not null and m\.grade_scale is distinct from 'none'/)
  expect(m).not.toMatch(/^\s*(delete|drop|truncate|update)\b/im)
})
