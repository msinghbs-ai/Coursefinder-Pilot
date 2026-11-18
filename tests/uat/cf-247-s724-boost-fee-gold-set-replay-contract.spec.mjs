// Guards: Fee-basis stratified gold set and replay (Platform Admin 19 Nov 2026 05:40, s724, REQ-61): strata are sized per stratum (annual fees 150 and more, whole-course totals 50 and more), the whole-course stratum takes provider and registered whole-course totals, a fee agrees only on the same basis, currency and fee year, the run stops at its spend limit (US$0.15 by default), and a field passes only with at least 100 verified answers compared, 95% agreement and no disagreement; the replay writes and qualifies nothing
// CF-247 S724. scripts/boost-fields-replay.mjs and workflow boost-fields-replay.yml. G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const S = fs.readFileSync('scripts/boost-fields-replay.mjs', 'utf8'), W = fs.readFileSync('.github/workflows/boost-fields-replay.yml', 'utf8')

test('strata are sized one by one, up to 200 each; the whole-course stratum takes registered totals too', () => {
  expect(S).toContain("const STRATA = ['intakes', 'course_fees', 'course_fees_total', 'course_description', 'application_deadlines']")
  expect(S).toContain('for (const st of STRATA) PER_OF[st] = Math.max(0, Math.min(200, PER_OF[st]))')
  expect(S).toContain("where rs <= case stratum ${STRATA.map((st) => `when ${lit(st)} then ${PER_OF[st]}`).join(' ')} else 0 end")
  expect(S).toContain("(f.fee_type in ('tuition', 'estimated_total_course_cost') and f.basis = 'registered_total_course'))) as has_total_fee")
  expect(W).toContain('intakes=60,course_fees=160,course_fees_total=60,course_description=40,application_deadlines=40')
})

test('a fee agrees only on the same basis, currency and fee year', () => {
  expect(S).toContain("if (!/^[A-Z]{3}$/.test(cur)) { bump(lane, 'gold_not_comparable'); continue }")
  expect(S).toContain('let same = p.fees.filter((g) => g.period === cls && g.currency === cur)')
  expect(S).toContain('same = yr ? same.filter((g) => Number(g.year) === yr) : same.filter((g) => (Number(g.year) || 0) === latest)')
  expect(S).toContain("if (!same.length) { bump(lane, `gold_no_${cls}_fee_same_year`); continue }")
})

test('the spend limit stops the run; the bar is 100 compared, 95% and no disagreement; nothing is written or qualified', () => {
  expect(S).toContain('MAX_COST = Math.min(1, Math.max(0.01, Number(process.argv[4]) || 0.15))')
  expect(S).toContain('if (cost >= MAX_COST) {')
  expect(S).toContain("return a + d >= 100 && a / (a + d) >= 0.95 && d === 0")
  expect(S).not.toMatch(/\b(insert into|update|delete from|drop|truncate|alter)\s+[a-z_]+\.[a-z_]+/i)
  expect(S).not.toMatch(/boost_model_qualifications|ai_route_qualifications/)
  expect(W).toContain('default: "0.15"')
  expect(W).not.toMatch(/pull_request|schedule:/)
})
