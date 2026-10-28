// Guards: CF-247 AER programme Step B (Platform Admin consolidated mandate 28 Oct 2026 23:22; admin docs/platform/ENTRY-REQUIREMENTS-PROGRAMME-DECISION-2026-10-28.md P4 and section 3): PDF entry matrices are rebuilt from the PDF's own drawn rules and proven before any AI read — every text item inside one column and between two row rules, each cell named by its column header, no partial table; misalignment (UQ / Macquarie style) or columns without rules fail the whole document closed
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import zlib from 'node:zlib'
import { pdfTables, PDF_METHOD } from '../../supabase/functions/coverage-sweep/pdf.ts'

const fx = (n) => JSON.parse(zlib.gunzipSync(fs.readFileSync(`tests/fixtures/entry-matrix/pdf/${n}.json.gz`))).pages
const lines = (r) => r.text.split('\n')

test('VU: four columns on every page, country sections, merged qualification cells carried, sub-rows kept apart', () => {
  const r = pdfTables(fx('vu'))
  expect(r.method).toBe(PDF_METHOD)
  expect(r.status).toBe('ok')
  expect(r.tables.every((t) => t.columns === 4)).toBe(true)
  const L = lines(r)
  expect(L).toContain('| Highest qualification | VU course | Level of completion | Result |')
  expect(L).toContain('| BHUTAN | Highest qualification: Bhutan Higher Secondary Education Certificate (BHSEC) | VU course: Diploma | Level of completion: Completed with an overall average of at least | Result: 60% |')
  expect(L).toContain('| BHUTAN | Highest qualification: Bhutan Higher Secondary Education Certificate (BHSEC) | VU course: Bachelor Courses | Level of completion: Completed with an overall average of at least | Result: 65% |')
  // two rows the page sets close together (no space between them) stay two rows
  expect(L).toContain('| CAMBODIA | Highest qualification: Diploma of Upper Secondary Education | VU course: Foundation Studies (Standard) | Level of completion: Completed with an average grade of Year 12 | Result: D |')
  expect(L).toContain('| CAMBODIA | Highest qualification: Diploma of Upper Secondary Education | VU course: Foundation Studies (Standard) | Level of completion: Completed with an average grade of Year 11 | Result: C |')
  // a cell merged over two rows (the qualification) is on each of them
  expect(L).toContain('| VIETNAM | Highest qualification: Bang Tot Nghiep Pho Thong Trung Hoc (Secondary School Graduation Certificate) | VU course: Bachelor courses | Level of completion: Completed with an overall average of | Result: 7.5 (out of 10) *Courses in Law, Health and Engineering may need 8.0 |')
  // the last row of a page printed under its last rule is still a row
  expect(L).toContain('| BHUTAN | Highest qualification: Bachelor degree | VU course: Masters (by Coursework) | Level of completion: Completed with a degree classification of | Result: 55% |')
  expect(L.filter((l) => l.startsWith('| ') && !l.startsWith('| ---')).every((l) => !/Result: .*Result:/.test(l))).toBe(true)
})

test('Federation: centred country cells and multi-paragraph cells stay in their own row; the header holds on pages without one', () => {
  const r = pdfTables(fx('federation'))
  expect(r.status).toBe('ok')
  const L = lines(r)
  expect(L).toContain('| COUNTRY | Higher Education Diploma Entry | Undergraduate Entry |')
  expect(L).toContain('| COUNTRY: Albania | Higher Education Diploma Entry: Case-by-case basis | Undergraduate Entry: Case-by-case basis |')
  const g = L.find((l) => l.startsWith('| COUNTRY: Global |'))
  expect(g).toMatch(/Higher Education Diploma Entry: .*International Baccalaureate Diploma score of 20 \(overall\) \| Undergraduate Entry: /)
  expect(g).toMatch(/Undergraduate Entry: .*International Baccalaureate Diploma score of 24 \(overall\)/)
  expect(L.find((l) => l.startsWith('| COUNTRY: India |'))).toContain('Undergraduate Entry: Completion of All India Senior School Certificate (CBSE) or Indian School Certificate (CISCE) With an average of 65% in best four academic subjects')
  // page 6 has no header row of its own: its rows are still named
  expect(L.find((l) => l.startsWith('| COUNTRY: Zimbabwe |'))).toContain('Undergraduate Entry: Zimbabwe School Examination Council')
})

test('WSU: two tables on one page, seven columns each, every level column named', () => {
  const r = pdfTables(fx('wsu'))
  expect(r.status).toBe('ok')
  expect(r.tables.every((t) => t.columns === 7)).toBe(true)
  const b = lines(r).find((l) => l.startsWith('| Qualification: Bangladesh |'))
  expect(b).toContain('| 3 Semester Diploma: Successful completion of HSC with a GPA of 3.0 or Edexcel GCE A Level examination with a score of 4 in 2 Advanced Level core subjects')
  expect(lines(r).find((l) => l.startsWith('| Qualification: Indian School Certificate (ISC) |'))).toContain('| 3 Semester Diploma: Successful completion of ISCE with an overall GPA of 50% in best 4 subjects |')
})

test('Adelaide and Curtin: three columns; Curtin\'s centred cells pair each criterion with its own country', () => {
  const a = pdfTables(fx('adelaide'))
  expect(a.status).toBe('ok')
  expect(lines(a)).toContain('| Country: India | Qualifications: All India Senior School Certificate, Indian School Certificate | Minimum Entry Requirements: Successful completion of Class 12 (10+2) with an average of at least 70% in the best four approved subjects |')
  const c = pdfTables(fx('curtin'))
  expect(c.status).toBe('ok')
  expect(lines(c)).toContain('| Country: Bhutan | Qualification: Bhutan Higher Secondary Education Certificate | Minimum admission criteria: An average of 65% in the best four academic subjects excluding Dzongkha. |')
  expect(lines(c)).toContain('| Country: Canada | Qualification: High School Graduation Diploma | Minimum admission criteria: An average of 60% in Grade 12 subjects. |')
})

test('misaligned or unruled tables fail closed, whole document, with the page and the text', () => {
  for (const [n, why] of [['uq', /^page 3: columns of text with no drawn rules/], ['mq_ug', /^page 1: columns of text with no drawn rules/],
                          ['unsw', /^page 1: "ACT" is in a column without row rules$/], ['sydney', /^page 1: "38" lies inside the table but outside its columns$/]]) {
    const r = pdfTables(fx(n))
    expect(r.status, n).toBe('unparsed')
    expect(r.reason, n).toMatch(why)
    expect(r.text, n).toBe('')   // nothing of a held document is given to the model
    expect(r.tables, n).toEqual([])
  }
})

// a small ruled table: two columns, header and two rows
const page = (items, extra = []) => [{ p: 1, width: 600, height: 800, items, rules: [
  ...[700, 680, 660, 640].map((y) => ({ o: 'h', y, a: 50, b: 250 })), ...[700, 680, 660, 640].map((y) => ({ o: 'h', y, a: 250, b: 500 })), ...extra] }]
const it = (x, y, s, w = 60) => ({ x, y, w, h: 8, s })
const base = [it(55, 688, 'Country'), it(255, 688, 'Minimum'), it(55, 668, 'India'), it(255, 668, '75%', 20), it(55, 648, 'Nepal'), it(255, 648, '70%', 20)]

test('synthetic: a clean table is read as named cells', () => {
  const r = pdfTables(page(base))
  expect(r.status).toBe('ok')
  expect(lines(r)).toEqual(['| Country | Minimum |', '| --- | --- |', '| Country: India | Minimum: 75% |', '| Country: Nepal | Minimum: 70% |'])
})

test('synthetic: an item across a column edge, or across a row rule, holds the document', () => {
  expect(pdfTables(page([...base.slice(0, 4), it(200, 648, 'Nepal 70%', 120)])).reason).toBe('page 1: "Nepal 70%" crosses a column edge')
  expect(pdfTables(page([...base, it(255, 657, 'and 60% English', 80)])).reason).toBe('page 1: "and 60% English" crosses a row rule')
})

test('synthetic: no drawn rules and short cells side by side are not read as a table', () => {
  const its = [0, 1, 2, 3].flatMap((i) => [it(50, 600 - i * 12, `Row ${i}`), it(150, 600 - i * 12, '70'), it(250, 600 - i * 12, '80'), it(350, 600 - i * 12, '90')])
  const r = pdfTables([{ p: 1, width: 600, height: 800, items: its, rules: [] }])
  expect(r.status).toBe('unparsed')
  expect(r.reason).toMatch(/columns of text with no drawn rules/)
})

test('the worker holds anything not proven before any AI read, for every PDF (not only completeness providers)', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const ai = w.slice(w.indexOf('if (mode === "entry_ai") {'), w.indexOf('if (mode === "fee_ai") {'))
  expect(w).toContain('import { getDocumentProxy, getResolvedPDFJS } from "npm:unpdf@0.12.1";')
  expect(w).toContain('const t = pdfTables(await pdfPages(doc, OPS, pdfMaxPages));')
  expect(ai).toContain('const stored = await storedText(it.storage_path, it.mime, Number(it.pdf_max_pages) || 40, it.completeness_required !== true), page = stored.text;')
  expect(ai).toContain('if (stored.pdf && stored.pdf.status !== "ok") {')
  expect(ai).toContain('await rec({ p_error: `held_unparsed: PDF ${stored.pdf.reason}`.slice(0, 400)')
  expect(ai).toContain('if (!stored.pdf && /\\.pdf($|[?#])/i.test(String(it.url || ""))) {')
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(5\d)\.\d+"/)
  // the PDF is read directly (robots.txt respected), never through Firecrawl, within a size cap from the settings
  expect(ai).toContain('const readPdf = async (url: string, maxBytes: number) => {')
  expect(ai).toContain('if (!robotsAllows(await robotsFor(u), u.pathname + u.search)) return { status: "robots_disallowed"')
  expect(ai).not.toMatch(/readPdf[\s\S]{0,400}firecrawl/i)
})

test('database: PDFs wait while entry.pdf_enabled is 0 (set to 0 here); a PDF source takes only a stored PDF; settings, not constants', () => {
  const m = fs.readFileSync('supabase/migrations/20261029002000_cf247_aer_steps_b_c_pdf_and_rendered.sql', 'utf8')
  const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
  for (const k of ['entry.pdf_enabled', 'entry.pdf_max_bytes', 'entry.pdf_max_pages']) expect(code).toContain(`('pipeline', '${k}', `)
  expect(code).toContain("to_jsonb(0), 0, 1, 'on/off', 920,")
  expect(code).toContain("if security.pipeline_num_v1('entry.pdf_enabled', 0) <> 0 then raise exception")
  expect(code).toContain("if security.pipeline_num_v1('entry.pdf_enabled', 0) < 1 then\n    update pipeline.entry_matrix_sources s set status = 'pdf_step_b'")
  expect(code).toContain("update pipeline.entry_matrix_sources f set status = 'found', attempts = 0, error = null, updated_at = now()\n     where f.status = 'pdf_step_b' and security.entry_matrix_enabled_v1(f.provider_id);")
  expect(code).toContain("and (s.url !~* '\\.pdf($|[?#])' or a.mime_type = 'application/pdf')")
  expect(code).toContain("'pdf', u.url ~* '\\.pdf($|[?#])', 'pdf_max_bytes', security.pipeline_num_v1('entry.pdf_max_bytes', 20000000)::bigint")
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(code).not.toMatch(/insert into pipeline\.(automation_catalogue|admin_job_kinds)|cron\.schedule/)
  expect(code).not.toMatch(/status = '(?!found|pdf_step_b)[a-z_]+'/)  // no new status
})
