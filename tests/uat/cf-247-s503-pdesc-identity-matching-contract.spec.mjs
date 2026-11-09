// Guards: F-PDESC Directive 3 Blocker B (Platform Admin, 9 Nov 2026): a provider's own official page is proved by registry evidence (own verified host, catalogue name or registry abbreviation in the title, h1 or site name, no heading naming anything else); a college, an offshore branch, a sub-unit, a different institution or a third-party host is still refused; the strict proof is unchanged.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { aboutPageCheck, descriptionIdentityAliases, descriptionPageText, descriptionSourceIdentity } from '../../supabase/functions/coverage-sweep/description.ts'

const fx = (name) => fs.readFileSync(`tests/fixtures/pdesc-identity/${name}`, 'utf8')
// the worker's call: the page text, the catalogue names and the evidence the database gave it (the final address and the provider's own verified hosts)
const prove = (file, names, url, hosts, withEvidence = true) => {
  const html = fx(file)
  return descriptionSourceIdentity(html, descriptionPageText(html, 16000), names, withEvidence ? { url, hosts } : undefined)
}
const UTS = ['University of Technology Sydney (UTS)', 'University of Technology Sydney (UTS)'], UTS_AT = ['https://www.uts.edu.au/about', ['uts.edu.au']]
const SYD = ['The University of Sydney', 'The University of Sydney'], SYD_AT = ['https://www.sydney.edu.au/about-us', ['sydney.edu.au']]
const CANT = ['University of Canterbury', 'University of Canterbury'], CANT_AT = ['https://www.canterbury.ac.nz/about', ['canterbury.ac.nz']]
const CONE = ['Conestoga College', 'Conestoga College'], CONE_AT = ['https://www.conestogac.on.ca/about', ['conestogac.on.ca']]

test('registry abbreviations come from the catalogue name only; a bare shared word or a short initialism is never one', () => {
  expect(descriptionIdentityAliases(['University of Technology Sydney (UTS)'])).toEqual(['UTS'])
  expect(descriptionIdentityAliases(['The University of Newcastle (UoN), The University of Newcastle Language Centre, Sydney'])).toEqual(['UoN', 'UN'].slice(0, 1))
  expect(descriptionIdentityAliases(['The University of Melbourne (UniMelb)'])).toEqual(['UniMelb', 'UM'].slice(0, 1))
  expect(descriptionIdentityAliases(['University of Western Australia'])).toEqual(['UWA'])
  expect(descriptionIdentityAliases(['Western Sydney University'])).toEqual(['WSU'])
  // not abbreviations: a bare word of the name (Deakin College shares it), a qualifier, a two-letter initialism
  expect(descriptionIdentityAliases(['Deakin University (Deakin)'])).toEqual([])
  expect(descriptionIdentityAliases(['RMIT University (RMIT)'])).toEqual([])
  expect(descriptionIdentityAliases(["Queen's University (Belfast)"])).toEqual([])
  expect(descriptionIdentityAliases(['University of Canterbury', 'Conestoga College', 'Conestoga'])).toEqual([])
  expect(descriptionIdentityAliases(['', '  '])).toEqual([])
})

test('POSITIVE: UTS is proved on uts.edu.au when the title or site name carries the name or UTS and the h1 is generic or UTS', () => {
  for (const [file, via] of [['uts-about-uts.html', 'registry_heading_name'], ['uts-abbreviation-title.html', 'registry_heading_abbreviation'], ['uts-site-name.html', 'registry_heading_name']]) {
    const r = prove(file, UTS, ...UTS_AT)
    expect(r.ok, `${file}: ${JSON.stringify(r)}`).toBe(true)
    expect(r.rule).toBe('current_provider_name')
    expect(r.via).toBe(via)
  }
})

test('POSITIVE: Sydney, Canterbury and Conestoga are proved on their own hosts', () => {
  for (const [file, names, at, via] of [
    ['sydney-repeated-name.html', SYD, SYD_AT, 'registry_heading_name'], ['sydney-tagline.html', SYD, SYD_AT, 'registry_heading_name'],
    ['canterbury-uc.html', CANT, CANT_AT, 'registry_heading_name'], ['canterbury-opening.html', CANT, CANT_AT, 'registry_opening_statement'],
    ['conestoga-short.html', CONE, CONE_AT, 'registry_heading_name'], ['conestoga-doubled.html', CONE, CONE_AT, 'registry_heading_name'],
  ]) {
    const r = prove(file, names, ...at)
    expect(r.ok, `${file}: ${JSON.stringify(r)}`).toBe(true)
    expect(r.via).toBe(via)
  }
})

test('the strict proof is unchanged: without the registry evidence the same pages are held, and a page that passed strictly still passes the same way', () => {
  for (const [file, names] of [['uts-about-uts.html', UTS], ['canterbury-uc.html', CANT], ['conestoga-short.html', CONE], ['sydney-repeated-name.html', SYD]]) {
    expect(prove(file, names, '', [], false).ok, file).toBe(false)
  }
  // a page on a host that is not the provider's: the evidence cannot help, the strict result is returned
  const r = prove('canterbury-uc.html', CANT, 'https://www.example-ranking.com/about', ['canterbury.ac.nz'])
  expect(r).toEqual({ ok: false, rule: 'provider_name_conflict' })
  expect(prove('canterbury-uc.html', CANT, 'not a url', ['canterbury.ac.nz']).ok).toBe(false)
  expect(prove('canterbury-uc.html', CANT, 'https://www.canterbury.ac.nz/about', []).ok).toBe(false)
  const strict = '<title>About | Riverstone University</title><h1>About our university</h1><main>Riverstone University teaches science.</main>'
  const withEvidence = descriptionSourceIdentity(strict, descriptionPageText(strict, 16000), ['Riverstone University'], { url: 'https://riverstone.example/about', hosts: ['riverstone.example'] })
  expect(withEvidence).toEqual(descriptionSourceIdentity(strict, descriptionPageText(strict, 16000), ['Riverstone University']))
  expect(withEvidence).toEqual({ ok: true, rule: 'current_provider_name', matched_name: 'riverstone university' })
})

test('NEGATIVE: a different institution, a college of the group, an unrelated brand and a separate entity are refused on the provider\'s own host', () => {
  expect(prove('uts-other-university.html', UTS, ...UTS_AT)).toEqual({ ok: false, rule: 'provider_name_not_proved' })
  // the abbreviation with extra words is another entity: UTS College, UTS Insearch
  expect(prove('uts-college.html', UTS, ...UTS_AT).ok).toBe(false)
  expect(prove('uts-insearch.html', UTS, ...UTS_AT).ok).toBe(false)
  expect(prove('uts-college.html', UTS, ...UTS_AT).rule).toMatch(/^provider_name_(conflict|not_proved)$/)
  expect(prove('unrelated-brand.html', UTS, ...UTS_AT).ok).toBe(false)
  // a college page when the target is the parent (h1 and title), and the parent's page when the target is the college
  expect(prove('sydney-college-of-arts.html', SYD, ...SYD_AT).ok).toBe(false)
  expect(prove('sydney-college-title.html', SYD, ...SYD_AT).ok).toBe(false)
  expect(prove('monash-college-vs-university.html', ['Monash College'], 'https://www.monash.edu/about', ['monash.edu']).ok).toBe(false)
})

test('NEGATIVE: an offshore branch, a faculty or school source and a bare shared name are refused', () => {
  // the offshore host is one of the group\'s hosts, so only the extra entity suffix can refuse it
  expect(prove('deakin-malaysia.html', ['Deakin University (Deakin)'], 'https://www.deakin.edu.my/about', ['deakin.edu.au', 'deakin.edu.my']).ok).toBe(false)
  expect(prove('deakin-malaysia.html', ['Deakin University'], 'https://www.deakin.edu.my/about', ['deakin.edu.au', 'deakin.edu.my']).ok).toBe(false)
  expect(prove('uts-faculty-h1.html', UTS, ...UTS_AT)).toEqual({ ok: false, rule: 'provider_subunit_source' })
  expect(prove('uts-school-title.html', UTS, ...UTS_AT).ok).toBe(false)
  // a bare shared name (Deakin College shares it) and a two-letter initialism are not registry abbreviations
  expect(prove('deakin-bare.html', ['Deakin University (Deakin)'], 'https://www.deakin.edu.au/about', ['deakin.edu.au'])).toEqual({ ok: false, rule: 'provider_name_not_proved' })
  expect(prove('canterbury-bare-uc.html', CANT, ...CANT_AT)).toEqual({ ok: false, rule: 'provider_name_not_proved' })
})

test('NEGATIVE: a third-party host (ranking or news site) never proves a provider, and a body mention or a partner statement is not enough', () => {
  for (const [file, url] of [['ranking-site.html', 'https://www.topuniversities.example/universities/uts'], ['news-site.html', 'https://www.dailynews.example/uts-campus']]) {
    expect(prove(file, UTS, url, ['uts.edu.au']).ok, file).toBe(false)
    // and the page rule that runs before the identity proof refuses the address
    expect(aboutPageCheck(url, ['uts.edu.au'], ['about'], {}).rule).toBe('wrong_host')
  }
  expect(prove('body-mention-only.html', UTS, ...UTS_AT).ok).toBe(false)
  expect(prove('partner-opening.html', CANT, ...CANT_AT).ok).toBe(false)
  expect(prove('news-site.html', UTS, ...UTS_AT).ok).toBe(false)
})

test('G2: the change adds no setting, no migration and no operational number; the worker passes the lease\'s hosts and the final address', () => {
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(ix).toContain('{ url: String(rec.url || ""), hosts })')
  expect(ix).toContain('coverage-sweep-worker-v0.59.13')
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.endsWith('.sql') && f >= '20261109130000' && f < '20261109140000')).toEqual([])
})
