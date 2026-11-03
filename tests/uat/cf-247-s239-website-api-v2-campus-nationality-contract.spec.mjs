// Guards: Platform Admin mandate 3 Nov 2026 11:46 (Website API v2 developer request: additive campus and nationality fields)
// Prepared, not approved: the migration refuses to apply until the Platform Admin records approval (mandate §7); provider campuses become one
// item per campus with additive campus_id, campus_name and course_count; scholarships gain an additive nationality_eligibility_status where an
// empty list is never "unrestricted". Fixture proof: tests/fixtures/website-api-v2-campus-nationality/run.sh.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261103180000_cf247_website_api_v2_campus_nationality.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('pending approval: the migration refuses to apply before it changes anything, and does not re-take the baseline', () => {
  expect(m.split('\n')[0]).toBe('-- Consumer API change approved: PENDING — Platform Admin approval required (mandate 3 Nov 2026 11:46 §7)')
  const gate = m.indexOf("if coalesce(security.pipeline_num_v1('api.v2_campus_nationality_approved', 0), 0) <> 1 then")
  expect(gate).toBeGreaterThan(0)
  expect(m).toContain("raise exception 'CF-247 Website API v2 campus and nationality change is PENDING Platform Admin approval")
  for (const s of ['create or replace function pg_temp.edit_once', 'select pg_temp.replace_once(', 'select pg_temp.edit_once(']) expect(m.indexOf(s)).toBeGreaterThan(gate)
  expect(code(m)).not.toContain('consumer_api_rebaseline_v1(')
  expect(code(m)).not.toMatch(/platform_toolset_settings/)
})

test('md5-guarded: the two consumer definitions are replaced only from the live text read on 3 Nov 2026', () => {
  expect(m).toContain("select pg_temp.replace_once('api.website_v2_provider_campuses(uuid)', '57115d3b8ddbc40729ec04078ee15d41', '698afad0bc236a314fb356632938c403', $def$")
  expect(m).toContain("select pg_temp.edit_once('api.website_v2_scholarship_item(uuid)', 'd1792cc7161101ce8c22abad70ecbd36', '74fb94060500970a2b7dc8923afe04a7', array[")
  expect(m).toContain("md5(pg_get_functiondef('security.place_presentable(text)'::regprocedure)) <> 'a7b720fc9b34203d0a23315376fd483a'")
  expect(m).toContain("md5(pg_get_viewdef('security.layer4_search_blocked_courses'::regclass)) <> '35cdaa19a775ffaaf60fc2be302affec'")
})

test('campuses: one item per stable campus identity, every existing key kept, counts from returned courses in one grouped read', () => {
  const body = m.slice(m.indexOf('CREATE OR REPLACE FUNCTION api.website_v2_provider_campuses'), m.indexOf('$function$\n$def$'))
  expect(body).not.toContain('jsonb_agg(distinct')
  for (const k of ["'city', security.place_presentable(k.city)", "'postcode', k.postcode", "'subdivision_code', s.code", "'metro_area', rc.metro_area",
    "'regional_category', rc.category", "'regional_category_name', rc.category_name", "'campus_id', k.stable_key", "'campus_name', nullif(btrim(k.name),'')",
    "'course_count', coalesce(n.n, 0)"]) expect(body).toContain(k)
  // the same campuses as before: a city held and not inactive
  expect(body).toContain("where k.provider_id = p_provider_id and nullif(btrim(k.city),'') is not null and coalesce(k.status,'active') <> 'inactive'")
  // counted: the provider's courses in the search documents, not held back by Layer 4, each once per campus
  expect(body).toContain('select cc.campus_id, count(distinct cc.course_id) n')
  expect(body).toContain('where d.provider_id = p_provider_id')
  expect(body).toContain('(select count(*) from security.layer4_search_blocked_courses b where b.course_id = cc.course_id) = 0')
  expect(body).toContain("order by lower(nullif(btrim(k.name),'')) nulls last, k.stable_key")
})

test('nationality: additive status, lists unchanged, an empty list is never unrestricted', () => {
  expect(m).toContain("$o$    'citizenship_eligibility', to_jsonb((select codes from nat)), 'eligible_countries_list', to_jsonb((select codes from nat)),\n$o$")
  expect(m).toContain("'nationality_eligibility_status', case")
  expect(m).toContain("then 'under_review'")
  expect(m).toContain("when coalesce(cardinality((select codes from nat)), 0) > 0 or (select v from st) = 'domestic' then 'restricted'")
  expect(m).toContain("cardinality(nr.codes) = 0 and nr.phrases ? 'ANY')")
  expect(m).toContain("else 'unknown' end,")
  expect(code(m).match(/select pg_temp\.(edit_once|replace_once)\(/g)).toHaveLength(2)
})

test('the fixture harness proves refusal, md5s, two runs and every case', () => {
  const run = fs.readFileSync('tests/fixtures/website-api-v2-campus-nationality/run.sh', 'utf8')
  expect(run).toContain('MIG=../../../supabase/migrations/20261103180000_cf247_website_api_v2_campus_nationality.sql')
  expect(run).toContain('no approval: refused, nothing changed')
  expect(run).toContain('second run: already applied, unchanged')
  const fx = fs.readFileSync('tests/fixtures/website-api-v2-campus-nationality/fixtures.sql', 'utf8')
  for (const c of ["('S3','unknown')", "('S4','unrestricted')", "('S5','under_review')", "('S6','restricted')", "'[\"R-SASIA\"]'::jsonb", 'array[2,1,0]']) expect(fx).toContain(c)
})
