// Guards: Boost study load reader, Domestic/International block splitter (Platform Admin S1-Courses directive 19 Nov 2026 05:22, item 3; from the S2-Courses live inspection of 18 Nov 2026 22:40): an unpunctuated stored block that holds both a Domestic label and an International label is split at those labels, so the International line alone decides the study load for international students (Charles Darwin University, La Trobe handbook, VIT); a block with only one label, and prose that only mentions international students, is never split.
// CF-247 S666. Worker coverage-sweep v1.0.24 (boost.ts splitAtStudentLabels; selectors study-load-windows-v6 and study-load-international-v3). No migration; prompt boost-study-load-v5 and the qualified route unchanged.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build } from 'esbuild'

const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
let B
test.beforeAll(async () => {
  const out = await build({ entryPoints: ['supabase/functions/coverage-sweep/boost.ts'], bundle: true, format: 'esm', write: false, logLevel: 'silent' })
  B = await import('data:text/javascript;base64,' + Buffer.from(out.outputFiles[0].text).toString('base64'))
})
const V = (v, q, page = q) => B.verifyStudyLoad({ study_load: v, quote: q, reason: null }, B.boostFlat(page), page)

// the shapes seen on the stored pages (one unpunctuated block each)
const CDU = 'Duration Domestic 1.5 years full-time or equivalent part-time International 1.5 years full-time Location Casuarina'
const LATROBE = 'Course length Domestic students: 3 years full-time or part-time equivalent International students: 3 years full-time Campus Bundoora'
const VIT = 'Study mode Domestic: Full-time or Part-time (only available for non-Visa students) International: Full-time on campus'
const PROSE = 'Part-time study is not available for international students on a student visa'
const ONE_LABEL = 'International students: 2 years full-time or 4 years part-time'

test('versions: worker v1.0.24, selectors v6 and v3; the prompt is unchanged', () => {
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.24"')
  expect(B.BOOST_SELECTOR).toBe('study-load-windows-v6')
  expect(B.BOOST_SELECTOR_INTERNATIONAL).toBe('study-load-international-v3')
  expect(B.BOOST_STUDY_LOAD_PROMPT_VERSION).toBe('boost-study-load-v5')
})

test('a block with both labels is split at them; one label or prose is not', () => {
  expect(B.splitAtStudentLabels(CDU)).toEqual(['Duration', 'Domestic 1.5 years full-time or equivalent part-time', 'International 1.5 years full-time Location Casuarina'])
  expect(B.splitAtStudentLabels(LATROBE)).toEqual(['Course length', 'Domestic students: 3 years full-time or part-time equivalent', 'International students: 3 years full-time Campus Bundoora'])
  expect(B.splitAtStudentLabels(VIT)).toEqual(['Study mode', 'Domestic: Full-time or Part-time (only available for non-Visa students)', 'International: Full-time on campus'])
  expect(B.splitAtStudentLabels(PROSE)).toEqual([PROSE])
  expect(B.splitAtStudentLabels(ONE_LABEL)).toEqual([ONE_LABEL])
  expect(B.splitAtStudentLabels('Domestic and international students: full-time or part-time')).toEqual(['Domestic and international students: full-time or part-time'])
})

test('the International line alone decides the load for international students', () => {
  for (const page of [CDU, LATROBE, VIT]) {
    const r = B.boostSentenceInspection(page)
    expect(r.international_sentences.map((x) => x.text).every((t) => !/domestic/i.test(t)), page).toBe(true)
    expect(r.required_load, page).toBe('full_time')
  }
  // the page check accepts full-time quoted from the whole block, and refuses "both" (the domestic line's load)
  for (const page of [CDU, LATROBE, VIT]) {
    expect(V('full_time', page).ok, page).toBe(true)
    expect(V('both', page).ok, page).toBe(false)
  }
  // only the International line is sent to the model for such a page
  const s = B.studyLoadSections(LATROBE, 1200)
  expect(s.selector).toBe('study-load-international-v3')
  expect(s.text).toBe('International students: 3 years full-time Campus Bundoora')
})

test('unchanged: a single labelled line, a closure sentence and a page with no international line', () => {
  expect(B.boostSentenceInspection(ONE_LABEL).required_load).toBe('both')
  expect(B.splitAtStudentLabels(PROSE)).toHaveLength(1)
  const general = 'Duration 3 years full-time or 6 years part-time'
  expect(B.boostSentenceInspection(general).international_total).toBe(0)
  expect(V('both', general).ok).toBe(true)
})
