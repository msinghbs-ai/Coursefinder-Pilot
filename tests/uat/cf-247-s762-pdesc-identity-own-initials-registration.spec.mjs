// Guards: Provider description identity proof, own initials and registration number (Platform Admin 19 Nov 2026 07:39 item 1): a title or h1 segment that holds the provider's whole catalogue name plus its own initials in brackets or an RTO, CRICOS or TEQSA registration number proves the provider on its own host; a place or sub-brand after the name, another institution, a campus, faculty or school, a foreign bracket, an abbreviation alone with a registration number, and a page off the provider's host stay held.
// CF-247 S762. Worker coverage-sweep/description.ts only; no migration.
import { test, expect } from '@playwright/test'
import { descriptionSourceIdentity, descriptionPageText, identityOwnInitials, identityOwnMarksRemoved } from '../../supabase/functions/coverage-sweep/description.ts'

const run = (names, url, hosts, html) => descriptionSourceIdentity(html, descriptionPageText(html, 16000), names, { url, hosts })
const page = (title, h1 = 'About us') => `<title>${title}</title><h1>${h1}</h1><main><p>We offer courses.</p></main>`

test('the whole name with its own initials in brackets is the provider', () => {
  expect(identityOwnInitials('New Zealand Biosecurity Academy')).toContain('nzba')
  expect(identityOwnInitials('International College of Management')).toEqual(expect.arrayContaining(['icom', 'icm']))
  expect(run(['Sydney Art School'], 'https://sydneyartschool.com.au/about', ['sydneyartschool.com.au'], page('About Us | Sydney Art School (SAS)'))).toMatchObject({ ok: true, rule: 'current_provider_name' })
  expect(run(['New Zealand Biosecurity Academy Limited'], 'https://nzba.ac.nz/about-us', ['nzba.ac.nz'], page('About Us | New Zealand Biosecurity Academy (NZBA)'))).toMatchObject({ ok: true })
})

test('the whole name with an RTO, CRICOS or TEQSA registration number is the provider', () => {
  const names = ['Health Institute Australasia'], hosts = ['hia.edu.au']
  for (const t of ['About Health Institute Australasia (RTO 45524)', 'Health Institute Australasia | RTO No. 45524', 'About Us - Health Institute Australasia CRICOS Provider Code 03456K', 'Health Institute Australasia (TEQSA PRV14040)']) {
    expect(run(names, 'https://hia.edu.au/about', hosts, page(t)), t).toMatchObject({ ok: true, rule: 'current_provider_name' })
  }
  expect(identityOwnMarksRemoved('X (RTO 45524)', 'health institute australasia', 'rto 45524')).toBe('')
})

test('a place, a sub-brand, another institution, a sub-unit and a foreign bracket stay held', () => {
  const held = [
    [['Scotch College'], 'About — Scotch College Melbourne'],
    [['Stella Maris College'], 'Our College - Stella Maris College Manly'],
    [['Sydney Art School'], 'About Us | Sydney Art School (Melbourne)'],
    [['Sydney Art School'], 'About Us | Sydney Art School (SAS) Parramatta'],
    [['Princeton Education Group Pty Ltd'], 'About Us - Princeton International College'],
    [['Health Institute Australasia'], 'Health Institute Australasia School of Nursing (RTO 45524)'],
    [['Health Institute Australasia'], 'Health Institute Australasia RTO'],
    [['Monash University'], 'Monash University Malaysia (MUM)'],
  ]
  for (const [names, t] of held) expect(run(names, 'https://example.edu.au/about', ['example.edu.au'], page(t)).ok, t).toBe(false)
  expect(identityOwnMarksRemoved('Sydney Art School (Melbourne)', 'sydney art school', 'melbourne')).toBe('melbourne')
})

test('the same title off the provider\'s own host stays held, and the earlier proofs are unchanged', () => {
  expect(run(['Sydney Art School'], 'https://directory.example.org/sas', ['sydneyartschool.com.au'], page('About Us | Sydney Art School (SAS)')).ok).toBe(false)
  expect(run(['Holmesglen, Holmesglen Institute'], 'https://www.holmesglen.edu.au/about-us', ['holmesglen.edu.au'], '<title>About Us – Holmesglen Institute | Leading Vocational &amp; Higher Education in Victoria</title><h1>About us</h1><main>Holmesglen offers courses.</main>')).toMatchObject({ ok: true, matched_name: 'holmesglen institute' })
  expect(run(['Holmesglen, Holmesglen Institute'], 'https://www.holmesglen.edu.au/x', ['holmesglen.edu.au'], '<title>About Us – Holmesglen Institute Moorabbin Campus</title><h1>About us</h1>').ok).toBe(false)
})
