// Guards: Platform Admin 18 Nov 2026 10:33 and 10:34 (S1-RM-Design): the API v3 course actions return study_load, empty_reason_code, campuses[].locality and provider.accreditations, the provider action returns accreditations, and every new field is in the reviewed field dictionary; Publish edition counts a city profiles edition's localities and publishes it once one is approved (ref G7QN3W).
// Behaviour is proven on isolated PostgreSQL by tests/fixtures/api-v3-course-fields/run.sh (workflow api-v3-course-fields-test); these checks keep the rules in the migration and the dictionary.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { load } from '../../scripts/api-v3-field-dictionary.mjs'

const read = (p) => fs.readFileSync(p, 'utf8')
const m = read('supabase/migrations-archive/20261118133707_cf247_api_v3_course_study_load_edition_rows.sql')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const EDITED = ['public.website_v3_course_item_r28(jsonb)', 'public.website_v3_provider_item(jsonb)', 'security.destination_edition_publish_v1(uuid,uuid)', 'public.admin_destination_overview()']

test('the migration edits four live bodies under an md5 guard, adds three functions, and drops nothing', () => {
  expect(m).toMatch(/^-- Replaces: the four bodies above, in place \(md5-guarded edits\)$/m)
  expect(m).toMatch(/^-- Retires: nothing$/m)
  for (const sig of EDITED) {
    const line = m.match(new RegExp(`^--   ${sig.replace(/[()$.]/g, '\\$&')}  ([0-9a-f]{32}) -> ([0-9a-f]{32})$`, 'm'))
    expect(line, sig).not.toBeNull()
    expect(c).toContain(`select pg_temp.edit_all('${sig}', '${line[1]}', '${line[2]}',`)
  }
  for (const l of c.split('\n')) expect(l).not.toMatch(/^\s*(drop|delete|truncate)\b/i)
  for (const f of ['security.provider_accreditations_v3_v1(uuid)', 'security.course_v3_fields_v1(jsonb, uuid)', 'security.destination_edition_rows_v1(uuid)'])
    expect(c).toContain(`revoke all on function ${f} from public, anon, authenticated;`)
})

test('every v3 course item carries the four fields; only approved localities and active, unexpired accreditations are returned', () => {
  expect(c).toContain("return security.course_v3_fields_v1(jsonb_set(p_item, '{intakes}', v_out), v_course);")
  expect(c).toContain("then return security.course_v3_fields_v1(p_item, v_course); end if;")
  expect(c).toContain("return p_item || jsonb_build_object('study_load', v_load, 'empty_reason_code', v_reason);")
  expect(c).toContain('security.destination_locality_for_postcode_v1(v_cc, k->>\'postcode\')')
  expect(c).toContain("where a.provider_id = p_provider and a.status = 'active' and (a.expires_at is null or a.expires_at >= current_date)")
  expect(c).toContain("'accreditations', security.provider_accreditations_v3_v1(v_provider));")
  // the frozen v2 surface is not named (G3)
  expect(c).not.toMatch(/website_v2_|zoho_v2_|zoho_edge_|website_edge_|website_api_v2_/)
})

test('a city profiles edition counts its localities by country and edition name, and needs one approved to publish', () => {
  expect(c).toContain('from destination.localities l where l.country_code = v_cc and l.dataset_edition = e.edition_label;')
  expect(c).toContain("v_rows := case v.domain when 'city_profiles' then (security.destination_edition_rows_v1(v.id)->>'rows_approved')::int")
  expect(c).toContain("message = 'INVALID_INPUT: an edition with no approved rows cannot be published. Approve its localities first'")
  expect(c).toContain("message = 'INVALID_INPUT: an edition with no rows cannot be published'")
  expect(c).toContain("else (security.destination_edition_rows_v1(e.id)->>'rows')::int end,")
})

test('the reviewed dictionary describes the new fields on every v3 course action and the provider action of both APIs', () => {
  const doc = load()
  const has = (s, e, p) => doc.fields.some((f) => f.api_surface === s && f.endpoint === e && f.field_path === p)
  for (const [s, e, root] of [['website', 'course', 'item'], ['website', 'search', 'items[]'], ['zoho', 'course', 'item'], ['zoho', 'search', 'items[]'], ['zoho', 'courses', 'items[]']]) {
    for (const p of ['study_load', 'empty_reason_code', 'campuses[].locality', 'campuses[].locality.name', 'provider.accreditations', 'provider.accreditations[].body_code'])
      expect(has(s, e, `${root}.${p}`), `${s} ${e} ${root}.${p}`).toBe(true)
  }
  for (const s of ['website', 'zoho']) expect(has(s, 'provider', 'item.accreditations[].body_code'), s).toBe(true)
  const sl = doc.fields.find((f) => f.api_surface === 'website' && f.endpoint === 'course' && f.field_path === 'item.study_load')
  expect(sl.allowed_values).toEqual(['full_time', 'part_time', 'both'])
  expect(read('.github/workflows/api-v3-course-fields-test.yml')).toContain('bash tests/fixtures/api-v3-course-fields/run.sh')
})
