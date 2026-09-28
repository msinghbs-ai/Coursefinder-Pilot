import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

// CF-247 Decision 162 step 4: UQ English Language Proficiency Table 1 (higher-than-minimum programs) and Table 3
// (minimum entry). Items below are taken from the real Table 1 layout (last approved 12 Dec 2025): wrapped names,
// several programs sharing one requirement block, a program printed just above its block, "sub-" / "band" split
// across lines, explicit TOEFL/PTE scores, and the research section header.
async function load() {
  const out = path.join(os.tmpdir(), `elp-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/fee-schedule-etl/elp.ts', '--format=esm', `--outfile=${out}`])
  return import(out)
}
const I = (p, x, y, s) => ({ p, x, y, s })
const hdr = (p) => [I(p, 34, 490.4, 'Programs'), I(p, 225.1, 490.4, 'Ways to satisfy ELP entry requirement')]
const ielts = (p, y, o, rest) => [I(p, 225.1, y, 'IELTS'), I(p, 250.7, y, ':'), I(p, 255.7, y, 'Overall Band Score'), I(p, 341.3, y, `of ${o}`), I(p, 358.8, y, 'AND'), I(p, 380.8, y, rest)]
const items = [
  ...hdr(3),
  I(3, 34, 473.9, 'Master of Finance and Investment'), ...ielts(3, 473.9, 7, 'a minimum score of 6 in each sub-band of Writing, Reading, Speaking and Listening'),
  I(3, 34, 463.6, 'Management'),
  I(3, 225.1, 457.6, 'TOEFL iBT (including Paper Edition)'), I(3, 380.8, 457.6, ': Overall 100, listening 19, reading 19, writing 21, speaking 19'),
  I(3, 34, 447.2, 'Graduate Certificate in Finance and'), I(3, 225.1, 441.2, 'PTE Academic'), I(3, 287.8, 441.2, ': Overall 72, all sub bands minimum 60'),
  I(3, 34, 436.9, 'Investment Management'), I(3, 225.1, 375.8, 'Clause 11(b), (e)-(g) of'),
  I(3, 34, 228.2, 'Bachelor of Laws (Honours) (64 units)'),
  ...ielts(3, 228.2, 7, 'a minimum score of 7 in each sub'), I(3, 515.4, 228.2, '-'), I(3, 518.4, 228.2, 'band of Writing and Speaking, and a minimum score of 6 in each sub'), I(3, 793.6, 228.2, '-'),
  I(3, 225.1, 217.9, 'band of Reading and Listening'), I(3, 225.1, 201.6, 'BE:'),
  I(3, 28.3, 28.6, 'Last approved: 12 December 2025'),
  ...hdr(4),
  I(4, 34, 375.6, 'Bachelor of Exercise and Sports Sciences'), ...ielts(4, 375.6, 7, 'a minimum score of 7 in each sub-band of Writing, Reading, Speaking and Listening'),
  I(4, 34, 365.3, '(Honours)'), I(4, 34, 349, 'Bachelor of Midwifery (Honours)'), I(4, 34, 332.6, 'Bachelor of Nursing (Honours)'),
  I(4, 34, 316.2, 'Bachelor of Social Work'), I(4, 34, 299.9, 'Bachelor of Social Work (Honours)'), I(4, 225.1, 299.9, 'Language Proficiency Admission —Table 2'),
  I(4, 225.1, 283.6, 'Clause 11(e) and (f) of'),
  I(4, 34, 261, 'Bachelor of Clinical Exercise Physiology'), ...ielts(4, 261, 7, 'a minimum score of 7 in each sub-band of Writing, Reading, Speaking and Listening'),
  I(4, 34, 250.7, '(Honours)'), I(4, 34, 234.2, 'Bachelor of Dental Science (Honours)'), I(4, 225.1, 174.8, 'Clause 11 (e) and (f) of'),
  I(4, 34, 152.4, 'Bachelor of Midwifery'), I(4, 225.1, 149.8, 'IELTS: Overall Band Score'), I(4, 341.8, 149.8, 'of 7'), I(4, 359.3, 149.8, 'AND'),
  I(4, 381.2, 149.8, 'a minimum score of 7 in each sub-band of Writing, Reading, Speaking and Listening'),
  I(4, 34, 136, 'Bachelor of Nursing'), I(4, 34, 119.6, 'Bachelor of Nursing/Bachelor of Midwifery'),
  ...hdr(9),
  I(9, 34, 473.9, 'Master of Teaching (Primary)'), ...ielts(9, 473.9, 7.5, 'a minimum score of 8 in Listening and Speaking and 7 in Writing and Reading'),
  I(9, 34, 457.6, 'Master of Teaching (Secondary)'), I(9, 225.1, 457.6, 'Note: other tests and Bridging English (BE) are not accepted'),
  I(9, 34, 247.8, 'HIGHER'), I(9, 68.9, 247.8, '-'), I(9, 71.9, 247.8, 'THAN'), I(9, 96.8, 247.8, '-'), I(9, 99.8, 247.8, 'MINIMUM ELP POSTGRADUATE RESEARCH PROGRAMS'),
  I(9, 34, 231.2, 'Higher Degree by Research in the Health'), ...ielts(9, 231.2, 7, 'a minimum score of 7 in each sub-band of Writing, Reading, Speaking and Listening'),
  I(9, 34, 220.9, 'Sciences where research is undertaken in a'), I(9, 34, 210.5, 'clinical placement setting'),
  I(9, 34, 194.2, 'Doctor of Veterinary Clinical Science'), ...ielts(9, 194.2, 7, 'a minimum score of 7 in each sub-band of Writing, Reading, Speaking and Listening'),
]

test('UQ Table 1: programs, shared blocks, wrapped names and component bands', async () => {
  const { parseUqTable1 } = await load()
  const r = parseUqTable1(items)
  expect(r.issues).toEqual([])
  expect(r.unassigned).toEqual([])
  const by = Object.fromEntries(r.programs.map((p) => [p.name, p]))
  expect(Object.keys(by)).toEqual([
    'Master of Finance and Investment Management', 'Graduate Certificate in Finance and Investment Management', 'Bachelor of Laws (Honours) (64 units)',
    'Bachelor of Exercise and Sports Sciences (Honours)', 'Bachelor of Midwifery (Honours)', 'Bachelor of Nursing (Honours)', 'Bachelor of Social Work',
    'Bachelor of Social Work (Honours)', 'Bachelor of Clinical Exercise Physiology (Honours)', 'Bachelor of Dental Science (Honours)', 'Bachelor of Midwifery',
    'Bachelor of Nursing', 'Bachelor of Nursing/Bachelor of Midwifery', 'Master of Teaching (Primary)', 'Master of Teaching (Secondary)',
    'Higher Degree by Research in the Health Sciences where research is undertaken in a clinical placement setting', 'Doctor of Veterinary Clinical Science'])
  const i = (n) => by[n].requirements.find((q) => q.test_code === 'IELTS')
  expect(i('Graduate Certificate in Finance and Investment Management')).toEqual({ test_code: 'IELTS', overall_score: 7, component_scores: { writing: 6, reading: 6, speaking: 6, listening: 6 } })
  expect(by['Master of Finance and Investment Management'].requirements.map((q) => q.test_code)).toEqual(['IELTS', 'TOEFL_IBT', 'PTE'])
  expect(i('Bachelor of Laws (Honours) (64 units)').component_scores).toEqual({ writing: 7, speaking: 7, reading: 6, listening: 6 })
  expect(i('Bachelor of Social Work (Honours)').overall_score).toBe(7)
  expect(i('Bachelor of Midwifery').component_scores).toEqual({ writing: 7, reading: 7, speaking: 7, listening: 7 })
  expect(i('Master of Teaching (Secondary)')).toEqual({ test_code: 'IELTS', overall_score: 7.5, component_scores: { listening: 8, speaking: 8, writing: 7, reading: 7 } })
  expect(by['Master of Teaching (Secondary)'].other_tests).toBe('not_accepted')
  expect(by['Doctor of Veterinary Clinical Science'].section).toBe('research')
  expect(by['Higher Degree by Research in the Health Sciences where research is undertaken in a clinical placement setting'].section).toBe('research')
  expect(by['Master of Teaching (Primary)'].section).toBe('coursework')
})

test('UQ Table 1: a skill stated twice or a missing overall is refused, not guessed', async () => {
  const { parseIelts } = await load()
  expect(parseIelts('IELTS: Overall Band Score of 7 AND a minimum score of 7 in Writing and 6 in Writing')).toBeNull()
  expect(parseIelts('IELTS: a minimum score of 7 in each sub-band of Writing')).toBeNull()
  expect(parseIelts('IELTS: Overall Band Score of 7 AND a minimum score of 7 in each sub-band of Writing, Reading and Listening and a score of 8 in Speaking'))
    .toEqual({ overall: 7, components: { writing: 7, reading: 7, listening: 7, speaking: 8 } })
})

test('UQ Table 3 minimum entry row set', async () => {
  const { parseUqTable3Minimum } = await load()
  const rows = ['English Language Proficiency Tables', 'UQ minimum entry (see | English Language Proficiency Admission Procedure Section 3 | )', 'Overall Score | L | R | W | S',
    'IELTS | Academic* | 6.5 | 6.0 | 6.0 | 6.0 | 6.0', 'TOEFL iBT | (inc. | 87 | 19 | 19 | 21 | 19', 'Paper Edition**)', 'PTE Academic | 64 | 60 | 60 | 60 | 60', 'CES | 176 | 169 | 169 | 169 | 169',
    'UQ higher than minimum entry (See | English Language Proficiency Admission | — | Table 1 | for', 'IELTS Academic* | 8.0 | 8.0 | 8.0 | 8.0 | 8.0']
  const r = parseUqTable3Minimum(rows)
  expect(r.issues).toEqual([])
  expect(r.requirements).toEqual([
    { test_code: 'IELTS', overall_score: 6.5, component_scores: { listening: 6, reading: 6, writing: 6, speaking: 6 } },
    { test_code: 'TOEFL_IBT', overall_score: 87, component_scores: { listening: 19, reading: 19, writing: 21, speaking: 19 } },
    { test_code: 'PTE', overall_score: 64, component_scores: { listening: 60, reading: 60, writing: 60, speaking: 60 } }])
})

test('English table worker and planning contract', () => {
  const w = fs.readFileSync('supabase/functions/fee-schedule-etl/index.ts', 'utf8')
  expect(w).toContain('const VERSION = "fee-schedule-etl-v0.7.1";')
  expect(w).toContain('mode === "elp_dry_run" || mode === "elp_apply"')
  const m = fs.readFileSync('supabase/migrations/20260928190000_d162_english_table_plan.sql', 'utf8')
  expect(m).toContain("'double degree: the policy has no double-degree rule'")
  expect(m).toContain("'research degree: Table 1 research rule is not tied to a named program'")
  expect(m).toContain("'close to a Table 1 program name: review'")
  expect(m).toContain('only courses with no English requirement are written')
})

test('UQ English: Search gate and double-degree higher-component rule contract', () => {
  const g = fs.readFileSync('supabase/migrations/20260929090000_d162_uq_english_search_gate.sql', 'utf8')
  expect(g).toContain("'courses','course_english',s.id,'approved'")
  expect(g).toContain("if v_n<>1 then raise exception 'expected 1 new Search gate")
  expect(g).toContain('security.consumer_api_snapshot_v1()')
  const d = fs.readFileSync('supabase/migrations/20260929091000_d162_english_double_degree_higher_component.sql', 'utf8')
  expect(d).toContain("when v_double='higher_component_v1' then case when ddr.n_t1=1 then 'table1' else 'minimum' end")
  expect(d).toContain("'double degree: component not recognised ('||ddr.unknown||')'")
  expect(d).toContain("'double degree: components carry different Table 1 requirements'")
  expect(d).toContain("exists(select 1 from p p2 where p2.k=btrim(comp.c) and p2.pl='minimum') single_min")
  const on = fs.readFileSync('supabase/migrations/20260929092000_d162_english_double_degree_rule_on.sql', 'utf8')
  expect(on).toContain("'double_degree_rule','higher_component_v1'")
})
