// Guards: CF-247 AER v1.1 RMIT D1–D3 (Platform Admin 27 Oct 2026 04:58): a band given as the page's own "Not applicable" is no band only where the line prints none (an absent band is still refused); a page that is not one country's table is held terminally before any AI read; a failed run can be read again with its history and attempts kept
// Record: admin docs/platform/aer-v1.1-build-log.md. Fixtures: tests/fixtures/entry-matrix/rmit-*.html (reconstructed RMIT pages) and
// ref-countries.json (the live ref.countries list, 249 rows, md5 e5698bb8… checked against live on 27 Oct).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryManifest, entryCompleteness, entryMatrixParsed, entryTables, entryPageCountry, entryNonCountryShape, NA_BAND } from '../../supabase/functions/coverage-sweep/entry.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'
const fx = (n) => fs.readFileSync(`tests/fixtures/entry-matrix/${n}`, 'utf8')
const COUNTRIES = JSON.parse(fx('ref-countries.json')).countries
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const m = fs.readFileSync('supabase/migrations/20261027001000_cf247_entry_matrix_d2_d3.sql', 'utf8')
const m709 = fs.readFileSync('supabase/migrations/20261026010000_cf247_entry_matrix_completeness_guard.sql', 'utf8')
const m710 = fs.readFileSync('supabase/migrations/20261026011000_cf247_entry_matrix_complete_admission.sql', 'utf8')
const rowsFor = (man, cc, cname, map = (x) => x) => man.entries.map(e => map({
  country_code: cc, country_name: cname, study_level: e.level, qualification_name: e.header.replace(/\*$/, ''), min_grade: e.cell, min_value: null,
  grade_scale: 'none', benchmark_band: e.band, course_name: null, conditions: {}, confidence: 0.95, quote: e.line }))
const read = (file, rows) => { const h = fx(file), t = entryTables(h, htmlToText), man = entryManifest(h, htmlToText), p = entryMatrixParsed({ rows }, t.text, t.lines); return { man, p, v: entryCompleteness(man, p.rows) } }
// a page shaped like RMIT's qualification and Foundation-equivalency pages (same table layout as a country page)
const page = (h1, header, rows) => `<!doctype html><html><head><title>${h1} - RMIT University</title></head><body><h1>${h1}</h1><table><tr>${header.map(c => `<th>${c}</th>`).join('')}</tr>${rows.map(r => `<tr>${r.map(c => `<td>${c}</td>`).join('')}</tr>`).join('')}</table></body></html>`
const bands = ['50%', '55%', '60%', '65%', '70%', '75%', '80%', '85%', '90%']
const ladder = (cell) => [['Foundation Studies', 'Not applicable', 'Completion of Year 1 with at least 24 points.'], ['University Pathways Fast Track', 'Not applicable', 'Completion of Year 1 with at least 26 points.'],
  ...bands.map((b, i) => [i === 0 ? 'Diploma/Associate degrees' : i === 3 ? 'Bachelor degrees' : '', b, cell(i)])]
const IB = page('International Baccalaureate Diploma', ['Level of study', 'Australian standard', 'International Baccalaureate Diploma (IBDP)'], ladder(i => `${24 + i} points`))
const GAC = page('Global Assessment Certificate', ['Level of study', 'Australian standard', 'Global Assessment Certificate (GAC)'], ladder(i => `Average of ${60 + i}%`))
const FE = page('Foundation equivalencies', ['Program', 'Australian standard', 'English Requirement 1', 'Academic Requirement', 'Prerequisites'],
  [['Foundation Studies', 'Not applicable', 'IELTS 5.5', 'Year 11', 'None'], ['Diploma', '50%', 'IELTS 6.0', 'Year 12', 'Mathematics']])

test('D1: the page\'s own "Not applicable" is no band where the line prints none; the source text stays in the quote', () => {
  expect(NA_BAND.test('Not applicable')).toBe(true)
  const china = entryManifest(fx('rmit-china.html'), htmlToText)
  // the 23:5x live failure: every Foundation and Fast Track row given "Not applicable" as its band (Hong Kong, IB, Denmark)
  const na = rowsFor(china, 'CN', 'China', x => x.benchmark_band ? x : { ...x, benchmark_band: 'Not applicable' })
  const r = read('rmit-china.html', na)
  expect(r.p.dropped).toEqual([])
  expect(r.p.rows.filter(x => /Foundation|Fast Track/.test(x.study_level)).map(x => x.benchmark_band)).toEqual([null, null, null, null])
  expect(r.p.rows.filter(x => /Foundation/.test(x.study_level)).every(x => x.quote.includes('| Not applicable |'))).toBe(true)  // evidence keeps the source text
  expect(r.v).toMatchObject({ status: 'complete', expected: 22, matched: 22 })
})

test('D1: an absent band, or "Not applicable" given on a line that prints a band, is still refused; nothing is manufactured', () => {
  const china = entryManifest(fx('rmit-china.html'), htmlToText), good = rowsFor(china, 'CN', 'China')
  const target = good.find(x => x.benchmark_band === '70%' && /Gao San/.test(x.qualification_name))
  for (const b of [null, '', 'Not applicable', 'N/A']) {
    const r = read('rmit-china.html', good.map(x => x === target ? { ...x, benchmark_band: b } : x))
    expect(r.p.dropped.map(d => d.reason), String(b)).toEqual(['band_missing'])
    expect(r.v.status).toBe('incomplete')  // the minimum it carried is now unread, so the whole read is held
  }
  // a band row given a band the line does not print is still a mismatch
  expect(read('rmit-china.html', good.map(x => x === target ? { ...x, benchmark_band: '75%' } : x)).p.dropped.map(d => d.reason)).toEqual(['band_not_in_quote'])
})

test('identity (#708): Foundation and Fast Track stay distinct with no band, by their level labels', () => {
  const china = entryManifest(fx('rmit-china.html'), htmlToText)
  const r = read('rmit-china.html', rowsFor(china, 'CN', 'China', x => x.benchmark_band ? x : { ...x, benchmark_band: 'Not applicable' }))
  const level = (l) => /foundation|pathway/i.test(l) ? 'foundation' : /bachelor|degree/i.test(l) ? 'bachelor' : 'diploma'
  const ids = new Set(r.p.rows.map(x => [level(x.study_level), x.benchmark_band ?? '', x.qualification_name, 'level: ' + x.study_level].join('|')))
  expect(ids.size).toBe(22)
  const nb = r.p.rows.filter(x => x.benchmark_band == null)
  expect(nb.length).toBe(4)  // Gao Er and Gao San, Foundation and Fast Track
  expect(new Set(nb.map(x => x.study_level + '|' + x.qualification_name)).size).toBe(4)
})

test('D2: IB, GAC and Foundation equivalencies are not country tables; RMIT\'s country pages are', () => {
  const shape = (h) => entryNonCountryShape(entryManifest(h, htmlToText), COUNTRIES)
  expect(shape(IB)).toMatch(/^no country named in the page heading \("International Baccalaureate Diploma/)
  expect(shape(GAC)).toMatch(/^no country named in the page heading \("Global Assessment Certificate/)
  expect(shape(FE)).toMatch(/^requirement-type columns, not qualifications \(English Requirement 1; Academic Requirement; Prerequisites\)/)
  for (const f of ['rmit-china.html', 'rmit-canada.html', 'rmit-cambodia.html', 'rmit-band-ladder.html']) expect(shape(fx(f)), f).toBeNull()
  // every RMIT country page's own heading names its country (the 33 country slugs as RMIT titles them)
  const headings = { 'United States of America': 'US', USA: 'US', 'Viet Nam': 'VN', Vietnam: 'VN', 'South Korea': 'KR', Taiwan: 'TW', 'Hong Kong': 'HK', 'United Kingdom': 'GB',
    'United Arab Emirates': 'AE', 'Saudi Arabia': 'SA', 'Sri Lanka': 'LK', 'New Zealand': 'NZ', 'China (People\'s Republic of)': 'CN', Malaysia: 'MY', Kenya: 'KE', Kuwait: 'KW',
    Mauritius: 'MU', Mexico: 'MX', Nigeria: 'NG', Nepal: 'NP', Norway: 'NO', Pakistan: 'PK', Philippines: 'PH', Qatar: 'QA', Singapore: 'SG', Thailand: 'TH', Japan: 'JP',
    India: 'IN', Indonesia: 'ID', Germany: 'DE', Denmark: 'DK', Colombia: 'CO', Cambodia: 'KH', Canada: 'CA', Bangladesh: 'BD' }
  // the guard asks only whether the heading names a country (which one is the reader's, checked per row by country_not_evidenced);
  // "South Korea" names both Koreas by the name before the comma, so only that a country is named is asserted
  for (const h of Object.keys(headings)) expect(entryPageCountry(`${h} | ${h} - RMIT University`, COUNTRIES), h).toBeTruthy()
  for (const [h, cc] of Object.entries(headings).filter(([h]) => h !== 'South Korea')) expect(entryPageCountry(`${h} | ${h} - RMIT University`, COUNTRIES), h).toBe(cc)
  for (const h of ['International Baccalaureate Diploma', 'Global Assessment Certificate', 'Foundation equivalencies'])
    expect(entryPageCountry(`${h} | ${h} - RMIT University`, COUNTRIES), h).toBeNull()
})

test('D2: held before any AI read, as "held_unparsed", which the database makes terminal (no retry)', () => {
  const i = w.indexOf('const nonCountry = it.completeness_required === true && stored.manifest.status === "ok" ? entryNonCountryShape(stored.manifest, await countryRefs()) : null;')
  expect(i).toBeGreaterThan(0)
  expect(i).toBeLessThan(w.indexOf('const slices = entrySlices(page, Number(it.max_rows) || 400);'))  // before the AI read
  expect(w).toContain('const why = nonCountry ? `not a country table: ${nonCountry}` : (stored.manifest.reason || stored.manifest.status);')
  expect(w).toContain('await rec({ p_error: `held_unparsed: ${why}`.slice(0, 400)')
  expect(w).toContain('countryList ??= ((await rpc("svc_entry_country_refs_v1", {})) || [])')
  expect(m709).toContain("state = case when p_error like 'held_unparsed%' then 'failed'")  // terminal: no retry
  expect(m).toContain('create or replace function public.svc_entry_country_refs_v1() returns jsonb')
  expect(m).toContain('grant execute on function public.svc_entry_country_refs_v1() to service_role;')
})

test('D3: a failed run can be read again; its state, error and attempts stay in the history; nothing is proposed twice', () => {
  expect(m).toContain("select pg_temp.edit_n('public.admin_entry_matrix_reread(uuid[],text)', 'cec7158550b26b2b88a6a5e559384231'")
  expect(m).toContain("state in ('done', 'failed') for update loop")
  expect(m).toContain("'state', r.state, 'error', r.error, 'attempts_used', r.attempts, 'earlier_index', jsonb_array_length(r.previous_results))),")
  expect(m).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})

test('completeness and whole-run approval remain enforced (#709, #710 unchanged)', () => {
  const china = entryManifest(fx('rmit-china.html'), htmlToText)
  expect(read('rmit-china.html', rowsFor(china, 'CN', 'China').filter(x => !/Gao Kao/.test(x.qualification_name))).v.status).toBe('incomplete')
  expect(m709).toContain("p_error := 'held_incomplete: no complete verdict (' || coalesce(p_result->'completeness'->>'status', 'missing') || ')';")
  expect(m710).toContain("a read is admitted whole or rejected', r.id,")
  expect(m).not.toMatch(/entry_matrix_review_apply_v1|svc_entry_matrix_record/)  // this change does not touch them
})
