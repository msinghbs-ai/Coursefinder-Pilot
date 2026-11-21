// Guards: Lane 2 (S2-Data-Destination-Continuous), Platform Admin 21 Nov 2026 21:16 AEDT, RM1C Australian application routes (s960): routes read
// from official pages at $0 (static, no Firecrawl) into a draft study-rules edition; an admissions centre's route applies to its states, not the
// whole country; nothing is published without the Platform Admin; immediate live activation (the static read runs on deploy).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { extractFact } from '../../supabase/functions/_shared/cf247-page-facts.js'

const MIG = fs.readFileSync('supabase/migrations/20261122040000_cf247_s960_rm1c_au_application_routes.sql', 'utf8')
const code = MIG.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n')
const LOADER = fs.readFileSync('supabase/functions/layer1-destination-geo-loader/index.ts', 'utf8')
const WF = fs.readFileSync('.github/workflows/destination-page-facts-static.yml', 'utf8')
const EDITION = 'Australian application routes (Study Australia and admissions centres)'

// the five facts as the migration seeds them: [title, pattern, states]
const facts = [...code.matchAll(/\('(https:\/\/[^']+)', '([^']+)',\s*\n\s*'([^']+)', '([^']+)', (null::text\[\]|array\[[^\]]+\])\)/g)]
  .map((m) => ({ url: m[1], title: m[2], pattern: m[3], states: m[5].startsWith('null') ? null : [...m[5].matchAll(/'([A-Z-]+)'/g)].map((x) => x[1]) }))

// the text of each page as the loader's htmlToText gave it on 21 Nov 2026 (the sentences each pattern must find)
const pages = {
  'Apply directly to the education provider': 'Step 3: Apply . Applying directly . Once you decide which course you want to study via our Course Search tool , you may be able to complete an application via the education provider’s website or request an application form by emailing the education provider directly. The education provider will assess your application.',
  'Apply through an education agent': 'Using an Education Agent . An education agent can give you information about your options for studying and living in Australia and help you with your study application. Agents have up-to-date course information.',
  'UAC': 'How to apply . International students undertaking one of the following qualifications in 2025 or 2026 can apply for undergraduate courses through UAC: . an Australian Year 12 in or outside Australia . an International Baccalaureate Diploma . a New Zealand National Certificate of Educational Achievement (NCEA) Level 3. . All other international students apply directly to the institutions, not through UAC. Each institution has its own application procedures and admission requirements.',
  'VTAC': 'Applying for tertiary education as an international student . The only international students that can apply for courses through VTAC are international Australian Year 12 students. . If you are an international student who is not completing an Australian Year 12, or who doesn’t meet the citizenship and residency requirements for applying through VTAC, you must apply directly to the institutions . If you wish to nominate an education agent, you can do so after submitting a course application.',
  'SATAC': 'Who is considered an International Year 12 applicant? . International students studying one of the following qualifications in Australia may apply for undergraduate courses (at the universities listed above) through SATAC: . South Australian Certificate of Education ( SACE ) . Northern Territory Certificate of Education and Training ( NTCET ) . Australian Capital Territory Senior Secondary Certificate (ACT SSC) . New South Wales Higher School Certificate (HSC) . Queensland Certificate of Education (QCE) . Tasmanian Certificate of Education (TCE) . Victorian Certificate of Education (VCE) . Western Australian Certificate of Education (WACE) . International Baccalaureate ( IB ) Diploma (in Australia only) . All other international students whose qualifications are not listed above must apply directly to the relevant institutions, rather than through SATAC. Awaiting permanent residency status.',
}
const pageFor = (f) => pages[f.title] ?? pages[Object.keys(pages).find((k) => f.title.includes(`through ${k}`))]

test('s960: five application-route facts, read directly, into one draft edition with terms pending; nothing published', () => {
  expect(facts.map((f) => f.title)).toHaveLength(5)
  expect(code).toContain(`'application_route', f.title, 'international student',\n       f.pattern, 'i', f.anchor, 'active', 'static', f.states,`)
  expect(code).toMatch(new RegExp(`'study_rules', '${EDITION.replace(/[()]/g, '\\$&')}', current_date, 'draft',`))
  expect(code).toMatch(/'pending', null\n  from ref\.countries c/)
  expect(code).not.toMatch(/'rendered'|'published'|edition_publish|terms_status = 'approved'/)
  for (const f of facts) expect(f.url, f.title).toMatch(/^https:\/\/(www\.)?(studyaustralia\.gov\.au|uac\.edu\.au|vtac\.edu\.au|satac\.edu\.au)\//)
})

test('s960: each pattern finds its rule, with a verbatim quote that holds the match (as the loader checks)', () => {
  for (const f of facts) {
    const r = extractFact(pageFor(f), { pattern: f.pattern, flags: 'i', kind: 'text' })
    expect(r.found, f.title).toBe(true)
    expect(r.quote, f.title).toContain(r.match)
  }
  // a changed page is not matched by accident: the UAC rule needs both sentences
  const uac = facts.find((f) => f.title.includes('through UAC'))
  expect(extractFact(pages.UAC.replace('All other international students', 'Some'), { pattern: uac.pattern, flags: 'i', kind: 'text' }).found).toBe(false)
})

test('s960: admissions-centre routes name their states; the national routes name none; state codes are checked against ref.subdivisions', () => {
  const by = Object.fromEntries(facts.map((f) => [f.title.match(/through (UAC|VTAC|SATAC)/)?.[1] ?? f.title, f.states]))
  expect(by.UAC).toEqual(['AU-NSW', 'AU-ACT']); expect(by.VTAC).toEqual(['AU-VIC']); expect(by.SATAC).toEqual(['AU-SA', 'AU-NT'])
  expect(by['Apply directly to the education provider']).toBeNull(); expect(by['Apply through an education agent']).toBeNull()
  expect(code).toContain("raise exception 'post-check: state codes not in ref.subdivisions: %'")
  expect(code).toContain('alter table destination.page_facts add column if not exists state_codes text[];')
})

test('s960: the load function writes state applicability for state facts and country applicability for the rest (md5-guarded edit)', () => {
  expect(code).toContain("'a81d0f62ec5443551fe191aa704415c4'")
  expect(code).toContain("select r.id, 'state', null, sc.code, 'proven', r.source_url, r.quote_on_page, coalesce(r.last_checked_at, now())")
  expect(code).toContain('and pf.rule_category = r.rule_category and pf.title = r.title and pf.state_codes is not null);')
  expect(code).toContain('case when cardinality(f.state_codes) = 1 then f.state_codes[1] end);')
  expect(code).toContain("r.quote_on_page, r.evidence_id, r.evidence_date, r.source_url, r.last_checked_at, 'draft', r.state_code")
  expect(code).toMatch(/<> 'c34e7946cb96daa41f6195398d9385e7' then/)
})

test('s960: the four authorities are in the Layer 1 Register under Australia, not auto-ingested', () => {
  for (const d of ['studyaustralia.gov.au', 'uac.edu.au', 'vtac.edu.au', 'satac.edu.au']) expect(code).toContain(`'${d}'`)
  expect(code).toContain("30, 30, 20, 60, false, null,")
  expect(code).toContain("raise exception 'post-check: expected 4 registered sources'")
})

test('s960: the static read skips every rendered page ($0 Firecrawl) and the workbook; the workflow runs it once and reads it back', () => {
  expect(LOADER).toContain('if (scope === "static" && list.some((f) => f.read_mode === "rendered")) continue;')
  expect(LOADER).toContain('if (cfg?.jsa?.page_url && scope !== "pages" && scope !== "static") {')
  expect(LOADER).toMatch(/const VERSION = "layer1-destination-geo-loader-v1\.([6-9]|[1-9][0-9])\.[0-9]+";/)
  expect(WF).toContain("jsonb_build_object('mode', 'facts', 'scope', 'static', 'trigger', 'static_read')")
  expect(WF).toContain('[ "$REF" != "${{ vars.SUPABASE_PROJECT_REF }}" ]')
  expect(WF).not.toMatch(/edition_publish|set_terms|approval_status = 'approved'/)
})
