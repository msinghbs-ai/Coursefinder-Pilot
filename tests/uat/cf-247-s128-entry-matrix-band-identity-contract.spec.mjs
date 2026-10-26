// Guards: CF-247 AER v1.1 RMIT benchmark-band fix (Platform Admin 26 Oct 2026 22:50): the band each quoted table line prints is kept as published, a row that shows a band it did not give is rejected, and rows are told apart by band and level label in the existing identity
// Record: admin docs/platform/aer-v1.1-build-log.md. The 22:4x re-read gave all 59 RMIT rows with no band (Bangladesh: 11 rows, 3 identities).
// Fixture: tests/fixtures/entry-matrix/rmit-band-ladder.html (reconstructed from the live Bangladesh page; blank and rowspan level cells).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryTables, entryPageText, entryMatrixParsed, ENTRY_PROMPT, ENTRY_PROMPT_VERSION } from '../../supabase/functions/coverage-sweep/entry.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'
const html = fs.readFileSync('tests/fixtures/entry-matrix/rmit-band-ladder.html', 'utf8')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const m = fs.readFileSync('supabase/migrations/20261026009000_cf247_entry_matrix_band_identity.sql', 'utf8')
const T = entryTables(html, htmlToText)
const HSC = 'Higher School Certificate (HSC)'
const row = (q, x = {}) => ({ country_code: 'BD', country_name: 'Bangladesh', study_level: 'Bachelor degrees', qualification_name: HSC,
  min_grade: 'Minimum CGPA of 4.2', min_value: 4.2, grade_scale: 'gpa', benchmark_band: '70%', course_name: null,
  conditions: { subject_minimums: [], best_n: null, alternatives: [] }, confidence: 0.95, quote: q, ...x })
const parse = (rows) => entryMatrixParsed({ rows }, T.text, T.lines)

test('each table line keeps the band its "Australian standard" column prints; the label is still carried down', () => {
  expect(T.text).toBe(entryPageText(html, htmlToText))  // the page text the reader sees is unchanged from #707
  const band = (l) => { const f = T.lines.find(x => x.line.trim() === l); expect(f, l).toBeTruthy(); return f.band }
  expect(band('Bachelor degrees | 70% | Not applicable | Minimum CGPA of 4.2')).toBe('70%')
  expect(band('Diploma/Associate degrees | 60% | Not applicable | Minimum CGPA of 3.9')).toBe('60%')  // blank level cell carried down
  expect(band('Diploma/Associate degrees | 55% | Minimum CGPA of 3.7')).toBe('55%')  // rowspan level cell carried down
  expect(band('Foundation Studies | Not applicable | Not applicable | Min Completion of Year 11 with CGPA of 3.5 (60%).')).toBeNull()  // "Not applicable" is no band
  expect(band('Level of study | Australian standard | Secondary School Certificate (SSC) | Higher School Certificate (HSC)')).toBeNull()  // the header row
  expect(band('| Not carried from the table above')).toBeNull()  // a table without the column publishes no band
})

test('the band kept is the one the quoted line prints; a missing, absent or different band is rejected', () => {
  const q = 'Bachelor degrees | 70% | Not applicable | Minimum CGPA of 4.2'
  const ok = parse([row(q)])
  expect(ok.rows.length).toBe(1)
  expect(ok.rows[0].benchmark_band).toBe('70%')
  expect(parse([row(q, { benchmark_band: '70' })]).rows[0].benchmark_band).toBe('70%')  // kept as printed, never as typed by the reader
  expect(parse([row(q, { benchmark_band: null })]).dropped[0].reason).toBe('band_missing')
  expect(parse([row(q, { benchmark_band: '' })]).dropped[0].reason).toBe('band_missing')
  expect(parse([row(q, { benchmark_band: '75%' })]).dropped[0].reason).toBe('band_not_in_quote')
  expect(parse([row(q, { benchmark_band: '4.2' })]).dropped[0].reason).toBe('band_mismatch')
  // a row whose line prints no band needs none, and a quote that does not show the band is not held to it
  const f = 'Foundation Studies | Not applicable | Not applicable | Min Completion of Year 11 with CGPA of 3.5 (60%).'
  expect(parse([row(f, { study_level: 'Foundation Studies', benchmark_band: null, min_grade: 'Min Completion of Year 11 with CGPA of 3.5 (60%)', min_value: 3.5 })]).rows.length).toBe(1)
  expect(parse([row('Minimum CGPA of 4.2', { benchmark_band: null })]).rows.length).toBe(1)
  // without band lines (a markdown copy, or a page with no band column) the earlier checks alone apply
  expect(entryMatrixParsed({ rows: [row(q, { benchmark_band: null })] }, T.text).rows.length).toBe(1)
})

test('all 11 Bangladesh HSC rows of the fixture keep distinct identities: band plus level label', () => {
  const lines = T.text.split('\n').map(s => s.trim()).filter(l => / \| Minimum CGPA of | \| Min Completion /.test(l) && l.split(' | ').length === 4)
  expect(lines.length).toBe(11)
  const rows = lines.map(l => { const c = l.split(' | '); return row(l, { study_level: c[0], benchmark_band: /%$/.test(c[1]) ? c[1] : null, min_grade: c[3].replace(/\.$/, ''), min_value: null, grade_scale: 'gpa' }) })
  const r = parse(rows)
  expect(r.dropped).toEqual([])
  // the database identity: study level (Foundation Studies and University Pathways Fast Track map to one), band, and the condition keys
  // (qualification name and, from this change, the level label)
  const level = (l) => /foundation|pathway/i.test(l) ? 'foundation' : /bachelor|degree/i.test(l) ? 'bachelor' : 'diploma'
  const bandOnly = new Set(r.rows.map(x => [level(x.study_level), x.benchmark_band, x.qualification_name].join('|')))
  const withLabel = new Set(r.rows.map(x => [level(x.study_level), x.benchmark_band, x.qualification_name, 'level: ' + x.study_level].join('|')))
  expect(bandOnly.size).toBe(10)  // the band alone leaves Foundation Studies and Fast Track on one identity
  expect(withLabel.size).toBe(11)
})

test('database: level label is a condition key of the existing identity; approval refuses a run whose rows share an identity', () => {
  expect(m).toContain("select pg_temp.edit_n('security.entry_matrix_identity_tg()', '86ddafc3140eab8bea505295bb2b5bea'")
  expect(m).toContain("jsonb_build_array(jsonb_build_object('key', 'level: ' || btrim(new.level_label)))")
  expect(m).toContain('new.row_hash := security.entry_matrix_row_hash_v1(new.provider_id, new.course_id, new.country_code, new.study_level_id, new.benchmark_band, new.qualification_name,')
  expect(m).toContain("select pg_temp.edit_n('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', 'e3f02aaa014afe4dd64946af0b3e44cf'")
  expect(m).toContain("group by m.row_hash having count(*) > 1) then")
  expect(m).toContain("raise exception 'entry matrix run %: proposed rows share an identity; nothing admitted'")
  expect(m).not.toMatch(/create or replace function security\.entry_matrix_row_hash_v1/)  // the hash itself is unchanged
  expect(m).not.toMatch(/'(band_ladder_v2|collapsed|blocked)'/)  // no new status values
  expect(m).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})

test('worker and prompt: band lines reach the check; the reader is told where the band is', () => {
  expect(w).toContain('const stored = await storedText(it.storage_path, it.mime), page = stored.text;')
  expect(w).toContain('entryMatrixParsed(JSON.parse(content), page, stored.lines)')
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.48\.[2-9]"/)
  expect(ENTRY_PROMPT_VERSION).toMatch(/^entry-matrix-v0\.1\.[2-9]$/)
  expect(ENTRY_PROMPT).toContain('When a table has an "Australian standard" column')
  expect(ENTRY_PROMPT).toContain('give it exactly as printed')
})
