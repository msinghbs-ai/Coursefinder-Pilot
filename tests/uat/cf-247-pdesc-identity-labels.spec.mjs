// Guards: Platform Admin follow-up 10 Nov 2026 (provider-description identity, worker v0.63.0): a catalogue name that is a list derives a later entity as a label only when it is the full name of a bare short first entity (Holmesglen); a quoted-sentence h1 is a pull-quote only when it names no other institution and no sub-unit (Bond University); a failed proof records its own cause in checks.identity.seen.proof (diagnostics only); nothing is relaxed for a merged record, a sub-unit, another institution, a page whose headings do not name the provider, or a page off the provider's own host
import fs from 'node:fs'
import { test, expect } from '@playwright/test'
import { descriptionSourceIdentity, descriptionPageText, descriptionIdentityLabels, IDENTITY_SENTENCE_WORDS, IDENTITY_TRACE_TEXT_MAX, IDENTITY_TRACE_HEADINGS_MAX } from '../../supabase/functions/coverage-sweep/description.ts'

const DS = fs.readFileSync('supabase/functions/coverage-sweep/description.ts', 'utf8')
const run = (names, url, hosts, html, trace) => descriptionSourceIdentity(html, descriptionPageText(html, 16000), names, { url, hosts }, trace)
const labels = (names) => descriptionIdentityLabels(names).map((x) => x.toLowerCase())

test('Holmesglen: the full name that is the second entity of the list is a label, so its own About page is proved on its own host', () => {
  const names = ['Holmesglen, Holmesglen Institute']
  expect(labels(names)).toContain('holmesglen institute')
  const html = '<title>About Us – Holmesglen Institute | Leading Vocational &amp; Higher Education in Victoria</title><h1>About us</h1><main>Holmesglen offers courses.</main>'
  expect(run(names, 'https://www.holmesglen.edu.au/about-us', ['holmesglen.edu.au'], html)).toMatchObject({ ok: true, rule: 'current_provider_name', matched_name: 'holmesglen institute' })
  // the same page off the provider's own host stays held
  expect(run(names, 'https://example.org/holmesglen', ['holmesglen.edu.au'], html).ok).toBe(false)
  // extra words in the segment, a sub-unit, another institution: held as before
  expect(run(names, 'https://www.holmesglen.edu.au/x', ['holmesglen.edu.au'], '<title>About Us – Holmesglen Institute Moorabbin Campus</title><h1>About us</h1>').ok).toBe(false)
  expect(run(names, 'https://www.holmesglen.edu.au/x', ['holmesglen.edu.au'], '<title>About Us – Holmesglen Institute</title><h1>Holmesglen Institute School of Nursing</h1>').ok).toBe(false)
  expect(run(names, 'https://www.holmesglen.edu.au/x', ['holmesglen.edu.au'], '<title>About Us – Holmesglen Institute</title><h1>About Monash University</h1>').ok).toBe(false)
})

test('a list of different institutions never derives a label from a later entity', () => {
  const none = [
    ['Murdoch College, The University of Adelaide College, Kaplan International College Adelaide', 'the university of adelaide college'],
    ['Humber College; Humber Trading Institute', 'humber trading institute'],
    ['Torrens Language Centre, Chifley Business School', 'chifley business school'],
    ['Solis College, Athena Institute', 'athena institute'],
    ['Queensford College, Q Learning', 'q learning'],
    ['Holmesglen, Holmesglen Institute School of Nursing', 'holmesglen institute school of nursing'],
    ['Holmesglen, Holmesglen Campus Institute', 'holmesglen campus institute'],
    ['Griffith University, Griffith College', 'griffith college'],
  ]
  for (const [n, later] of none) expect(labels([n]), n).not.toContain(later)
  // a page that names only one of two merged institutions does not prove the merged record
  expect(run(['Humber College; Humber Trading Institute'], 'https://humber.ca/about', ['humber.ca'], '<title>About Us – Humber Trading Institute</title><h1>About us</h1>').ok).toBe(false)
  // the compound name with an abbreviation tag is not split (Platform Admin catalogue decision)
  expect(run(['Manukau Institute of Technology and Unitec - Unitec'], 'https://www.unitec.ac.nz/about', ['unitec.ac.nz'], '<title>About Us – Unitec</title><meta property="og:site_name" content="Unitec"><h1>About us</h1>').ok).toBe(false)
  expect(run(['Manukau Institute of Technology and Unitec - MIT'], 'https://www.manukau.ac.nz/about', ['manukau.ac.nz'], '<title>About MIT | Manukau Institute of Technology</title><h1>About us</h1>').ok).toBe(false)
})

test('the first entity and the earlier labels are unchanged', () => {
  expect(labels(['Centennial Flight Centre, Inc.'])).toEqual(expect.arrayContaining(['centennial flight centre, inc.', 'centennial flight centre']))
  expect(labels(['Bond University Limited'])).toEqual(expect.arrayContaining(['bond university limited', 'bond university']))
  expect(labels(['Griffith University, Griffith College'])).toContain('griffith university')
})

const BOND = (h1) => `<title>Our University | Bond University | Australia</title><meta property="og:site_name" content="Bond University"><h1>${h1}</h1><main>Bond University is in Queensland.</main>`
const bond = (h1, extra = {}) => run(['Bond University Limited'], extra.url || 'https://bond.edu.au/our-university', extra.hosts || ['bond.edu.au'], BOND(h1))

test('Bond: a quoted sentence h1 is a pull-quote, the title and site name prove the provider', () => {
  expect(bond('“Bond University will be bold and pioneering; resourceful and determined.”')).toMatchObject({ ok: true, rule: 'current_provider_name', matched_name: 'bond university' })
  expect(IDENTITY_SENTENCE_WORDS).toBe(6)
  expect(DS).toMatch(/export const IDENTITY_SENTENCE_WORDS = \d+;\s+\/\/ fixed:/)
})

test('Bond: the same sentence without quotation marks, a short quoted name, another institution or a sub-unit stays refused', () => {
  expect(bond('Bond University will be bold and pioneering; resourceful and determined.').ok).toBe(false)
  expect(bond('“Bond University Malaysia”').ok).toBe(false)
  expect(bond('“Bond University and Monash University will be bold and pioneering together.”').ok).toBe(false)
  expect(bond('“Bond University Faculty of Law will be bold and pioneering in research.”').ok).toBe(false)
  expect(bond('“The Bond University campus will be bold and pioneering in its field.”').ok).toBe(false)
  expect(bond('“Bond University will be bold and pioneering; resourceful and determined.”', { url: 'https://example.org/bond', hosts: ['bond.edu.au'] }).ok).toBe(false)
  // a quoted sentence never proves the provider by itself: with no title and no site name the page is held
  expect(run(['Bond University Limited'], 'https://bond.edu.au/x', ['bond.edu.au'], '<h1>“Bond University will be bold and pioneering; resourceful and determined.”</h1><main>Bond University</main>').ok).toBe(false)
})

test('the pages that are not relaxed stay held: TAFE South Australia, TAFE NSW privacy page, CTM College, Centennial Aviation', () => {
  expect(run(['TAFE South Australia'], 'https://www.tafesa.edu.au/about-us', ['tafesa.edu.au'], '<title>About Us</title><meta property="og:site_name" content="Default"><h1>About Us</h1>').ok).toBe(false)
  expect(run(['TAFE NSW'], 'https://www.tafensw.edu.au/privacy', ['tafensw.edu.au'], '<title>Privacy Policy</title><h1>Privacy Policy</h1><main>TAFE NSW collects personal information.</main>').ok).toBe(false)
  expect(run(['Canadian Technical and Management College'], 'https://ctmcollege.ca/about-us/', ['ctmcollege.ca'], '<title>About Us – CTM College</title><h1>About Us</h1>').ok).toBe(false)
  expect(run(['Centennial Flight Centre, Inc.'], 'https://centennial.ca/about/', ['centennial.ca'], '<title>About Centennial Aviation | Centennial</title><h1>CENTENNIAL Aviation Ltd.</h1>').ok).toBe(false)
})

test('Cape Breton University: the title, the site name and the abbreviation prove the provider on its own host', () => {
  const html = '<title>About CBU - Cape Breton University : Cape Breton University</title><meta property="og:site_name" content="Cape Breton University"><h1>About CBU</h1><h1>About CBU</h1><h1>We’re national leaders</h1><main>Cape Breton University is a university.</main>'
  expect(run(['Cape Breton University'], 'https://www.cbu.ca/about-cbu/', ['cbu.ca'], html)).toMatchObject({ ok: true, rule: 'current_provider_name' })
})

test('the trace names the labels used, the headings read, why the strict proof refused and where the registry proof refused; it never changes the result', () => {
  const html = '<title>About Us – CTM College</title><h1>About Us</h1>'
  const names = ['Canadian Technical and Management College']
  const t = {}
  const withTrace = run(names, 'https://ctmcollege.ca/about-us/', ['ctmcollege.ca'], html, t)
  expect(withTrace).toEqual(run(names, 'https://ctmcollege.ca/about-us/', ['ctmcollege.ca'], html))
  expect(t.labels).toEqual(['canadian technical and management college'])
  expect(t.aliases).toEqual(['ctmc'])
  expect(t.headings).toEqual([{ tag: 'title', text: 'About Us – CTM College' }, { tag: 'h1', text: 'About Us' }])
  expect(t.strict).toMatchObject({ rule: 'provider_name_not_proved' })
  expect(t.registry).toMatchObject({ reached: true, rule: 'provider_name_conflict', tag: 'title', segment: 'CTM College', extra: 'another institution' })
  expect(t.returned).toBe('strict')
  // a registry proof that is not reached says why
  const off = {}
  run(names, 'https://example.org/x', ['ctmcollege.ca'], html, off)
  expect(off.registry).toEqual({ reached: false, why: "the page is not on one of the provider's verified hosts" })
  const none = {}
  descriptionSourceIdentity(html, descriptionPageText(html, 16000), names, undefined, none)
  expect(none.registry).toEqual({ reached: false, why: 'no registry evidence given' })
  // a pass records that the registry proof was the one that passed
  const ok = {}
  run(['Holmesglen, Holmesglen Institute'], 'https://www.holmesglen.edu.au/about-us', ['holmesglen.edu.au'], '<title>About Us – Holmesglen Institute | Leading Vocational &amp; Higher Education in Victoria</title><h1>About us</h1>', ok)
  expect(ok.returned).toBe('registry'); expect(ok.registry).toEqual({ reached: true })
  // the excerpts are bounded
  const long = {}
  run(names, 'https://ctmcollege.ca/x', ['ctmcollege.ca'], '<title>' + 'About Us '.repeat(60) + '</title>' + Array.from({ length: 30 }, (_, i) => `<h1>Heading ${i}</h1>`).join(''), long)
  expect(long.headings.length).toBeLessThanOrEqual(IDENTITY_TRACE_HEADINGS_MAX)
  for (const h of long.headings) expect(h.text.length).toBeLessThanOrEqual(IDENTITY_TRACE_TEXT_MAX)
  expect(DS).toMatch(/export const IDENTITY_TRACE_TEXT_MAX = \d+;\s+\/\/ fixed:/)
  expect(DS).toMatch(/export const IDENTITY_TRACE_HEADINGS_MAX = \d+;\s+\/\/ fixed:/)
})

test('the worker stores the trace inside checks.identity.seen only when the proof fails, and the hold is unchanged', () => {
  const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(IX).toMatch(/descriptionSourceIdentity\(html, page, [^\n]*\{ url: String\(rec\.url \|\| ""\), hosts \}, proofTrace\);/)
  expect(IX).toContain("if (!identity.ok) rec.identity_check.seen = { ...descriptionIdentitySeen(html), proof: proofTrace };")
  expect(IX).toContain('if (!identity.ok) { out.push({ ...base, ...rec, rule: identity.rule, reason: "The page does not prove the provider\'s current full institutional identity; no AI call was made." }); return }')
})
