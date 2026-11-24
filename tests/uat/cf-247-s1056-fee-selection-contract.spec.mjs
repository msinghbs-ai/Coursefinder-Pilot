// Guards: Platform Admin 24 Nov 2026 21:35 AEDT (FEE-FU-01, Feedback 4: one governed fee selection; never full-course or another year as annual tuition; superseded fees out of current selection; VU EBCL year corrected)
// s1056: security.course_fee_selected_v1, the active-only course detail fee array, and the 105139H correction.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261125180000_cf247_s1056_fee_selection_and_feedback4.sql', 'utf8')
const fnStart = MIG.indexOf('CREATE OR REPLACE FUNCTION security.course_fee_selected_v1')
const fn = MIG.slice(fnStart, MIG.indexOf('$function$;', fnStart))

test('s1056: annual tuition only from active provider rows of basis annual or indicative_annual, for the asked year only', () => {
  expect(fn).toContain("f.status = 'active'")
  expect(fn).toContain("f.fee_type = 'provider_current_tuition' and f.basis in ('annual', 'indicative_annual') and f.amount > 0")
  expect(fn).toContain('where fee_year is not distinct from v_year and v_year is not null')
  expect(fn).toContain("'provider_published' else 'calculated_equivalent'")
  for (const s of ["'missing'", "'conflict'", "'campus_differs'", "'year_unstated'", "'past_year'"]) expect(fn).toContain(s)
  expect(fn).toContain("extract(year from (now() at time zone 'Australia/Melbourne'))")
})

test('s1056: CRICOS total, non-tuition and estimated total course cost are separate and never annual tuition', () => {
  expect(fn).toContain("'cricos_total_tuition'")
  expect(fn).toContain("f.fee_type = 'tuition' and f.basis = 'registered_total_course'")
  expect(fn).toContain("'non_tuition'")
  expect(fn).toContain("'estimated_total_course_cost'")
  expect(MIG).toContain("raise exception 'post-check: VU Nursing shows CRICOS total as annual or lost it: %'")
})

test('s1056: the course detail returns active fee rows with provenance and the governed selection; history is superseded, never deleted; locks respected', () => {
  expect(MIG).toContain("from catalogue.course_fees f where f.course_id=c.id and f.status='active'), '[]'::jsonb),")
  expect(MIG).toContain("'fee_selected', security.course_fee_selected_v1(c.id, 'international', null),")
  expect(MIG).toContain("update catalogue.course_fees set status = 'superseded'")
  expect(MIG).toContain("l.field in ('provider_tuition', 'provider_current_tuition', 'fees')")
  expect(MIG).not.toMatch(/delete from catalogue\.course_fees|drop table|cron\.schedule/i)
  expect(MIG).toContain("(v_course, 2027, r.audience, 'provider_current_tuition', 35500,")
})
