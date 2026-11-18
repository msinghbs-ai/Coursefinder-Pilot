// Guards: Boost study load, the international study load first (Platform Admin 18 Nov 2026 07:08, decision 1): only a sentence that states a rule about how international students may study counts as their study load; fee, tuition, work-rights and experience lines never do; a load offered only to others is not counted; every earlier reading is read again; the change qualifies no model and admits nothing
// CF-247 S614. Migration 20261118093000_cf247_boost_international_rule_sentences, worker coverage-sweep v1.0.14 (boost.ts prompt boost-study-load-v4). The sentences below are taken from live readings of 18 Nov 2026. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build } from 'esbuild'

const M = fs.readFileSync('supabase/migrations/20261118093000_cf247_boost_international_rule_sentences.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
let B
test.beforeAll(async () => {
  const out = await build({ entryPoints: ['supabase/functions/coverage-sweep/boost.ts'], bundle: true, format: 'esm', write: false, logLevel: 'silent' })
  B = await import('data:text/javascript;base64,' + Buffer.from(out.outputFiles[0].text).toString('base64'))
})

test('migration: every earlier reading is given back; nothing is qualified or admitted', () => {
  expect(code).toContain("update pipeline.boost_extract_items set state = 'released', note = 'read again by worker v1.0.14 (prompt boost-study-load-v4)', done_at = now()\n where state in ('verified', 'rejected', 'failed');")
  expect(code).toContain("set prompt_version = 'boost-study-load-v4'")
  expect(code).toContain("set value = to_jsonb('bench-4'::text)")
  expect(code).not.toMatch(/insert into pipeline\.boost_model_qualifications|boost_promote_v1\(|update catalogue\.|insert into catalogue\.|create or replace function/)
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.23"')  // v1.0.19 from s674
  expect(B.BOOST_STUDY_LOAD_PROMPT_VERSION).toBe('boost-study-load-v5')  // v5 from worker v1.0.17 (s647)
})

test('boost.ts v1.0.14: fee, work-rights and general lines are not a study load for international students', () => {
  const notIntl = ['Most students studying full time at Deakin need a Student Visa (Subclass 500).', 'As an international student at Deakin, you can work part time according to the conditions of your visa.',
 'This is an indicative fee for one year of full-time study for international students.', 'Fees are per 48 credit points which represents a standard full-time course load for a year.',
 'The indicative annual tuition fee is calculated based on a standard full-time study load which is usually 80 credit points.', 'This is full-time face-to-face classroom based course for International Students.',
 'This course is one of a select number of courses offered online at a reduced annual fee for international students studying from outside Australia.', 'On a Student Visa (Subclass 500), you can work up to 48 hours per fortnight during trimesters while studying full-time.']
  for (const x of notIntl) expect(B.internationalStudySentences(x), x).toEqual([])
})

test('boost.ts v1.0.14: a stated rule for international students is one, and gives the load it states', () => {
  const V = (v, q, page = q) => B.verifyStudyLoad({ study_load: v, quote: q, reason: null }, B.boostFlat(page), page)
  const yes = [['full_time','Note: International students who hold a student visa can only choose the full-time study option for our courses.'], ['full_time','International student visa holders can only study full-time.'],
 ['full_time','No. Part-time study is currently not available for international students due to visa conditions.'], ['full_time','Part-time equivalent study options are not available for international students.'],
 ['full_time','Please note that RPL cannot result in an international student having less than a full time load of study (20 hours per week).'], ['full_time','The recommended study load for international students is full-time.'],
 ['full_time','If you are an international student you must always be full-time.'], ['full_time','Student Visa holders must study internally full time'], ['full_time','International students must maintain a full-time study load.'],
 ['full_time','Only a full-time study option is available to international students on a Student visa.'], ['full_time','Note: Part-time is not available for international students.']]
  for (const [v, x] of yes) {
    expect(B.internationalStudySentences(x).length, x).toBe(1)
    expect(V(v, x), x).toMatchObject({ ok: true, basis: 'international' })
    expect(V('both', x).ok, x).toBe(false)
  }
})

test('boost.ts v1.0.14: a general statement passes when the page has no such rule, even beside fee and visa notes', () => {
  const V = (v, q, page = q) => B.verifyStudyLoad({ study_load: v, quote: q, reason: null }, B.boostFlat(page), page)
  const gen = [['full_time','Duration 4 years (full time)'], ['both','Duration: 2 years full-time, 4 years part-time'], ['both','Availability: Full-time Part-time'], ['both','This course is available to study as both part-time or full-time'],
 ['both','Duration 3 years full-time, or part-time equivalent'], ['full_time','Study Load: Full-time. Part-time available for domestic students'], ['full_time','This course is available to study only on a full-time basis'],
 ['both','Over two years full-time (part-time available)'], ['both','This program is offered on-campus full-time or part-time.']]
  for (const [v, x] of gen) expect(V(v, x), x).toMatchObject({ ok: true, basis: 'general' })
  expect(V('full_time', 'Duration 3 years full-time, or part-time equivalent').ok).toBe(false)
  const page = 'Duration 4 years (full time)\nFees are per 48 credit points which represents a standard full-time course load for a year.\nMost students studying full time at Deakin need a Student Visa (Subclass 500).'
  expect(V('full_time', 'Duration 4 years (full time)', page).ok).toBe(true)
  expect(V('full_time', 'Fees are per 48 credit points which represents a standard full-time course load for a year.', page).ok).toBe(false)
  const nv = 'Duration: 1 year, full-time or part-time study (only available for non-Visa students).'
  expect(V('full_time', nv)).toMatchObject({ ok: true, basis: 'international' })
  expect(V('full_time', 'Study mode: full-time (not available part-time).').ok).toBe(true)
})
