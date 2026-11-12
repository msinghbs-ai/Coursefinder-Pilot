// Guards: F-SCH.01 shadow review (Platform Admin 12 Nov 2026 11:50: act on evidence-proven cases only after validation succeeds): an international proof must name international students or applicants as who may apply; a course name holding the word "international" is not a proof
// The quotes are the six proofs of the first 200 shadow reads on live (12 Nov 2026 12:45 AEDT), plus the shapes the rule must keep.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { INTL_APPLICANT, eligibilityProof } from '../../supabase/functions/coverage-sweep/eligibility.ts'

const proven = (audience, audience_quote) => ({ audience, audience_quote, audience_proven: true, recommendation: 'international_check_and_publish' })

test('the two shadow false positives (course names) are no longer proofs; the three true ones and the domestic one stay', () => {
  expect(eligibilityProof(proven('both', 'Applicants who are currently enrolled either part or full-time in the Master of International Business at the University of Sydney Business School.')).audience_proven).toBe(false)
  expect(eligibilityProof(proven('international', 'This scholarship supports high-achieving students commencing an international business honours program in the University of Sydney Business School.')).audience_proven).toBe(false)
  expect(eligibilityProof(proven('both', 'Applicants must be an Australian or New Zealand citizen, holder of an Australian permanent resident or permanent humanitarian visa, or an International student.')).audience_proven).toBe(true)
  expect(eligibilityProof(proven('both', 'Prospective students (domestic) Prospective students (international)')).audience_proven).toBe(true)
  expect(eligibilityProof(proven('domestic', 'You must: be an Australian citizen or permanent resident, or New Zealand citizen')).audience_proven).toBe(true)
  const down = eligibilityProof(proven('both', 'Master of International Relations students'))
  expect([down.recommendation, down.proof]).toEqual(['audience_not_stated', 'international_not_applicant'])
})

test('shapes that name who may apply are kept; an unproven answer is unchanged', () => {
  for (const q of ['Open to domestic and international students.', 'International applicants are eligible.', 'Available to overseas students commencing in 2027.',
    'Applicants must hold a student visa (subclass 500).', 'Local or international students may apply.', 'Non-residents of Australia may apply.'])
    expect(INTL_APPLICANT.test(q), q).toBe(true)
  for (const q of ['Bachelor of International Studies', 'the International House residential college', 'an international conference travel grant'])
    expect(INTL_APPLICANT.test(q), q).toBe(false)
  const u = { audience: 'not_stated', audience_proven: false }
  expect(eligibilityProof(u)).toBe(u)
})

test('worker v0.76.0 applies the proof to every eligibility answer (page and linked page)', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('return eligibilityProof(judgeScholarshipRecheck(ans.a, `${title} ${h1} ${text}`));')
  expect(w).toMatch(/(?:const WORKER = "coverage-sweep-worker-v0\.76\.0"; |\/\/ was v0\.76\.0 )\/\/ v0\.76\.0 \(12 Nov 2026, CF-247 F-SCH\.01 shadow review/)
  const m = fs.readFileSync('supabase/migrations/20261113050000_cf247_sch_eligibility_proof.sql', 'utf8')
  expect(m).toContain("where outcome = 'proven' and result->>'audience' in ('international', 'both')")
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings/i) // no switch changes: the reader stays in shadow
})
