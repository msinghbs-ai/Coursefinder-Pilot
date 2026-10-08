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
  expect(worker).toContain('const VERSION = "scholarships-au-etl-v0.2.0";')
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
  expect(c).toContain('const VERSION="layer1-operations-control-v1.7.0";')
  expect(c).toContain('if(system==="SCHOLARSHIP_REGISTER")return validateScholarshipRegister(')
  expect(c).toContain('if(system==="SCHOLARSHIP_REGISTER"){const code=String(ctx.source?.metadata?.register_code||"")')
  const s = fs.readFileSync('supabase/functions/layer1-operations-scheduled/index.ts', 'utf8')
  expect(s).toContain('const VERSION="layer1-operations-scheduled-v1.3.0"')
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
