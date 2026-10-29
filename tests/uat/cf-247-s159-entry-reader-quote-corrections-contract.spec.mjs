// Guards: CF-247 AER reader corrections (Platform Admin mandate 28 Oct 2026 23:22; decision 29 Oct 2026 09:57): structure-driven line forms let printed cells be quoted for Federation, Otago Polytechnic, Wollongong and UWA; every gate unchanged
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import zlib from 'node:zlib'
import { createHash } from 'node:crypto'
import { entryTables, entryMatrixParsed, headerBand } from '../../supabase/functions/coverage-sweep/entry.ts'
import { pdfTables } from '../../supabase/functions/coverage-sweep/pdf.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'

const pdf = (n) => JSON.parse(zlib.gunzipSync(fs.readFileSync(`tests/fixtures/entry-matrix/pdf/${n}.json.gz`))).pages
const html = (n) => fs.readFileSync(`tests/fixtures/entry-matrix/quote-corrections/${n}.html`, 'utf8')
const row = (x) => ({ country_code: 'AU', country_name: 'Australia', study_level: null, qualification_name: 'Qualification', min_grade: null, min_value: null, grade_scale: 'none', benchmark_band: null, course_name: null, conditions: {}, confidence: 0.9, ...x })
const gate = (page, lines, x) => entryMatrixParsed({ rows: [row(x)] }, page, lines)
const why = (r) => r.dropped[0]?.reason ?? 'kept'
// a structure-aware read (outside the completeness guard), as the worker's storedText gives it
const htmlRead = (h) => { const t = entryTables(h, htmlToText, true); return { page: t.text, lines: t.lines, t } }
const pdfRead = (pages) => { const t = pdfTables(pages); return { page: t.text, lines: Object.assign([], { forms: t.forms }), t } }

test('Federation (stored PDF, ruled-cells-v1): a row\'s first cell with its Undergraduate cell is the printed row; the text read is unchanged', () => {
  const { page, lines, t } = pdfRead(pdf('federation'))
  expect(t.status).toBe('ok')
  // the live drop (item 381f479f, 28 of 35): the model quotes the country with the third column; the line prints the second between them
  const q = 'COUNTRY: Italy | Undergraduate Entry: Completion of Esame di Stato with overall average of 60%.'
  expect(page).toContain('| COUNTRY: Italy | Higher Education Diploma Entry: Completion of Esame di Stato with an overall average of 55%. | Undergraduate Entry: Completion of Esame di Stato with overall average of 60%. |')
  expect(why(gate(page, [], { quote: q, min_grade: '60%', min_value: 60, grade_scale: 'percentage' }))).toBe('quote_not_on_page')  // v0.51.0
  const ok = gate(page, lines, { country_code: 'IT', quote: q, min_grade: '60%', min_value: 60, grade_scale: 'percentage', study_level: 'Undergraduate' })
  expect(why(ok)).toBe('kept')
  expect(ok.rows[0].quote).toBe(q)
  expect(why(gate(page, lines, { quote: 'COUNTRY: Albania | Undergraduate Entry: Case-by-case basis' }))).toBe('kept')
  // the forms sit beside the text: the model reads exactly what it read before
  expect(page).not.toContain('| COUNTRY: Albania | Undergraduate Entry: Case-by-case basis |')
  expect(t.forms).toContain('| COUNTRY: Albania | Undergraduate Entry: Case-by-case basis |')
})

test('Federation negatives: a value not printed, a paraphrase and a cell from another row are still refused', () => {
  const { page, lines } = pdfRead(pdf('federation'))
  expect(why(gate(page, lines, { quote: 'COUNTRY: Italy | Undergraduate Entry: Completion of Esame di Stato with overall average of 65%.', min_grade: '65%', min_value: 65, grade_scale: 'percentage' }))).toBe('quote_not_on_page')
  expect(why(gate(page, lines, { quote: 'COUNTRY: Albania | Undergraduate: Case by case' }))).toBe('quote_not_on_page')
  expect(why(gate(page, lines, { quote: 'COUNTRY: Albania | Undergraduate Entry: Completion of Esame di Stato with overall average of 60%.' }))).toBe('quote_not_on_page')
  // a grade the quoted cell does not print is still not in the quote
  expect(why(gate(page, lines, { quote: 'COUNTRY: Italy | Undergraduate Entry: Completion of Esame di Stato with overall average of 60%.', min_grade: '70%' }))).toBe('grade_not_in_quote')
})

test('UWA: a table\'s header line quoted with one of its rows is on the page; a header with a row of another table is not', () => {
  const { page, lines } = htmlRead(html('uwa-score-tables'))
  // the live drop (item c70b3d2a, 27 quote_not_on_page: NCUK, Norway, Singapore): header line + a row other than the first
  const q = 'NCUK | ATAR equivalent NCUK: 9 | ATAR equivalent: 80.00'
  expect(why(gate(page, [], { country_code: 'GB', quote: q, min_grade: '9', min_value: 9, grade_scale: 'points', benchmark_band: '80.00' }))).toBe('quote_not_on_page')
  expect(why(gate(page, lines, { country_code: 'GB', quote: q, min_grade: '9', min_value: 9, grade_scale: 'points', benchmark_band: '80.00' }))).toBe('kept')
  expect(why(gate(page, lines, { quote: 'NCUK | ATAR equivalent French Baccalaureat Points: 12 | ATAR equivalent: 80' }))).toBe('quote_not_on_page')
  expect(why(gate(page, lines, { quote: 'NCUK | ATAR equivalent NCUK: 9 | ATAR equivalent: 81.00', benchmark_band: '81.00' }))).toBe('quote_not_on_page')
})

test('UWA: a band given with its column header\'s words is the printed cell only when the whole row is quoted', () => {
  const { page, lines } = htmlRead(html('uwa-score-tables'))
  const fr = 'French Baccalaureat Points: 10 | ATAR equivalent: 70'
  const x = { country_code: 'FR', quote: fr, min_grade: '10', min_value: 10, grade_scale: 'points' }
  // the live drop (101 band_not_in_quote): every quote prints its band cell; the band text given is not in the quote as written
  expect(why(gate(page, [], { ...x, benchmark_band: 'ATAR 70' }))).toBe('band_not_in_quote')  // v0.51.0
  const ok = gate(page, lines, { ...x, benchmark_band: 'ATAR 70' })
  expect(why(ok)).toBe('kept')
  expect(ok.rows[0].benchmark_band).toBe('70')  // the cell as printed, never the model's wording
  // a worded grade table and a range table with a header row of words
  const gb = gate(page, lines, { country_code: 'GB', quote: 'CDD | 7 | 70', min_grade: 'CDD', grade_scale: 'letter', benchmark_band: 'ATAR 70' })
  expect([why(gb), gb.rows[0]?.benchmark_band]).toEqual(['kept', '70'])
  const ie = gate(page, lines, { country_code: 'IE', quote: '330 to 339 | 76', min_grade: '330 to 339', grade_scale: 'points', benchmark_band: 'ATAR 76' })
  expect([why(ie), ie.rows[0]?.benchmark_band]).toEqual(['kept', '76'])
  // negatives: another number, words not in the column header, a part of the row, a band printed in no row the quote holds
  expect(why(gate(page, lines, { ...x, benchmark_band: 'ATAR 75' }))).toBe('band_not_in_quote')
  expect(why(gate(page, lines, { ...x, benchmark_band: 'Selection rank 70' }))).toBe('band_not_in_quote')
  expect(why(gate(page, lines, { ...x, quote: 'ATAR equivalent: 70', min_grade: null, min_value: null, grade_scale: 'none', benchmark_band: 'ATAR 70' }))).toBe('band_not_in_quote')
  expect(why(gate(page, lines, { ...x, benchmark_band: 'ATAR 70.00' }))).toBe('band_not_in_quote')
  expect(headerBand('ATAR 70', 'frenchbaccalaureatpoints10atarequivalent70', [])).toBe(null)
  expect(headerBand('70', 'frenchbaccalaureatpoints10atarequivalent70', [{ line: fr, cells: [{ h: 'ATAR equivalent', c: '70' }] }])).toBe(null)
})

test('UWA: a table that is neither headed nor labelled is read as before (Gao Kao stays as published)', () => {
  const { page, t } = htmlRead(html('uwa-score-tables'))
  expect(page).toContain('\n488 to 491 | 65% | 70\n')
  expect(t.labelled).toBe(0)
})

test('Wollongong: a matrix with an empty top-left cell is a header; its header line with any row is quotable', () => {
  const { page, lines, t } = htmlRead(html('uow-country-matrix'))
  expect(t.heads.length).toBe(5)
  const hdr = ' | Foundation Studies (2-session) | Diploma (3-session) | Diploma (2-session) | Bachelor Degree - Group 1 | Bachelor Degree - Group 2 | Bachelor Degree - Group 3'
  expect(page).toContain(`\n${hdr}\n`)
  // the live drop (item 50b5cbf6, 61 of the 75 quote_not_on_page begin with the header line): header + the second or later row
  const q = `| Foundation Studies (2-session) | Diploma (3-session) | Diploma (2-session) | Bachelor Degree - Group 1 | Bachelor Degree - Group 2 | Bachelor Degree - Group 3\nUEC | - | 8 | 12 | 18 | 20 | 23`
  const x = { country_code: 'MY', quote: q, study_level: 'Bachelor Degree - Group 2', min_grade: '20', min_value: 20, grade_scale: 'aggregate' }
  expect(why(gate(page, [], x))).toBe('quote_not_on_page')
  expect(why(gate(page, lines, x))).toBe('kept')
  // negatives: a row of another table under this header, a value not printed, and a row joined to a note it is not printed beside
  expect(why(gate(page, lines, { ...x, quote: `${q.split('\n')[0]}\nCSAT | 255 | 260 | 280 | 305 | 333 | 349` }))).toBe('quote_not_on_page')
  expect(why(gate(page, lines, { ...x, quote: `${q.split('\n')[0]}\nUEC | - | 8 | 12 | 18 | 21 | 23`, min_grade: '21', min_value: 21 }))).toBe('quote_not_on_page')
  expect(why(gate(page, lines, { country_code: 'KR', quote: 'CSAT | 255 | 260 | 280 | 305 | 333 | 348\nAssessment methodology Scores are based on an aggregate calculated from the standard scores' }))).toBe('quote_not_on_page')
})

test('Otago Polytechnic: a table with no header row carries the label printed just above it; a country appended to a cell is still refused', () => {
  const h = html('otago-country-tables')
  const { page, lines, t } = htmlRead(h)
  expect(t.labelled).toBe(4)
  expect(page).toContain('\nArgentina | NCEA Level 2 Certificate/Diploma Level | Titulo de Bachiller OR Titulo de Técnico-Auxiliar\n')
  expect(page).toContain('\nArgentina | NCEA Level 3 Degree Level | Trayecto Técnico Profesional OR Successful completion of one (1) full year of tertiary studies')
  const ok = gate(page, lines, { country_code: 'AU', quote: 'Australia | NCEA Level 3 Degree Level | Successful completion of Year 12, AND ATAR score of 65 or above', study_level: 'NCEA Level 3 Degree Level', min_grade: 'ATAR score of 65 or above', min_value: 65, grade_scale: 'rank' })
  expect(why(ok)).toBe('kept')
  // the live drop (item 5e40fcd8): the country written after the last row of its own table is not printed there
  expect(why(gate(page, lines, { country_code: 'AR', quote: 'NCEA Level 3 Degree Level | Trayecto Técnico Profesional OR Successful completion of one (1) full year of tertiary studies at a recognised tertiary institution, OR Completion of an appropriate Otago Polytechnic pathway programme Argentina' }))).toBe('quote_not_on_page')
  expect(why(gate(page, lines, { country_code: 'AU', quote: 'NCEA Level 3 Degree Level | Successful completion of Year 12, AND ATAR score of 65 or above Australia' }))).toBe('quote_not_on_page')
  // a grade the cell does not print stays refused (live grade_not_in_quote, 11): Kenya's Level 2 cell names the certificate only
  expect(why(gate(page, lines, { country_code: 'KE', quote: 'Kenya | NCEA Level 2 Certificate/Diploma Level | Kenya Certificate of Secondary Education (KCSE)', min_grade: 'C plain' }))).toBe('grade_not_in_quote')
  // a value not printed and a paraphrase are refused
  expect(why(gate(page, lines, { quote: 'Australia | NCEA Level 3 Degree Level | Successful completion of Year 12, AND ATAR score of 70 or above', min_value: 70, grade_scale: 'rank' }))).toBe('quote_not_on_page')
  expect(why(gate(page, lines, { quote: 'Australia | Degree Level | Year 12 completed with an ATAR of 65' }))).toBe('quote_not_on_page')
})

test('off under the completeness guard and wherever the caller does not ask: the text and the gate are as before', () => {
  for (const n of ['otago-country-tables', 'uow-country-matrix', 'uwa-score-tables']) {
    const off = entryTables(html(n), htmlToText)
    expect([off.forms.length, off.heads.length, off.labelled]).toEqual([0, 0, 0])
    expect(off.text).not.toMatch(/^(Algeria|Argentina) \| /m)
  }
  expect(entryTables(html('otago-country-tables'), htmlToText).text).toContain('\nNCEA Level 2 Certificate/Diploma Level | Titulo de Bachiller OR Titulo de Técnico-Auxiliar\n')
})

test('worker v0.52.0 passes the structure with the band lines, read only outside the completeness guard; the gate call is unchanged', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const ai = w.slice(w.indexOf('if (mode === "entry_ai") {'), w.indexOf('if (mode === "fee_ai") {'))
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(5[2-9]|[6-9]\d)\.\d+"/)
  expect(ai).toContain('lines: Object.assign([] as EntryBandLine[], { forms: t.forms }) as EntryLineSet')
  expect(ai).toContain('const tb = entryTables(t, htmlToText, nameNumbers), md = entryManifestDetail(t, htmlToText); return { text: tb.text, lines: tb.lines, manifest: md.manifest')
  const t = entryTables(html('uow-country-matrix'), htmlToText, true)
  expect([t.lines.forms.length, t.lines.heads.length]).toEqual([t.forms.length, t.heads.length])  // the band lines carry the structure to the gate
  expect(ai).toContain('const stored = await storedText(it.storage_path, it.mime, Number(it.pdf_max_pages) || 40, it.completeness_required !== true), page = stored.text;')
  expect(ai).toContain('const parsed = entryMatrixParsed(JSON.parse(content), page, stored.lines);')
  for (const r of ['quote_too_short', 'quote_not_on_page', 'value_without_scale', 'value_not_in_quote', 'grade_not_in_quote', 'band_ambiguous', 'band_missing', 'band_not_in_quote', 'band_mismatch']) expect(fs.readFileSync('supabase/functions/coverage-sweep/entry.ts', 'utf8')).toContain(`d("${r}")`)
})

test('fixtures are the recorded excerpts', () => {
  const readme = fs.readFileSync('tests/fixtures/entry-matrix/quote-corrections/README.md', 'utf8')
  for (const n of ['uwa-score-tables', 'uow-country-matrix', 'otago-country-tables']) {
    const sha = createHash('sha256').update(fs.readFileSync(`tests/fixtures/entry-matrix/quote-corrections/${n}.html`)).digest('hex')
    expect(readme).toContain(`| ${n}.html |`)
    expect(readme).toContain(sha)
  }
})
