// Guards: F-PDESC Platform Admin directive 9-10 Nov 2026 (fix provider-description identity holds autonomously, never weaken the source checks): an official page is still proved only by the provider's own verified host plus its catalogue name or registry abbreviation as a whole title/h1/site-name segment; a heading is read as the page shows it (numeric entities decoded), and a bare institution word inside a sentence heading is not another institution's name; a different institution, a sub-unit, a lookalike or third-party host and a mention in a link stay refused.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { aboutPageCheck, decodeHeadingEntities, descriptionIdentityAliases, descriptionIdentityLabels, descriptionPageText, descriptionSourceIdentity, namesAnotherInstitution, withoutCompanyForm } from '../../supabase/functions/coverage-sweep/description.ts'

// the worker's call: the page text, the catalogue names and the evidence the database gave it (the final address and the provider's own verified hosts)
const prove = (html, names, url, hosts) => descriptionSourceIdentity(html, descriptionPageText(html, 16000), names, { url, hosts })
const page = (head, body = '') => `<!doctype html><html><head>${head}</head><body><nav><a href="/">Home</a></nav>${body}</body></html>`
const SYD = ['The University of Sydney', 'The University of Sydney'], SYD_AT = ['https://www.sydney.edu.au/about-us.html', ['sydney.edu.au']]
const UTS = ['University of Technology Sydney (UTS)', 'University of Technology Sydney (UTS)'], UTS_AT = ['https://www.uts.edu.au/about', ['uts.edu.au']]
const UQ = ['The University of Queensland', 'The University of Queensland'], UQ_AT = ['https://about.uq.edu.au/', ['uq.edu.au']]
const RMIT = ['RMIT University (RMIT)', 'RMIT University (RMIT)'], RMIT_AT = ['https://www.rmit.edu.au/about', ['rmit.edu.au']]

// Shapes read from the live pages on 10 Nov 2026 (title, headings and site-name only; short synthetic equivalents, no third-party text beyond the headings):
// Sydney: title "About us - The University of Sydney", og:site_name "The University of Sydney", og:title "About us", one h1 that is a long sentence ending "... in our university."
const sydneyPage = page(
  '<title>About us - The University of Sydney</title><meta property="og:site_name" content="The University of Sydney"/><meta property="og:title" content="About us"/>',
  '<h1>We get behind a range of activities to ensure everyone is accepted and has equal opportunities when it comes to education and employment in our university.</h1><h2>About us</h2><p>We make lives better by producing leaders of society.</p>')
// UTS: title and og:title "About UTS &#x2013; University of Technology Sydney" (numeric entity), h1 "About UTS", a main element, an opening paragraph
const utsPage = (dash) => page(`<title>About UTS ${dash} University of Technology Sydney</title><meta property="og:title" content="About UTS ${dash} University of Technology Sydney" />`,
  '<main><h1>About UTS</h1><p>As Australia\'s #1 young university, we thrive in the heart of central Sydney.</p></main>')
// UQ: on the sub-domain about.uq.edu.au; title "About UQ - The University of Queensland - Create change", h1 "About"
const uqPage = page('<title>About UQ - The University of Queensland - Create change</title><meta property="og:title" content="About"/>', '<main><h1>About</h1><p>UQ is one of Australia\'s leading universities.</p></main>')

test('decodeHeadingEntities decodes numeric and the common named entities, and leaves anything else exactly as printed', () => {
  expect(decodeHeadingEntities('About UTS &#x2013; University')).toBe('About UTS – University')
  expect(decodeHeadingEntities('About UTS &#8211; University')).toBe('About UTS – University')
  expect(decodeHeadingEntities('Queen&#8217;s University &amp; College')).toBe('Queen’s University & College')
  expect(decodeHeadingEntities('A&nbsp;B &ndash; C &mdash; D')).toBe('A B – C — D')
  expect(decodeHeadingEntities('&unknownthing; &#0; &#xD800; &#1114112; &#; &#x;')).toBe('&unknownthing; &#0; &#xD800; &#1114112; &#; &#x;')
  expect(decodeHeadingEntities('')).toBe('')
})

test('namesAnotherInstitution: a name is a capitalised word before the institution word, or "of" and a capitalised word; a bare word in a sentence is not', () => {
  for (const named of ['Western Sydney University', 'Welcome to Griffith University', 'University of Melbourne', 'University Of Melbourne', 'College of Arts', 'Murdoch College Open Day', 'In partnership with the University of New South Wales', 'Sydney Institute of Technology', 'Monash College']) {
    expect(namesAnotherInstitution(named), named).toBe(true)
  }
  for (const plain of ['We get behind a range of activities to ensure everyone is accepted in our university.', 'About our university', 'Study at our college', 'We are a leading university with heart', 'The institute for everyone']) {
    expect(namesAnotherInstitution(plain), plain).toBe(false)
  }
  // no case to read: the old rule stands, the bare word is refused
  expect(namesAnotherInstitution('WELCOME TO OUR UNIVERSITY')).toBe(true)
  expect(namesAnotherInstitution('welcome to murdoch university')).toBe(true)
  expect(namesAnotherInstitution('')).toBe(false)
})

test('POSITIVE: The University of Sydney (live shape 10 Nov 2026) is proved: a sentence h1 containing "university" no longer vetoes a title and site name that name the provider', () => {
  const r = prove(sydneyPage, SYD, ...SYD_AT)
  expect(r).toEqual({ ok: true, rule: 'current_provider_name', matched_name: 'university of sydney', via: 'registry_heading_name' })
})

test('POSITIVE: UTS (live shape 10 Nov 2026) is proved with the title as the page prints it, hex or decimal, and with the dash decoded already', () => {
  for (const dash of ['&#x2013;', '&#8211;', '&ndash;', '–', '-']) {
    const r = prove(utsPage(dash), UTS, ...UTS_AT)
    expect(r.ok, `${dash}: ${JSON.stringify(r)}`).toBe(true)
    expect(r.rule).toBe('current_provider_name')
  }
})

test('POSITIVE: UQ is proved on its official sub-domain about.uq.edu.au (host allowance is the provider\'s verified host or a sub-domain of it); RMIT on its own host', () => {
  expect(prove(uqPage, UQ, ...UQ_AT).ok).toBe(true)
  expect(aboutPageCheck('https://about.uq.edu.au/about', ['uq.edu.au'], ['about'], {})).toEqual({ ok: true, rule: 'about_page', main: false })
  expect(aboutPageCheck('https://www.uq.edu.au/about', ['uq.edu.au'], ['about'], {})).toEqual({ ok: true, rule: 'about_page', main: true })
  // RMIT: a synthetic equivalent of the usual shape (the catalogue name carries the bare shared word in a parenthetical, which is not an alias)
  const rmit = page('<title>About RMIT | RMIT University</title>', '<main><h1>About RMIT</h1><p>RMIT is a global university of technology, design and enterprise.</p></main>')
  expect(prove(rmit, RMIT, ...RMIT_AT).ok).toBe(true)
})

test('POSITIVE: a curly apostrophe printed as an entity matches the catalogue name', () => {
  const html = page('<title>About Queen&#8217;s University | Queen&#8217;s University</title>', '<main><h1>About us</h1></main>')
  expect(prove(html, ["Queen's University", "Queen's University"], 'https://www.queensu.example/about', ['queensu.example']).ok).toBe(true)
})

test('NEGATIVE: a different institution named in a heading of the page is still a conflict, in a sentence or not', () => {
  for (const h1 of ['Welcome to Western Sydney University', 'In partnership with the University of New South Wales', 'Murdoch College Open Day', 'Part of the Navitas Institute group']) {
    const html = page('<title>About us - The University of Sydney</title><meta property="og:site_name" content="The University of Sydney"/>', `<h1>${h1}</h1>`)
    expect(prove(html, SYD, ...SYD_AT), h1).toEqual({ ok: false, rule: 'provider_name_conflict' })
  }
  // the title names another institution and no heading names the provider
  const t = page('<title>About us - Western Sydney University</title>', '<h1>Our story</h1><p>The University of Sydney is mentioned here once.</p>')
  expect(prove(t, SYD, ...SYD_AT).ok).toBe(false)
})

test('NEGATIVE: sub-unit words are not relaxed: a faculty, school or campus heading is refused wherever it occurs, for the wrong provider too', () => {
  const faculty = page('<title>Faculty of Law - University of Technology Sydney</title>', '<main><h1>Faculty of Law</h1></main>')
  expect(prove(faculty, UTS, ...UTS_AT)).toEqual({ ok: false, rule: 'provider_subunit_source' })
  const sentence = page('<title>About us - The University of Sydney</title>', '<h1>We take students from school to career at our university.</h1>')
  expect(prove(sentence, SYD, ...SYD_AT).ok).toBe(false)
  const campus = page('<title>About us - The University of Sydney</title>', '<h1>Camperdown Campus</h1>')
  expect(prove(campus, SYD, ...SYD_AT)).toEqual({ ok: false, rule: 'provider_subunit_source' })
  // another provider's college of the same group stays refused
  const college = page('<title>About - Sydney College of the Arts</title><meta property="og:site_name" content="Sydney College of the Arts"/>', '<h1>Sydney College of the Arts</h1>')
  expect(prove(college, SYD, ...SYD_AT).ok).toBe(false)
})

test('NEGATIVE: no case to read keeps the old refusal; entity decoding never turns a different name into a match', () => {
  for (const h1 of ['WELCOME TO MONASH UNIVERSITY', 'welcome to monash university']) {
    const caps = page('<title>About us - The University of Sydney</title>', `<h1>${h1}</h1>`)
    expect(prove(caps, SYD, ...SYD_AT), h1).toEqual({ ok: false, rule: 'provider_name_conflict' })
  }
  const other = page('<title>About UTS &#x2013; Other University of Technology</title>', '<main><h1>About UTS</h1></main>')
  expect(prove(other, UTS, ...UTS_AT).ok).toBe(false)
})

test('NEGATIVE: the provider\'s name only in a link or in the body is not an identity proof', () => {
  const link = page('<title>About us</title>', '<main><h1>Our story</h1><p>Read <a href="https://example.test/">about The University of Sydney</a> and its partners.</p></main>')
  expect(prove(link, SYD, ...SYD_AT).ok).toBe(false)
  expect(prove(link, SYD, ...SYD_AT).rule).toMatch(/^provider_name_(conflict|not_proved)$/)
  const nav = page('<title>About us</title>', '<h1>Who we are</h1><footer><a href="/">The University of Sydney</a></footer>')
  expect(prove(nav, SYD, ...SYD_AT).ok).toBe(false)
})

test('NEGATIVE: a wrong, lookalike or redirected host never proves a provider, however the headings read; the sub-domain rule is the provider\'s own registrable host only', () => {
  for (const url of ['https://www.unsw.edu.au/about', 'https://sydney.edu.au.example.test/about', 'https://notsydney.edu.au/about', 'https://sydney-edu.au/about', 'https://example.test/sydney.edu.au/about', 'ftp://www.sydney.edu.au/about', 'not a url']) {
    const r = prove(sydneyPage, SYD, url, ['sydney.edu.au'])
    expect(r.ok, url).toBe(false)
    expect(aboutPageCheck(url, ['sydney.edu.au'], ['about-us'], {}).ok, url).toBe(false)
  }
  // no verified host from the lease: only the strict proof applies and it refuses
  expect(prove(sydneyPage, SYD, SYD_AT[0], []).ok).toBe(false)
  // a genuine sub-domain of the verified host is allowed by the same rule the About-page rule uses
  expect(aboutPageCheck('https://about.uq.edu.au/about', ['uq.edu.au'], ['about'], {}).ok).toBe(true)
  expect(aboutPageCheck('https://uq.edu.au.example.test/about', ['uq.edu.au'], ['about'], {}).rule).toBe('wrong_host')
})

test('withoutCompanyForm drops only a trailing company form and never leaves fewer than two words; the labels and abbreviations are derived from the catalogue name only', () => {
  expect(withoutCompanyForm('Helix College Pty Ltd')).toBe('Helix College')
  expect(withoutCompanyForm('Imperial College of New Zealand Limited')).toBe('Imperial College of New Zealand')
  expect(withoutCompanyForm('SIGNATURE TRAINING PTY. LTD.')).toBe('SIGNATURE TRAINING')
  expect(withoutCompanyForm('Edvantage Institute Australia Pty Ltd')).toBe('Edvantage Institute Australia')
  expect(withoutCompanyForm('Learner Me 2018 Limited')).toBe('Learner Me 2018')
  expect(withoutCompanyForm('Pivot Pty Ltd')).toBe('Pivot Pty Ltd')          // one word would be left: kept whole
  expect(withoutCompanyForm('Limited Edition College')).toBe('Limited Edition College')   // only a trailing form
  expect(withoutCompanyForm('Monash University')).toBe('Monash University')
  expect(descriptionIdentityLabels(['Helix College Pty Ltd'])).toEqual(['Helix College Pty Ltd', 'Helix College'])
  expect(descriptionIdentityLabels(['Monash University', 'Monash University'])).toEqual(['Monash University', 'Monash University'])
  expect(descriptionIdentityAliases(['Engineering Institute of Technology Pty Ltd'])).toEqual(['EIT'])
  expect(descriptionIdentityAliases(['Helix College Pty Ltd'])).toEqual([])   // two capitalised words: no abbreviation of fewer than three letters
})

test('POSITIVE: a registered company name is proved by the trading name the page prints (live shapes Helix College and Thames International College, 10 Nov 2026)', () => {
  // Helix: title "About Helix College | Courses in Melbourne VIC &amp; Australia", og:site_name "Helix College", h1 "About Us"
  const helix = page('<title>About Helix College | Courses in Melbourne VIC &amp; Australia</title><meta property="og:site_name" content="Helix College"/>', '<main><h1>About Us</h1><p>Helix College is a registered training organisation.</p></main>')
  expect(prove(helix, ['Helix College Pty Ltd', 'Helix College Pty Ltd'], 'https://helixcollege.edu.au/about-us/', ['helixcollege.edu.au'])).toEqual({ ok: true, rule: 'current_provider_name', matched_name: 'helix college', via: 'registry_heading_name' })
  // Thames: title "About us &#8211; Thames International College" (numeric entity), h1 an unrelated widget heading
  const thames = page('<title>About us &#8211; Thames International College</title>', '<main><h1>Follow Us On Instagram</h1><p>Thames International College offers courses in Sydney.</p></main>')
  const r = prove(thames, ['Thames International College Pty Ltd', 'Thames International College Pty Ltd'], 'https://thames.edu.au/about-us/', ['thames.edu.au'])
  expect(r.ok, JSON.stringify(r)).toBe(true)
  // the same pages are still held when the catalogue name is a different institution, or the host is not the provider's
  expect(prove(helix, ['Helix Institute Pty Ltd', 'Helix Institute Pty Ltd'], 'https://helixcollege.edu.au/about-us/', ['helixcollege.edu.au']).ok).toBe(false)
  expect(prove(helix, ['Helix College Pty Ltd'], 'https://helix-college.example.test/about-us/', ['helixcollege.edu.au']).ok).toBe(false)
})

test('NEGATIVE: dropping the company form never widens the match: extra words in the heading, a one-word name and another entity are still refused (live shape Brighton College Australia)', () => {
  // Brighton: catalogue "Brighton College Pty Ltd", page title "About Us | Brighton College Australia" -> "Australia" is an extra word, held as before
  const brighton = page('<title>About Us | Brighton College Australia</title>', '<main><h1>About Us</h1></main>')
  expect(prove(brighton, ['Brighton College Pty Ltd'], 'https://brighton.edu.au/about-us/', ['brighton.edu.au']).ok).toBe(false)
  // a one-word trading name is not enough to prove anything
  const pivot = page('<title>About Pivot</title><meta property="og:site_name" content="Pivot"/>', '<main><h1>About Pivot</h1></main>')
  expect(prove(pivot, ['Pivot Pty Ltd'], 'https://pivot.example.test/about', ['pivot.example.test']).ok).toBe(false)
  // an offshore or group entity with the trading name inside it
  const offshore = page('<title>About Helix College International | Helix College</title>', '<main><h1>About us</h1></main>')
  expect(prove(offshore, ['Helix College Pty Ltd'], 'https://helixcollege.edu.au/about-us/', ['helixcollege.edu.au']).ok).toBe(false)
})

test('contract: worker v0.59.15 stamps provider-description-source-guard-v3 (the existing re-offer reads earlier holds again); no migration, no setting and no operational number', () => {
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const ds = fs.readFileSync('supabase/functions/coverage-sweep/description.ts', 'utf8')
  expect(ix).toContain('const WORKER = "coverage-sweep-worker-v0.59.15"; // v0.59.15 (10 Nov 2026, CF-247 F-PDESC')
  expect(ix).toContain('reader_behavior_version: "provider-description-source-guard-v3" };')
  expect(ix).not.toContain('provider-description-source-guard-v2" }')
  expect(ix).toContain('descriptionSourceIdentity(html, page,')
  // the only literal limit is the Unicode range, marked fixed
  expect(ds).toMatch(/\/\/ fixed: Unicode limit; anything outside it is left as printed\n\s+return Number\.isInteger\(cp\) && cp > 0 && cp <= 0x10ffff/)
  // the strict proof is not edited by this change, and the page text the model reads is not decoded
  const strict = ds.slice(ds.indexOf('function strictSourceIdentity'), ds.indexOf('// v0.59.13 (CF-247 F-PDESC, Platform Admin Directive 3, Blocker B)'))
  expect(strict).not.toContain('decodeHeadingEntities')
  expect(ds.slice(ds.indexOf('export function descriptionPageText'), ds.indexOf('// the letters of an abbreviation'))).not.toContain('decodeHeadingEntities')
  // sub-unit words are checked outside the relaxed test
  expect(ds).toContain('if (IDENTITY_SUBUNIT.test(w) || namesAnotherInstitution(seg)) return fail(')
})

test('NEGATIVE (QA #975 defects 1-4): "University of the X", possessive and hyphenated names still count as another institution; the strict proof keeps its pre-v0.59.15 labels; very long names are not run through the company-form pattern', () => {
  for (const h1 of ['University of the Sunshine Coast', 'Part of the University of the South Pacific', 'Institute of the Arts', 'Monash University’s story', "Welcome to Monash University's home", 'Griffith-University news']) {
    const html = page('<title>About us - The University of Sydney</title><meta property="og:site_name" content="The University of Sydney"/>', `<h1>${h1}</h1>`)
    expect(prove(html, SYD, ...SYD_AT), h1).toEqual({ ok: false, rule: 'provider_name_conflict' })
  }
  expect(namesAnotherInstitution('Our university is a place to learn')).toBe(false)
  // the strict (no segment rules) proof does not use the company-form-free label
  expect(descriptionIdentityLabels(['Pacific College Pty Ltd'], false)).toEqual(['Pacific College Pty Ltd'])
  expect(descriptionIdentityLabels(['Pacific College Pty Ltd'])).toContain('Pacific College')
  // a pathological name returns at once and unchanged
  const long = ('a, ' .repeat(30000)) + 'Ltdx'
  const t0 = Date.now()
  expect(withoutCompanyForm(long)).toBe(long.replace(/\s+/g, ' ').trim())
  expect(Date.now() - t0).toBeLessThan(500)
})
