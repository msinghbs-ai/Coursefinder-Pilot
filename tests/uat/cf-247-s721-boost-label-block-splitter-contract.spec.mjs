// Guards: Study load label-block splitter (Platform Admin 19 Nov 2026 05:40, s721; the open problem of s661): an unpunctuated stored block that holds both an explicit Domestic label and an explicit International label is split at its labels before any study-load rule reads it, so the International line alone decides the international study load; a block with one kind of label, lower-case mentions and closures ("not available to international students") are never split or read as a load
// CF-247 S721. Worker coverage-sweep v1.0.24 (boost.ts splitLabelBlocks; selectors study-load-windows-v6 and study-load-international-v3). The prompt boost-study-load-v5 is unchanged. G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build } from 'esbuild'

let B
test.beforeAll(async () => {
  const out = await build({ entryPoints: ['supabase/functions/coverage-sweep/boost.ts'], bundle: true, format: 'esm', write: false, logLevel: 'silent' })
  B = await import('data:text/javascript;base64,' + Buffer.from(out.outputFiles[0].text).toString('base64'))
})

// block shapes of the CDU, La Trobe and VIT pages named in s661 (stored text has no sentence punctuation between the lines)
const CDU = 'Duration Domestic 3 years full-time or part-time equivalent International 1.5 years full-time Study mode On campus'
const LATROBE = 'Study mode Domestic students: full-time or part-time International students: full-time only Location Bundoora'
const VIT = 'Domestic: Full-time and part-time International: Full-time only for student visa holders'

test('a block with both labels is split at each label; the International line stands alone', () => {
  expect(B.splitLabelBlocks(CDU)).toEqual(['Duration', 'Domestic 3 years full-time or part-time equivalent', 'International 1.5 years full-time Study mode On campus'])
  expect(B.splitLabelBlocks(LATROBE)).toEqual(['Study mode', 'Domestic students: full-time or part-time', 'International students: full-time only Location Bundoora'])
  expect(B.internationalStudySentences(CDU)).toEqual(['International 1.5 years full-time Study mode On campus'])
  expect(B.internationalStudySentences(LATROBE)).toEqual(['International students: full-time only Location Bundoora'])
  expect(B.internationalStudySentences(VIT)).toEqual(['International: Full-time only for student visa holders'])
})

test('the reader is sent the International line only, and the page check requires its load, not the whole block\'s', () => {
  const s = B.studyLoadSections(CDU, 6000)
  expect(s.selector).toBe('study-load-international-v3')
  expect(s.text).toBe('International 1.5 years full-time Study mode On campus')
  const flat = B.boostFlat(CDU)
  expect(B.verifyStudyLoad({ study_load: 'full_time', basis: 'international', quote: 'International 1.5 years full-time', reason: null }, flat, CDU).ok).toBe(true)
  const both = B.verifyStudyLoad({ study_load: 'both', basis: 'general', quote: CDU, reason: null }, flat, CDU)
  expect(both.ok).toBe(false)
  expect(both.problems).toContain('the study load is not what the quoted sentence states for international students')
  expect(B.verifyStudyLoad({ study_load: null, basis: null, quote: null, reason: 'not_stated' }, flat, CDU).ok).toBe(false)
})

test('no split without both labels; lower-case mentions and closures stay out', () => {
  const one = 'International students must study full-time.'
  expect(B.splitLabelBlocks(one)).toEqual([one])
  const lower = 'Both domestic and international students can study full-time or part-time on campus.'
  expect(B.splitLabelBlocks(lower)).toEqual([lower])
  expect(B.internationalStudySentences(lower)).toEqual([])
  const closed = 'Domestic 2 years part-time International: this program is offered part-time online and is not available to international students on a student visa'
  expect(B.internationalStudySentences(closed)).toEqual([])
  const closedNoLoad = 'Domestic 2 years part-time International: not available to international students'
  expect(B.internationalStudySentences(closedNoLoad)).toEqual([])
  expect(B.studyLoadSections(closedNoLoad, 6000).selector).toBe('study-load-windows-v6')
})

test('versions: worker v1.0.24, selectors v6 and v3, prompt unchanged', () => {
  expect(B.BOOST_SELECTOR).toBe('study-load-windows-v6')
  expect(B.BOOST_SELECTOR_INTERNATIONAL).toBe('study-load-international-v3')
  expect(B.BOOST_STUDY_LOAD_PROMPT_VERSION).toBe('boost-study-load-v5')
  expect(fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')).toContain('const WORKER = "coverage-sweep-worker-v1.0.62"')  // v1.0.38 from s1037  // v1.0.37 from s1029  // v1.0.36 from s1017  // v1.0.35 from s992  // v1.0.34 from s851
})

test('a line under the Domestic label is never an international sentence, whatever it says about visas', () => {
  const VIT2 = 'Study mode Domestic: Full-time or Part-time (only available for non-Visa students) International: Full-time on campus'
  expect(B.internationalStudySentences(VIT2)).toEqual(['International: Full-time on campus'])
  expect(B.boostSentenceInspection(VIT2).required_load).toBe('full_time')
  expect(B.verifyStudyLoad({ study_load: 'both', quote: VIT2, reason: null }, B.boostFlat(VIT2), VIT2).ok).toBe(false)
})
