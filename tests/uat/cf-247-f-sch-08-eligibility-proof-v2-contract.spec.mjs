// Guards: F-SCH.01 post-activation review (12 Nov 2026 16:55): an international proof must say that this scholarship is open to international students; course titles, site banners, fee instructions, menu tags and search controls are not proofs; unsupported claims stay protected (directive 12 Nov 2026 16:12 §5, §14 item 5)
// The quotes are the live proofs of 12 Nov 2026 (first live run and shadow), plus shapes that must stay proofs.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { eligibilityProof } from '../../supabase/functions/coverage-sweep/eligibility.ts'

const proven = (audience, audience_quote) => ({ audience, audience_quote, audience_proven: true, recommendation: 'international_check_and_publish' })
const ok = (a, q) => eligibilityProof(proven(a, q)).audience_proven
const why = (a, q) => eligibilityProof(proven(a, q)).proof

test('the false proofs of the first live run are refused, each with its reason', () => {
  expect(why('both', 'Continuing full-time student in the Master of Pharmacy (C04252) or Master of Pharmacy (International) (C04253); and')).toBe('international_not_applicant')
  expect(why('both', 'Scholarships With a broad offering for both domestic and international applicants, our scholarship program rewards high achievers in academia, leadership, community engagement, and sport.')).toBe('programme_wide')
  expect(why('both', 'International students must pay their International Tuition Deposit prior to receiving access to the online awards application .')).toBe('payment_instruction')
  expect(why('both', 'If you are an international student find out how much you will need to pay to enter.')).toBe('payment_instruction')
  expect(why('both', 'Prospective students (domestic) Prospective students (international)')).toBe('no_eligibility_cue')
  expect(why('both', 'Student type: * Select... Domestic (Australia or New Zealand) International')).toBe('form_control')
})

test('sentences that say who may apply stay proofs; domestic proofs and unproven answers are unchanged', () => {
  for (const q of ['Academic course fees and the Student Services Amenities fee are not included for a successful international applicant.',
    'Applicants must be an Australian or New Zealand citizen, holder of an Australian permanent resident or permanent humanitarian visa, or an International student.',
    'Open to domestic and international students.', 'Student type: Domestic students, International students', 'You must: be an international student',
    'Eligible student type International students', 'Be applying to The University of Western Australia as an international student on an Australian student visa',
    'UNE offers eligible commencing international students a bursary in the form of a 20% fee reduction', 'This opportunity is open to domestic and international applicants.'])
    expect(ok('both', q), q).toBe(true)
  const d = proven('domestic', 'You must: be an Australian citizen or permanent resident, or New Zealand citizen')
  expect(eligibilityProof(d)).toBe(d)
  const u = { audience: 'not_stated', audience_proven: false }
  expect(eligibilityProof(u)).toBe(u)
})

test('worker v0.78.0 and migration 20261113064000: shadow only, government sites refused, the international proofs read again', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toMatch(/(?:const WORKER = "coverage-sweep-worker-v0\.78\.0"; |\/\/ was v0\.78\.0 )\/\/ v0\.78\.0 \(12 Nov 2026, CF-247 F-SCH\.01 post-activation review/)
  const m = fs.readFileSync('supabase/migrations/20261113064000_cf247_sch_eligibility_proof_v2.sql', 'utf8')
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings/i) // the reader stays in shadow; going live is its own step
  expect(m).toContain("'5b684e8b755092672641c7d113c3800e'")
  expect(m).toContain("security.scholarship_government_host_v1(v_url)")
  expect(m).toContain("where outcome = 'proven' and result->>'audience' in ('international', 'both')")
})
