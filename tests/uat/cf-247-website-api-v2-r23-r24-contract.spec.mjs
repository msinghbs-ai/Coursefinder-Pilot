// Guards: Platform Admin decision 5 Nov 2026 19:14 §5 and G3 approval 9 Nov 2026 (website developer requests R23 campus names and course counts, R24 scholarship nationality status)
// CF-247 R23 (provider campuses: campus_id, campus_name, course_count; one item per campus) and R24 (scholarship
// nationality_eligibility_status). G3 approved by the Platform Admin on 9 Nov 2026 ("G3 change is approved in principle. Complete the required API
// compatibility tests, developer guide, versioned handover and record the formal G3 approval before merging. Do not release an unvalidated
// consumer contract change."). The migration records the approval on its first line, still refuses to apply until the Platform Admin's approval
// setting exists (a Platform Admin write, never a migration), and re-takes the consumer API baseline after checking that nothing else differs from it.
// Proof on a production-parity PostgreSQL: tests/fixtures/website-api-v2-r23-r24/ (run.sh; CI workflow website-api-v2-r23-r24-fixture.yml).
// Approval package and compatibility record: admin docs/platform/approvals/2026-11-06-g3-r23-r24-approval-package.md (section 11).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261109150000_cf247_website_api_v2_r23_r24.sql'
const FX = 'tests/fixtures/website-api-v2-r23-r24'
const m = fs.readFileSync(MIG, 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('G3 approval is recorded on the first line; the gate still refuses without the Platform Admin setting; the baseline is re-taken last', () => {
  const approval = '-- Consumer API change approved: Platform Admin (Mandeep Singh), 9 Nov 2026, in chat: G3 change approved for R23 and R24 on condition of API compatibility tests, developer guide and versioned handover'
  expect(m.split('\n')[0]).toBe(approval)
  expect(approval).toMatch(/^-- Consumer API change approved: (?!.*\bPENDING\b).{10,}$/)  // what s57 accepts
  expect(m).not.toMatch(/NOT APPROVED|G3 approval PENDING/)
  const gate = m.indexOf("if coalesce(security.pipeline_num_v1('api.v2_r23_r24_approved', 0), 0) <> 1 then")
  expect(gate).toBeGreaterThan(0)
  expect(m).toContain("raise exception 'CF-247 Website API v2 R23/R24 consumer change: setting api.v2_r23_r24_approved is not 1 (no recorded Platform Admin approval): not applied'")
  for (const s of ['create or replace function pg_temp.edit_once', 'select pg_temp.replace_once(', 'select pg_temp.edit_once(']) expect(m.indexOf(s)).toBeGreaterThan(gate)
  // the migration never creates its own approval (a migration must not approve itself) and drops or deletes nothing
  expect(code(m)).not.toMatch(/platform_toolset_settings|insert\s+into|update\s+\w+\.\w+\s+set|delete\s+from|drop\s+/i)
  // the baseline is re-taken exactly once, after both changes and after the check that nothing else differs from it
  const reb = code(m).match(/consumer_api_rebaseline_v1\(/g) || []
  expect(reb).toHaveLength(1)
  const iReb = m.indexOf("select security.consumer_api_rebaseline_v1('R23/R24")
  expect(iReb).toBeGreaterThan(m.indexOf("select pg_temp.edit_once('api.website_v2_scholarship_item(uuid)'"))
  expect(iReb).toBeGreaterThan(m.indexOf("select pg_temp.replace_once('api.website_v2_provider_campuses(uuid)'"))
  const drift = m.indexOf("where d not in ('api.website_v2_provider_campuses(uuid)', 'api.website_v2_scholarship_item(uuid)')")
  expect(drift).toBeGreaterThan(0)
  expect(iReb).toBeGreaterThan(drift)
  expect(m).toContain('approved Platform Admin (Mandeep Singh) 9 Nov 2026')
})

test('md5-guarded: only the two builders change, from the live text of 5 Nov 2026; their readers and wrappers are pinned', () => {
  expect(m).toContain("select pg_temp.replace_once('api.website_v2_provider_campuses(uuid)', '57115d3b8ddbc40729ec04078ee15d41', ")
  expect(m).toContain("select pg_temp.edit_once('api.website_v2_scholarship_item(uuid)', 'd1792cc7161101ce8c22abad70ecbd36', '04532402307717c6dab17567551364e1', array[")
  expect(code(m).match(/select pg_temp\.(edit_once|replace_once)\(/g)).toHaveLength(2)
  for (const [sig, md5] of [['security.place_presentable(text)', 'a7b720fc9b34203d0a23315376fd483a'],
    ['public.website_v2_providers(jsonb,integer,integer,text)', '73ba533ee2f4c20b840c4cf172c17912'],
    ['public.website_v2_scholarships(jsonb,integer,integer)', 'b3a616d8ec31a86ffa3e770cf24db0af'],
    ['public.website_v2_scholarship(text)', '79131c22331c7439438177517bd1ba12'],
    ['security.layer4_search_blocked_courses', '35cdaa19a775ffaaf60fc2be302affec'],
    ['security.layer4_active_blocks', '300ac7ca5fe9b72b13e2647a861ea8c6'],
    ['security.provider_hidden_v1', 'c8e2c132cc6fa8a52dccdbb04317707b']]) expect(m).toContain(`('${sig}', '${md5}')`)
  // the fixture loads exactly the live "before" texts the migration is guarded on
  const live = fs.readFileSync(`${FX}/functions-live.tsv`, 'utf8')
  expect(live).toContain('api.website_v2_provider_campuses(uuid)\t57115d3b8ddbc40729ec04078ee15d41\tpostgres=X/postgres')
  expect(live).toContain('api.website_v2_scholarship_item(uuid)\td1792cc7161101ce8c22abad70ecbd36\tpostgres=X/postgres')
})

test('R23 campuses: one item per stable campus identity, every existing key kept, counts from returned courses in one grouped read', () => {
  const body = m.slice(m.indexOf('CREATE OR REPLACE FUNCTION api.website_v2_provider_campuses'), m.indexOf('$function$\n$def$'))
  expect(body).not.toContain('jsonb_agg(distinct')
  for (const k of ["'city', security.place_presentable(k.city)", "'postcode', k.postcode", "'subdivision_code', s.code", "'metro_area', rc.metro_area",
    "'regional_category', rc.category", "'regional_category_name', rc.category_name", "'campus_id', k.stable_key", "'campus_name', nullif(btrim(k.name),'')",
    "'course_count', coalesce(n.n, 0)"]) expect(body).toContain(k)
  expect(body).toContain("where k.provider_id = p_provider_id and nullif(btrim(k.city),'') is not null and coalesce(k.status,'active') <> 'inactive'")
  expect(body).toContain('select cc.campus_id, count(distinct cc.course_id) n')
  expect(body).toContain('where d.provider_id = p_provider_id')
  expect(body).toMatch(/security\.layer4_search_blocked_courses b where b\.course_id = (cc|d)\.course_id/)
  expect(body).toContain("order by lower(nullif(btrim(k.name),'')) nulls last, k.stable_key")
})

test('R24 nationality: additive status from held evidence and the review queues; the lists are unchanged; an empty list is never unrestricted', () => {
  expect(m).toContain("$o$    'citizenship_eligibility', to_jsonb((select codes from nat)), 'eligible_countries_list', to_jsonb((select codes from nat)),\n$o$")
  const c = m.slice(m.indexOf("'nationality_eligibility_status', case"), m.indexOf("else 'unknown' end,"))
  const order = ["then 'under_review'", "then 'restricted'", "then 'unrestricted'"].map(s => c.indexOf(s))
  expect(order.every((v, i) => v > 0 && (i === 0 || v > order[i - 1]))).toBe(true)
  expect(c).toContain("r.field_code in ('nationalities', 'nationality', 'citizenship_eligibility', 'audience', 'student_type')")
  expect(c).toContain("a.status = 'pending' and a.reason ~* 'who it is for'")
  expect(c).toContain("when coalesce(cardinality((select codes from nat)), 0) > 0 or (select v from st) = 'domestic'")
  expect(c).toContain("cardinality(nr.codes) = 0 and nr.phrases ? 'ANY'")
})

test('the production-parity fixture proves refusal, md5s, two runs, every case, end-to-end byte identity and the benchmark', () => {
  const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
  for (const s of ['MIG=../../../supabase/migrations/20261109150000_cf247_website_api_v2_r23_r24.sql', 'diff parity-live-2026-11-09.txt',
    'functions-live.tsv', 'no approval: refused, nothing changed', 'unrelated consumer API difference: refused, nothing changed',
    'baseline re-taken: the two approved functions changed, no other consumer function differs from it',
    'second run: already applied, unchanged; privileges unchanged', 'bench.sql'])
    expect(run).toContain(s)
  expect(fs.readFileSync(`${FX}/parity-live-2026-11-09.txt`, 'utf8').trim().split('\n')).toHaveLength(46)
  const fx = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
  for (const s of ["('S11','restricted')", "('S3','unknown')", "('S4','unrestricted')", "('S5','under_review')", "('S13','under_review')", "('S6','restricted')",
    "'[\"R-SASIA\"]'::jsonb", 'array[3,1,0]', 'set role service_role', "a::text like '%provider:fx:hidden%'", 'insufficient_privilege'])
    expect(fx).toContain(s)
  const seed = fs.readFileSync(`${FX}/seed.sql`, 'utf8')
  expect(seed).toContain("update catalogue.providers set publication_status = 'unpublished' where id = fx.i('P4')")
  expect(fs.readFileSync('.github/workflows/website-api-v2-r23-r24-fixture.yml', 'utf8')).toContain('bash tests/fixtures/website-api-v2-r23-r24/run.sh')
})

test('no edge function changes: the five frozen edge hashes are untouched, so the edge baseline file is not updated', () => {
  const base = JSON.parse(fs.readFileSync('tests/uat/consumer-api-baseline.json', 'utf8'))
  expect(Object.keys(base.edge_files)).toHaveLength(5)
  expect(fs.existsSync(`${FX}/consumer-api-baseline.on-approval.json`)).toBe(false)  // retired: nothing to apply, the edge functions do not change
})

test('the approval setting is a Platform Admin write documented with the migration: label, range, unit and used_by, and a missing setting reads as not approved', () => {
  const doc = fs.readFileSync(`${FX}/approval-setting.sql`, 'utf8')
  for (const s of ["'pipeline', 'api.v2_r23_r24_approved'", "'number', '1', 0, 1, 'on (1) / off (0)', 'Website API'", 'migration 20261109150000', 'Mandeep Singh'])
    expect(doc).toContain(s)
  expect(code(m)).toContain("coalesce(security.pipeline_num_v1('api.v2_r23_r24_approved', 0), 0) <> 1")
  expect(m).toContain('a missing setting reads as 0 and refuses')
})
