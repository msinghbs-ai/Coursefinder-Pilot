// Guards: Campus locality rule, campus names (Platform Admin 19 Nov 2026 05:40 item 4, s727): rule l4-campus-locality-v1 also settles a postcode whose leading Significant Urban Area holds more than half its mesh blocks and is named, as a whole word, in every waiting campus's suburb or own campus name, never only through its provider's name (Roseworthy 5371 waits); the two rule functions are replaced in place behind md5 guards and nothing is added
// CF-247 S727. Migration 20261119062000_cf247_s727_campus_locality_campus_name. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119062000_cf247_s727_campus_locality_campus_name.sql', 'utf8')

test('the candidates add the campus_name basis on suburb or campus name, never the provider name, above half the mesh blocks', () => {
  expect(M).toContain("lower(concat_ws(' | ', p.canonical_name, p.display_name, p.short_name)) provider_l")
  expect(M).toContain("where o.city_l ~ r.re or (o.name_l ~ r.re and o.provider_l !~ r.re))) then 'campus_name'")
  expect(M).toContain("and t.mshare > 0.5  -- fixed: more than half the mesh blocks is more than any other part")
  expect(M).toContain("security.pipeline_num_v1('destination.postcode_mesh_name_min_share', 0.5)")
  // the existing bases are kept as they were
  for (const b of ["then 'mesh_share'", "then 'outside'", "then 'suburb_name'"]) expect(M).toContain(b)
})

test('the rule records the campus_name reason and still settles through the Layer 4 Inbox decision under the system account', () => {
  expect(M).toContain("names %s in its suburb or its own campus name (not through its provider''s name)")
  expect(M).toContain('security.layer4_campus_locality_inbox_decide_v1(w.ref')
  expect(M).toContain("v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150'")
})

test('replaced in place behind md5 guards; Roseworthy is held; nothing is created', () => {
  expect(M).toContain("'28a5e96bab4c7b1a296449625adc70c6'")
  expect(M).toContain("'3665a17bd630e0c91b04dab4d633cfc0'")
  expect(M).toContain("where postcode = '5371' and basis <> 'hold'")
  expect(M).not.toMatch(/create (table|schema|extension)|cron\.schedule|insert into pipeline\.platform_toolset_settings|insert into pipeline\.automation_catalogue/i)
  expect((M.match(/create or replace function/g) || []).length).toBe(2)
  expect(M).toMatch(/^-- Replaces: .+$/m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
})
