// Guards: Boost study load, the international study load first (Platform Admin 18 Nov 2026 07:08, decisions 1 and 5): the study load a page states for international students is reported and checked ahead of the general one; a general definition of full-time study is refused; Boost no longer skips for a running dispatcher tick unless setting boost.yield_to_dispatchers is 1; the change qualifies no model and admits nothing
// CF-247 S601 (was s597; renumbered 18 Nov 2026). Migration 20261118074500_cf247_boost_international_first, worker coverage-sweep v1.0.12 (boost.ts; the prompt is boost-study-load-v3 from v1.0.13, s602). G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build } from 'esbuild'

const M = fs.readFileSync('supabase/migrations-archive/20261118074500_cf247_boost_international_first.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
let B
test.beforeAll(async () => {
  const out = await build({ entryPoints: ['supabase/functions/coverage-sweep/boost.ts'], bundle: true, format: 'esm', write: false, logLevel: 'silent' })
  B = await import('data:text/javascript;base64,' + Buffer.from(out.outputFiles[0].text).toString('base64'))
})

test('migration: the gate yields to dispatcher ticks only by its setting, earlier readings are given back, nothing is qualified or admitted', () => {
  expect(code).toContain("if v <> 'fdcd9973d9029a80479ac0ec71384755' then raise exception")   // replaces the definition it read live
  expect(code).toMatch(/\('pipeline', 'boost\.yield_to_dispatchers', [^\n]+\n[^\n]+\n\s+'number', to_jsonb\(0\), 0, 1, 'switch'/)
  expect(code).toMatch(/\('pipeline', 'reading\.boost_extract_parallel', [^\n]+\n[^\n]+\n\s+'number', to_jsonb\(4\), 1, 8, 'pages'/)
  expect(code).toContain("if p_check_locks and security.pipeline_num_v1('boost.yield_to_dispatchers', 0) >= 1 then")
  // the other holds of the gate are kept
  for (const hold of ["'switched off (boost.ingest_on)'", "'Pipeline Maintenance Mode'", "'blackout (migration squash)'", "'housekeeping-daily running or just started'"]) expect(code).toContain(hold)
  expect(code).toContain("update pipeline.boost_extract_items set state = 'released', note = 'read again under boost-study-load-v2 (worker v1.0.12, international study load first)', done_at = now()")
  expect(code).toContain("('boost.benchmark_label', to_jsonb('bench-2'::text),")
  // the idle check may have paused boost-extract; the migration gives it work and switches it on, and does not require the other Boost jobs to be on
  expect(code).toContain("select cron.alter_job((select jobid from cron.job where jobname = 'boost-extract'), active := true)")
  expect(code).not.toContain('not active or command')
  expect(code).not.toMatch(/insert into pipeline\.boost_model_qualifications|boost_promote_v1\(|update catalogue\.|insert into catalogue\./)
  expect(code.replace(/on commit drop/g, '')).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
  expect(code).toContain("raise exception 'post-check: a model is qualified for admission; this migration qualifies none'")
  expect(code).toContain("raise exception 'post-check: a Boost gate is open inside the squash lock (Thu 01:15 to 03:30)'")
})

test('worker v1.0.12: the page check is given the whole page, and a run reads a few pages at a time by its setting', () => {
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.15"')
  expect(IX).toContain('const v = verifyStudyLoad(ra.a, boostFlat(page), page);')
  expect(IX).toContain('const v = verifyStudyLoad(ra.a, pageFlat, page);')
  expect(IX).toContain('const par = boostParallel(ws); for (let i = 0; i < items.length; i += par) await Promise.all(items.slice(i, i + par).map(readOne));')
  expect(B.boostParallel({})).toBe(4)
  expect(B.boostParallel({ 'reading.boost_extract_parallel': 2 })).toBe(2)
  expect(B.boostParallel({ 'reading.boost_extract_parallel': 50 })).toBe(8)
  expect(B.BOOST_STUDY_LOAD_PROMPT_VERSION).toBe('boost-study-load-v4')  // v4 from worker v1.0.14 (s614)
  expect(B.BOOST_SELECTOR).toBe('study-load-windows-v3')
  expect(B.BOOST_STUDY_LOAD_SYSTEM).toContain('International students first')
  expect(B.BOOST_STUDY_LOAD_SYSTEM).toContain('"basis": "international" | "general" | null')
})

test('boost.ts: the study load stated for international students is preferred, and must be the one the answer rests on', () => {
  const V = (a, page) => B.verifyStudyLoad(a, B.boostFlat(page), page)
  const visa = 'Only a full-time study option is available to international students on a Student visa.'
  const p1 = `About the course.\n${visa}\nDuration: 3 years full-time or part-time equivalent.`
  expect(B.internationalStudySentences(p1)).toEqual([visa])
  expect(V({ study_load: 'full_time', basis: 'international', quote: visa, reason: null }, p1).ok).toBe(true)
  expect(V({ study_load: 'both', basis: 'general', quote: 'Duration: 3 years full-time or part-time equivalent.', reason: null }, p1).problems).toEqual(['the page states a study load for international students; the answer does not use it'])
  expect(V({ study_load: null, basis: null, quote: null, reason: 'not_stated' }, p1).problems).toEqual(['the page states a study load for international students; the answer says not stated'])
  // one sentence for both audiences: the value is the one stated for international students
  const p2 = 'Domestic students: 6 study periods (2 years full-time) or part-time equivalent. International students: 9 Study Periods (3 years) full-time.'
  expect(V({ study_load: 'full_time', basis: 'international', quote: p2, reason: null }, p2).ok).toBe(true)
  expect(V({ study_load: 'both', basis: 'international', quote: p2, reason: null }, p2).problems).toEqual(['the study load is not what the quoted sentence states for international students'])
  // no international statement: the general study load, and an international basis needs a sentence about international students
  const p3 = 'Duration: 3 Study Periods (1 year) full-time, or equivalent part-time. Delivered on campus.'
  expect(B.internationalStudySentences(p3)).toEqual([])
  expect(V({ study_load: 'both', basis: 'general', quote: '3 Study Periods (1 year) full-time, or equivalent part-time', reason: null }, p3).ok).toBe(true)
  expect(V({ study_load: 'both', basis: 'international', quote: '3 Study Periods (1 year) full-time, or equivalent part-time', reason: null }, p3)).toMatchObject({ ok: true, basis: 'general' })   // v1.0.13: the basis is read from the quote, not from the model's label
  const p7 = 'International students must study full-time. Domestic students may study full-time or part-time.'
  expect(V({ study_load: 'full_time', basis: 'international', quote: 'International students must study full-time.', reason: null }, p7).ok).toBe(true)
  expect(V({ study_load: 'both', basis: 'general', quote: 'Domestic students may study full-time or part-time.', reason: null }, p7).ok).toBe(false)
})

test('boost.ts: a general definition of full-time study is not a study load, and a load named only as not offered is not counted', () => {
  const V = (a, page) => B.verifyStudyLoad(a, B.boostFlat(page), page)
  const p4 = 'As a full-time student, you can expect to commit around 48 hours of study per week. Duration 4 years (full time).'
  expect(V({ study_load: 'full_time', basis: 'general', quote: 'As a full-time student, you can expect to commit around 48 hours of study per week.', reason: null }, p4).problems).toEqual(["the quote defines full-time or part-time study in general; it does not state the course's study load"])
  expect(V({ study_load: 'full_time', basis: 'general', quote: 'Duration 4 years (full time).', reason: null }, p4).ok).toBe(true)
  const p5 = 'This course is offered full-time only. Part-time study is not available.'
  expect(V({ study_load: 'full_time', basis: 'general', quote: p5, reason: null }, p5).ok).toBe(true)
  expect(V({ study_load: 'both', basis: 'general', quote: p5, reason: null }, p5).ok).toBe(false)
  const p6 = 'Study mode: full-time (not available part-time).'
  expect(V({ study_load: 'full_time', basis: 'general', quote: p6, reason: null }, p6).ok).toBe(true)
})
