// Guards: CF-247 AER v1.1 completeness guard (Platform Admin 26 Oct 2026 23:16): a read is compared with a manifest of every minimum the stored page's band tables publish; an omitted column or row, a misplaced cell, a cell-only quote or a duplicate holds the whole run; the database refuses to propose or admit a read without a complete verdict
// Record: admin docs/platform/aer-v1.1-build-log.md. After #708 a China read gave 13 of 22 rows (the Gao Kao column left out) with nothing dropped.
// Fixtures: tests/fixtures/entry-matrix/rmit-{china,canada,cambodia}.html, reconstructed from the live RMIT pages (cell values as published).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { entryManifest, entryCompleteness, entryMatrixParsed, entryTables, ENTRY_PROMPT, ENTRY_PROMPT_VERSION, ENTRY_COMPLETENESS_BASIS } from '../../supabase/functions/coverage-sweep/entry.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'
const fx = (n) => fs.readFileSync(`tests/fixtures/entry-matrix/${n}`, 'utf8')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const m = fs.readFileSync('supabase/migrations/20261026010000_cf247_entry_matrix_completeness_guard.sql', 'utf8')
const COUNTRY = { 'rmit-china.html': ['CN', 'China'], 'rmit-canada.html': ['CA', 'Canada'], 'rmit-cambodia.html': ['KH', 'Cambodia'] }
// the rows a correct read gives: one per manifest entry, quoting the entry's whole table line (as the reader is asked to)
const rowsFor = (file, man, pick = () => true) => man.entries.filter(pick).map(e => ({
  country_code: COUNTRY[file][0], country_name: COUNTRY[file][1], study_level: e.level, qualification_name: e.header.replace(/\*$/, ''),
  min_grade: e.cell, min_value: null, grade_scale: 'none', benchmark_band: e.band, course_name: null, conditions: {}, confidence: 0.95, quote: e.line }))
// the full path: the reader's checks first (entryMatrixParsed), then the guard on the rows it kept
const read = (file, rows) => {
  const html = fx(file), t = entryTables(html, htmlToText), man = entryManifest(html, htmlToText)
  const parsed = entryMatrixParsed({ rows }, t.text, t.lines)
  return { man, parsed, verdict: entryCompleteness(man, parsed.rows) }
}

test('manifests: every published minimum of the RMIT band tables, footnote rows apart', () => {
  const china = entryManifest(fx('rmit-china.html'), htmlToText)
  expect(china.status).toBe('ok')
  expect(china.entries.length).toBe(22)
  const per = (man) => Object.fromEntries(man.columns.map(c => [c, man.entries.filter(e => e.header === c).length]))
  expect(per(china)).toEqual({ 'Gao Er (Senior Middle 2) (Year 11)': 2, 'Gao San (Senior Middle 3) (Year 12)': 11, 'Gao Kao (NCEE) - Beijing': 9 })
  expect(china.footnotes.length).toBe(1)
  const canada = entryManifest(fx('rmit-canada.html'), htmlToText)
  expect(canada.entries.length).toBe(24)
  expect(canada.footnotes[0]).toContain('*Overall average from best 6 academic subjects')
  const cambodia = entryManifest(fx('rmit-cambodia.html'), htmlToText)
  expect(cambodia.entries.length).toBe(11)
  // the merged case-by-case cell is published on each of the nine band rows, under each row's own carried-down level
  const merged = cambodia.entries.filter(e => e.cell.startsWith('Assessed on a case-by-case basis'))
  expect(merged.map(e => e.band)).toEqual(['50%', '55%', '60%', '65%', '70%', '75%', '80%', '85%', '90%'])
  expect(merged.map(e => e.level)).toEqual([...Array(3).fill('Diploma/Associate degrees'), ...Array(6).fill('Bachelor degrees')])
  // the Bangladesh fixture of s127/s128: SSC publishes nothing (every cell "Not applicable"), HSC eleven minimums
  expect(entryManifest(fx('rmit-band-ladder.html'), htmlToText).entries.filter(e => /HSC/.test(e.header)).length).toBe(14)  // 11 + 3 in the rowspan table
})

test('China with the Gao Kao column left out: 13 rows, the whole run held; complete: 22 rows, passes', () => {
  const man = entryManifest(fx('rmit-china.html'), htmlToText)
  const short = read('rmit-china.html', rowsFor('rmit-china.html', man, e => !/Gao Kao/.test(e.header)))
  expect(short.parsed.rows.length).toBe(13)
  expect(short.parsed.dropped).toEqual([])  // nothing the earlier checks could see
  expect(short.verdict.status).toBe('incomplete')
  expect(short.verdict.omitted_columns).toEqual(['Gao Kao (NCEE) - Beijing'])
  expect(short.verdict.omitted.length).toBe(9)
  expect(short.verdict.reason).toContain('column left out: Gao Kao (NCEE) - Beijing')
  const full = read('rmit-china.html', rowsFor('rmit-china.html', man))
  expect(full.parsed.rows.length).toBe(22)
  expect(full.verdict).toMatchObject({ status: 'complete', expected: 22, matched: 22, omitted: [], unexplained: [], basis: ENTRY_COMPLETENESS_BASIS })
  // one omitted row (not a column) also holds the run
  const one = read('rmit-china.html', rowsFor('rmit-china.html', man).filter(r => r.min_grade !== '480'))
  expect(one.verdict.status).toBe('incomplete')
  expect(one.verdict.omitted).toEqual([{ level: 'Bachelor degrees', band: '80%', column: 'Gao Kao (NCEE) - Beijing', cell: '480' }])
})

test('Cambodia: the merged cell and carried level labels pass; a misplaced level, band or column holds the run', () => {
  const man = entryManifest(fx('rmit-cambodia.html'), htmlToText), good = rowsFor('rmit-cambodia.html', man)
  expect(read('rmit-cambodia.html', good).verdict.status).toBe('complete')
  // the 22:47 live case: a band row read again without its band is dropped by the band check, and the run is complete without it
  const withDup = [...good, { ...good[2], benchmark_band: null }]
  const r = read('rmit-cambodia.html', withDup)
  expect(r.parsed.dropped.map(d => d.reason)).toEqual(['band_missing'])
  expect(r.verdict.status).toBe('complete')
  // a row given the wrong level for its line
  const wrongLevel = good.map((x, i) => i === 2 ? { ...x, study_level: 'Bachelor degrees' } : x)
  expect(read('rmit-cambodia.html', wrongLevel).verdict.unexplained.map(u => u.reason)).toEqual(['wrong_level'])
  // a cell assigned to the wrong qualification column (China: Gao San's grade under Gao Er)
  const cman = entryManifest(fx('rmit-china.html'), htmlToText), crow = rowsFor('rmit-china.html', cman)
  const wrongCol = crow.map(x => x.min_grade === 'Minimum average of 50%' ? { ...x, qualification_name: 'Gao Er (Senior Middle 2) (Year11)' } : x)
  const v = read('rmit-china.html', wrongCol).verdict
  expect(v.status).toBe('incomplete')
  expect(v.unexplained.map(u => u.reason)).toEqual(['wrong_column'])
})

test('Canada: footnote text is not a minimum; OSSD rows pass only with their whole line; a cell-only quote is refused', () => {
  const man = entryManifest(fx('rmit-canada.html'), htmlToText), good = rowsFor('rmit-canada.html', man)
  expect(read('rmit-canada.html', good).verdict).toMatchObject({ status: 'complete', expected: 24, matched: 24 })
  // the 22:4x case: OSSD Foundation quoted from the footnote row
  const foot = good.map(x => x.study_level === 'Foundation Studies' && /Ontario/.test(x.qualification_name)
    ? { ...x, min_grade: 'Overall average from best 6 academic subjects', quote: '*Overall average from best 6 academic subjects from Year 12 (C, M and U syllabuses)' } : x)
  const f = read('rmit-canada.html', foot).verdict
  expect(f.status).toBe('incomplete')
  expect(f.unexplained.map(u => u.reason)).toEqual(['not_a_table_row'])
  // the 23:0x case: the six Foundation and Fast Track rows quoting only their cell ("Completion of Ontario Secondary School Diploma" is the
  // same text on two lines, so the quote cannot show the level)
  const cellOnly = good.map(x => x.benchmark_band ? x : { ...x, quote: x.min_grade })
  const c = read('rmit-canada.html', cellOnly)
  expect(c.parsed.rows.length).toBe(24)  // on the page, so the earlier checks keep them
  expect(c.verdict.status).toBe('incomplete')
  expect(c.verdict.unexplained.filter(u => u.reason === 'level_not_evidenced').length).toBe(6)
  expect(c.verdict.matched).toBe(18)
})

test('duplicates, rows from outside the tables and a page that is not this country are refused; a page without band tables is not this guard\'s', () => {
  const man = entryManifest(fx('rmit-canada.html'), htmlToText), good = rowsFor('rmit-canada.html', man)
  expect(read('rmit-canada.html', [...good, good[5]]).verdict.unexplained.map(u => u.reason)).toEqual(['duplicate_row'])
  expect(read('rmit-canada.html', good.map(x => ({ ...x, country_code: 'US', country_name: 'United States' }))).verdict.unexplained[0].reason).toBe('country_not_evidenced')
  expect(entryCompleteness(entryManifest('<h1>UTS</h1><p>no tables</p>', htmlToText), []).status).toBe('not_applicable')
  // the same table twice on the page (a copy for small screens) is one set of minimums
  const twice = fx('rmit-china.html').replace(/(<table>[\s\S]*<\/table>)/, '$1$1')
  const tm = entryManifest(twice, htmlToText)
  expect(tm.entries.length).toBe(22)
  expect(entryCompleteness(tm, rowsFor('rmit-china.html', tm)).status).toBe('complete')
  // a band table the guard cannot read (a row shorter than its header) is unparsed, never "complete"
  const broken = fx('rmit-china.html').replace('<td>Foundation Studies</td><td>Not applicable</td>', '<td>Foundation Studies</td>')
  const bm = entryManifest(broken, htmlToText)
  expect(bm.status).toBe('unparsed')
  expect(entryCompleteness(bm, []).status).toBe('unparsed')
})

test('database: the verdict is enforced at record and at approval; held reads are kept; retries use entry.matrix_attempts', () => {
  expect(m).toContain("('pipeline', 'entry.completeness_providers', 'Entry matrices: completeness guard',")
  expect(m).toContain("'[\"8e1adb6c-e069-43db-9584-bd054255e702\"]'::jsonb")
  expect(m).toContain("select pg_temp.edit_n('public.svc_entry_matrix_record(uuid,jsonb,numeric,text)', 'd80183c6903a48eb1e9c08fbc8a1e706'")
  expect(m).toContain("p_error := 'held_incomplete: no complete verdict (' || coalesce(p_result->'completeness'->>'status', 'missing') || ')';")
  expect(m).toContain("else previous_results || jsonb_build_array(jsonb_build_object('held', p_error like 'held_%'")
  expect(m).toContain("state = case when p_error like 'held_unparsed%' then 'failed' when p_error = 'time budget' then 'queued' when attempts >= security.pipeline_num_v1('entry.matrix_attempts', 3) then 'failed' else 'queued' end,")
  expect(m).toContain("'completeness', p_result->'completeness'),")
  expect(m).toContain("select pg_temp.edit_n('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', '76cce959081557411a5db494a85b6817'")
  expect(m).toContain("raise exception 'entry matrix run %: the read has not passed the completeness guard (%); nothing admitted'")
  // the #708 identity guard stays ahead of it
  expect(m.indexOf("proposed rows share an identity; nothing admitted', r.id using errcode = '23505';\n    end if;\n    -- completeness guard")).toBeGreaterThan(0)
  expect(m).toContain("'completeness_required', security.entry_completeness_required_v1(u.provider_id)")
  expect(m).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
  expect(m).not.toMatch(/state in \('held'|'held'::text/)  // no new state values
})

test('worker: manifest before the AI read, verdict on every result, held reads go to the database whole', () => {
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.48\.([3-9]|[1-9][0-9])"/)
  expect(w).toContain('if (it.completeness_required === true && (stored.manifest.status !== "ok" || nonCountry || unscaled.length)) {')  // v0.48.8 (s135) adds the bare-number hold  // v0.48.4 (s131) adds the non-country shapes
  expect(w).toContain('const completeness = entryCompleteness(stored.manifest, rows);')
  expect(w).toContain('if (it.completeness_required === true && completeness.status !== "complete") {')
  expect(w).toContain('await rec({ p_error: `held_incomplete: ${completeness.reason || completeness.status}`.slice(0, 400), p_result: result, p_cost: c1 });')
  expect(ENTRY_PROMPT_VERSION).toMatch(/^entry-matrix-v0\.1\.([3-9]|[1-9][0-9])$/)  // v0.1.4 (s134) adds the cell list
  expect(ENTRY_PROMPT).toContain("Read every qualification column of such a table")
  expect(ENTRY_PROMPT).toContain("never the cell alone")
})
