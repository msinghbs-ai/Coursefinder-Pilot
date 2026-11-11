// Guards: F-AER.08 steps 3 and 4, course links and the grid route (Platform Admin 11 Nov 2026 decision 2 "Code, title, then AI match, with verification": AI or similarity only suggests, a person links what is ambiguous, confirmed links are reused; decision 1: every minimum maps to exactly one course, shadow validation before admission)
// Measured 12 Nov 2026 against the live catalogue: Sydney prints a CRICOS code on every row (89 of 89 labels link by code); UNSW and UQ print none
// (44 of 65 and 49 of 54 link by exact title and level). The rest wait for a person in Layer 4 with suggested courses.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import zlib from 'node:zlib'
import { execFileSync } from 'node:child_process'

async function load(file, name) {
  const out = path.join(os.tmpdir(), `${name}-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', [file, '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`])
  return import(out)
}
const M = fs.readFileSync('supabase/migrations/20261112213100_cf247_aer_course_links.sql', 'utf8')
const refs = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/country-refs.json', 'utf8'))
const Q = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/qualifications.json', 'utf8'))
const LIST = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/grid-heading-list.json', 'utf8'))

test('a course is linked only by its CRICOS code or a unique exact title at a level the label names; otherwise a person decides', () => {
  expect(M).toMatch(/-- 1 the CRICOS code printed on the row, at this provider, one active course/)
  expect(M).toMatch(/cardinality\(v_ids\) = 1 then v_method := 'cricos'/)
  expect(M).toMatch(/s\.short_code = any \(v_levels\)/)
  expect(M).toMatch(/cardinality\(v_ids\) = 1 then v_method := 'title'/)
  // suggestions are stored for a person and never become a link by themselves
  expect(M).toMatch(/'unresolved', 'none', nullif\(v_code, ''\), v_cand/)
  expect(M).not.toMatch(/'confirmed', 'none'/)
  // a confirmed link is reused, a person's "no catalogue course" stands
  expect(M).toMatch(/if l\.state = 'confirmed' then return l\.course_id; end if;/)
  expect(M).toMatch(/if l\.state = 'rejected' then return null; end if;/)
  // the link is made before the identity (the course is part of a row's identity)
  expect(M).toContain('create or replace trigger provider_entry_matrix_0_course_link before insert')
})

test('an unlinked course row cannot be admitted, a per-course qualification row is never admitted as the provider\'s, and grid reads stay with a person', () => {
  expect(M).toContain("then 'the course is not linked to a catalogue course (Layer 4 course links)'")
  expect(M).toMatch(/q\.course_label is not null and q\.course_id is null;\n\s+if v_qc > 0 then[\s\S]*?v_fix := false;/)
  expect(M).toMatch(/'pdf-grid-v1' and security\.pipeline_num_v1\('aer\.grid_machine_admission_on', 0\) < 1/)
  expect(M).toMatch(/'aer\.grid_machine_admission_on'[\s\S]*?'number', to_jsonb\(0\)/)
  // every edited live function is md5-guarded; nothing is dropped or deleted
  for (const h of ['2cdbd0a839cb928be0983509e3c68670', '78ca8d1f195a285c1736338768bfaa54', '9b4aed8b80471beaac513cdf0aa55e3d', '4a18fbc05936dc6ae20b33c70345770c']) expect(M).toContain(`'${h}'`)
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  // a person's link is a Layer 4 reviewer's decision with a reason, recorded, and only the label's waiting rows take it
  expect(M).toMatch(/admin_entry_course_link_decide[\s\S]*?current_role_rank\(\) < 3[\s\S]*?length\(v_reason\) < 5[\s\S]*?m\.status = 'proposed'[\s\S]*?admin_control_events/)
})

test('the grid keeps each course row\'s CRICOS code (Sydney: every course row), never as a minimum', async () => {
  const { pdfGrids2 } = await load('supabase/functions/coverage-sweep/pdf-grid.ts', 'grid')
  const eg = await load('supabase/functions/coverage-sweep/entry-grid.ts', 'egrid')
  const g = pdfGrids2(JSON.parse(zlib.gunzipSync(fs.readFileSync('tests/fixtures/entry-matrix/pdf/sydney.json.gz')).toString()).pages)
  const r = eg.entryGridRead(g.tables, refs, Q.qualifications, eg.entryGridHeadingList(LIST))
  const labels = new Set(r.answer.rows.map((x) => x.course_name))
  const coded = new Set(r.answer.rows.filter((x) => /^[0-9]{6}[0-9A-Z]$/.test(x.conditions.cricos_code || '')).map((x) => x.course_name))
  expect(labels.size).toBe(89)
  expect(coded.size).toBe(89)
  expect(r.answer.rows.find((x) => x.course_name === 'B Arts').conditions.cricos_code).toBe('000705M')
  expect(r.answer.rows.some((x) => /cricos/i.test(x.qualification_name))).toBe(false)
  // UNSW prints no code: its rows carry none (linked by title)
  const u = pdfGrids2(JSON.parse(zlib.gunzipSync(fs.readFileSync('tests/fixtures/entry-matrix/pdf/unsw.json.gz')).toString()).pages)
  expect(eg.entryGridRead(u.tables, refs, Q.qualifications, eg.entryGridHeadingList(LIST)).answer.rows.some((x) => x.conditions.cricos_code)).toBe(false)
})

test('worker v0.73.0 reads a proven grid only with its switch, before a PDF is held, and names its reader; Layer 4 shows course links', () => {
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(ix).toMatch(/(?:const WORKER = "coverage-sweep-worker-v0\.73\.0"; |\/\/ was v0\.73\.0 )\/\/ v0\.73\.0 \(12 Nov 2026, CF-247 F-AER\.08/)
  expect(ix).toMatch(/Number\(ws\["reading\.entry_grid_reader_on"\]\) >= 1 \? pdfGrids2\(stored\.pdfPages\)/)
  expect(ix).toMatch(/if \(stored\.pdf && stored\.pdf\.status !== "ok" && !grid\)/)
  expect(ix).toContain('entryGridHeadingList(ws["reading.entry_grid_headings"])')
  expect(ix).toMatch(/gridRead \? \{ reader: ENTRY_GRID_READER/)
  expect(ix).toMatch(/if \(!cellRead && !gridRead\) await pool/)
  const ui = fs.readFileSync('src/AerCourseLinks.jsx', 'utf8'), inbox = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
  expect(ui).toContain("call('admin_entry_course_link_decide'")
  expect(ui).toContain("call('admin_entry_course_links'")
  expect(ui).toMatch(/Suggestions are only suggestions/)
  expect(inbox).toContain('<AerCourseLinks providerId={aer.provider_id}')
})

test('recovery: the held UNSW, Sydney and UQ PDFs are read again only with the grid switch on, on the proven stored copies, never an item a person holds', () => {
  const r = fs.readFileSync('supabase/migrations/20261112233100_cf247_aer_grid_reread.sql', 'utf8')
  expect(r).toContain("pipeline_num_v1('reading.entry_grid_reader_on', 0) < 1")
  for (const h of ['be64345329d911fcaa1fab3b261f4529f39b32cd73832f4962f657f84112b0a9', 'bb850ce1acc52800c2ee250233eb48ec58c8e1719c85c2d7373824c8eec198d1', 'b0f7b80368299d165fd90c501ce647cbb7a885661a8dfcf10e2b10acfc9cf62d']) expect(r).toContain(h)
  expect(r).toMatch(/claimed_at is not null or li\.assigned_to is not null/)
  expect(r).toContain('public.admin_entry_matrix_reread(ids,')
  expect(r).not.toMatch(/^\s*(update|delete|insert|drop)\b/im)
})

test('production verification: the printed course is part of a row\'s identity (streams of one course), and the ATAR column is a course fact, read again', () => {
  const r = fs.readFileSync('supabase/migrations/20261113013100_cf247_aer_grid_identity_and_atar.sql', 'utf8')
  expect(r).toContain("'915df18ea188103fbf0f9978bdd25536'")
  expect(r).toContain("jsonb_build_object('key', 'course: ' || btrim(new.course_label))")
  expect(r).toMatch(/when 'ATAR=AU' then 'ATAR=fact'/)
  const list = JSON.parse(fs.readFileSync('tests/fixtures/entry-cells/grid-heading-list.json', 'utf8'))
  expect(list).toContain('ATAR=fact')
  expect(list).not.toContain('ATAR=AU')
  expect(r).toMatch(/claimed_at is not null or li\.assigned_to is not null/)
  expect(r).not.toMatch(/^\s*(delete|drop)\b/im)
  // one stored PDF per worker call (the CPU allowance); a further PDF goes back without spending a try
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(ix).toMatch(/(?:const WORKER = "coverage-sweep-worker-v0\.74\.1"; |\/\/ was v0\.74\.1 )\/\/ v0\.74\.1 /)  // current, or kept as "was" by a later version (F-SCH.01 is v0.75.0)
  expect(ix).toMatch(/pdfTaken\+\+ >= Math\.max\(1, Number\(ws\["reading\.entry_pdf_per_call"\]\) \|\| 1\)\) \{ await rec\(\{ p_error: "time budget" \}\)/)
  expect(r).toContain("'reading.entry_pdf_per_call'")
})
