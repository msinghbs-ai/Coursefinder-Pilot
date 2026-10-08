import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { transformSync } from 'esbuild'

// CF-247 Scholarships (8 Oct 2026): central register, country tagged, on Layer 1.
// Decisions: "Central register, country tagged"; "Record for govt, index for provider"; "AU, then NZ, then CA, monthly".

const worker = fs.readFileSync('supabase/functions/scholarships-au-etl/index.ts', 'utf8')

// Load the listing parser straight from the worker source (no network, no Deno): TypeScript stripped by esbuild.
function loadParsers() {
  const pick = (name) => {
    const start = worker.indexOf(name)
    if (start < 0) throw new Error(`missing ${name}`)
    const line = worker.slice(start, worker.indexOf('\n', start))
    const balance = (t) => (t.match(/\{/g) || []).length - (t.match(/\}/g) || []).length
    if (balance(line) === 0) return line
    return worker.slice(start, worker.indexOf('\n}', start) + 2)
  }
  const ts = [
    pick('const clean = '), pick('function decodeHtml('), pick('function htmlLines('), pick('const htmlText = '),
    pick('function absolute('), pick('type Listing='), pick('const cardText='),
    pick('export function parseStudyListingPage('), pick('export function studyListingTotal('),
    pick('export function studyListingLastPage('), pick('export function parseVisitWebsite('),
  ].join('\n').replace(/^export /gm, '')
  const js = transformSync(ts, { loader: 'ts' }).code
  return new Function(`${js}; return { parseStudyListingPage, studyListingTotal, studyListingLastPage, parseVisitWebsite };`)()
}

const svg = '<svg width="16" height="16" viewbox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg" class="me-2 self-center" alt role="presentation"><path d="M10 4.66675H6" stroke="currentColor"></path></svg>'
const card = (id, name, prov, provId, fields) => `<div class="scholarship-list-card"><div class="block md:flex"><div class="me-4"><div class="mb-3"><a tabindex="-1" href="/provider/x/${provId}"><img src="https://d1vcqlflm6aitx.cloudfront.net/images/original/00246M-myhc_254498.jpg" alt="${prov}"></a></div></div><div><h3 class="font-au-sans-regular text-xl"><!--[--><strong><!--[--><a href="/scholarship/s/${id}" class="border-none">${name}</a><!--]--></strong><!--]--></h3><!--[--><strong><a href="/provider/x/${provId}" class="border-none inline-block my-1" aria-label="Scholarship provider ${prov}">${prov}</a></strong><!--]--><!--[-->${fields}<!--]--><ul><li><a role="link" href="/scholarship/s/${id}/enquiry"> Enquire </a></li></ul></div></div><hr></div>`
const page = `<h2 class="font-au-sans-regular text-3xl mb-6 font-bold"><!--[--> Showing 1172 scholarships<!--]--></h2>`
  + card('e85badd3c8b6c51507bb520bf5c40480', 'Australian Industrial Relations Commission (AIRC) Centennial Prize', 'The University of Melbourne', '86a2923f5df9c3208070ae2ebc22b9a9',
    `<p class="text-sm mb-2">${svg}Award value - AUD $1,000 annually </p><p class="text-sm mb-2">${svg}Level of study - Postgraduate, Undergraduate / VET</p><!----><p class="text-sm mb-2">${svg}Closing date - 6 Dec 2026</p>`)
  + card('47e9e0dfaba68a6e9d2ef32c6bc81a3e', 'Japanese Undergraduate Health Science', 'Think Education', '786951af2c999d9c66f3bb2948440037',
    `<!----><p class="text-sm mb-2">${svg}Level of study - Postgraduate, Undergraduate / VET</p><p class="text-sm mb-2">${svg}Nationality - Japan</p><!---->`)
  + card('f73ec300f90be6735ac6214c95f2d743', 'Americas &amp; European Health Scholarship', 'Think Education', '786951af2c999d9c66f3bb2948440037',
    `<!----><p class="text-sm mb-2">${svg}Level of study - Postgraduate, Undergraduate / VET</p><!----><!---->`)
  + `<a aria-label="Page 2" href="/scholarships?page=2">2</a><a aria-label="Last page" href="/scholarships?page=118">118</a>`

test('Study Australia listing cards: id, name, provider, value, level, closing date, nationality', () => {
  const p = loadParsers()
  const rows = p.parseStudyListingPage('https://search.studyaustralia.gov.au/scholarships?page=1', page)
  expect(rows).toHaveLength(3)
  expect(rows[0]).toEqual({
    id: 'e85badd3c8b6c51507bb520bf5c40480',
    url: 'https://search.studyaustralia.gov.au/scholarship/s/e85badd3c8b6c51507bb520bf5c40480',
    name: 'Australian Industrial Relations Commission (AIRC) Centennial Prize',
    provider_ref: '86a2923f5df9c3208070ae2ebc22b9a9', provider_name: 'The University of Melbourne',
    level: 'Postgraduate, Undergraduate / VET', award: 'AUD $1,000 annually', closing: '6 Dec 2026', nationality: null,
  })
  expect(rows[1].nationality).toBe('Japan')
  expect(rows[1].award).toBeNull()
  expect(rows[2].name).toBe('Americas & European Health Scholarship')
  expect(p.studyListingTotal(page)).toBe(1172)
  expect(p.studyListingLastPage(page)).toBe(118)
  const detail = '<li class="h-fit mb-0"><a role="link" data="Royal Greenhill Institute of Technology (RGIT) Australia" target="_blank" href="http://rgit.edu.au/students/international/scholarship" class="inline-block"><!--[--> Visit website <!--]--></a></li>'
  expect(p.parseVisitWebsite(detail)).toBe('http://rgit.edu.au/students/international/scholarship')
})

test('register worker: whole listing read, raw pages kept, stable hash, Layer 1 service authority', () => {
  expect(worker).toContain('const VERSION = "scholarships-au-etl-v0.3.1";')
  expect(worker).toContain('if(listings.length<Math.floor(total*0.98)) throw new Error(')
  expect(worker).toContain('const listings=[...seen.values()].sort((a,b)=>a.id.localeCompare(b.id));')
  expect(worker).toContain('pages:r.pages.map(p=>({url:p.url,sha256:p.hash,html:p.html}))')
  expect(worker).toContain('internal===serviceKey')
  expect(worker).toContain('svc_scholarship_register_save')
  expect(worker).toContain('svc_scholarship_register_detail_save')
  // the old provider-record path for Study Australia is not used by the register
  expect(worker).toMatch(/if\(feed==="study_australia_register"\)\{[\s\S]*?return reply\(\{ok:true,workerVersion:VERSION,mode,feed,phase:"detail"/)
})

test('Layer 1 run controller and scheduler dispatch the scholarship registers', () => {
  const c = fs.readFileSync('supabase/functions/layer1-operations-control/index.ts', 'utf8')
  expect(c).toContain('const VERSION="layer1-operations-control-v1.7.1";')
  expect(c).toContain('if(system==="SCHOLARSHIP_REGISTER")return validateScholarshipRegister(')
  expect(c).toContain('if(system==="SCHOLARSHIP_REGISTER"){const code=String(ctx.source?.metadata?.register_code||"")')
  const s = fs.readFileSync('supabase/functions/layer1-operations-scheduled/index.ts', 'utf8')
  expect(s).toContain('const VERSION="layer1-operations-scheduled-v1.3.1"')
  expect(s).toContain('if(system==="SCHOLARSHIP_REGISTER"){')
  const wf = fs.readFileSync('.github/workflows/deploy-edge-functions.yml', 'utf8')
  expect(wf).toContain('[scholarships-au-etl]=false')
})

test('register migration: country tagged, index hands off to the page reader, nothing deleted, no schedule switched on', () => {
  const m = fs.readFileSync('supabase/migrations/20261008004500_cf247_scholarship_central_register.sql', 'utf8')
  expect(m).toContain("role text not null check (role in ('record','index'))")
  expect(m).toContain("country_code char(2) not null")
  expect(m).toContain("('au_study_australia','AU',")
  expect(m).toContain("('nz_mfat_manaaki','NZ',")
  expect(m).toContain("('ca_gac_study_in_canada','CA',")
  expect(m).toContain("'source_system','SCHOLARSHIP_REGISTER'")
  expect(m).toContain("insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, title, source)")
  expect(m).toContain("security.url_on_provider_sites(l.website_url, l.provider_id)")
  expect(m).not.toMatch(/delete\s+from/i)
  expect(m).not.toMatch(/update\s+scholarship\.scholarships/i)
  // the schedule is set afterwards by a Platform Admin; auto ingest starts off
  expect(m).toMatch(/'scholarship listings',true,false,30,30,false,/)
  expect(m).toContain("where feed in ('study_australia','australia_awards');")
})

test('register hand-off uses the candidate source "register" (md5-guarded replace)', () => {
  const m = fs.readFileSync('supabase/migrations/20261008004600_cf247_scholarship_register_candidate_source.sql', 'utf8')
  expect(m).toContain("<> 'ff5eb351f07c7f61df6e9bb12f9641e6' then")
  expect(m).toContain("check (source = any (array['sitemap'::text, 'map'::text, 'search'::text, 'register'::text]))")
  expect(m).toContain("left(t.name, 300), 'register'")
  expect(m).not.toMatch(/delete\s+from/i)
})

test('register hand-off writes each provider page candidate once per batch (md5-guarded replace)', () => {
  const m = fs.readFileSync('supabase/migrations/20261008004700_cf247_scholarship_register_handoff_once.sql', 'utf8')
  expect(m).toContain("<> '1de473b90e9844055ed23758d3e4a728' then")
  expect(m).toContain('select distinct on (t.provider_id, security.scholarship_url_norm(t.website_url))')
  expect(m).not.toMatch(/delete\s+from/i)
})


test('New Zealand Manaaki register: regions, countries, levels, approved institutions, rounds read from the pages', () => {
  const pick = (name) => {
    const start = worker.indexOf(name)
    if (start < 0) throw new Error(`missing ${name}`)
    const line = worker.slice(start, worker.indexOf('\n', start))
    const b = (t) => (t.match(/\{/g) || []).length - (t.match(/\}/g) || []).length
    if (b(line) === 0) return line
    return worker.slice(start, worker.indexOf('\n}', start) + 2)
  }
  const ts = [pick('const clean = '), pick('function decodeHtml('), pick('const months:'), pick('function parseDateOnly('), pick('export function splitTopLevel('),
    pick('export function manaakiCountries('), pick('export function manaakiRegions('), pick('export function manaakiInstitutions('),
    pick('const MONTHS='), pick('export function manaakiWindows(')].join('\n').replace(/^export /gm, '')
  const p = new Function(`${transformSync(ts, { loader: 'ts' }).code}; return { manaakiRegions, manaakiInstitutions, manaakiWindows }`)()
  const countries = "Select a region to find out if your country is eligible. 01 Eligible Pacific Countries Citizens from eligible countries in the Pacific have two tertiary scholarship options. Eligible scholars can choose to study at a New Zealand or Pacific tertiary education institute. Note: Cook Island scholars have their own scholarship managed by the Cook Islands Ministry of Education and funded by the New Zealand Government Note: Tokelau scholars are currently only eligible to apply for Short Term Training Scholarships Option 1: Scholarships to study in New Zealand Eligible Pacific countries: Fiji (postgraduate only), French Pacific (New Caledonia, French Polynesia, Wallis and Futuna), Kiribati, Naoero, Niue, North Pacific (Federated States of Micronesia, Palau, Marshall Islands), Papua New Guinea, Samoa, Solomon Islands, Tonga, Tuvalu, Vanuatu Levels of study available: Undergraduate Degree (3-4 years) Postgraduate Certificate (6 months) Postgraduate Diploma (1 year) Master’s Degree (1-2 years) PhD (3.5 years) Expected start dates: We aim for Pacific scholars to commence study in semester 1 the year after they submitted their scholarship application. Option 2: Scholarships to study at a Pacific university Eligible Pacific countries: Kiribati, Niue, Samoa, Solomon Islands, Tonga, Tuvalu, Vanuatu. Levels of study available: You can study these qualifications at one of two universities in Fiji: Undergraduate Degree (3-4 years) Postgraduate Certificate (6 months) Postgraduate Diploma (1 year) Master’s Degree (1-2 years) PhD (3.5 years) Expected start dates: We aim for Pacific scholars to commence study from Semester 1 the year after they submitted their application. We only accept applications from citizens from eligible countries If your country is not on this page, you can research scholarships from other New Zealand organisations NEXT: / 02 Eligible Asian Countries Cambodia, Indonesia, Lao PDR, Malaysia, Nepal, Philippines, Thailand, Timor-Leste, Viet Nam Levels of study available: Undergraduate Degree (3-4 years) (Timor-Leste only) Postgraduate Certificate (6 months) Postgraduate Diploma (1 year) Master’s Degree (1-2 years) PhD (3.5 years) Expected start dates: We aim for scholars to commence study from Semester 1, the year after they submit their application. We only accept applications from citizens from eligible countries. NEXT: If you are from an eligible country"
const instTextUnused = "Eight available universities QS World University Rankings ranks New Zealand universities in the top 3%. New Zealand universities rank in the world's top 100 in over 30 subjects. Auckland University of Technology Lincoln University Massey University University of Auckland University of Canterbury University of Otago University of Waikato Victoria University of Wellington Two available institutes of technology New Zealand's institutes of technology are world class. They provide high-quality qualifications and training that focus on practical skills and hands-on experience. Southern Institute of Technology Unitec Institute of Technology Eligible Pacific citizens can choose to study at a Pacific university Citizens from eligible Pacific countries can also study at one of two approved Pacific universities. University of South Pacific Fiji National University Do more"
const apply = "Select your region to find the application process for your country. Applications for Samoa Foundation open midnight 4 August 2026 and close midday 4 September 2026 Applicants for a Manaaki Scholarship are required"
  const inst = '<p>Eight available universities</p><p>QS ranks...</p><div><ul><li><a href="https://www.aut.ac.nz/">Auckland University of Technology</a></li><li><a href="http://www.lincoln.ac.nz/">Lincoln University</a></li><li><a href="https://www.victoria.ac.nz/">Victoria University of Wellington</a></li></ul></div><p><b>Two available institutes of technology</b></p><p>world class</p><ul><li><a href="https://www.sit.ac.nz/">Southern Institute of Technology</a></li><li><a href="https://www.unitec.ac.nz/">Unitec Institute of Technology</a></li></ul><p>Citizens can also study at one of two approved Pacific universities.</p><ul><li><a href="https://www.usp.ac.fj/">University of the South Pacific</a></li><li><a href="https://www.fnu.ac.fj/">Fiji National University</a></li></ul>'
  const regions = p.manaakiRegions(countries)
  expect(regions.map(r => [r.region, r.destination, r.countries.length])).toEqual([
    ['Pacific', 'Scholarships to study in New Zealand', 16],
    ['Pacific', 'Scholarships to study at a Pacific university', 7],
    ['Asian', 'Scholarships to study in New Zealand', 9],
  ])
  expect(regions[0].countries[0]).toEqual({ country: 'Fiji', group: null, note: 'postgraduate only' })
  expect(regions[0].countries[1]).toEqual({ country: 'New Caledonia', group: 'French Pacific', note: null })
  expect(regions[2].levels.map(l => l.level)).toEqual(['Undergraduate Degree', 'Postgraduate Certificate', 'Postgraduate Diploma', 'Master’s Degree', 'PhD'])
  expect(regions[2].levels[0].note).toBe('Timor-Leste only')
  const i = p.manaakiInstitutions(inst)
  expect(i.new_zealand).toEqual(['Auckland University of Technology', 'Lincoln University', 'Victoria University of Wellington', 'Southern Institute of Technology', 'Unitec Institute of Technology'])
  expect(i.pacific).toEqual(['University of the South Pacific', 'Fiji National University'])
  expect(i.universities[0].website).toBe('https://www.aut.ac.nz/')
  expect(p.manaakiWindows(apply)).toEqual([{ label: 'Samoa Foundation', opens: '2026-08-04', closes: '2026-09-04', quote: 'Applications for Samoa Foundation open midnight 4 August 2026 and close midday 4 September 2026' }])
  // fails loudly rather than storing an empty record
  expect(worker).toContain('if(!regions.length||countries.length<5) throw new Error(')
  expect(worker).toContain('if(inst.new_zealand.length<5) throw new Error(')
  const m = fs.readFileSync('supabase/migrations/20261008004800_cf247_scholarship_register_nz_manaaki.sql', 'utf8')
  expect(m).toContain("'register_code','nz_mfat_manaaki'")
  expect(m).toContain("array['nzscholarships.govt.nz']")
  expect(m).not.toMatch(/delete\s+from/i)
})

test('government awards: nationalities from the register, institutions by official website, guarded patches, nothing published', () => {
  const m = fs.readFileSync('supabase/migrations/20261008004900_cf247_scholarship_government_awards.sql', 'utf8')
  // stops rather than storing a partial nationality list
  expect(m).toContain("raise exception 'register % lists countries without a nationality code: %'")
  // institutions matched by website (or where it redirects), never by name
  expect(m).toContain("security.url_base_host(p.website) in (security.url_base_host(i->>'website'), security.url_base_host(i->>'final_website'))")
  expect(m).toContain("sl.code in ('bachelor','masters','doctorate') or (sl.code in ('diploma','certificate') and c.canonical_title ~* '\\mpost ?graduate\\M')")
  // each live function patched only if it is exactly the expected version
  expect(m).toContain("'c855a8ed523e39470529f1def62db833'")
  expect(m).toContain("'aa0d0f35d70d99a20ff7522bf4edb4aa'")
  expect(m).toContain("'5fa8ee54af103bf126e96ccfcf416a5c'")
  expect(m).toContain("coverage_type='tuition_fees' and cv.percentage=100")
  expect(m).toContain("coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required'")
  expect(m).not.toMatch(/delete\s+from/i)
  expect(m).not.toMatch(/publication_status\s*=/i)
  expect(m).toContain("'(?<!New )(?<!Equatorial )(?<!Papua New )Guinea(?!-Bissau)'")
  expect(worker).toContain('(x as any).final_website=await landing(x.website);')
  expect(worker).toContain('svc_scholarship_register_record_profile')
})

test('country onboarding: AU, NZ, CA only; new countries trigger a readiness alert; switch on only when ready', () => {
  const m = fs.readFileSync('supabase/migrations/20261008005000_cf247_scholarship_country_onboarding.sql', 'utf8')
  expect(m).toContain("update ref.countries set scholarship_ingestion_enabled = false where scholarship_ingestion_enabled and iso_alpha2 not in ('AU','NZ','CA');")
  expect(m).toContain("status text not null check (status in ('enabled','watch'))")
  expect(m).toContain("('uk_fcdo_chevening','GB'")
  expect(m).toContain("('us_fulbright_foreign_student','US'")
  // the daily watch raises one platform issue per country and resolves it itself
  expect(m).toContain("'scholarship_country:' || r.country_code, 'warning', 'scholarships'")
  expect(m).toContain("check_key like 'scholarship_country:%' and not (check_key = any(v_keys))")
  expect(m).toContain("select cron.schedule('scholarship-country-watch', '13 19 * * *', 'select security.scholarship_country_watch_v1()');")
  // switching on is a Platform Admin step, refused until ready, and queues discovery
  expect(m).toContain("if p_on and not r.ready then raise exception 'country % is not ready: %'")
  expect(m).toContain('security.scholarship_discovery_refill_v1(30 + coalesce(r.universities, 0)::int)')
  // the two hard-wired country lists become data-driven, guarded by md5
  expect(m).toContain("'643f0224c501380348763c42cc466473'")
  expect(m).toContain("'6c85cb74ea3b00bc45e385f6c278dc08'")
  expect(m).toContain("$a$c.iso_alpha2 <> 'AU' and c.scholarship_ingestion_enabled$a$")
  expect(m).toContain("from scholarship.country_onboarding o where o.country_code = t.cc and coalesce(o.domestic_terms, '') <> ''")
  expect(m).not.toMatch(/delete\s+from/i)
  expect(m).not.toMatch(/publication_status\s*=/i)
})
