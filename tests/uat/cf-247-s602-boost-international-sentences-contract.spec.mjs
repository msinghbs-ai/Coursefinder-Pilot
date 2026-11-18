// Guards: Boost study load, the international study load first (Platform Admin 18 Nov 2026 07:08, decision 1): a page that states a study load for international students is asked about those sentences only, and the page check reads the basis from the quote, not from the model's label; the change qualifies no model and admits nothing
// CF-247 S602. Migration 20261118083000_cf247_boost_international_sentences, worker coverage-sweep v1.0.13 (boost.ts prompt boost-study-load-v3, selector study-load-international-v1). G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build } from 'esbuild'

const M = fs.readFileSync('supabase/migrations/20261118083000_cf247_boost_international_sentences.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
let B
test.beforeAll(async () => {
  const out = await build({ entryPoints: ['supabase/functions/coverage-sweep/boost.ts'], bundle: true, format: 'esm', write: false, logLevel: 'silent' })
  B = await import('data:text/javascript;base64,' + Buffer.from(out.outputFiles[0].text).toString('base64'))
})

test('migration: only the refused readings are given back; nothing is qualified or admitted', () => {
  expect(code).toContain("update pipeline.boost_extract_items set state = 'released', note = 'refused under boost-study-load-v2; read again by worker v1.0.13', done_at = now()\n where state in ('rejected', 'failed');")
  expect(code).toContain("set prompt_version = 'boost-study-load-v3'")
  expect(code).toContain("set value = to_jsonb('bench-3'::text)")
  expect(code).not.toMatch(/insert into pipeline\.boost_model_qualifications|boost_promote_v1\(|update catalogue\.|insert into catalogue\.|create or replace function/)
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
  expect(code).toContain("raise exception 'post-check: a model is qualified for admission; this migration qualifies none'")
})

test('boost.ts v1.0.13: a page with a statement for international students is asked about that statement only', () => {
  const visa = 'International student visa holders can only study full-time.'
  const page = `Bachelor of X.\nDuration: 3 years full-time or 6 years part-time.\n${visa}\nApply now.`
  const s = B.studyLoadSections(page, 6000)
  expect(s).toMatchObject({ selector: 'study-load-international-v1', text: visa, hits: 3 })
  expect(B.BOOST_SELECTOR_INTERNATIONAL).toBe('study-load-international-v1')
  expect(B.studyLoadSections(page, 20).text.length).toBeLessThanOrEqual(20)
  // a page with no such statement is read as before
  expect(B.studyLoadSections('Duration: 3 years full-time or 6 years part-time.', 6000).selector).toBe('study-load-windows-v4')  // v4 from worker v1.0.17 (s643)
  expect(B.BOOST_STUDY_LOAD_PROMPT_VERSION).toBe('boost-study-load-v5')  // v4 from worker v1.0.14 (s614); v5 from v1.0.17 (s643)
  expect(B.BOOST_STUDY_LOAD_SYSTEM).toContain('When the text you are given is only sentences about international students, answer from those sentences.')
})

test('boost.ts v1.0.13: the basis is what the quote shows, whatever the model called it', () => {
  const V = (a, page) => B.verifyStudyLoad(a, B.boostFlat(page), page)
  const visa = 'International student visa holders can only study full-time.'
  const page = `Duration: 3 years full-time or 6 years part-time.\n${visa}`
  expect(V({ study_load: 'full_time', basis: 'general', quote: visa, reason: null }, page)).toMatchObject({ ok: true, basis: 'international' })
  expect(V({ study_load: 'full_time', quote: visa, reason: null }, page)).toMatchObject({ ok: true, basis: 'international' })
  expect(V({ study_load: 'both', basis: 'international', quote: visa, reason: null }, page).problems).toEqual(['the study load is not what the quoted sentence states for international students'])
  expect(V({ study_load: 'both', basis: 'international', quote: 'Duration: 3 years full-time or 6 years part-time.', reason: null }, page).problems).toEqual(['the page states a study load for international students; the answer does not use it'])
  const general = 'Duration: 3 years full-time or 6 years part-time.'
  expect(V({ study_load: 'both', basis: 'international', quote: general, reason: null }, general)).toMatchObject({ ok: true, basis: 'general' })
  expect(V({ study_load: 'full_time', basis: 'general', quote: general, reason: null }, general).ok).toBe(false)
})
