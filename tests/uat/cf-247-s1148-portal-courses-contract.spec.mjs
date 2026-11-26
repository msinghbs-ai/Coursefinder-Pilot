// Guards: StudySearch Portal lane (Platform Admin 25 Nov 2026 16:44, S1-API-Frontend-Delivery): the Courses screen follows the agreed portal_course_search_v1 contract, never invents a value, never relaxes a filter by itself, and says plainly when the search is not live yet (G2: relaxation numbers belong to the function's settings).; amended by s1222 (Atlas brief 26 Nov 2026 15:59 AEDT, portal UAT fixes: concise cards, drawer, pinned student countries)
// CF-247 S1148. The function is S1-Build's; this screen is built to the contract in the portal design document and does not wait for it.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { toApiError } from '../../portal/src/lib/apiErrors.js'

const read = (p) => fs.readFileSync(p, 'utf8')
const courses = read('portal/src/screens/Courses.jsx')

test('it calls the agreed function with the agreed arguments', () => {
  expect(courses).toContain("const FN = 'portal_course_search_v1'")
  expect(courses).toMatch(/rpc\(FN, \{ p_args: \{ q, countries: studyIn \? \[studyIn\] : \[\], provider_id: provider \|\| null, removed: drop, relax \} \}\)/)
})

test('a function that is not live yet gives a calm message, not an error screen', () => {
  const e = toApiError({ code: 'PGRST202', message: 'Could not find the function public.portal_course_search_v1(p_args) in the schema cache' })
  expect(e.kind).toBe('missing')
  expect(courses).toMatch(/e\.kind === 'missing'/)
  expect(courses).toMatch(/Course search is not switched on yet/)
  expect(courses).toMatch(/nothing has been searched/)
})

test('the "Understood as" chips can be removed, topic words are badged, and nothing relaxes without a click', () => {
  expect(courses).toMatch(/Understood as/)
  expect(courses).toMatch(/aria-label=\{`Remove \$\{c\.label\}`\}/)
  expect(courses).toMatch(/c\.kind === 'topic'/)
  expect(courses).toMatch(/Topic match/)
  expect(courses).toMatch(/Nothing changes until you choose/)
  expect(courses).toMatch(/onClick=\{\(\) => applyRelax\(r\)\}/)
  expect(courses).toMatch(/Not exact matches/)
  expect(courses).toMatch(/0 courses match every filter/)
})

test('a value the function leaves out is not shown on the card (s1222: "Not recorded" is said in Course details), and no budget rule is written into the screen', () => {
  expect(courses).toMatch(/fee: primaryFeeAmount\(c\.fee\)/)
  expect(courses).toMatch(/lengthOrBlank\(c\.duration_value, c\.duration_unit\)/)
  expect(courses).not.toContain('NOT_RECORDED')
  expect(courses).not.toMatch(/1\.05|\b1000\b|Math\.ceil/)
  expect(courses).not.toMatch(/topic_score\s*[<>]=?\s*0\.\d/)
})

test('the near-miss list names what each course misses and a course card has no data of its own', () => {
  expect(courses).toMatch(/n\.misses/)
  expect(courses).toMatch(/miss_text/)
  expect(courses).not.toMatch(/\.from\(/)
})
