// Guards: Platform Admin directive 8 Nov 2026 (AER reader quality: repair quote truncation, qualification-country aliases and dropped minimums under the existing evidence rules; nothing auto-admitted; the reader revision is changed by the Integration Controller only after deployment) with G2 (every value is a setting) and G3 (consumer API untouched)
// CF-247 AER reader quality (coverage-sweep v0.59.11). No network, no AI, no Firecrawl: the worker's pure functions (course-entry.ts, entry.ts) run on fixtures
// that reproduce the live shapes (8 Nov 2026: 113 ellipsis-joined quotes in 81 waiting reads, 51 dropped and 171 kept quotes at exactly 300 characters,
// UK and GB-SCT country tokens, 22 value_without_scale and 12 value_not_in_quote matrix drops). The migration is settings only; its PostgreSQL 16 run is
// tests/fixtures/aer-reader-quality/run.sh.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { courseEntryMerge, courseEntrySliceRows, proveQuote, quoteFragments, storeQuote, COURSE_ENTRY_SYSTEM } from '../../supabase/functions/coverage-sweep/course-entry.ts'
import { entryCountryAliases, entryMatrixParsed } from '../../supabase/functions/coverage-sweep/entry.ts'

const MIG = fs.readFileSync('supabase/migrations/20261108020000_cf247_aer_reader_quality.sql', 'utf8')
const W = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const flat = (s) => String(s || '').toLowerCase().normalize('NFKD').replace(/[^a-z0-9]+/g, '')

const PAGE = [
  'Entry requirements. Applicants must have completed the Victorian Certificate of Education (VCE) with a study score of at least 25 in English.',
  'Applicants who have not completed VCE may apply through the alternative entry scheme, which assesses prior study and work experience.',
  'A folio of up to ten works is required for the design stream, and an interview may be asked of shortlisted applicants.',
].join(' ')
const P = flat(PAGE)
const mk = (quote, x = {}) => ({ kind: 'general_note', audience: 'all', description: 'd', min_entry_score: null, min_entry_score_basis: null, benchmark_band: null, min_grade: null, confidence: 0.9, quote, ...x })
const ON = { fragments: true, minFragment: 6 }

test('a quote joined from passages with an ellipsis is proven fragment by fragment, in the page order', () => {
  const joined = 'Applicants must have completed the Victorian Certificate of Education (VCE) ... a folio of up to ten works is required for the design stream'
  expect(P.includes(flat(joined))).toBe(false)  // the joined text is not on the page
  expect(proveQuote(joined, P, ON)).toEqual({ ok: true, fragments: 2 })
  // the single-character ellipsis and two dots, and a leading or trailing ellipsis
  expect(proveQuote(joined.replace('...', '…'), P, ON)).toEqual({ ok: true, fragments: 2 })
  expect(proveQuote(joined.replace('...', '..'), P, ON)).toEqual({ ok: true, fragments: 2 })
  expect(proveQuote('... a folio of up to ten works is required for the design stream ...', P, ON)).toEqual({ ok: true, fragments: 1 })  // one fragment: the whole text is on the page, as before
  // out of order
  const swapped = 'a folio of up to ten works is required for the design stream ... Applicants must have completed the Victorian Certificate of Education (VCE)'
  expect(proveQuote(swapped, P, ON)).toEqual({ ok: false, detail: 'fragment 2 of 2 is not after fragment 1 on the page' })
  // a fragment that is not on the page at all
  expect(proveQuote('Applicants must have completed the Victorian Certificate of Education (VCE) ... a portfolio of fifty works is needed', P, ON))
    .toEqual({ ok: false, detail: 'fragment 2 of 2 is not on the page' })
  // a fragment too short to prove anything
  expect(proveQuote('Applicants must have completed the Victorian Certificate of Education (VCE) ... the', P, ON).detail).toMatch(/^fragment 2 of 2 is shorter than reading\.course_entry_fragment_min_chars \(6\)$/)
  // the switch off: only a whole quote is accepted, as before
  expect(proveQuote(joined, P, { fragments: false, minFragment: 6 })).toEqual({ ok: false, detail: 'quote is not on the page' })
  // a quote whole on the page is accepted whatever the switch says
  expect(proveQuote('Applicants who have not completed VCE may apply through the alternative entry scheme', P, { fragments: false, minFragment: 6 })).toEqual({ ok: true, fragments: 1 })
  // a fragment may not be reused: the same passage twice needs two places on the page
  const twice = 'a folio of up to ten works ... a folio of up to ten works'
  expect(proveQuote(twice, P, ON).ok).toBe(false)
  expect(quoteFragments('a ... b..c…d').length).toBe(4)
})

test('rows: a joined quote is kept (switch on) or dropped with the fragment named (off or failing); every other row is unchanged', () => {
  const good = mk('Applicants must have completed the Victorian Certificate of Education (VCE) ... a study score of at least 25 in English')
  const bad = mk('Applicants must have completed the Victorian Certificate of Education (VCE) ... a study score of at least 99 in English')
  const whole = mk('an interview may be asked of shortlisted applicants')
  const a = { rows: [good, bad, whole] }
  const on = courseEntrySliceRows(a, PAGE, { fragments: true })
  expect(on.rows.map((r) => r.quote.slice(0, 20))).toEqual(['Applicants must have', 'an interview may be '])
  expect(on.rows[0].quote_fragments).toBe(2)
  expect(on.rows[1].quote_fragments).toBeUndefined()
  expect(on.dropped).toHaveLength(1)
  expect(on.dropped[0]).toMatchObject({ reason: 'quote_not_on_page', kind: 'general_note', detail: 'fragment 2 of 2 is not on the page' })
  const off = courseEntrySliceRows(a, PAGE)  // the defaults are today's behaviour
  expect(off.rows).toHaveLength(1)
  expect(off.dropped.map((d) => d.reason)).toEqual(['quote_not_on_page', 'quote_not_on_page'])
  expect(off.dropped[0].detail).toBeUndefined()
  // a quote too short to prove (under four letters and digits) is still dropped
  expect(courseEntrySliceRows({ rows: [mk('VCE')] }, PAGE, ON).dropped[0].reason).toBe('quote_not_on_page')
})

test('the quote kept is the setting\'s length and a cut is recorded on the row and counted in the read, never silent', () => {
  const long = 'An applicant must have completed the Victorian Certificate of Education (VCE) with a study score of at least 25 in English and the page goes on to say much more than a quote needs to'
  expect(long.length).toBeGreaterThan(150)
  expect(storeQuote(long, 300)).toEqual({ quote: long, cut: null })
  const c = storeQuote(long, 100)
  expect(c.quote).toBe(long.slice(0, 100))
  expect(c.cut).toEqual({ chars: long.length, kept: 100 })
  // a joined quote is cut at a whole fragment when one fits, and keeps the fragments that fit in order
  const j = 'Applicants must have completed the Victorian Certificate of Education (VCE) ... a folio of up to ten works is required for the design stream'
  const cj = storeQuote(j, 100)
  expect(cj.quote).toBe('Applicants must have completed the Victorian Certificate of Education (VCE)')
  expect(cj.cut).toEqual({ chars: j.length, kept: cj.quote.length })
  expect(storeQuote(j, 300).cut).toBeNull()
  // the proof is on the whole quote as the model gave it, so the kept text is the start of proven text
  const pageLong = `${PAGE} ${long}`
  const r = courseEntrySliceRows({ rows: [mk(long)] }, pageLong, { quoteChars: 100 })
  expect(r.rows[0].quote).toBe(long.slice(0, 100))
  expect(r.rows[0].quote_cut).toEqual({ chars: long.length, kept: 100 })
  expect(flat(pageLong)).toContain(flat(r.rows[0].quote))
  // the read says how many quotes it kept short or joined
  const slices = [{ index: 0, start: 0, end: pageLong.length, text: pageLong }]
  const m = courseEntryMerge(slices, [{ index: 0, ok: true, ...courseEntrySliceRows({ rows: [mk(long), mk('Victorian Certificate of Education (VCE) ... alternative entry scheme')] }, pageLong, { quoteChars: 100, fragments: true }), cost: 0 }], pageLong.length)
  expect(m.complete).toBe(true)
  expect(m.coverage).toMatchObject({ quotes_cut: 1, quotes_fragmented: 1 })
  // nothing to say when nothing was cut or joined
  const clean = courseEntryMerge(slices, [{ index: 0, ok: true, ...courseEntrySliceRows({ rows: [mk('an interview may be asked of shortlisted applicants')] }, pageLong), cost: 0 }], pageLong.length)
  expect(clean.coverage.quotes_cut).toBeUndefined()
  expect(clean.coverage.quotes_fragmented).toBeUndefined()
})

test('a requirement is one row: the same kind and quote read twice with different score fields counts once, as the database counts it', () => {
  const q = 'a study score of at least 25 in English'
  const sl = (i) => ({ index: i, start: 0, end: PAGE.length, text: PAGE })
  const a = courseEntrySliceRows({ rows: [mk(q, { min_entry_score: 25, min_entry_score_basis: 'study score' }), mk(q, { min_entry_score: null }), mk(q.toUpperCase(), { min_entry_score: 25 })] }, PAGE)
  expect(a.rows).toHaveLength(3)
  const m = courseEntryMerge([sl(0)], [{ index: 0, ok: true, ...a, cost: 0 }], PAGE.length)
  expect(m.rows).toHaveLength(1)
  expect(m.coverage.duplicates).toBe(2)
  // a different kind with the same words is another requirement
  const k = courseEntrySliceRows({ rows: [mk(q), mk(q, { kind: 'subject_prerequisite' })] }, PAGE)
  expect(courseEntryMerge([sl(0)], [{ index: 0, ok: true, ...k, cost: 0 }], PAGE.length).rows).toHaveLength(2)
})

test('the prompt text is unchanged (its md5 is registered): the limit is enforced after the answer, not asked for in a new prompt', () => {
  expect(COURSE_ENTRY_SYSTEM).toContain('(at most 300 characters)')
})

// ---- matrix reader: country aliases and the number with no printed basis ----
const MP = 'United Kingdom | Bachelor | GCE A Levels | grades BBB | Scotland | Scottish Highers | AAAB | India | CBSE | 75% | Worldwide | International Baccalaureate | 30 points | Dubai | GCSE with 6 passes'
const mrow = (q, x = {}) => ({ country_code: 'GB', country_name: 'United Kingdom', study_level: 'Bachelor', qualification_name: 'GCE A Levels', min_grade: 'grades BBB', min_value: null,
  grade_scale: 'none', benchmark_band: null, course_name: null, conditions: {}, confidence: 0.9, quote: q, ...x })
const ALIASES = entryCountryAliases(JSON.parse(MIG.match(/'list', '(\["UK=GB"[^']*\])'::jsonb/)[1]))

test('the seeded aliases are only names a country can have; every other token stays held', () => {
  expect(ALIASES).toEqual({ UK: 'GB', 'GB-SCT': 'GB', 'GB-ENG': 'GB', 'GB-WLS': 'GB', 'GB-NIR': 'GB' })
  for (const held of ['GLOBAL', 'INT', 'IB', 'WW', 'GAC', 'ANY', 'ALL', 'WORLDWIDE', 'GENERAL']) expect(ALIASES[held], held).toBeUndefined()
  // a malformed or self-referring entry is ignored, and a non-list is no aliases
  expect(entryCountryAliases(['UK=GB', 'nonsense', 'GB=GB', 'XX=', '=GB', 'IB=ZZZ', 'ww = au'])).toEqual({ UK: 'GB', WW: 'AU' })
  expect(entryCountryAliases(null)).toEqual({})
})

test('an alias turns UK or GB-SCT into GB only with the switch on, records the token, and leaves other tokens held', () => {
  const q = 'United Kingdom | Bachelor | GCE A Levels | grades BBB'
  for (const token of ['UK', 'GB-SCT', 'uk']) {
    const off = entryMatrixParsed({ rows: [mrow(q, { country_code: token })] }, MP)
    // off: "UK" has two letters, so the worker passes it and the database drops it (ref.countries has GB, not UK); "GB-SCT" is dropped by the worker
    if (token.toUpperCase() === 'UK') expect(off.rows[0].country_code, token).toBe('UK')
    else expect(off.dropped[0], token).toMatchObject({ reason: 'unknown_country' })
    const on = entryMatrixParsed({ rows: [mrow(q, { country_code: token })] }, MP, [], { countryAliases: ALIASES })
    expect(on.dropped, token).toEqual([])
    expect(on.rows[0].country_code, token).toBe('GB')
    expect(on.rows[0].conditions.country_token, token).toBe(token.toUpperCase())
  }
  // a real code is untouched and carries no token
  const gb = entryMatrixParsed({ rows: [mrow(q)] }, MP, [], { countryAliases: ALIASES })
  expect(gb.rows[0].country_code).toBe('GB')
  expect(gb.rows[0].conditions.country_token).toBeUndefined()
  // the existing conditions are kept beside the token
  expect(entryMatrixParsed({ rows: [mrow(q, { country_code: 'UK', conditions: { best_n: 4 } })] }, MP, [], { countryAliases: ALIASES }).rows[0].conditions).toEqual({ best_n: 4, country_token: 'UK' })
  // not a country: still held with the aliases on
  for (const token of ['INT', 'WW', 'IB', 'GLOBAL', 'ANY', 'GAC', '', 'India']) {
    const r = entryMatrixParsed({ rows: [mrow('Worldwide | International Baccalaureate | 30 points', { country_code: token, min_grade: '30 points' })] }, MP, [], { countryAliases: ALIASES })
    // a token of two letters passes the worker and the database drops it (not in ref.countries); the others are dropped by the worker; none becomes a country
    if (r.rows.length) expect(r.rows[0].country_code, token).toBe(token.toUpperCase())
    else expect(r.dropped[0].reason, token).toBe('unknown_country')
    expect(r.rows.some((x) => x.conditions.country_token), token).toBe(false)
  }
  // the quote, grade and band checks are not relaxed by an alias
  expect(entryMatrixParsed({ rows: [mrow('United Kingdom | Bachelor | words not on the page', { country_code: 'UK' })] }, MP, [], { countryAliases: ALIASES }).dropped[0].reason).toBe('quote_not_on_page')
})

test('a number with no printed basis is left out and the row kept only when its grade is printed, and only with the switch on', () => {
  const q = 'Dubai | GCSE with 6 passes'
  const base = { country_code: 'AE', qualification_name: 'GCSE', min_grade: '6 passes', min_value: 6, grade_scale: 'none' }
  expect(entryMatrixParsed({ rows: [mrow(q, base)] }, MP).dropped[0].reason).toBe('value_without_scale')
  const on = entryMatrixParsed({ rows: [mrow(q, base)] }, MP, [], { nullValue: true })
  expect(on.dropped).toEqual([])
  expect(on.rows[0]).toMatchObject({ min_grade: '6 passes', min_value: null, grade_scale: 'none' })
  expect(on.rows[0].conditions.value_removed).toEqual({ reason: 'value_without_scale', value: 6 })
  // the number is not in the quote
  const q2 = 'India | CBSE | 75%'
  const nv = { country_code: 'IN', qualification_name: 'CBSE', min_grade: '75%', min_value: 80, grade_scale: 'percentage' }
  expect(entryMatrixParsed({ rows: [mrow(q2, nv)] }, MP).dropped[0].reason).toBe('value_not_in_quote')
  const on2 = entryMatrixParsed({ rows: [mrow(q2, nv)] }, MP, [], { nullValue: true })
  expect(on2.rows[0]).toMatchObject({ min_grade: '75%', min_value: null, grade_scale: 'percentage' })
  expect(on2.rows[0].conditions.value_removed).toEqual({ reason: 'value_not_in_quote', value: 80 })
  // a number that is printed and scaled is kept as it is
  expect(entryMatrixParsed({ rows: [mrow(q2, { ...nv, min_value: 75 })] }, MP, [], { nullValue: true }).rows[0]).toMatchObject({ min_value: 75 })
  // no grade text, or a grade not printed in the quote: the row is still dropped, for the reason it was
  expect(entryMatrixParsed({ rows: [mrow(q, { ...base, min_grade: null })] }, MP, [], { nullValue: true }).dropped[0].reason).toBe('value_without_scale')
  expect(entryMatrixParsed({ rows: [mrow(q, { ...base, min_grade: '9 passes' })] }, MP, [], { nullValue: true }).dropped[0].reason).toBe('value_without_scale')
  expect(entryMatrixParsed({ rows: [mrow(q2, { ...nv, min_grade: '85%' })] }, MP, [], { nullValue: true }).dropped[0].reason).toBe('value_not_in_quote')
  // a band, a confidence and a quote not on the page are checked as before
  expect(entryMatrixParsed({ rows: [mrow(q, { ...base, quote: 'Dubai | not on the page 6 passes' })] }, MP, [], { nullValue: true }).dropped[0].reason).toBe('quote_not_on_page')
})

// ---- the migration and the worker wiring ----
test('the migration adds settings only, each with a label, range, unit and used_by; the three behaviours ship off; the limit ships at today\'s 300', () => {
  const code = MIG.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
  expect(MIG).toMatch(/^-- Replaces: .+/m)
  expect(MIG).toMatch(/^-- Retires: .+/m)
  expect(code).not.toMatch(/\b(create|alter|drop|delete|truncate)\b\s+(or replace\s+)?(table|function|view|trigger|index|schema)/i)
  expect(code).not.toMatch(/reader_revision/)
  const insert = MIG.slice(MIG.indexOf('insert into pipeline.platform_toolset_settings'), MIG.indexOf('on conflict'))
  for (const k of ['enrich.course_entry_quote_chars', 'reading.course_quote_fragments_on', 'reading.course_entry_fragment_min_chars', 'reading.entry_country_aliases_on', 'reading.entry_country_aliases', 'reading.entry_value_null_on']) {
    const block = insert.split("\n ('pipeline', '").find((e) => e.startsWith(`${k}'`))
    expect(block, k).toBeTruthy()
    expect(block, k).toMatch(/'(number|list)',/)
    expect(block, k).toMatch(/'Entry requirements',\s+'worker coverage-sweep/)  // section and used_by
    expect(block, k).toMatch(/^[^,]+, '[^']+',\s+'/)  // label then help
  }
  expect(MIG).toMatch(/'enrich\.course_entry_quote_chars'[\s\S]*?to_jsonb\(300\), 100, 300, 'characters'/)
  for (const k of ['reading.course_quote_fragments_on', 'reading.entry_country_aliases_on', 'reading.entry_value_null_on']) expect(MIG).toMatch(new RegExp(`'${k.replace('.', '\\.')}'[\\s\\S]*?to_jsonb\\(0\\), 0, 1, 'on/off'`))
  expect(MIG).toMatch(/'reading\.course_entry_fragment_min_chars'[\s\S]*?to_jsonb\(6\), 4, 40, 'characters'/)
  expect(MIG).toContain('on conflict (toolset_key, key) do nothing')
})

test('the worker reads the settings through svc_worker_settings_v1 and passes them to the readers; the version records the change', () => {
  expect(W).toMatch(/(?:const WORKER = "coverage-sweep-worker-v0\.59\.11"; |\/\/ was v0\.59\.11 )\/\/ v0\.59\.11 \(8 Nov 2026, CF-247 AER reader quality/)
  expect(W).toContain('// was v0.59.10 // v0.59.10 (6 Nov 2026')
  expect(W).toContain('const ws: Record<string, unknown> = (await rpc("svc_worker_settings_v1", {}).catch(() => ({}))) || {};')
  expect(W).toContain('wsNum("enrich.course_entry_quote_chars", 300)')
  expect(W).toContain('ws["reading.course_quote_fragments_on"]')
  expect(W).toContain('wsNum("reading.course_entry_fragment_min_chars", 6)')
  expect(W).toContain('courseEntrySliceRows(ans.a, s.text, quoteOpts)')
  expect(W).toContain('ws["reading.entry_country_aliases_on"]')
  expect(W).toContain('entryCountryAliases(ws["reading.entry_country_aliases"])')
  expect(W).toContain('ws["reading.entry_value_null_on"]')
  expect(W).toContain('entryMatrixParsed(JSON.parse(content), page, stored.lines, parseOpts)')
  // no new AI call, fetch or spend in the changed readers
  const ce = fs.readFileSync('supabase/functions/coverage-sweep/course-entry.ts', 'utf8')
  expect(ce.slice(ce.indexOf('export const quoteFragments'), ce.indexOf('export type CourseSliceOutcome'))).not.toMatch(/fetch\(|openrouter|firecrawl/i)
})

test('the PostgreSQL fixture mirrors the live settings table and proves the migration twice, a recorded change kept, and both guards', () => {
  const run = fs.readFileSync('tests/fixtures/aer-reader-quality/run.sh', 'utf8'), schema = fs.readFileSync('tests/fixtures/aer-reader-quality/schema.sql', 'utf8')
  expect(schema).toContain("constraint platform_toolset_settings_kind_check check (kind = any (array['number','text','boolean','list']))")
  expect(schema).toContain('help text not null default')
  expect(schema).toContain("section text not null default 'Notices'")
  for (const t of ['migration applied twice: no change', 'a re-run does not reset a recorded setting change', 'post-check refuses a number outside its range', 'guard refuses when svc_worker_settings_v1 would not return the keys']) expect(run).toContain(t)
})
