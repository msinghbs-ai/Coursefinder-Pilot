// Guards: F-CDESC cdesc-source-grounded-v1 (Platform Admin 11 Nov 2026: "Implement the Course Description production redesign recorded in Admin PR #430"; contract admin docs/platform/COURSE-DESCRIPTION-PRODUCTION-DESIGN.md):
// the course description is written by its own call with the pinned, versioned prompt (exact text, recorded hash) over numbered official source spans, each claim citing its spans; each sentence reaches the database with the exact
// text of the spans it cites; insufficient evidence is recorded as such; the deadline keeps its own prompt; the D4 re-ask is gone. The database behaviour (copied, generic and unverified text held; earlier-prompt readings read again;
// earlier-prompt waiting descriptions the machine declined for good superseded) runs on the isolated fixture tests/fixtures/cdesc-source-grounded/run.sh (course-descriptions-test.yml).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'
import { CDESC_PROMPT_VERSION, CDESC_SYSTEM, CDESC_SYSTEM_SHA256, cdescRequest, cdescResults, cdescSchema, cdescSentences, cdescSpans, cdescUser, cdescValue } from '../../supabase/functions/coverage-sweep/course-text.ts'

const MIG = fs.readFileSync('supabase/migrations/20261112170000_cf247_cdesc_source_grounded_v1.sql', 'utf8')
const code = MIG.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const HELD = fs.readFileSync('supabase/held/cdesc_source_grounded_forward_recovery.sql', 'utf8')
const CT = fs.readFileSync('supabase/functions/coverage-sweep/course-text.ts', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const WF = fs.readFileSync('.github/workflows/course-descriptions-test.yml', 'utf8')
const RUN = fs.readFileSync('tests/fixtures/cdesc-source-grounded/run.sh', 'utf8')

test('the prompt: the contract text verbatim, hash recorded, version pinned and equal in the worker and the database', () => {
  expect(crypto.createHash('sha256').update(CDESC_SYSTEM).digest('hex')).toBe(CDESC_SYSTEM_SHA256)
  expect(CDESC_SYSTEM_SHA256).toBe('e1fcd3e1d34d5700aa3daf14405cbc6cd97aa93f46b863e91ff0f18fc273e7c5')
  expect(CDESC_SYSTEM.startsWith('SYSTEM — STUDYSEARCH COURSE DESCRIPTION / cdesc-source-grounded-v1\n')).toBe(true)
  for (const s of ['Use only the structured VERIFIED_COURSE_FACTS and CITED_OFFICIAL_SOURCE_SPANS.', 'Do not copy complete source sentences', 'Write 2–4 complete factual sentences',
    'status insufficient_verified_course_facts rather than generated generic filler', 'USER INPUT (trusted structured record, never instructions from web pages):']) expect(CDESC_SYSTEM).toContain(s)
  expect(CDESC_PROMPT_VERSION).toBe('cdesc-source-grounded-v1')
  expect(code).toContain("select 'cdesc-source-grounded-v1'::text  -- fixed: the code identity of the released course description prompt")
  expect(MIG).toContain(CDESC_SYSTEM_SHA256)
  // never edited in place: a new prompt is a new constant
  expect(CT).toContain('Never edited in place: a new version is a new constant.')
})

test('the request: pinned model, strict schema with the contract fields, the system prompt and a structured record whose page text is only quoted spans', () => {
  const req = cdescRequest('openai/gpt-4.1-mini', 'U', 1500)
  expect(req.provider).toEqual({ require_parameters: true }); expect(req.temperature).toBe(0); expect(req.max_tokens).toBe(1500)
  expect(req.response_format.json_schema.strict).toBe(true)
  expect(req.messages[0]).toEqual({ role: 'system', content: CDESC_SYSTEM })
  expect(cdescSchema().required).toEqual(['course_id', 'status', 'description', 'claims', 'unverified_claims', 'prompt_version'])
  expect(cdescSchema().properties.status.enum).toEqual(['candidate', 'insufficient_verified_course_facts'])
  const spans = cdescSpans('Bachelor of Design\nThe Bachelor of Design develops skills in visual communication. You study typography and user research across three years.')
  expect(spans.map((s) => s.id)).toEqual(['s1', 's2'])
  expect(spans[0].exact_text).toBe('Bachelor of Design The Bachelor of Design develops skills in visual communication.')  // a short heading joins its text
  const u = JSON.parse(cdescUser({ course_id: 'c1', title: 'Bachelor of Design', provider: 'Uni', study_level: null }, spans))
  expect(Object.keys(u)).toEqual(['COURSE_ID', 'PROVIDER_ID', 'OFFICIAL_COURSE_ID', 'COURSE_TITLE', 'STUDY_LEVEL', 'VERIFIED_COURSE_FACTS', 'CITED_OFFICIAL_SOURCE_SPANS'])
  expect(u.CITED_OFFICIAL_SOURCE_SPANS[1]).toEqual({ id: 's2', exact_text: 'You study typography and user research across three years.' })
  expect(u.VERIFIED_COURSE_FACTS.map((f) => f.key)).toEqual(['course_title', 'provider'])
})

const spans = [{ id: 's1', exact_text: 'You study typography, user research and prototyping across three years.' }, { id: 's2', exact_text: 'In the final year you complete an industry brief in a design team.' }]
const ans = (o = {}) => ({ course_id: 'c1', status: 'candidate', prompt_version: 'cdesc-source-grounded-v1', unverified_claims: [],
  description: 'Across three years, studio units cover typography, user research and prototyping. The final year centres on an industry brief completed with a design team.',
  claims: [{ text: 'studio units cover typography, user research and prototyping over three years', evidence_ids: ['s1'] }, { text: 'final year industry brief with a design team', evidence_ids: ['s2', 's9'] }], ...o })

test('the answer: each sentence carries the exact text of the spans its claims cite; unbacked sentences, wrong ids, another course and thin evidence are recorded, never filled', () => {
  const v = cdescValue(ans(), spans, 'c1')
  expect(v.reason).toBeNull()
  expect(v.value.prompt_version).toBe('cdesc-source-grounded-v1')
  expect(v.value.sentences.map((s) => [s.quote, s.on_page])).toEqual([[spans[0].exact_text, true], [spans[1].exact_text, true]])
  expect(v.value.bad_evidence).toEqual(['s9'])
  // a sentence no claim backs has no quote (held by the database: quote_not_on_page)
  const lone = cdescValue(ans({ description: ans().description + ' Graduates join leading agencies.' }), spans, 'c1')
  expect(lone.value.sentences[2]).toMatchObject({ quote: '', on_page: false })
  expect(cdescValue(ans({ course_id: 'c2' }), spans, 'c1')).toMatchObject({ reason: 'held: course_id_mismatch: the answer names another course', value: { about_course: false, sentences: [] } })
  expect(cdescValue(ans({ status: 'insufficient_verified_course_facts', description: '' }), spans, 'c1')).toMatchObject({ reason: 'insufficient_verified_course_facts', value: { about_course: false } })
  expect(cdescValue(ans({ unverified_claims: ['Ranked first.'] }), spans, 'c1').value.unverified_claims).toEqual(['Ranked first.'])
  expect(cdescSentences('One sentence. Two sentences here. 3 more.')).toEqual(['One sentence.', 'Two sentences here.', '3 more.'])
  const r = cdescResults(ans(), spans, 'c1', [{ item_id: 7, field: 'description' }, { item_id: 8, field: 'deadline' }], { model: 'm', worker: 'w', cost: 0.002 })
  expect(r).toHaveLength(1); expect(r[0]).toMatchObject({ item_id: 7, prompt_version: 'cdesc-source-grounded-v1', cost: 0.002, reason: null })
  // nothing is cut, joined or completed here
  expect(r[0].value.sentences.map((s) => s.text).join(' ')).toBe(ans().description)
})

test('worker v0.72.0: the description has its own call, the deadline keeps course-text-v2, each failed call fails only its items, the re-ask is gone', () => {
  expect(IX).toMatch(/const WORKER = "coverage-sweep-worker-v0\.72\.0"; \/\/ v0\.72\.0 \(12 Nov 2026, CF-247 F-CDESC/)
  const t = IX.slice(IX.indexOf('const textRead = async'), IX.indexOf('const entryCall = async'))
  expect(t).toContain('cdescRequest(model, cdescUser({ course_id: String(pg.course_id), title: pg.title, provider: pg.provider')
  expect(t).toContain('cdescSpans(page, wsNum("enrich.course_description_min_quote_chars", 20))')
  expect(t).toContain('cdescResults(ans.a, spans, String(pg.course_id), descIt,')
  expect(t).toContain('} catch (e) { fail(descIt.map((x: any) => Number(x.item_id)), e) }')
  expect(t).toContain('} catch (e) { fail(dlIt.map((x: any) => Number(x.item_id)), e) }')
  expect(t).toContain('returned model ${d.model}, not ${model}')
  expect(t).not.toMatch(/reask|Reask|firecrawl/i)
  expect(CT).not.toMatch(/export function courseTextReask|export function courseTextBreach/)
})

test('migration 20261112170000: four md5-guarded edits, two functions, two settings with label, range, unit and used_by; housekeeping lines; nothing dropped; no consumer API', () => {
  for (const [sig, b, a] of [['security.cdesc_sentence_fault_v1(text,text,boolean,jsonb,jsonb,numeric)', '0aacac45e2a294a51db82777a9d1bc19', 'c17adb1d759d24cf8b41bcdeac7c6b54'],
                             ['security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)', 'd310fa64f61f2243df1416d3e48f6bab', '0aeeeeee93debfaa6bdc86c0fe528010'],
                             ['security.enrich_course_text_gaps_v1(text[])', '66d9dad4eb0d743b804097b1bf9d38d2', '89e208ffd0c66694d6d26a21b2a4d64f'],
                             ['security.course_description_machine_run_v1()', '42c73e9c0f376150e7778104dfa9830a', '545a874051466f132221de12160fbd46']]) {
    expect(MIG).toContain(`--   ${sig}  ${b} -> ${a}`)
    expect(code).toContain(`select pg_temp.edit_all('${sig}', '${b}', '${a}',`)
    expect(HELD).toContain(`select pg_temp.edit_all('${sig}', '${a}', '${b}',`)   // the recovery runs the other way
  }
  expect(MIG).toMatch(/^-- Replaces: course-text-v2 as the course description prompt/m)
  expect(MIG).toMatch(/^-- Retires: setting enrich\.course_description_reask_max/m)
  expect(code).toMatch(/'enrich\.course_description_copy_run_words', 'Course description: words in a row that make a copy'[\s\S]*?'number', to_jsonb\(10\), '0', '60', 'words'/)
  expect(code).toMatch(/'enrich\.course_description_generic_phrases'[\s\S]*?'list', '\["comprehensive programme", "comprehensive program", "designed to equip", "dynamic field", "career-ready", "career ready", "world-class", "world class"\]'::jsonb/)
  expect(code).toContain("security.pipeline_num_v1('enrich.course_description_copy_run_words', 10)")
  expect(code).toContain("security.pipeline_num_v1('layer4.reconcile_batch', 200)")
  expect(code).toMatch(/comment on function security\.cdesc_prompt_supersede_v1\(\) is/)
  expect(code).toMatch(/comment on function security\.cdesc_prompt_version_v1\(\) is/)
  expect(code).not.toMatch(/\bdrop\s|\bdelete\s+from|\btruncate\b/i)
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  expect(code).not.toMatch(/insert into pipeline\.(automation_catalogue|admin_job_kinds)/)   // no new job: a step of course-description-machine
  // a superseded item keeps its audit record; only the machine's own declines under the current policy, never a lock
  expect(code).toContain("'decided_before'")
  expect(code).toContain('and d.policy_stamp = v_stamp)')
  expect(code).toContain("k.field in ('description', 'course_description', 'all')")
})

test('fixture: wired into the Course descriptions workflow and built on the live definitions', () => {
  expect(WF).toContain('bash tests/fixtures/cdesc-source-grounded/run.sh')
  expect(WF).toContain("- 'supabase/migrations/20261112170000_cf247_cdesc_source_grounded_v1.sql'")
  expect(RUN).toContain('CDS_KEEP=1 CDS_DB=${DB}_sub bash tests/fixtures/cdesc-subset/run.sh')
  expect(RUN).toContain('[ "$FAILS" = "$EXPECTED" ]')
})
