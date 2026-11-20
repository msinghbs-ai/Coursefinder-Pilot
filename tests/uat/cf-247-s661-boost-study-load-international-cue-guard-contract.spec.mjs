// Guards: Boost study load reader, international cue guard (Platform Admin S2-Courses directive 18 Nov 2026 21:59, item 1): a course closed to international students is never read as a study load rule, nothing is inferred from "not available to international students", and an international statement needs its international and study words within 80 characters or a labelled "International ..." line; the prompt and the model route are unchanged
// CF-247 S661. Worker coverage-sweep v1.0.22 (boost.ts selectors study-load-windows-v5 and study-load-international-v2). No migration. The sentences are those matched on the 41 stored pages settled "Not stated" (findings 18 Nov 2026). G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build } from 'esbuild'

const BX = fs.readFileSync('supabase/functions/coverage-sweep/boost.ts', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
let B
test.beforeAll(async () => {
  const out = await build({ entryPoints: ['supabase/functions/coverage-sweep/boost.ts'], bundle: true, format: 'esm', write: false, logLevel: 'silent' })
  B = await import('data:text/javascript;base64,' + Buffer.from(out.outputFiles[0].text).toString('base64'))
})
const V = (v, q, page = q) => B.verifyStudyLoad({ study_load: v, quote: q, reason: null }, B.boostFlat(page), page)

// live matches of 18 Nov 2026
const GRIFFITH_CLOSED = 'This program is offered part-time online and is not available to international students on a student visa'
const TRI3 = 'Trimester 3 is part-time only and is not available to commencing International students studying in Australia on a student visa.'
const DARWIN_LIST = 'You may be interested in Bachelor of Education Full-time Not available to international students Bachelor of Arts Part-time Not available to international students'
const DARWIN_TABLE = 'International 1.5 years full-time'

test('versions: the reader is v6 by selector; the prompt and the route are unchanged', () => {
  expect(B.BOOST_SELECTOR).toBe('study-load-windows-v6')  // v6 from s721
  expect(B.BOOST_SELECTOR_INTERNATIONAL).toBe('study-load-international-v3')  // v3 from s721
  expect(B.BOOST_STUDY_LOAD_PROMPT_VERSION).toBe('boost-study-load-v5')  // the route qualification is tied to the prompt version (a migration), so the prompt text stays
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.33"')  // v1.0.25 from s721
  expect(BX).toMatch(/const INTL_NEAR = 80;\s+\/\/ fixed: /)
  expect(BX).toMatch(/const INTL_LABEL_NEAR = 160;\s+\/\/ fixed: /)
  expect(BX).toMatch(/const LOAD_SUBJECT_GAP = 40;\s+\/\/ fixed: /)
})

test('a course closed to international students is not a study load rule, and nothing is inferred from it', () => {
  for (const x of [GRIFFITH_CLOSED, TRI3, DARWIN_LIST]) {
    expect(B.internationalClosure(x), x).toBe(true)
    expect(B.internationalStudySentences(x), x).toEqual([])
  }
  // the reader inferred full-time from the Griffith sentence; the page check now refuses it as an international statement
  expect(V('full_time', GRIFFITH_CLOSED).basis).not.toBe('international')
  expect(V('full_time', GRIFFITH_CLOSED).ok).toBe(false)
  // and a page holding only such a sentence is asked about as any other page (no international selector)
  expect(B.studyLoadSections(`Bachelor of Arts. ${GRIFFITH_CLOSED}.`, 6000).selector).not.toBe('study-load-international-v3')  // v3 from s721
  expect(B.boostSentenceInspection(`Bachelor of Arts. ${TRI3}`).international_total).toBe(0)
})

test('a load that is itself ruled out for international students still states the other load', () => {
  const yes = ['Part-time study is not available to international students on a student visa.', 'No. Part-time study is currently not available for international students due to visa conditions.',
    'Part-time equivalent study options are not available for international students.', 'Note: Part-time is not available for international students.']
  for (const x of yes) {
    expect(B.internationalClosure(x), x).toBe(false)
    expect(B.internationalStudySentences(x).length, x).toBe(1)
    expect(V('full_time', x), x).toMatchObject({ ok: true, basis: 'international' })
    expect(V('part_time', x).ok, x).toBe(false)
  }
})

test('proximity: the international word and the study word lie within 80 characters, or the line is labelled', () => {
  const near = 'Student Visa holders must study internally full time.'
  expect(B.internationalNear(near)).toBe(true)
  const far = `International students must provide IELTS. ${'Entry requirements are listed for each pathway and every intake across all campuses of the provider. '.repeat(2)}Applicants may study full-time.`
  expect(B.internationalNear(far)).toBe(false)
  expect(B.internationalStudySentences(far)).toEqual([])
  // a block with no sentence punctuation: IELTS procedure, then navigation, then a duration line (Griffith, ACAP)
  const block = 'International applicants must meet the IELTS requirement before an offer is made see the English language proficiency table for each course and the alternative evidence accepted by the university Duration 3 years full-time'
  expect(B.internationalStudySentences(block)).toEqual([])
  // labelled lines count
  for (const x of ['International students: full-time', 'International onshore Study mode: Full time', 'International students - 1.5 years full-time on campus']) {
    expect(B.internationalNear(x), x).toBe(true)
  }
  expect(B.internationalNear(DARWIN_TABLE)).toBe(true)
  // exactly at the width
  const at = (gap) => `international students${' '.repeat(gap)}full-time`
  expect(B.internationalNear(at(80))).toBe(true)
  expect(B.internationalNear(at(81))).toBe(false)
})

test('live false matches of the first inspection (18 Nov 2026 22:25): a CRICOS code, a course title or a far label is not an international statement', () => {
  const no = ['1 year full-time, or part-time equivalent Starts SMAH Annual 2026 Codes CRICOS: 012095M UOW: 862 Overview This one-year degree is designed for students who must have completed a Bachelor of Nursing',
    'Short courses International Exchange - One Sem 0.5 year/s full-time Not available to domestic students.',
    'Master of Business Administration (International) 2 years full-time and you must hold an AQF level 7 degree',
    'Master of Applied Human Performance Science Status Not available in 2027 CRICOS code 073570 Attendance Full-time only']
  for (const x of no) expect(B.internationalStudySentences(x), x).toEqual([])
  // a label counts only with its study word close after it
  const far = `International - Academic and English Requirements ${'You must meet the entry requirements set out for every pathway and intake of the provider. '.repeat(3)}at least one year of full-time studies`
  expect(B.internationalNear(far)).toBe(false)
  // what names the student still counts
  for (const x of ['Note: International students studying in Australia on a student visa may only take this course in on-campus mode full time.', 'Student Visa holders must study internally full time.', 'International onshore Study mode: Full time']) expect(B.internationalNear(x), x).toBe(true)
})

test('earlier rules are unchanged: fee, work and definition lines are still not a load; a general statement still passes', () => {
  for (const x of ['Most students studying full time at Deakin need a Student Visa (Subclass 500).', 'This is an indicative fee for one year of full-time study for international students.',
    'On a Student Visa (Subclass 500), you can work up to 48 hours per fortnight during trimesters while studying full-time.']) expect(B.internationalStudySentences(x), x).toEqual([])
  expect(V('full_time', 'Student Visa holders must study internally full time').ok).toBe(true)
  expect(V('both', 'Duration: 2 years full-time, 4 years part-time').basis).toBe('general')
  expect(V('full_time', 'Only a full-time study option is available to international students on a Student visa.')).toMatchObject({ ok: true, basis: 'international' })
})

test('the sentence inspection (s660) reports the same cue the reader and the page check use', () => {
  const r = B.boostSentenceInspection(`Overview. ${GRIFFITH_CLOSED}. Student Visa holders must study internally full time.`)
  expect(r.international_sentences.map((x) => x.text)).toEqual(['Student Visa holders must study internally full time.'])
  expect(r.required_load).toBe('full_time')
  expect(r.selector).toBe('study-load-international-v3')  // v3 from s721
})

test('no migration: the lane writes no database object, and the model prompt text is untouched', () => {
  const files = fs.readdirSync('supabase/migrations').filter((f) => /s661|study_load_v6|study-load-v6/.test(f))
  expect(files).toEqual([])
  expect(B.BOOST_STUDY_LOAD_SYSTEM).toContain('International students first')
  expect(B.BOOST_STUDY_LOAD_SYSTEM).not.toContain('not available to international')
})
