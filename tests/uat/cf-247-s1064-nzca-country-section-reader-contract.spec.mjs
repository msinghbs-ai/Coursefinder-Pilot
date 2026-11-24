// Guards: Platform Admin 24 Nov 2026 S3-AER NZ/CA P0; F-AER.08, source-grounded
// qualification/level/country, $0 deterministic first; no inferred minima, AU writes,
// separate reader, manual-lock bypass, or Consumer API G3 changes.
// Source-shaped reproductions of Otago Polytechnic and Wintec's printed level
// blocks. Stored-copy run read-back is required; this fixture is not source proof.
import { test, expect } from '@playwright/test'
import path from 'node:path'
import fs from 'node:fs'
import os from 'node:os'
import { execFileSync } from 'node:child_process'

async function load(name) {
  const output = path.join(os.tmpdir(), 's1064-' + name + '-' + process.pid + '.mjs')
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/entry-html-table.ts',
    '--bundle','--platform=node','--format=esm','--outfile=' + output,'--log-level=error'])
  return import(output)
}
const COUNTRIES = [
  { a2: 'AU', name: 'Australia' }, { a2: 'AR', name: 'Argentina' },
  { a2: 'IN', name: 'India' }, { a2: 'BD', name: 'Bangladesh' },
  { a2: 'NP', name: 'Nepal' }, { a2: 'CN', name: 'China' }
]

test('existing real-source-shaped Otago quote-correction fixture: four country accordion tables without headers', async () => {
  const ht = await load('otago-existing-fixture')
  const source = fs.readFileSync('tests/fixtures/entry-matrix/quote-corrections/otago-country-tables.html', 'utf8')
  const refs = [...COUNTRIES, { a2: 'DZ', name: 'Algeria' }, { a2: 'KE', name: 'Kenya' }]
  const parsed = ht.entryHtmlTableRead(source, refs, [], {}, { minRows: 5, providerCountry: 'NZ' })
  expect(parsed).not.toBeNull()
  expect(parsed.tables).toHaveLength(4)
  expect(parsed.answer.rows).toHaveLength(8)
  expect(new Set(parsed.answer.rows.map(x => x.country_code))).toEqual(new Set(['DZ','AR','AU','KE']))
  expect(parsed.answer.rows.find(x => x.country_code === 'AU' && x.study_level.includes('Degree'))?.min_value).toBe(65)
  expect(parsed.answer.rows.every(x => parsed.text.includes(x.quote))).toBe(true)
})

test('Otago Polytechnic: country, NCEA and degree divs; no invented grade or country', async () => {
  const ht = await load('otago')
  const html = [
    '<h1>Entry requirements for international students</h1>',
    '<h2>Equivalent academic entry requirements by country</h2>',
    '<section><div>Australia</div><div>NCEA Level 2</div><div>Certificate/Diploma Level</div>',
    '<div>Successful completion of Year 12</div>',
    '<div>NCEA Level 3</div><div>Degree Level</div>',
    '<div>Successful completion of Year 12, AND ATAR score of 65 or above</div></section>',
    '<section><div>Bangladesh</div><div>NCEA Level 2</div><div>Certificate/Diploma Level</div>',
    '<div>Higher Secondary Certificate</div>',
    '<div>NCEA Level 3</div><div>Degree Level</div>',
    '<div>Successful completion of Higher Secondary Certificate with a GPA of 3.5 or higher</div></section>'
  ].join('')
  const r = ht.entryHtmlTableRead(html, COUNTRIES, [], {}, { minRows: 5, providerCountry: 'NZ' })
  expect(r).not.toBeNull()
  expect(r.tables).toHaveLength(2)
  expect(r.tables.every(t => t.level_from === 'row')).toBe(true)
  expect(r.answer.rows).toHaveLength(4)
  expect(new Set(r.answer.rows.map(x => x.country_code))).toEqual(new Set(['AU','BD']))
  const au = r.answer.rows.filter(x => x.country_code === 'AU')
  expect(au.find(x => x.grade_scale === 'rank')?.min_value).toBe(65)
  expect(au.find(x => x.min_value == null)?.min_grade).toBeNull()
  expect(r.answer.rows.find(x => x.country_code === 'BD' && x.grade_scale === 'gpa')?.min_value).toBe(3.5)
  expect(ht.entryHtmlTableCompleteness(r).status).toBe('complete')
  for (const x of r.answer.rows) {
    expect(x.conditions.reader).toBe('html-table-v1')
    expect(r.text.includes(x.quote)).toBe(true)
  }
})
test('Wintec: heading and printed country-level requirement pairs outside tables', async () => {
  const ht = await load('wintec')
  const html = [
    '<h1>International academic entry requirements</h1>',
    '<h2>Argentina</h2><p>Certificate (level 4)</p><p>Título de Técnico Auxiliar.</p>',
    '<p>Diploma (level 5)</p><p>Título de Bachiller/Bachillerato, or Trayecto Técnico Profesional.</p>',
    '<p>Degree level</p><p>One year of successful undergraduate-level study at a recognised tertiary institution.</p>',
    '<h2>Australia</h2><p>Certificate (level 4) | Depends on state/territory.</p>',
    '<p>Diploma (level 5) | Depends on state/territory.</p>',
    '<p>Degree level | Successful completion of Year 12 Certificate and ATAR of 74 or higher.</p>'
  ].join('')
  const r = ht.entryHtmlTableRead(html, COUNTRIES, [], {}, { minRows: 5, providerCountry: 'NZ' })
  expect(r).not.toBeNull()
  expect(r.tables).toHaveLength(2)
  expect(r.answer.rows).toHaveLength(6)
  expect(r.answer.rows.filter(x => x.country_code === 'AR')).toHaveLength(3)
  expect(r.answer.rows.filter(x => x.country_code === 'AU')).toHaveLength(3)
  expect(r.answer.rows.find(x => x.country_code === 'AU' && x.grade_scale === 'rank')?.min_value).toBe(74)
})
test('fails closed: only one level, unknown country, prose context or English-only grades', async () => {
  const ht = await load('negative')
  const pairs = '<div>Degree level</div><div>ATAR score of 74 or higher</div>'
  expect(ht.entryHtmlTableRead('<h2>Australia</h2>' + pairs, COUNTRIES, [], {}, { providerCountry: 'NZ' })).toBeNull()
  expect(ht.entryHtmlTableRead('<h2>Unknownland</h2>' + pairs + '<p>Certificate (level 4)</p><p>Year 12</p>', COUNTRIES, [], {}, { providerCountry: 'NZ' })).toBeNull()
  expect(ht.entryHtmlTableRead('<h2>Academic entry for Australia</h2>' + pairs + '<p>Certificate (level 4)</p><p>Year 12</p>', COUNTRIES, [], {}, { providerCountry: 'NZ' })).toBeNull()
  expect(ht.entryHtmlTableRead('<h2>Australia</h2><p>English language requirements</p>' + pairs + '<p>Diploma (level 5)</p><p>IELTS 6.0</p>', COUNTRIES, [], {}, { providerCountry: 'NZ' })).toBeNull()
  const html = '<script><h2>Australia</h2><p>Degree level</p><p>ATAR 65</p></script><h2>Argentina</h2><p>Certificate (level 4)</p><p>Year 12</p>'
  expect(ht.entryHtmlTableRead(html, COUNTRIES, [], {}, { providerCountry: 'NZ' })).toBeNull()
})

test('VUW: explicit undergraduate IB Diploma minimum is global qualification-first, never mapped to an invented country', async () => {
  const ht = await load('vuw-global')
  const source = [
    '<h1>Entry requirements</h1><h2>Undergraduate entry requirements</h2>',
    '<p>All Bachelors degrees share the same academic entry criteria.</p>',
    '<h3>Country-specific requirements</h3><label>Select your country</label><select><option>India</option></select>',
    '<h3>International high school qualifications</h3>',
    '<ul><li>IB (International Baccalaureate) Diploma: Minimum 24 points</li>',
    '<li>CAIE: Three GCE A-Level passes at grade C or higher</li></ul>',
    '<h3>English language requirements</h3><p>IELTS 6.0 overall</p>'
  ].join('')
  const QUALS = [{ code: 'IB_DP', aliases: ['international baccalaureate','ib diploma'] }]
  const r = ht.entryHtmlTableRead(source, COUNTRIES, QUALS, {}, { providerCountry: 'NZ' })
  expect(r).not.toBeNull()
  expect(r.answer.rows).toHaveLength(1)
  expect(r.answer.rows[0].qualification_name).toContain('Baccalaureate')
  expect(r.answer.rows[0].country_code).toBe('')
  expect(r.answer.rows[0].min_value).toBe(24)
  expect(r.answer.rows[0].grade_scale).toBe('points')
  expect(r.tables[0].level_from).toBe('heading')
  expect(ht.entryHtmlTableCompleteness(r).status).toBe('complete')
  expect(ht.entryHtmlTableRead(source, COUNTRIES, [], {}, { providerCountry: 'NZ' })).toBeNull()
  expect(ht.entryHtmlTableRead(source.replace('<h2>Undergraduate entry requirements</h2>', ''), COUNTRIES, QUALS, {}, { providerCountry: 'NZ' })).toBeNull()
  expect(ht.entryHtmlTableRead(source.replace('Minimum 24 points', 'Expected around 24 points'), COUNTRIES, QUALS, {}, { providerCountry: 'NZ' })).toBeNull()
})

test('Confederation: printed country and Diploma/Certificate vs postgraduate level, no country sharing', async () => {
  const ht = await load('confederation')
  const html = [
    '<h1>Admission Requirements - by country</h1><h2>Africa</h2>',
    '<h3>Cameroon</h3><h4>Diploma/Certificate</h4>',
    '<p>OSSD Equiv: General Certificate Advanced Level (A) with minimum 2 courses OR Baccalaureat</p>',
    '<p>Minimum GPA: C; 10</p><h4>Postgraduate Certificate</h4>',
    '<p>Bachelor Equiv: Bachelor’s Transcripts &amp; Degree</p><p>Minimum GPA: 50%</p>',
    '<h3>India</h3><h4>Diploma/Certificate</h4>',
    '<p>OSSD Equiv: Higher Secondary School Certificate (Class 12)</p><p>Minimum GPA: 50%</p>',
    '<h4>Postgraduate Certificate</h4><p>Bachelor Equiv: Bachelor Degree</p><p>Minimum GPA: 55%</p>'
  ].join('')
  const refs = [...COUNTRIES, { a2: 'CM', name: 'Cameroon' }]
  const r = ht.entryHtmlTableRead(html, refs, [], {}, { minRows: 5, providerCountry: 'CA' })
  expect(r).not.toBeNull()
  expect(r.tables).toHaveLength(2)
  expect(r.answer.rows).toHaveLength(4)
  expect(r.answer.rows.filter(x => x.country_code === 'CM')).toHaveLength(2)
  expect(r.answer.rows.filter(x => x.country_code === 'IN')).toHaveLength(2)
  expect(r.answer.rows.find(x => x.country_code === 'CM' && x.grade_scale === 'percentage')?.min_value).toBe(50)
})
