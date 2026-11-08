// Guards: Platform Admin directive 8 Nov 2026 (verified AER reader corrections under the existing evidence rules; nothing auto-admitted; no blanket approval) and "a passing check never switches anything on by itself".
// CF-247 AER lane aer2: before/after counts for the three reader switches shipped OFF in #908 (reading.course_quote_fragments_on, reading.entry_country_aliases_on, reading.entry_value_null_on),
// run through the worker's own functions on the SHAPE of the live drops (tests/fixtures/aer-reader-switch-evidence/quote-shapes-20261108.json: 113 ellipsis-joined quote_not_on_page drops
// in 81 waiting reads, read 8 Nov 2026 about 03:20 UTC; 122 unknown_country matrix drops in 31 runs). No network, no AI, no Firecrawl, nothing written.
// Limit of this evidence, stated once: it shows what the reader does WITH the switch for quotes whose fragments are on the page in order, and that it never accepts the others.
// Whether the live quotes are on the live pages is not known until a read is made with the switch on (the page copies are in storage, not in the database).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { courseEntrySliceRows } from '../../supabase/functions/coverage-sweep/course-entry.ts'
import { entryCountryAliases, entryMatrixParsed } from '../../supabase/functions/coverage-sweep/entry.ts'

const SHAPES = JSON.parse(fs.readFileSync('tests/fixtures/aer-reader-switch-evidence/quote-shapes-20261108.json', 'utf8')).drops
const QM = fs.readFileSync('supabase/migrations/20261108020000_cf247_aer_reader_quality.sql', 'utf8')
const flat = (s) => String(s || '').toLowerCase().normalize('NFKD').replace(/[^a-z0-9]+/g, '')

// deterministic text of exactly `letters` letters in words, unlike any other text of the fixture
let seed = 20261108
const rnd = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296
const text = (letters) => {
  let out = '', left = letters
  while (left > 0) { const w = Math.min(left, 3 + Math.floor(rnd() * 6)); let s = ''; for (let i = 0; i < w; i++) s += String.fromCharCode(97 + Math.floor(rnd() * 26)); out += (out ? ' ' : '') + s; left -= w }
  return out
}
const mk = (quote) => ({ kind: 'general_note', audience: 'all', description: 'd', min_entry_score: null, min_entry_score_basis: null, benchmark_band: null, min_grade: null, confidence: 0.9, quote })

const MULTI = SHAPES.filter((s) => s.fragment_letters.length >= 2)

test('the live shapes: 113 drops in 81 reads, 112 joined from 2 to 5 passages, every passage at least 6 letters', () => {
  expect(SHAPES).toHaveLength(113)
  expect(new Set(SHAPES.map((s) => s.item)).size).toBe(81)
  expect(MULTI).toHaveLength(112)
  expect(Math.max(...SHAPES.map((s) => s.fragment_letters.length))).toBe(5)
  expect(Math.min(...SHAPES.flatMap((s) => s.fragment_letters))).toBeGreaterThanOrEqual(6)  // reading.course_entry_fragment_min_chars default 6
})

test('BEFORE and AFTER: with the switch off none of the 112 joined quotes is kept; with it on all 112 are, each fragment found in order; the single-passage drop is unchanged', () => {
  let off = 0, on = 0, fragmentsProved = 0
  for (const s of MULTI) {
    const frags = s.fragment_letters.map((n) => text(n))
    const page = frags.map((f) => `${text(40)}. ${f}. ${text(30)}.`).join(' ')
    const quote = frags.join(s.item.charCodeAt(0) % 2 ? ' ... ' : '...')
    const a = { rows: [mk(quote)] }
    const r0 = courseEntrySliceRows(a, page, { fragments: false })
    const r1 = courseEntrySliceRows(a, page, { fragments: true, minFragment: 6 })
    off += r0.rows.length; on += r1.rows.length
    if (r1.rows[0]) fragmentsProved += r1.rows[0].quote_fragments
    expect(r0.dropped[0]?.reason, s.item).toBe('quote_not_on_page')
  }
  expect({ off, on }).toEqual({ off: 0, on: 112 })
  expect(fragmentsProved).toBe(MULTI.reduce((n, s) => n + s.fragment_letters.length, 0))
})

test('NEVER accepted with the switch on: a passage missing from the page, passages out of order, or a passage under the minimum (no false admission in any variant)', () => {
  let variants = 0, accepted = 0
  for (const s of MULTI) {
    const frags = s.fragment_letters.map((n) => text(n))
    const quote = frags.join(' ... ')
    const ok = (page) => { variants++; accepted += courseEntrySliceRows({ rows: [mk(quote)] }, page, { fragments: true, minFragment: 6 }).rows.length }
    // each passage missing in turn
    for (let k = 0; k < frags.length; k++) ok(frags.filter((_, i) => i !== k).map((f) => `${text(20)}. ${f}.`).join(' '))
    // the passages in reverse order
    ok([...frags].reverse().map((f) => `${text(20)}. ${f}.`).join(' '))
    // the first passage cut short on the page (not whole)
    ok(frags.map((f, i) => `${text(20)}. ${i === 0 ? f.slice(0, f.length - 3) : f}.`).join(' '))
  }
  expect(variants).toBe(MULTI.reduce((n, s) => n + s.fragment_letters.length + 2, 0))
  expect(accepted).toBe(0)
  // a passage under the minimum is refused with its reason named, even when it is on the page
  const first = text(30), q = `${first} ... ab`
  const r = courseEntrySliceRows({ rows: [mk(q)] }, `${first}. ${text(25)}. ab.`, { fragments: true, minFragment: 6 })
  expect(r.rows).toHaveLength(0)
  expect(r.dropped[0].detail).toMatch(/shorter than reading\.course_entry_fragment_min_chars \(6\)/)
})

// the 122 live unknown_country drops (31 matrix runs), by the country token the page or the model printed
const TOKENS = { INT: 26, 'International Baccalaureate': 16, Worldwide: 15, '': 11, 'International Baccalaureate (IB) diploma': 9, 'International Baccalaureate (IB) Diploma': 7, 'Pacific Islands': 6,
  'International Baccalaureate Certificate (IB)': 5, GLOBAL: 5, General: 4, 'International Baccalaureate (IB)': 2, 'Pacific Islands (not Fiji)': 2, GAC: 2, UK: 1, 'University of Otago': 1,
  'Cambridge International Examinations (CIE)': 1, 'Advanced Placement International Diploma (APID)': 1, 'GB-SCT': 1, 'Global / IB': 1, ANY: 1, ALL: 1, 'LRN International': 1,
  'Northern Consortium United Kingdom (NCUK)': 1, 'Pearson Edexcel': 1, 'South Pacific countries (not individually listed)': 1 }
const MP = 'United Kingdom | Bachelor | GCE A Levels | grades BBB | Scotland | Scottish Highers | AAAB'
const mrow = (cc) => ({ country_code: cc, country_name: 'United Kingdom', study_level: 'Bachelor', qualification_name: 'GCE A Levels', min_grade: 'grades BBB', min_value: null, grade_scale: 'none',
  benchmark_band: null, course_name: null, conditions: {}, confidence: 0.9, quote: 'United Kingdom | Bachelor | GCE A Levels | grades BBB' })
const ALIASES = entryCountryAliases(JSON.parse(QM.match(/'list', '(\["UK=GB"[^']*\])'::jsonb/)[1]))

test('BEFORE and AFTER for the 122 live unknown_country drops: the alias list turns 2 into a country (UK, GB-SCT) and the other 120 are not touched', () => {
  expect(Object.values(TOKENS).reduce((a, b) => a + b, 0)).toBe(122)
  const became = { off: 0, on: 0 }, others = { off: 0, on: 0 }
  for (const [tok, n] of Object.entries(TOKENS)) {
    const off = entryMatrixParsed({ rows: [mrow(tok)] }, MP)
    const on = entryMatrixParsed({ rows: [mrow(tok)] }, MP, [], { countryAliases: ALIASES })
    // a row becomes a GB row only through the alias (a 2-letter token such as UK is passed through unchanged with the switch off and dropped by the database)
    const gbOff = off.rows.filter((r) => r.country_code === 'GB' && tok.toUpperCase() !== 'GB').length, gbOn = on.rows.filter((r) => r.country_code === 'GB' && tok.toUpperCase() !== 'GB').length
    became.off += gbOff * n; became.on += gbOn * n
    if (!['UK', 'GB-SCT'].includes(tok)) { others.off += n * (on.rows.length ? 0 : 1); others.on += n * (on.rows.length ? 0 : 1); expect(on.rows.some((r) => r.conditions?.country_token), tok).toBe(false) }
  }
  expect(became).toEqual({ off: 0, on: 2 })
  expect(others.on).toBe(others.off)  // nothing else changes
})

test('the three switches still ship off, the revision is not touched by this lane\'s migrations, and the prepared revision change is documented but not applied', () => {
  for (const k of ['reading.course_quote_fragments_on', 'reading.entry_country_aliases_on', 'reading.entry_value_null_on']) expect(QM).toMatch(new RegExp(`'${k.replace('.', '\\.')}'[\\s\\S]*?to_jsonb\\(0\\), 0, 1, 'on/off'`))
  for (const f of fs.readdirSync('supabase/migrations').filter((x) => /^2026110815\d{4}_/.test(x))) {
    const body = fs.readFileSync(`supabase/migrations/${f}`, 'utf8').split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
    expect(body, f).not.toMatch(/reader_revision|reading\.(course_quote_fragments_on|entry_country_aliases_on|entry_value_null_on)/)
  }
  const paste = fs.readFileSync('docs/paste/AER2-20261108-reader-revision-2.md', 'utf8')
  expect(paste).toContain('Nothing in this file has been applied')
  expect(paste).toContain('layer4.reader_revision')
  expect(paste).toContain('raising the revision now releases nothing')
})
