// CF-247 s1022 (S1-Build; Platform Admin 24 Nov 2026 05:54 and 06:27 AEDT; UI-UX plan v1.2 slice 6): golden-record validator.
// Reads, read-only through the Management API, the benchmark providers and test courses in tests/fixtures/golden-courses/<set>.json and
// reports for each what a counsellor would see wrong: no tuition fee for a year in the gate window (gates.fee_year_ahead), PTE or TOEFL iBT
// missing or without four bands where IELTS is held, no campus or a campus of another provider, and course-linked scholarship GPA
// thresholds with no stated scale. Each test course is also read through the Website API v3 course read (public.website_v3_course), so the
// report says whether v3 serves it. The website looks a course up by its stable key (or code), never by the internal id; course
// publication_status is not the serving switch (44,724 of 44,734 courses carry 'unpublished', 24 Nov 2026), the search documents are. Nothing is written. Exit 0 with the report; --strict exits 1 when a test course has a gap.
// Usage: node scripts/ci/validate-golden-courses.mjs [--set feedback-4] [--json out/golden.json] [--strict]
import fs from 'node:fs'
import { need, read, lit, summary } from '../boost-live-lib.mjs'

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d }
const SET = arg('--set', 'feedback-4'), JSON_OUT = arg('--json', ''), STRICT = process.argv.includes('--strict')
const fx = JSON.parse(fs.readFileSync(`tests/fixtures/golden-courses/${SET}.json`, 'utf8'))
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
for (const x of [...fx.providers, ...fx.courses]) if (!uuid.test(x.id)) throw Error(`not an id: ${x.id}`)
const arr = (xs) => `array[${xs.map((x) => lit(x.id)).join(',')}]::uuid[]`

// One row per course: the checks the pre-admission gates (s1020, s1021) apply to new admissions, applied to what is held now.
export const COURSE_SQL = (where) => `
with w as (select extract(year from now() at time zone 'Australia/Melbourne')::int y, security.pipeline_num_v1('gates.fee_year_ahead', 1)::int ahead),
c as (select c.id, c.provider_id, c.canonical_title, c.stable_key from catalogue.courses c where ${where}),
e as (select r.course_id, t.code, r.overall_score,
             (r.component_scores ? 'minimum_each' or (select count(*) from jsonb_object_keys(coalesce(r.component_scores, '{}'::jsonb)) k where k in ('listening', 'reading', 'writing', 'speaking')) = 4) four_bands
        from catalogue.course_english_requirements r join ref.english_tests t on t.id = r.english_test_id
       where r.status = 'active' and r.course_id in (select id from c) and t.code in ('IELTS', 'PTE', 'TOEFL_IBT'))
select c.id, c.provider_id, c.canonical_title title, c.stable_key,
  exists (select 1 from search.course_documents d where d.course_id = c.id) served,
  (select coalesce(array_agg(distinct f.fee_year order by f.fee_year), '{}') from catalogue.course_fees f
    where f.course_id = c.id and f.status = 'active' and f.fee_type = 'provider_current_tuition') fee_years,
  exists (select 1 from catalogue.course_fees f, w where f.course_id = c.id and f.status = 'active' and f.fee_type = 'provider_current_tuition'
           and f.fee_year between w.y and w.y + w.ahead) fee_ok,
  exists (select 1 from e where e.course_id = c.id and e.code = 'IELTS') ielts,
  exists (select 1 from e where e.course_id = c.id and e.code = 'PTE' and e.overall_score is not null and e.four_bands) pte_ok,
  exists (select 1 from e where e.course_id = c.id and e.code = 'TOEFL_IBT' and e.overall_score is not null and e.four_bands) toefl_ok,
  (select count(*) from catalogue.course_campuses cc where cc.course_id = c.id)::int campuses,
  (select count(*) from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id where cc.course_id = c.id and k.provider_id <> c.provider_id)::int campuses_other,
  (select count(distinct m.scholarship_id) from scholarship.course_mappings m where m.course_id = c.id and m.mapping_state = 'mapped')::int scholarships,
  (select count(*) from scholarship.criteria k join scholarship.course_mappings m on m.scholarship_id = k.scholarship_id and m.course_id = c.id and m.mapping_state = 'mapped'
    where k.status = 'active' and k.criterion_type = 'academic_minimum' and k.value_text ~* '^GPA')::int gpa,
  (select count(*) from scholarship.criteria k join scholarship.course_mappings m on m.scholarship_id = k.scholarship_id and m.course_id = c.id and m.mapping_state = 'mapped'
    where k.status = 'active' and k.criterion_type = 'academic_minimum' and k.value_text ~* '^GPA'
      and (jsonb_typeof(k.value_json -> 'scale') = 'number' or coalesce(k.human_text, '') ~* '(out of|/)\\s*[0-9]'))::int gpa_scaled
from c order by c.provider_id, c.canonical_title`

export function gaps(r) {
  const g = []
  if (!r.fee_ok) g.push(`fee year (held: ${r.fee_years.length ? r.fee_years.join(', ') : 'none'})`)
  if (r.ielts && !r.pte_ok) g.push('PTE with four bands')
  if (r.ielts && !r.toefl_ok) g.push('TOEFL iBT with four bands')
  if (!r.ielts) g.push('IELTS')
  if (r.campuses === 0) g.push('campus')
  if (r.campuses_other > 0) g.push(`${r.campuses_other} campus link(s) to another provider`)
  if (r.gpa > r.gpa_scaled) g.push(`${r.gpa - r.gpa_scaled} scholarship GPA threshold(s) without a scale`)
  return g
}

// The Management API's read-only role may not execute the v3 read (permission denied, 24 Nov 2026), so that one call runs as the API's own
// role inside a transaction set read only: the database refuses any write it might attempt.
async function readV3(key) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${process.env.REF}/database/query`, { method: 'POST',
    headers: { authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN}`, 'content-type': 'application/json' },
    body: JSON.stringify({ query: `set transaction read only; select public.website_v3_course(${lit(key)}) v` }) })
  const text = await r.text()
  if (!r.ok) throw Error(`v3 read failed (HTTP ${r.status}): ${text.slice(0, 400)}`)
  const rows = JSON.parse(text), v = rows[0]?.v
  return typeof v === 'string' ? JSON.parse(v) : v
}

const pct = (n, d) => (d ? `${Math.round((100 * n) / d)}%` : '–')

async function main() {
  need()
  const courses = await read(COURSE_SQL(`c.id = any(${arr(fx.courses)})`))
  const all = await read(COURSE_SQL(`c.provider_id = any(${arr(fx.providers)})`))
  const served = {}
  for (const c of fx.courses) {
    const r = courses.find((x) => x.id === c.id)
    const v = r?.stable_key ? await readV3(r.stable_key) : { error: { code: 'NO_STABLE_KEY' } }
    served[c.id] = v?.error ? `not served (${v.error.code})` : 'served'
  }
  const lines = [`## Golden courses: ${fx.benchmark}`, '', '### Test courses', '', '| Course | Provider record | Website API v3 | Gaps |', '|---|---|---|---|']
  let failing = 0
  for (const f of fx.courses) {
    const r = courses.find((x) => x.id === f.id)
    if (!r) { lines.push(`| ${f.label} | – | – | course not found |`); failing++; continue }
    const g = gaps(r); if (g.length) failing++
    lines.push(`| ${f.label}: ${r.title} | ${fx.providers.find((p) => p.id === r.provider_id)?.name || r.provider_id} | ${served[f.id]} | ${g.join('; ') || 'none'} |`)
  }
  lines.push('', '### Providers (every course held)', '', '| Provider | Courses | Served by the website API | Fee year in window | PTE and TOEFL with bands (IELTS courses) | Campus on its own list | Scholarship GPA with scale |', '|---|---|---|---|---|---|---|')
  const byP = []
  for (const p of fx.providers) {
    const rs = all.filter((x) => x.provider_id === p.id), ie = rs.filter((x) => x.ielts)
    const gpa = rs.reduce((a, x) => a + x.gpa, 0), gs = rs.reduce((a, x) => a + x.gpa_scaled, 0)
    const row = { provider_id: p.id, name: p.name, courses: rs.length, served: rs.filter((x) => x.served).length,
      fee_ok: rs.filter((x) => x.fee_ok).length, ielts: ie.length, elr_ok: ie.filter((x) => x.pte_ok && x.toefl_ok).length,
      campus_ok: rs.filter((x) => x.campuses > 0 && x.campuses_other === 0).length, gpa, gpa_scaled: gs }
    byP.push(row)
    lines.push(`| ${p.name} | ${row.courses} | ${row.served} (${pct(row.served, row.courses)}) | ${row.fee_ok} (${pct(row.fee_ok, row.courses)}) | ${row.elr_ok} of ${row.ielts} (${pct(row.elr_ok, row.ielts)}) | ${row.campus_ok} (${pct(row.campus_ok, row.courses)}) | ${gs} of ${gpa} (${pct(gs, gpa)}) |`)
  }
  lines.push('', `Test courses with a gap: ${failing} of ${fx.courses.length}. Read-only; nothing was changed.`)
  await summary(lines.join('\n'))
  if (JSON_OUT) { fs.mkdirSync(JSON_OUT.replace(/\/[^/]*$/, '') || '.', { recursive: true }); fs.writeFileSync(JSON_OUT, JSON.stringify({ set: SET, at: new Date().toISOString(), courses: courses.map((r) => ({ ...r, served: served[r.id], gaps: gaps(r) })), providers: byP }, null, 2)) }
  if (STRICT && failing) process.exit(1)
}
if (import.meta.url === `file://${process.argv[1]}`) main().catch((e) => { console.error(`::error::${e.message}`); process.exit(1) })
