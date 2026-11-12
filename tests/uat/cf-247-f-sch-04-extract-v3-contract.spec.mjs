// Guards: F-SCH production redesign (Platform Admin directive 12 Nov 2026 16:12): one versioned extraction contract (sch-extract-v3) whose every field is kept only when its passage is on the official evidence bundle; direct official read before Firecrawl; empty canonical fields filled, never a locked or filled one; no default second AI pass; no Layer 4 review for an unproven or technical case
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { SCH_EXTRACT_CONTRACT, DETAIL_SCHEMA, checkScholarshipDetail, checkSummary, directReadUsable, quoteSource, scholarshipExtractRequest } from '../../supabase/functions/coverage-sweep/sch-extract.ts'

const NAMES = { IN: ['India', 'Indian national'], VN: ['Vietnam', 'Viet Nam'], NG: ['Nigeria'], CA: ['Canada', 'Canadian'], GB: ['United Kingdom', 'UK', 'British'], AU: ['Australia', 'Australian'] }
const PAGE = { id: 'page', text: 'The Global Excellence Scholarship is funded by the Department of Education (award code GES-27). It provides a 25% reduction in tuition fees for the duration of the degree and a one-off $5,000 living allowance. Students from India, Vietnam and Nigeria are eligible. Citizens of Canada are not eligible. You do not need to apply; all eligible applicants are automatically considered when they receive an offer. Applicants must achieve a minimum GPA of 5.0 and enrol full-time. The scholarship is renewable each year for up to 3 years subject to satisfactory progress.' }
const LINKED = { id: 'linked', text: 'Terms and conditions. Recipients must be international students holding a student visa (subclass 500) and must maintain a credit average.' }
const empty = { award_code: null, sponsor: null, programme: null, identity_quote: '', award_type: 'not_stated', award_type_quote: '', residency: 'not_stated', residency_quote: '',
  nationality: { eligible: [], excluded: [], regions: [], quote: '' }, course_scope: 'not_stated', course_scope_quote: '', criteria: [], criteria_conjunction: 'not_stated', benefits: [],
  payment_basis: 'not_stated', payment_quote: '', application: { method: 'not_stated', url: null, rolling: null, quote: '' }, duration: { value: null, unit: 'not_stated', renewable: 'not_stated', quote: '' },
  availability: 'unknown', availability_quote: '', summary: '', missing: [] }

test('every field is kept only when its passage is on the bundle and carries the value; linked terms count as evidence', () => {
  const d = { ...empty,
    award_code: 'GES-27', sponsor: 'Department of Education', identity_quote: 'funded by the Department of Education (award code GES-27)',
    award_type: 'scholarship', award_type_quote: 'The Global Excellence Scholarship is funded by the Department of Education',
    residency: 'student_visa_holders', residency_quote: 'must be international students holding a student visa (subclass 500)',
    nationality: { eligible: ['IN', 'VN', 'NG', 'GB'], excluded: ['CA'], regions: [], quote: 'Students from India, Vietnam and Nigeria are eligible. Citizens of Canada are not eligible.' },
    criteria: [{ kind: 'academic_minimum', text: 'Minimum GPA of 5.0', quote: 'Applicants must achieve a minimum GPA of 5.0' }, { kind: 'study_load', text: 'Full-time enrolment', quote: 'and enrol full-time' },
      { kind: 'other', text: 'Invented condition', quote: 'Applicants must have volunteered for two years' }],
    criteria_conjunction: 'all',
    benefits: [{ kind: 'tuition_percentage', amount: null, currency: null, percentage: 25, maximum: false, quote: 'It provides a 25% reduction in tuition fees' },
      { kind: 'living_allowance', amount: 5000, currency: 'AUD', percentage: null, maximum: false, quote: 'a one-off $5,000 living allowance' },
      { kind: 'tuition_amount', amount: 9000, currency: 'AUD', percentage: null, maximum: false, quote: 'a one-off $5,000 living allowance' }],
    payment_basis: 'program_duration', payment_quote: 'a 25% reduction in tuition fees for the duration of the degree',
    application: { method: 'automatic_consideration', url: null, rolling: null, quote: 'You do not need to apply; all eligible applicants are automatically considered' },
    duration: { value: 3, unit: 'years', renewable: 'conditional', quote: 'renewable each year for up to 3 years subject to satisfactory progress' } }
  const c = checkScholarshipDetail(d, [PAGE, LINKED], NAMES)
  expect(c.identity).toBe(true)
  expect(c.award_type).toBe(true)
  expect([c.residency, c.sources.residency]).toEqual([true, 'linked'])
  expect(c.nationality).toEqual({ eligible: ['IN', 'NG', 'VN'], excluded: ['CA'], regions: [], proven: true, source: 'page' }) // GB is not named in the quote: dropped
  expect(c.criteria.map((x) => x.text)).toEqual(['Minimum GPA of 5.0', 'Full-time enrolment']) // the invented condition is not on the evidence
  expect(c.criteria_conjunction).toBe('all')
  expect(c.benefits.map((b) => [b.kind, b.amount, b.percentage])).toEqual([['tuition_percentage', null, 25], ['living_allowance', 5000, null]]) // 9000 is not in its quote
  expect(c.payment).toBe(true)
  expect(c.application.method).toBe(true)
  expect(c.duration).toBe(true)
})

test('silent evidence proves nothing; a wrong payment word, a number outside its quote or an off-page quote is dropped', () => {
  const c = checkScholarshipDetail(empty, [PAGE], NAMES)
  expect([c.identity, c.award_type, c.residency, c.nationality.proven, c.payment, c.application.method, c.duration, c.availability, c.criteria.length, c.benefits.length]).toEqual([false, false, false, false, false, false, false, false, 0, 0])
  const bad = checkScholarshipDetail({ ...empty, payment_basis: 'annual', payment_quote: 'a one-off $5,000 living allowance', duration: { value: 4, unit: 'years', renewable: 'yes', quote: 'renewable each year for up to 3 years' },
    application: { method: 'separate_application', url: null, rolling: true, quote: 'This text is not on the page at all' } }, [PAGE], NAMES)
  expect([bad.payment, bad.duration, bad.application.method, bad.application.rolling]).toEqual([false, false, false, null])
  expect(quoteSource('Students from India ... are eligible', [PAGE, LINKED])).toBe('page')
  expect(quoteSource('student visa (subclass 500)', [PAGE, LINKED])).toBe('linked')
  expect(quoteSource('', [PAGE])).toBe(null)
})

test('country terminology: a UK bursary in pounds and a Canadian residency condition are read as printed', () => {
  const uk = { id: 'page', text: 'The Vice-Chancellor International Bursary is worth £3,000 per year of study for overseas fee-paying students. British citizens are not eligible.' }
  const c = checkScholarshipDetail({ ...empty, award_type: 'bursary', award_type_quote: 'The Vice-Chancellor International Bursary is worth £3,000',
    benefits: [{ kind: 'tuition_amount', amount: 3000, currency: 'GBP', percentage: null, maximum: false, quote: 'is worth £3,000 per year of study' }],
    payment_basis: 'annual', payment_quote: 'worth £3,000 per year of study', nationality: { eligible: [], excluded: ['GB'], regions: [], quote: 'British citizens are not eligible.' } }, [uk], NAMES)
  expect([c.award_type, c.payment, c.benefits[0]?.currency, c.nationality.excluded]).toEqual([true, true, 'GBP', ['GB']])
  const ca = { id: 'page', text: 'Open to international students. Canadian citizens and permanent residents are not eligible for this entrance award.' }
  expect(checkScholarshipDetail({ ...empty, residency: 'excludes_citizens_and_residents', residency_quote: 'Canadian citizens and permanent residents are not eligible' }, [ca], NAMES).residency).toBe(true)
})

test('the summary is complete original prose with no invented number and no copied run', () => {
  const ok = 'This scholarship reduces tuition by a quarter for the length of the degree and adds a single living allowance of $5,000. It is open to students from several named countries who meet a GPA of 5.0, and eligible applicants are considered automatically.'
  expect(checkSummary(ok, [PAGE])).toEqual({ ok: true, why: null })
  expect(checkSummary(ok.replace('$5,000', '$7,500'), [PAGE]).why).toBe('number_not_in_evidence')
  expect(checkSummary('You do not need to apply; all eligible applicants are automatically considered when they receive an offer. ' + ok, [PAGE]).why).toBe('copied')
  expect(checkSummary('A world-class opportunity for students from many countries who want to study abroad with financial support from the university each year.', [PAGE]).why).toBe('filler')
  expect(checkSummary('Too short.', [PAGE]).why).toBe('length')
  expect(checkSummary(ok.slice(0, -1) + ' and', [PAGE]).why).toBe('incomplete_sentence')
})

test('a direct read is evidence only with real content; a script shell goes to the scraper', () => {
  expect(directReadUsable(1200, 'x')).toBe(true)
  expect(directReadUsable(420, 'Global Scholarship. Eligibility: international students. How to apply: apply online.')).toBe(true)
  expect(directReadUsable(420, 'Menu Home Study Research Contact Accept cookies')).toBe(false)
  expect(directReadUsable(120, 'Scholarship eligibility apply')).toBe(false)
})

test('the request: version 2 keys unchanged, one strict detail object, sources fenced as untrusted data, the governed prompt as system', () => {
  const r = scholarshipExtractRequest('qwen/qwen3-30b-a3b-instruct-2507', 'PROMPT V3', { provider: 'Example University', country: 'AU', currency: 'AUD',
    parts: [{ id: 'page', url: 'https://example.edu.au/s/ges', title: 'GES', h1: 'Global Excellence Scholarship', text: PAGE.text }, { id: 'linked', url: 'https://example.edu.au/s/ges/terms', text: LINKED.text }] })
  const sch = r.response_format.json_schema.schema
  expect(sch.required).toEqual(['is_scholarship', 'single_scholarship', 'not_scholarship_reason', 'name', 'name_quote', 'audience', 'audience_quote', 'offered', 'offered_quote', 'value', 'levels', 'levels_quote', 'courses', 'open_date', 'close_date', 'dates_quote', 'detail'])
  expect(sch.properties.detail).toBe(DETAIL_SCHEMA)
  expect(r.response_format.json_schema.strict).toBe(true)
  expect(r.provider).toEqual({ require_parameters: true })
  expect(r.messages[0]).toEqual({ role: 'system', content: 'PROMPT V3' })
  expect(r.messages[1].content).toContain('<<<SOURCE linked | https://example.edu.au/s/ges/terms>>>')
  expect(r.messages[1].content).toContain('untrusted web content')
  expect(SCH_EXTRACT_CONTRACT).toBe('sch-extract-v3')
})

test('worker v0.77.0: direct official read first, scraper for a rendered listing; version 3 items read the bundle and check every detail field', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.77\.0"; \/\/ v0\.77\.0 \(12 Nov 2026, CF-247 F-SCH production redesign/)
  expect(w).toContain('const dr = directFirst ? await readDirect(url) :')
  expect(w).toContain('if (directReadUsable(mt.length, mt)) return { status: "read"')
  expect(w).toContain('wsNum("scholarship.catalogue_render_wait_ms", 5000), false)')
  expect(w).toContain('const v3 = Number(it.prompt_version || 0) >= 3;')
  expect(w).toContain('checks.detail = checkScholarshipDetail(a.detail, parts, NAT_NAMES);')
})

test('migration 20261113060000: prompt 3 active, no default second pass, fill only empty and unlocked fields, no Layer 4 review for unproven or technical cases', () => {
  const m = fs.readFileSync('supabase/migrations/20261113060000_cf247_sch_extract_v3.sql', 'utf8')
  expect(m).toContain('SYSTEM — STUDYSEARCH SCHOLARSHIP EXTRACTION / sch-extract-v3')
  expect(m).toContain('update pipeline.scholarship_ai_prompts set active = (version = 3)')
  expect(m).toContain('set confirm_admissions = false')
  // the fill never overwrites: description only when under 80 characters, basis only when empty, a manual lock always wins, provider identity checked
  expect(m).toContain("length(coalesce(s.description, '')) < 80")
  expect(m).toContain('s.award_duration_basis is null')
  expect(m).toContain("k.field = 'description'")
  expect(m).toContain("k.field = 'nationalities'")
  expect(m).toContain("if e.provider_id is distinct from s.provider_id then return jsonb_build_object('applied', false, 'reason', 'provider differs')")
  // a re-read that does not prove a fact again keeps the admitted record; a technical failure is not a review
  expect(m).toContain("r := jsonb_build_object('unproven_kept', v_why)")
  expect(m).toContain("r := jsonb_build_object('technical_failure', left(p_error, 200))")
  expect(m.split('scholarship_ai_review_open_v1(v_id').length - 1).toBe(1) // only in the replaced (old) text the guarded edit matches
  // each live function is replaced only from the definition it was written against
  for (const h of ['77f4657de2b349b2b1f4afab9270e78b', 'b62c7711a98e3d1705120d6e4af7f581', '0a432552546d2031d1dcacbed71dc4bf', '666b232e6c05563987163de1796b3505']) expect(m).toContain(`'${h}'`)
  // the detail fill is not an admission authority: it never calls the admission or withdrawal rules
  const fill = m.slice(m.indexOf('create or replace function security.scholarship_detail_apply_v1'), m.indexOf("comment on function security.scholarship_detail_apply_v1"))
  expect(fill).not.toMatch(/scholarship_admit_from_provider_page_v1|scholarship_admission_withdraw_v1|publication_status\s*=/)
  // the eligibility reader stays in shadow (its switches are not touched here)
  expect(m).not.toMatch(/sch_elig\.apply_on/)
})
