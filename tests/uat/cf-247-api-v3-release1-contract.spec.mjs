// Guards: API v3 release 1 (Platform Admin 12 Nov 2026 21:12: "API v3 is getting prepared - any new field that needs programing or missing in v2 should defined, added to v3 and be ready for website and zoho"); v3 is v2 plus additions at its own URLs, same keys, held until api.v3_released
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113140000_cf247_api_v3_release1.sql', 'utf8')
const web = fs.readFileSync('supabase/functions/website-api-v3/index.ts', 'utf8')
const zoho = fs.readFileSync('supabase/functions/zoho-api-v3/index.ts', 'utf8')
const edges = JSON.parse(fs.readFileSync('.github/edge-functions.json', 'utf8')).functions

test('the dispatchers answer every v2 action through the unchanged v2 function and add the v3 fields', () => {
  for (const f of ['website_v2_reference()', 'website_v2_course_search(', 'website_v2_providers(', 'website_v2_rankings(', 'website_v2_scholarships(',
    'website_v2_course(', 'website_v2_provider(', 'website_v2_scholarship(', 'website_v2_sync(']) expect(m).toContain(`public.${f}`)
  for (const f of ['zoho_v2_reference()', 'zoho_v2_course_search(', 'zoho_v2_course(', 'zoho_v2_courses(', 'zoho_v2_providers(', 'zoho_v2_provider(',
    'zoho_v2_list(', 'zoho_v2_statistics(', 'zoho_v2_passthrough(', 'zoho_v2_report(', 'zoho_v2_report_status(', 'zoho_v2_sync(', 'zoho_v2_export_page(']) expect(m).toContain(`public.${f}`)
  expect(m).toContain("return api_v3.reply(e, r, 'contract_version', 'website-v3');")
  expect(m).toContain("return api_v3.reply(e, r, 'api_version', 'zoho-v3');")
  expect(m).toContain("x || jsonb_build_object('item', api_v3.enrich(x->>'entity', x->'item'))")
})

test('release 1 fields: scholarships, R23 campuses, R28 intake status, the excerpt and the defined-not-held fields', () => {
  for (const k of ['award_type', 'sponsor', 'programme', 'award_code', 'benefits', 'application', 'award_duration', 'academic_year',
    'nationality_eligibility_status', 'excluded_nationality_codes', 'nationality_regions']) expect(m).toContain(`'${k}'`)
  expect(m).toContain("'campus_id', k.stable_key, 'campus_name', nullif(btrim(k.name), ''), 'course_count', coalesce(n.n, 0)")
  expect(m).toContain("i || jsonb_build_object('start_date_status',")
  for (const s of ['known', 'no_official_calendar', 'month_only', 'not_on_course_page', 'course_page_not_verified', 'next_year_calendar_pending',
    'not_yet_read', 'own_calendar', 'conflicting_evidence', 'held_for_review', 'rolling']) expect(m).toContain(`'${s}'`)
  expect(m).toContain("security.pipeline_num_v1('api.v3_description_excerpt_chars', 280)")
  for (const k of ['teaching_language', 'study_load', 'post_study_work', 'field_of_study_codes', 'recognition', 'admission_tests', 'entry_conditions',
    'application_route', 'logo_dark', 'brand_colour']) expect(m).toMatch(new RegExp(`'${k}', null`))
})

test('held until released: the switch is off and an API caller is refused until it is set', () => {
  expect(m).toContain("('pipeline', 'api.v3_released', 'API v3 released to the website and Zoho'")
  expect(m).toContain("'number', '0'::jsonb, 0, 1, 'on (1) or off (0)'")
  expect(m.match(/if current_user <> 'postgres' and not api_v3\.released\(\) then raise exception 'V3_NOT_RELEASED'/g)).toHaveLength(2)
  expect(m).toContain('grant execute on function public.website_v3_call(text, jsonb) to service_role;')
  expect(m).toContain('revoke all on function public.zoho_v3_call(text, jsonb) from public, anon, authenticated;')
})

test('the v3 URLs: v2 routing and keys, one dispatcher call, 403 until released, registered for deploy', () => {
  expect(web).toContain('const API_VERSION = "website-v3";')
  expect(web).toContain('svc.rpc("website_api_v2_auth"')
  expect(web).toContain('svc.rpc("website_v3_call", { p_action: action, p_args: args })')
  expect(zoho).toContain('const API_VERSION = "zoho-v3";')
  expect(zoho).toContain('svc.rpc("zoho_v2_auth"')
  expect(zoho).toContain('svc.rpc("zoho_v3_call", { p_action: dispatch, p_args: args })')
  for (const s of [web, zoho]) {
    expect(s).toContain('if (m.includes("V3_NOT_RELEASED")) return fail(403, "V3_NOT_RELEASED");')
    expect(s).toContain('p_action: action ? `v3.${action}` : null')
  }
  expect(edges['website-api-v3']).toBe(false)
  expect(edges['zoho-api-v3']).toBe(false)
})
