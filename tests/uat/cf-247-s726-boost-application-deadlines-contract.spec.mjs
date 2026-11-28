// Guards: Application deadline field (Platform Admin 19 Nov 2026 05:40, s726, REQ-70): the multi-field prompt asks for application deadlines with the intake each belongs to; a deadline is verified only where the quote gives that day and month (and the answer's year) as the last day to apply next to a deadline word, never a census, orientation, fee or start date, and an intake named with it must be in the quote; live reading asks the field only where the lanes setting names it
// CF-247 S726. Worker coverage-sweep (boost-fields.ts prompt boost-fields-v2, page check boost-fields-check-v3) and scripts/boost-fields-replay.mjs. G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build } from 'esbuild'

let F, B
test.beforeAll(async () => {
  const load = async (f) => { const out = await build({ entryPoints: [f], bundle: true, format: 'esm', write: false, logLevel: 'silent' }); return import('data:text/javascript;base64,' + Buffer.from(out.outputFiles[0].text).toString('base64')) }
  F = await load('supabase/functions/coverage-sweep/boost-fields.ts'); B = await load('supabase/functions/coverage-sweep/boost.ts')
})
const page = 'Intakes: March, July and November. Applications for the July 2026 intake close on 30 May 2026. Census date 31 March. Orientation 20 July. Apply by 15 January for March.'
const check = (a) => F.verifyBoostField('application_deadlines', a, B.boostFlat(page), page)

test('the prompt asks for deadlines with their intake; the lane is known and the check is versioned', () => {
  expect(F.BOOST_FIELD_LANES).toContain('application_deadlines')
  expect(F.BOOST_FIELDS_CHECK_VERSION).toBe('boost-fields-check-v3')
  expect(F.BOOST_FIELDS_SYSTEM).toContain('- application_deadlines: {"deadlines": [{"date": "YYYY-MM-DD"')
  expect(F.BOOST_FIELDS_SYSTEM).toContain('Never a census, orientation, fee payment or start date.')
})

test('a deadline stated as the last day to apply, with its intake, is verified', () => {
  expect(check({ deadlines: [{ date: '2026-05-30', intake: 'July 2026' }], quote: 'Applications for the July 2026 intake close on 30 May 2026.' }).status).toBe('verified')
  expect(check({ deadlines: [{ date: '01-15', intake: 'March' }], quote: 'Apply by 15 January for March.' }).status).toBe('verified')
})

test('census, orientation, a wrong intake, a missing year or a date not in the quote are refused', () => {
  const census = check({ deadlines: [{ date: '03-31', intake: null }], quote: 'Census date 31 March.' })
  expect(census.status).toBe('rejected')
  expect(census.problems).toContain('03-31 is a census, orientation, fee or start date, not a deadline')
  expect(check({ deadlines: [{ date: '07-20', intake: null }], quote: 'Orientation 20 July.' }).status).toBe('rejected')
  expect(check({ deadlines: [{ date: '2026-05-30', intake: 'February 2027' }], quote: 'Applications for the July 2026 intake close on 30 May 2026.' }).problems).toContain('the intake "February 2027" is not in the quote')
  expect(check({ deadlines: [{ date: '2027-01-15', intake: null }], quote: 'Apply by 15 January for March.' }).problems).toContain('the year 2027 is not in the quote')
  expect(check({ deadlines: [{ date: '2026-06-30', intake: null }], quote: 'Applications for the July 2026 intake close on 30 May 2026.' }).problems).toContain('2026-06-30 is not in the quote')
})

test('the replay compares deadlines with held course intake deadlines', () => {
  const S = fs.readFileSync('scripts/boost-fields-replay.mjs', 'utf8')
  expect(S).toContain("to_char(i.application_deadline, 'YYYY-MM-DD')) from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active' and i.application_deadline is not null) as deadlines")
  expect(S).toContain("agree = ans.length > 0 && ans.every((d) => held.some((h) => d.length === 10 ? h === d : h.slice(5) === d))")
})

test('the worker that carries the v2 prompt is v1.0.25', () => {
  expect(fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')).toContain('const WORKER = "coverage-sweep-worker-v1.0.64"')  // v1.0.38 from s1037  // v1.0.37 from s1029  // v1.0.36 from s1017  // v1.0.35 from s992  // v1.0.34 from s851
})
