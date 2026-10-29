// Guards: Platform Admin approval 30 Oct 2026 08:45 (D5) under decision A4 (admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md §9 and §11.2; register WEBSITE-DEVELOPER-REQUIREMENTS O9): the additive Website API v2 marker scale_stated on entry_matrix items and entry.resolution rows (true stated scale, false printed grade with no stated scale, null case by case); no inferred scale; no existing key changed; option R1, the governed "Not stated on the page" scale choice in the AER workspace (G3 itself is guarded by s57)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const dir = 'supabase/migrations'
const find = suffix => {
  const f = fs.readdirSync(dir).filter(x => x.endsWith(suffix))
  expect(f, suffix).toHaveLength(1)
  return fs.readFileSync(`${dir}/${f[0]}`, 'utf8')
}
const m = find('_cf247_d5_scale_stated_marker.sql')
const r1 = find('_cf247_d5_aer_scale_not_stated.sql')
const code = s => s.split('\n').filter(l => !/^\s*--/.test(l)).join('\n')
const ui = fs.readFileSync('src/AerWorkspace.jsx', 'utf8')

// the one expression both payload parts use (stored data only: min_grade and grade_scale as a person admitted them)
const SCALE_STATED_SQL = "case when m.min_grade is null or m.grade_scale = 'none' then null else m.grade_scale is not null end"
const CASE_BY_CASE_SQL = "m.min_grade is null or m.grade_scale is not distinct from 'none'"

// ---------------------------------------------------------------- resolver fixtures
// A JS mirror of the two SQL expressions with SQL three-valued logic (null = unknown). The test below pins the mirror to the literal SQL,
// so the fixtures and the migration cannot drift. The live rolled-back dry run checked the same rows (RMIT, 30 Oct 2026).
const sqlOr = (a, b) => (a === true || b === true) ? true : (a === null || b === null) ? null : false
const eq = (a, b) => (a === null || b === null) ? null : a === b
const scaleStated = row => (sqlOr(row.min_grade === null, eq(row.grade_scale, 'none')) === true) ? null : row.grade_scale !== null
const caseByCase = row => row.min_grade === null || row.grade_scale === 'none'      // "is not distinct from": never null
const payloadScale = row => row.min_grade === null ? 'none' : row.grade_scale      // unchanged entry_matrix `scale`
const outcome = rows => rows.some(r => !caseByCase(r)) ? 'minimum_published' : 'case_by_case'

const RESOLVER_FIXTURES = [
  { name: 'stated scale (RMIT IN, AISSC, band 65%)', row: { min_grade: 'Minimum average of 65%', grade_scale: 'percentage' },
    expect: { scale: 'percentage', case_by_case: false, scale_stated: true, outcome: 'minimum_published' } },
  { name: 'printed grade, no stated scale (recorded "Not stated on the page")', row: { min_grade: 'Minimum average of 70%', grade_scale: null },
    expect: { scale: null, case_by_case: false, scale_stated: false, outcome: 'minimum_published' } },
  { name: 'case by case with the provider\'s words (RMIT NZ, NCEA, band 65%)', row: { min_grade: 'Achieved NCEA Level 3 with Merit average', grade_scale: 'none' },
    expect: { scale: 'none', case_by_case: true, scale_stated: null, outcome: 'case_by_case' } },
  { name: 'case by case, no minimum printed', row: { min_grade: null, grade_scale: 'none' },
    expect: { scale: 'none', case_by_case: true, scale_stated: null, outcome: 'case_by_case' } },
  { name: 'no minimum and no scale held', row: { min_grade: null, grade_scale: null },
    expect: { scale: 'none', case_by_case: true, scale_stated: null, outcome: 'case_by_case' } },
]

test('resolver fixtures: the three-way distinction, and no-scale rows are a published minimum, never case by case', () => {
  for (const f of RESOLVER_FIXTURES) {
    expect({ scale: payloadScale(f.row), case_by_case: caseByCase(f.row), scale_stated: scaleStated(f.row), outcome: outcome([f.row]) }, f.name).toEqual(f.expect)
  }
  // a mixed set (case by case beside a no-scale row) is minimum_published; only case-by-case rows give case_by_case
  expect(outcome([RESOLVER_FIXTURES[2].row, RESOLVER_FIXTURES[1].row])).toBe('minimum_published')
  expect(outcome([RESOLVER_FIXTURES[2].row, RESOLVER_FIXTURES[3].row])).toBe('case_by_case')
  // the mirror is the SQL: the same literal expressions are in the migration
  const c = code(m)
  expect(c.split(`'scale_stated', ${SCALE_STATED_SQL})`).length - 1).toBe(2)
  expect(c).toContain(`'case_by_case', ${CASE_BY_CASE_SQL},`)
  expect(fs.readFileSync(`${dir}/20261028005000_cf247_entry_step_b_consumer_api.sql`, 'utf8')).toContain("'scale', case when m.min_grade is null then 'none' else m.grade_scale end")
})

// ---------------------------------------------------------------- the consumer part (paste-applied)
test('approved, self-contained consumer change: md5-guarded before → after, count-guarded, baseline re-taken', () => {
  expect(m).toMatch(/^-- Consumer API change approved: Platform Admin, 30 Oct 2026 08:45 \(decision D5, admin decision §11\.2/m)
  expect(m).toMatch(/^-- Replaces: security\.entry_matrix_payload_v1, security\.entry_resolve_v1 /m)
  expect(m).toMatch(/^-- Retires: nothing$/m)
  const c = code(m)
  expect(c).toContain("if md5(v_def) = p_after then return p_sig || ': already applied'; end if;")
  expect(c).toContain("select pg_temp.edit_once('security.entry_matrix_payload_v1(uuid,text)', 'be5478d0402620cbc4c701a1e590856e', 'c1f83b82ce5c0b4b934f620a9864710f', array[")
  expect(c).toContain("select pg_temp.edit_once('security.entry_resolve_v1(uuid,text)', '492ece033520ad81cd0046c5a851bedb', '74d48db0de885e69cd98db374547b22e', array[")
  expect(c).toContain("raise exception 'count guard: % matrix rows hold a null scale before the marker exists'")
  expect(c).toContain("raise exception 'count guard: % active matrix rows, % payload items, % with scale_stated'")
  expect(c).toMatch(/select security\.consumer_api_rebaseline_v1\('D5 \(30 Oct 2026\)/)
  expect(c).not.toMatch(/\b(drop|rename|alter\s+(table|column)|delete\s+from|truncate)\b/i)
  expect(c).not.toMatch(/\b(insert\s+into|update)\s+(catalogue|pipeline)\./i)   // no data written
})

test('only the two payload parts change: one additive key; the website_v2 entry points and every edge function are untouched', () => {
  const c = code(m)
  expect(c).not.toMatch(/create\s+or\s+replace\s+function\s+(public\.)?(website_v2_|website_edge_|website_api_v2_|zoho_edge_)|function\s+api\./i)
  expect(c).not.toMatch(/edit_once\('(public\.website_v2_|security\.entry_course_payload_v1)/)
  // step 1 (course-page rows) carry null: the course reader stores no scale, so its null grade_scale is never read as "not stated"
  expect(c).toContain("'case_by_case', r.min_grade is null and r.min_entry_score is null,\n                                      'scale_stated', null::boolean)$n$")
  // every existing key of the edited row objects is still built with its unchanged expression
  for (const k of ["'band', m.benchmark_band, 'conditions', m.conditions, 'as_at', m.as_at,"]) expect(c).toContain(k)
  // no inference: the new text parses nothing and converts nothing
  const added = [...c.matchAll(/\$n\$([\s\S]*?)\$n\$/g)].map(x => x[1]).join('\n')
  expect(added).not.toMatch(/~|regexp|similar to|like|atar|percent|%|band\s*=|::numeric|min_value/i)
  for (const f of ['website-api-v2', 'wix-course-api', 'website-course-api', 'zoho-api-v2', 'zoho-course-api'])
    expect(fs.readFileSync(`supabase/functions/${f}/index.ts`, 'utf8'), f).not.toContain('scale_stated')
})

// ---------------------------------------------------------------- R1: the governed recording path (ordinary migration)
test('R1: "Not stated on the page" through the existing governed edit path; refused until the marker is live; no number without its scale', () => {
  expect(r1).toMatch(/^-- Replaces: public\.admin_aer /m)
  expect(r1).toMatch(/^-- Retires: nothing$/m)
  expect(r1).not.toMatch(/^-- Consumer API change approved:/m)                    // admin side only; not a consumer change
  const c = code(r1)
  expect(c).toContain("select pg_temp.edit_once('public.admin_aer(text,jsonb)', '09dbbaf2aadc78e1c992d21a1048e661', '5e58f5d6126b3b2fe026e376a56c7686', array[")
  expect(c).toContain("'rank', 'none', 'not_stated') then raise exception 'unknown scale'")
  expect(c).toContain("position('scale_stated' in pg_get_functiondef('security.entry_matrix_payload_v1(uuid,text)'::regprocedure)) = 0")
  expect(c).toContain("position('scale_stated' in pg_get_functiondef('security.entry_resolve_v1(uuid,text)'::regprocedure)) = 0")
  expect(c).toContain("m.grade_scale := case when v_txt = 'not_stated' then null else coalesce(v_txt, 'none') end;")
  expect(c).toContain("      m.grade_scale := 'none';")                                  // never null by omission on add
  expect(c).toContain("if m.grade_scale is null and m.min_grade is null then raise exception '\"Not stated on the page\" needs the grade as printed'")
  // the course-row scale line is not edited (course-page rows hold no scale)
  expect(c).not.toContain("x.grade_scale := case")
  // no data: no row is written, re-read or admitted, and no row id appears (the 20 quarantined rows are untouched)
  expect(c).not.toMatch(/\b(insert\s+into|update|delete\s+from)\s+(catalogue|pipeline)\./i)
  expect(c).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)
  expect(c).not.toMatch(/consumer_api_rebaseline_v1\(/)
})

test('R1 in the workspace: matrix rows offer and show "Not stated on the page"; course rows do not; Resolution inspection shows it', () => {
  expect(ui).toContain("none:'No scale',not_stated:'Not stated on the page'}")
  expect(ui).toContain("const matrixScale=r=>r.scale==null&&r.min_grade?'not_stated':r.scale")
  expect(ui).toContain('scales={withNotStated(o.scales)}')
  expect(ui).toContain("<EditList kind=\"course\" rows={rows} busy={busy} fields={COURSE_FIELDS} scales={o.scales||[]}")
  expect(ui).toContain("(kind==='matrix'?withNotStated(o.scales):(o.scales||['none']))")
  expect(ui).toContain("const cellValue=(r,f)=>{const x=kind==='matrix'&&f.kind==='scale'?matrixScale(r):r[f.key];")
  expect(ui).toContain('const before=cellValue(cur,field)')                         // an unchanged cell never saves
  expect(ui).toContain("x.scale_stated===false?SCALE_LABEL.not_stated:")
})
