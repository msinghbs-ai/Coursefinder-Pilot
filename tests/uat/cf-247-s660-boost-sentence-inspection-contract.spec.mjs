// Guards: Boost learnings are inspected before they are promoted (Platform Admin 18 Nov 2026 17:02 item 1): the read-only worker mode boost_sentences returns, for stored course pages named by their storage path, the sentences the study load reader takes as a statement for international students and the load the page check requires for each; it calls no model, fetches no web page and writes nothing.
// CF-247 S660. Worker coverage-sweep v1.0.18 (boost.ts boostSentenceInspection, index.ts mode boost_sentences), script scripts/boost-sentences-inspect.mjs and workflow boost-sentences-inspect.yml. No migration. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build } from 'esbuild'

const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const mode = IX.slice(IX.indexOf('if (mode === "boost_sentences") {'), IX.indexOf('if (mode === "boost_fields_replay") {'))
let B
test.beforeAll(async () => {
  const out = await build({ entryPoints: ['supabase/functions/coverage-sweep/boost.ts'], bundle: true, format: 'esm', write: false, logLevel: 'silent' })
  B = await import('data:text/javascript;base64,' + Buffer.from(out.outputFiles[0].text).toString('base64'))
})

// sentences quoted in live readings of 18 Nov 2026
const T3 = 'Trimester 3 is part-time only and is not available to commencing International students studying in Australia on a student visa.'
const VISA = 'Student Visa holders must study internally full time.'
const FEE = 'Your student contribution amount is based on a standard full-time load of 48 credit points (1.0 EFTSL).'

test('the inspection returns each sentence for international students with the load the page check requires for it', () => {
  const page = `This program is offered full-time on campus in Trimester 1 and Trimester 2. ${T3} Duration 2 years full-time.`
  const r = B.boostSentenceInspection(page)
  expect(r.page_chars).toBe(page.length)
  expect(r.study_word_hits).toBe(3)
  expect(r.selector).toBe('study-load-international-v1')
  expect(r.international_total).toBe(1)
  expect(r.international_sentences[0].text).toBe(T3)
  expect(r.international_sentences[0].load).toBe('full_time')
  expect(r.international_sentences[0].offers.ruledOut).toEqual({ full: false, part: true })
  expect(r.required_load).toBe('full_time')
  const v = B.boostSentenceInspection(`Overview. ${VISA} ${FEE}`)
  expect(v.international_sentences.map((x) => x.text)).toEqual([VISA])
  expect(v.required_load).toBe('full_time')
})

test('a page with no such sentence returns none, and what it returns is what the reader and the page check use', () => {
  const page = `Course overview. This degree is offered full-time or part-time on campus. ${FEE}`
  const r = B.boostSentenceInspection(page)
  expect(r.international_sentences).toEqual([])
  expect(r.international_total).toBe(0)
  expect(r.required_load).toBeNull()
  expect(r.selector).toBe(B.studyLoadSections(page, 6000).selector)
  expect(B.boostSentenceInspection('No study words here.').selector).toBe('no_signal')
  // the same sentences the page check holds an answer to
  const both = `${VISA} This course is available part-time.`
  expect(B.boostSentenceInspection(both).international_sentences.map((x) => x.text)).toEqual(B.internationalStudySentences(both))
  expect(B.verifyStudyLoad({ study_load: 'full_time', basis: 'international', quote: VISA, reason: null }, B.boostFlat(both), both).ok).toBe(true)
})

test('the size of what one call returns is capped', () => {
  const many = Array.from({ length: 20 }, (_, i) => `International students in stream ${i} must study full-time.`).join(' ')
  const r = B.boostSentenceInspection(many)
  expect(r.international_total).toBe(20)
  expect(r.international_sentences.length).toBe(12)
  const long = `International students must study full-time ${'and attend every scheduled class on campus '.repeat(40)}.`
  expect(B.boostSentenceInspection(long).international_sentences[0].text.length).toBe(600)
  expect(B.boostSentenceInspection(long).international_sentences[0].chars).toBe(long.length)
  expect(B.BOOST_INSPECT_MAX_PAGES).toBe(60)
})

test('the worker mode is read only: stored pages by path, no model, no web fetch, no database call, no file written', () => {
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.18"')
  expect(mode.length).toBeGreaterThan(200)
  expect(mode).toContain('.slice(0, BOOST_INSPECT_MAX_PAGES)')
  expect(mode).toContain('!p.includes("..")')
  expect(mode).toContain('boostSentenceInspection(await readEvidenceCopy(c, x.p))')
  expect(mode).toContain('model_calls: 0')
  expect(mode).not.toMatch(/cascadeFetch|openrouter|fetch\(|rpc\(|\.upload\(|\.from\("staging-boost"\)|c\.rpc/)
})

test('the workflow runs it through the Management API with no prompt, and only reads production tables', () => {
  const S = fs.readFileSync('scripts/boost-sentences-inspect.mjs', 'utf8'), W = fs.readFileSync('.github/workflows/boost-sentences-inspect.yml', 'utf8')
  expect(W).toContain('workflow_dispatch:')
  expect(W).toContain('SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}')
  expect(W).toContain('REF: ${{ vars.SUPABASE_PROJECT_REF }}')
  const L = fs.readFileSync('scripts/boost-live-lib.mjs', 'utf8')
  expect(S).toContain("await worker(`jsonb_build_object('mode', 'boost_sentences', 'storage_paths', to_jsonb(array[")
  expect(S).toContain("if (res.model_calls !== 0) throw Error('the inspection reported a model call')")
  expect(L).toContain("select pipeline.svc_pilot_submit_nonce('coverage-sweep', ${bodySql}) as id")
  expect(L).toContain('readOnly ? { query, read_only: true } : { query }')
  expect((S.match(/await worker\(/g) || []).length).toBe(1)
  expect(S.replace(/await worker\([^\n]*\n/, '')).not.toMatch(/\bcall\(|read_only: false/)
  for (const f of [S, L]) expect(f).not.toMatch(/\b(insert into|update|delete from|drop|truncate|alter)\s+[a-z_]+\.[a-z_]+/i)
})
