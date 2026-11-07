// Guards: AER precedent 29 Oct 2026 ("a budget refusal is not the page failing") for provider pages and scholarship reads, with G2 (settings) and the housekeeping rule (Replaces/Retires): migration 20261107060000, central English page choice (agent finding 7 Nov 2026).
// The database behaviour (refused reads keep their tries, the picker waits, the scholarship wait) is tests/fixtures/english-refusal/run.sh (CI: english-refusal-test.yml), on real PostgreSQL built from the production manifest.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { centralCandidates } from '../../supabase/functions/coverage-sweep/central.ts'

const MIG = fs.readFileSync('supabase/migrations/20261107060000_cf247_refusal_is_not_a_try.sql', 'utf8')
const CODE = MIG.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const WORKER = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const eng = (urls, host) => centralCandidates(urls.map((url) => ({ url })), host).filter((c) => c.kind === 'english_policy')

test('pages taken as a provider\'s English requirements on 7 Nov 2026 that are a test centre, a news story, a sample test or an English course are not suggested', () => {
  expect(eng(['https://www.canterbury.ac.nz/about-uc/our-structure/faculties/education-faculty/centre-for-assessment-and-monitoring/ielts'], 'canterbury.ac.nz')).toEqual([])
  expect(eng(['https://www.manukau.ac.nz/news-stories/mit-celebrates-25-years-of-ielts-testing'], 'manukau.ac.nz')).toEqual([])
  expect(eng(['https://www-assets.conestogac.on.ca/documents/www/testing-services/mature-student-assessment-sample-english-test.pdf'], 'conestogac.on.ca')).toEqual([])
  expect(eng(['https://www.massey.ac.nz/study/international-students/qualifications-and-courses-for-international-students/english-language-courses'], 'massey.ac.nz')).toEqual([])
})

test('real admission English pages found on the live system are still suggested, as strong candidates', () => {
  const pages = [
    ['https://study.unimelb.edu.au/how-to-apply/english-language-requirements', 'unimelb.edu.au'],
    ['https://www.auckland.ac.nz/en/study/applications-and-admissions/entry-requirements/english-language-requirements.html', 'auckland.ac.nz'],
    ['https://bond.edu.au/entry-to-bond/entry-requirements/international-entry-requirements/english-language-requirements', 'bond.edu.au'],
    ['https://durhamcollege.ca/admissions/english-language-proficiency-requirement', 'durhamcollege.ca'],
    ['https://www.flinders.edu.au/international/apply/entry-requirements/english-language-requirements', 'flinders.edu.au'],
  ]
  for (const [url, host] of pages) { const c = eng([url], host); expect(c.length, url).toBe(1); expect(c[0].score, url).toBeGreaterThanOrEqual(5) }
})

test('with a wrong page removed the provider has no strong English candidate, so the targeted map is asked for one', async () => {
  const { weakKinds } = await import('../../supabase/functions/coverage-sweep/central.ts')
  const found = centralCandidates([{ url: 'https://www.canterbury.ac.nz/about-uc/our-structure/faculties/education-faculty/centre-for-assessment-and-monitoring/ielts' }], 'canterbury.ac.nz')
  expect(weakKinds(found)).toContain('english_policy')
})

test('the migration guards the three live definitions on their md5, replaces them in place, drops nothing and states Replaces/Retires', () => {
  for (const [sig, md5] of [['public.svc_provider_facts_read_next(integer)', '5125d17949c155b56bd2b3a3903e6479'],
    ['public.svc_provider_facts_read_record(uuid,text,integer,text,text,text,jsonb,jsonb)', '1d365d6a6357e6a7db701a1814744604'],
    ['public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)', 'b2fafccb2532afc3e0d1337588b5c43d']])
    expect(MIG, sig).toContain(`('${sig}', '${md5}')`)
  expect(MIG).toMatch(/^-- Replaces: .+/m); expect(MIG).toMatch(/^-- Retires: nothing/m); expect(MIG).toMatch(/Consumer API: unchanged \(G3\)/)
  expect(CODE).not.toMatch(/\b(drop|delete|truncate)\b/i)
  expect(CODE).not.toMatch(/cron\.(schedule|alter_job)/)   // no job is added or changed: G1 has nothing to catalogue
})

test('G2: the waits and the waiting limit are settings with a label, range, unit and used_by; no new number is written into the functions', () => {
  for (const key of ['retry.provider_facts_refusal_hours', 'retry.sch_ai_wait_minutes', 'sch_ai.wait_max_days']) expect(MIG, key).toContain(`'${key}'`)
  expect(MIG).toContain("to_jsonb(6), 1, 168, 'hours'"); expect(MIG).toContain("to_jsonb(30), 5, 1440, 'minutes'"); expect(MIG).toContain("to_jsonb(14), 1, 90, 'days'")
  expect(CODE).not.toMatch(/interval '30 minutes'/)   // the literal the old retry branch carried
  expect(CODE).toContain("security.pipeline_num_v1('retry.sch_ai_wait_minutes', 30)")
})

test('the worker records the refusal names the database treats as refusals (nothing else is hidden behind them)', () => {
  for (const n of ['budget', 'credits_refused', 'credits_reserve', 'target_list_refused', 'no_firecrawl_key', 'time budget']) expect(MIG, n).toContain(`'${n}'`)
  // the provider_facts reader records g.why (credits_refused, credits_reserve, target_list_refused, no_firecrawl_key) or "time budget" as p_summary.error
  expect(WORKER).toMatch(/svc_provider_facts_read_record", \{ p_id: it\.id, p_status: "failed", p_http: null, p_storage_path: null, p_sha256: null, p_mime: null, p_rows: \[\], p_summary: \{ error: g\.why \} \}/)
  expect(WORKER).toContain('{ ok: false, why: "time budget" }')
})

test('the requeue of closed pages is a paste file with a rollback, never a migration, and does not touch pages that gave no content', () => {
  const paste = fs.readFileSync('docs/paste/PASTE-20261107-english-refused-sources-requeue.sql', 'utf8')
  const back = fs.readFileSync('docs/paste/PASTE-20261107-english-refused-sources-requeue-rollback.sql', 'utf8')
  expect(paste).toContain('security.provider_fact_refusal_v1(f.parse_summary->>\'error\')')
  expect(paste).toContain("f.status = 'failed'"); expect(paste).toContain("'requeued_from'")
  expect(back).toContain("parse_summary ? 'requeued_from'"); expect(back).toContain('f.read_at is null')
  expect(CODE).not.toContain('requeued_from')
})
