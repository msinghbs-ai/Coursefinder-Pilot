// Guards: Decision 276 AER v2 step 1 (Platform Admin 12 Nov 2026 17:20; admin docs/platform/AER-DESIGN-V2-PROPOSAL.md v0.3 §3.3, §3.4, §3.9, §9): a shadow course-page reader with a versioned, pinned prompt and a strict deterministic verifier (quote on the stored page, minimum in its own quote, values never converted, ISO country and reference qualification); ships off and admits nothing
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { AER_V2_SCHEMA, aerFlat, aerNumbers, aerV2Answer, aerV2Refs, aerV2Request, aerV2Sha256, aerV2User, aerV2Verify } from '../../supabase/functions/coverage-sweep/aer-v2.ts'

const MIG = 'supabase/migrations/20261113103100_cf247_aer_v2_shadow.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const mod = fs.readFileSync('supabase/functions/coverage-sweep/aer-v2.ts', 'utf8')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const shadowMode = w.slice(w.indexOf('if (mode === AER_V2_MODE) {'), w.indexOf('    if (mode === "central_ai") {'))
const prompt = m.slice(m.indexOf('(select $p$') + '(select $p$'.length, m.indexOf('$p$::text x) t'))

// a real-looking stored course page (text as the worker gives it to the model)
const PAGE = `Bachelor of Nursing | La Trobe University
Entry requirements
Australian Year 12 or equivalent: Prerequisites: Units 3 and 4 - a study score of at least 25 in English (EAL) or at least 20 in English other than EAL. Lowest selection rank 2026: ATAR 65.20.
International students
Indian Senior School Certificate (CBSE): overall average of 65% in best four academic subjects.
Sri Lanka GCE A Levels: minimum of 7 points from three A Level subjects.
International Baccalaureate Diploma: a minimum score of 26 points.
English language requirements: IELTS (Academic) overall score of 7.0 with no band less than 7.0.
Applicants with prior study at a recognised institution may be considered.`
const refs = aerV2Refs(['AU', 'IN', 'LK', 'NZ', 'CN'], [{ code: 'IB', name: 'International Baccalaureate Diploma' }, { code: 'A_LEVELS', name: 'GCE A Levels' }])
const rec = (o) => ({ scope: 'course', course_name: null, audience: 'international', applicant_country: null, qualification: null, qualification_code: null, study_level: 'undergraduate',
  route: 'school leaver', min_grade: null, min_value: null, grade_scale: 'none', conditions: null, quotes: [], confidence: 0.9, ...o })
const IN = rec({ applicant_country: 'IN', qualification: 'Indian Senior School Certificate (CBSE)', min_grade: '65%', min_value: 65, grade_scale: 'percentage',
  quotes: [{ value: 'min_grade', text: 'Indian Senior School Certificate (CBSE): overall average of 65% in best four academic subjects.' }] })
const verify = (records, seen = []) => aerV2Verify({ records, seen_not_mapped: seen }, PAGE, refs, 300)

test('verifier: a quote on the stored page with the minimum printed in it passes; spacing, case and punctuation do not matter (canonical flat form)', () => {
  const v = verify([IN, rec({ ...IN, quotes: [{ value: 'min_grade', text: 'indian senior school certificate CBSE overall  average of 65 % in best four' }] })])
  expect(v.checks.map((c) => c.pass)).toEqual([true, true])
  expect(v.checks[0]).toMatchObject({ quote_on_page: true, minimum_in_quote: true, country_known: true, qualification_known: true, has_target: true, reasons: [] })
  expect(v.passed).toBe(2)
  expect(aerFlat('ATAR 65.20')).toBe('atar6520')
  expect(mod).toContain('const aerFlat = (s: unknown) => String(s ?? "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");')
})

test('verifier: a quote not on the page fails; a minimum not in its own quote fails; a value not printed in the minimum fails', () => {
  const offPage = rec({ ...IN, quotes: [{ value: 'min_grade', text: 'Indian Senior School Certificate (CBSE): overall average of 60% in best four academic subjects.' }], min_grade: '60%', min_value: 60 })
  const wrongQuote = rec({ ...IN, quotes: [{ value: 'min_grade', text: 'Indian Senior School Certificate (CBSE)' }] })  // the 65% is not in its own quote
  const noOwnQuote = rec({ ...IN, quotes: [{ value: 'requirement', text: 'Indian Senior School Certificate (CBSE): overall average of 65%' }] })
  const value = rec({ ...IN, min_value: 70 })
  const v = verify([offPage, wrongQuote, noOwnQuote, value])
  expect(v.checks.map((c) => c.pass)).toEqual([false, false, false, false])
  expect(v.checks[0].reasons).toContain('quote_not_on_page')
  expect(v.checks[1].reasons).toEqual(['minimum_not_in_quote'])
  expect(v.checks[2].reasons).toEqual(['minimum_has_no_quote'])
  expect(v.checks[3].reasons).toEqual(['value_not_printed_in_minimum'])
  expect(v.failed).toBe(4)
})

test('verifier: values are never converted between countries or scales', () => {
  // the page prints a domestic ATAR; a model that "converts" it into an Indian percentage, or gives a number the minimum does not print, fails
  const converted = rec({ applicant_country: 'IN', min_grade: '72%', min_value: 72, grade_scale: 'percentage', quotes: [{ value: 'min_grade', text: 'Lowest selection rank 2026: ATAR 65.20.' }] })
  const scaled = rec({ applicant_country: 'LK', qualification: 'Sri Lanka GCE A Levels', min_grade: '7 points', min_value: 70, grade_scale: 'points',
    quotes: [{ value: 'min_grade', text: 'Sri Lanka GCE A Levels: minimum of 7 points from three A Level subjects.' }] })
  const printed = rec({ applicant_country: 'LK', qualification: 'Sri Lanka GCE A Levels', min_grade: '7 points', min_value: 7, grade_scale: 'points',
    quotes: [{ value: 'min_grade', text: 'Sri Lanka GCE A Levels: minimum of 7 points from three A Level subjects.' }] })
  const v = verify([converted, scaled, printed])
  expect(v.checks.map((c) => c.pass)).toEqual([false, false, true])
  expect(v.checks[0].reasons).toContain('minimum_not_in_quote')
  expect(v.checks[1].reasons).toEqual(['value_not_printed_in_minimum'])
  expect(aerNumbers('ATAR 65.20')).toEqual([65.2])
  expect(aerNumbers('GPA 5.0 out of 7; 1,200 points')).toEqual([5, 7, 1200])
  expect(prompt).toContain('Never convert a grade, score or rank between countries or scales.')
})

test('verifier: an unknown applicant country fails; a domestic route names no country; a qualification code must exist in reference data', () => {
  const unknown = rec({ ...IN, applicant_country: 'XX' })
  const name = rec({ ...IN, applicant_country: 'India' })
  const domestic = rec({ audience: 'domestic', applicant_country: null, min_grade: 'ATAR 65.20', min_value: 65.2, grade_scale: 'rank', quotes: [{ value: 'min_grade', text: 'Lowest selection rank 2026: ATAR 65.20.' }] })
  const domesticWithCountry = rec({ ...domestic, applicant_country: 'AU' })
  const ib = rec({ qualification: 'International Baccalaureate Diploma', qualification_code: 'IB', min_grade: '26 points', min_value: 26, grade_scale: 'points',
    quotes: [{ value: 'min_grade', text: 'International Baccalaureate Diploma: a minimum score of 26 points.' }] })
  const badCode = rec({ ...ib, qualification_code: 'IBDP' })
  const v = verify([unknown, name, domestic, domesticWithCountry, ib, badCode])
  expect(v.checks.map((c) => c.pass)).toEqual([false, false, true, false, true, false])
  expect(v.checks[0].reasons).toEqual(['country_not_in_reference'])
  expect(v.checks[2]).toMatchObject({ has_target: false, has_minimum: true })
  expect(v.checks[3].reasons).toEqual(['domestic_route_with_country'])
  expect(v.checks[4]).toMatchObject({ qualification_known: true, has_target: true })
  expect(v.checks[5].reasons).toEqual(['qualification_not_in_reference'])
})

test('verifier: no quote or an over-long quote fails; seen-but-not-mapped statements are kept with whether they are on the page', () => {
  const long = 'x'.repeat(301)
  const v = verify([rec({ applicant_country: 'IN' }), rec({ ...IN, quotes: [...IN.quotes, { value: 'requirement', text: long }] })],
    [{ statement: 'prior study considered', quote: 'Applicants with prior study at a recognised institution may be considered.' }, { statement: 'invented', quote: 'Portfolio required for all applicants.' }])
  expect(v.checks[0].reasons).toEqual(['no_quote'])
  expect(v.checks[1].reasons).toContain('quote_too_long')
  expect(v.seen_not_mapped.map((s) => s.on_page)).toEqual([true, false])
})

test('request and answer: strict schema, pinned model, a cut or other-model answer is never parsed; the prompt text is checked by its sha-256', async () => {
  const req = aerV2Request('openai/gpt-4.1-mini', prompt, aerV2User({ title: 'Bachelor of Nursing', provider: 'La Trobe University', provider_country: 'AU' }, [{ code: 'IB', name: 'International Baccalaureate Diploma' }], PAGE), 6000)
  expect(req).toMatchObject({ model: 'openai/gpt-4.1-mini', temperature: 0, max_tokens: 6000, provider: { require_parameters: true } })
  expect(req.response_format.json_schema.strict).toBe(true)
  expect(AER_V2_SCHEMA.required).toEqual(['records', 'seen_not_mapped'])
  expect(req.messages[1].content).toContain('QUALIFICATIONS (code: name):\nIB: International Baccalaureate Diploma')
  const ok = { model: 'openai/gpt-4.1-mini-2025-04-14', usage: { cost: 0.004 }, choices: [{ finish_reason: 'stop', message: { content: '{"records":[],"seen_not_mapped":[]}' } }] }
  expect(aerV2Answer(ok, 'openai/gpt-4.1-mini')).toEqual({ ok: true, a: { records: [], seen_not_mapped: [] }, cost: 0.004 })
  expect(aerV2Answer({ ...ok, choices: [{ finish_reason: 'length', message: { content: '{"records":[' } }] }, 'openai/gpt-4.1-mini').ok).toBe(false)
  expect(aerV2Answer({ ...ok, model: 'anthropic/other' }, 'openai/gpt-4.1-mini').ok).toBe(false)
  // the database records encode(sha256(convert_to(system_text, 'UTF8')), 'hex'); the worker computes the same over the same text
  expect(await aerV2Sha256('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
  expect(m).toContain("encode(sha256(convert_to(t.x, 'UTF8')), 'hex'), 'openai/gpt-4.1-mini', 300, 'trial'")
  expect(shadowMode).toContain('(await aerV2Sha256(system)) !== String(ver.system_sha256 || "")')
})

test('the prompt: one versioned trial text, pinned to the course entry reader model, short, with the design rules', () => {
  expect(prompt.startsWith('AER course page reader, prompt aer-v2-course-v1.')).toBe(true)
  expect(prompt.length).toBeLessThan(4000)
  for (const s of ['applicant_country: the ISO 3166-1 alpha-2 code', 'qualification_code: its code from the QUALIFICATIONS list', 'min_grade: the minimum exactly as printed',
    'min_value: only when min_grade is one printed number', 'grade_scale: percentage, gpa, points, rank, letter, aggregate or none', 'each at most 300 characters',
    'English language tests and English proficiency are not academic entry', 'audience domestic and no applicant_country', 'only when the page prints it', 'seen_not_mapped:'])
    expect(prompt).toContain(s)
  expect(code).toContain("check (status in ('trial', 'active', 'retired'))")
  expect(code).toContain("check (purpose in ('course_page'))")
  expect(code).toContain("if coalesce(security.toolset_setting('pipeline', 'entry.matrix_model') #>> '{}', 'openai/gpt-4.1-mini') <> 'openai/gpt-4.1-mini' then")
})

test('migration: ships off, budget and sample are settings, the job is catalogued, the sample reads stored course pages only', () => {
  expect(m).toMatch(/\('pipeline', 'aer\.v2_shadow_on', [^\n]*\n[^\n]*\n\s*'number', to_jsonb\(0\), 0, 1,/)
  expect(m).toMatch(/\('pipeline', 'aer\.v2_shadow_budget_usd', [^\n]*\n[^\n]*\n\s*'number', to_jsonb\(20\),/)
  expect(m).toMatch(/\('pipeline', 'aer\.v2_shadow_sample', [^\n]*\n[^\n]*\n\s*'number', to_jsonb\(2000\),/)
  expect(m).toMatch(/\('pipeline', 'batch\.aer_v2_shadow', [^\n]*\n[^\n]*\n\s*'number', to_jsonb\(20\),/)
  expect(code).toContain("('aer-v2-shadow', 'Course pages', 41, 'Entry requirements v2 shadow reader',")
  expect(code).toContain("perform cron.schedule('aer-v2-shadow', '8,38 * * * *', 'select security.aer_v2_shadow_fire_v1()');")
  expect(code).toContain("jsonb_build_object('mode', 'aer_v2_shadow', 'limit', security.pipeline_num_v1('batch.aer_v2_shadow', 20)::int)")
  expect(code).toContain("join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound'")
  expect(code).toContain('join pipeline.evidence_artifacts a on a.id = g.evidence_id and a.storage_path is not null')
  expect(code).toContain("when v_spent >= v_budget then format('trial budget reached")
  expect(code).toContain("if security.pipeline_num_v1('aer.v2_shadow_on', 0) < 1 then return jsonb_build_object('on', false); end if;")
  expect(code).toContain("from pipeline.aer_labelled_rows_v1 l where l.source_kind = 'course_page'")
  expect(code).toContain("if (security.aer_v2_shadow_fire_v1()->>'on')::boolean then raise exception 'post-check: the shadow reader ran while off'; end if;")
})

test('no admission: neither the migration nor the module or the worker mode writes catalogue tables or Layer 4 items; no live fetch', () => {
  for (const src of [code, mod, shadowMode]) {
    expect(src).not.toMatch(/(insert\s+into|update|delete\s+from)\s+catalogue\./i)
    expect(src).not.toMatch(/layer4_review_items/)
    expect(src).not.toMatch(/_admit_v1|aer_machine_run|svc_entry_matrix_record|enrich_entry_record|course_entry_review_apply/)
  }
  expect(shadowMode).not.toMatch(/firecrawl|readDirect|useFc/i)
  expect(shadowMode).toContain('readEvidenceCopy(c, String(it.storage_path))')
  expect(code).toMatch(/insert into pipeline\.aer_v2_shadow_results\(/)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
