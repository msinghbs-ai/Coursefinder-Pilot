// Decision 211: scholarship eligibility criteria and award scope from the provider page; old course-link candidates retired.
import { test, expect } from '@playwright/test'
import os from 'node:os'
import path from 'node:path'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')
async function load() {
  const out = path.join(os.tmpdir(), `sch-crit-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/scholarship.ts', '--bundle', '--format=esm', `--outfile=${out}`])
  return import(out)
}
const kinds = list => list.map(c => [c.type, c.value_text ?? c.value_codes, c.value_number].filter(v => v != null))

test('reader: criteria from the eligibility wording, negations respected', async () => {
  const { scholarshipCriteria } = await load()
  expect(kinds(scholarshipCriteria('Eligibility To be eligible you must: identify as a woman be an Australian citizen, an Australian permanent resident or permanent humanitarian visa holder be enrolled full-time be in your third or fourth year of study in 2026 have a Grade Point Average (GPA) to date of 2.5 or higher')))
    .toEqual([['student_type', ['domestic']], ['study_stage', 'current'], ['study_load', 'full_time'], ['academic_minimum', 'GPA', 2.5], ['gender', 'women']])
  expect(kinds(scholarshipCriteria('eligible To be eligible for this award, you must: be an international student receive admission into a full-time undergraduate degree, commencing in 2027 not be an Australian or New Zealand citizen, or a permanent resident of Australia')))
    .toEqual([['student_type', ['international']], ['study_stage', 'commencing'], ['study_load', 'full_time']])
  expect(kinds(scholarshipCriteria('Eligibility: Australian citizens and permanent residents are not eligible. You must be an international student.'))).toEqual([['student_type', ['international']]])
  expect(kinds(scholarshipCriteria('Eligible student type Domestic and international students Eligible study stage Future study. Open for automatic consideration')))
    .toEqual([['student_type', ['domestic', 'international']], ['study_stage', 'commencing'], ['application_method', 'automatic']])
  // a shortened list hides the rest: not domestic-only
  expect(kinds(scholarshipCriteria('Key information Eligible citizenship Australian citizen, Permanent resident +2 more Eligible student type Current student'))).toEqual([['study_stage', 'current']])
  expect(kinds(scholarshipCriteria('Who is eligible? You must be a citizen of India, Sri Lanka, Nepal or Bangladesh.'))).toEqual([['nationality', ['BD', 'IN', 'LK', 'NP']]])
  expect(kinds(scholarshipCriteria('Eligibility: commencing a Bachelor with an Australian Tertiary Admission Rank (ATAR) of 85 or higher'))).toEqual([['study_stage', 'commencing'], ['academic_minimum', 'ATAR', 85]])
  // "future or current" is mixed: left out; "an equivalent international degree" is not a student type
  expect(kinds(scholarshipCriteria('Eligibility Future or current PhD student. You hold an Honours degree or an equivalent international degree.'))).toEqual([])
  for (const c of scholarshipCriteria('Eligibility: be an international student commencing full-time study')) expect(c.text.length).toBeGreaterThan(10)
})

test('reader: award scope from the benefit wording only', async () => {
  const { awardScope } = await load()
  expect(awardScope('Benefits This scholarship provides $2500 per year for three years, paid in half-yearly instalments.')).toMatchObject({ duration: 'annual_program_duration', years: 3 })
  expect(awardScope('Key information Benefit amount $6,000 (one-off payment)')).toMatchObject({ duration: 'one_off' })
  expect(awardScope('The scholarship provides a 20% reduction in tuition fees for the standard duration of your program.')).toMatchObject({ duration: 'program_duration', applies_to: ['tuition_fee'] })
  // "for the duration of your program" inside eligibility is about enrolment, not the award
  expect(awardScope('Eligibility you must be enrolled full-time for the duration of your program')).toBeNull()
})

test('database: criteria rows marked by the sweep, other sources untouched; old candidates kept as superseded', () => {
  const m = read('supabase/migrations/20261002180300_cf247_scholarship_criteria_and_scope.sql')
  expect(m).toContain("check (status = any (array['needs_review','accepted','rejected','superseded']))")
  expect(m).toContain("update scholarship.course_mapping_candidates set status = 'superseded'")
  expect(m).toContain("status=case when scholarship.course_mapping_candidates.status='superseded' then 'superseded' else 'needs_review' end;")
  expect(m).toContain("where scholarship_id = s.id and status = 'active' and value_json->>'by' = 'scholarship_sweep';")
  expect(m).toContain("if s.award_duration_basis is null and v_dur in")
  expect(m).toContain("v_changes:=v_changes||security.scholarship_criteria_apply_v1(s.id);")
  for (const h of ['227e2ee15a868acc5555b55bfc41ad7d', '30c019473f3fe3e46382e93079d8cfb5', '19619049f548b3af7a26429af0a13084']) expect(m).toContain(`if v is distinct from '${h}' then raise exception`)
  expect(m.toLowerCase()).not.toContain('delete from')
  expect(m.toLowerCase()).not.toContain('on delete cascade')
  // publication rules unchanged in this migration
  expect(m).not.toContain('scholarship_publishability_v1')
  expect(m).not.toMatch(/set\s+publication_status/)
  const idx = read('supabase/functions/coverage-sweep/index.ts')
  expect(idx).toContain('mode === "scholarship_reextract"')
  expect(idx).toContain('scholarship-sweep-v0.5.0')
})

test('browser: scholarship record shows eligibility and award duration (active rows only)', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#scholarships?id=5f92fc8c-ad2b-5182-a3b7-2e9bba5b3d99')
  const p = page.locator('[data-scholarship-eligibility]')
  await expect(p).toContainText('Each year, for the length of the course')
  await expect(p).toContainText('International students')
  await expect(p).toContainText('GPA 5.5 out of 7 or higher')
  await expect(p).not.toContainText('old reading')
})
