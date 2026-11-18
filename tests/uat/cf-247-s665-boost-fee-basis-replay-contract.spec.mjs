// Guards: Boost multi-field qualification replay compares like with like (Platform Admin S2-Courses directive 18 Nov 2026 21:59, item 4): an annual fee answer is scored against held annual fees and a whole-course total against held whole-course totals; another period is not compared; a basis the course holds no fee for is never a disagreement; the replay stays offline and qualifies nothing
// CF-247 S665. scripts/boost-fields-replay.mjs and .github/workflows/boost-fields-replay.yml (no worker change, no migration). G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57; the check and prompt of the fields reader are s663.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const S = fs.readFileSync('scripts/boost-fields-replay.mjs', 'utf8')
const W = fs.readFileSync('.github/workflows/boost-fields-replay.yml', 'utf8')

test('the gold query holds the fee basis: provider annual bases are "year", provider and registered whole-course totals are "total"', () => {
  expect(S).toContain("case when f.basis in ('annual', 'indicative_annual', 'current indicative annual international tuition') then 'year' else 'total' end")
  expect(S).toContain("f.fee_type = 'provider_current_tuition' and f.basis in ('annual', 'indicative_annual', 'current indicative annual international tuition', 'total_indicative')")
  expect(S).toContain("f.fee_type in ('tuition', 'estimated_total_course_cost') and f.basis = 'registered_total_course'")  // a page's "Total course cost" includes non-tuition fees
  expect(S).toContain("if (f.value?.audience === 'domestic') { bump(lane, 'gold_not_comparable'); continue }")
  expect(S).toContain("f.status = 'active'")
  expect(S).toContain("f.audience = 'international'")
  // a separate stratum draws pages of courses whose provider states a whole-course total, so the total basis is tested at all
  expect(S).toContain("('course_fees_total', g.has_total_fee)")
})

test('an answer is compared with held fees of its own basis only', () => {
  expect(S).toContain("const cls = f.value?.period === 'year' ? 'year' : f.value?.period === 'total' ? 'total' : null")
  expect(S).toContain("if (!cls) { bump(lane, 'gold_not_comparable'); continue }")
  expect(S).toContain('const same = p.fees.filter((g) => g.period === cls)')
  expect(S).toContain("if (!same.length) { bump(lane, `gold_no_${cls}_fee`); continue }")
  expect(S).toContain("bump(lane, `${cls}_${agree ? 'agree' : 'disagree'}`)")
  // the old comparison, any held amount against any answer, is gone
  expect(S).not.toContain('agree = p.fees.some(')
})

test('intakes: an answer that lists every held month and more is counted, so the intake question can be asked', () => {
  expect(S).toContain("bump(lane, 'gold_superset')")
  expect(S).toContain('the S2-Intakes question')
})

test('the report shows each basis on its own row and says what was not compared', () => {
  expect(S).toContain('**Fees by basis**')
  expect(S).toContain("'Annual (period year)'")
  expect(S).toContain("'Whole-course total'")
  expect(S).toContain('Fee answers in another period (semester, credit point, unit)')
})

test('offline: the replay writes and qualifies nothing, and runs only by hand through the Management API', () => {
  expect(S).not.toMatch(/boost_model_qualifications|boost_promote_v1|ai_route_qualifications|insert into|update catalogue|update pipeline/i)
  expect(S).toContain("'mode', 'boost_fields_replay'")
  expect(W).toMatch(/on:\s+workflow_dispatch:/)
  expect(W).toContain('node scripts/boost-fields-replay.mjs "$PER" "$LABEL"')
  expect(W).not.toMatch(/\bschedule:|\bpush:|pull_request/)
})
