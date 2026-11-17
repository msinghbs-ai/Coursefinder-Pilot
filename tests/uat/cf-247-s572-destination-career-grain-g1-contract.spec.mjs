// Guards: Destination decision G-1 (Platform Admin 17 Nov 2026 11:52; run before the squash, 13:12): career outcomes are one row per edition, country, occupation scheme, occupation code and area (national, state or locality); the old key is replaced inside the constraint block only while the table is empty; the importer upserts on the new key and the v3 destination read returns the area
// CF-247 S572. Migration 20261117050000_cf247_destination_career_grain_g1.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261117050000_cf247_destination_career_grain_g1.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the new key and the area rule; the old key is dropped only inside the constraint block and only while the table is empty', () => {
  expect(code).toContain('add constraint career_outcomes_area_key unique nulls not distinct\n        (edition_id, country_id, occupation_scheme, occupation_code, geography_level, state_code, locality_id);')
  expect(code).toContain("(geography_level = 'national' and state_code is null and locality_id is null)")
  expect(code).toContain("or (geography_level = 'state' and state_code is not null and locality_id is null)")
  expect(code).toContain("or (geography_level = 'locality' and locality_id is not null)")
  const block = code.slice(code.indexOf("conname = 'career_outcomes_edition_id_country_id_occupation_code_key') then"), code.indexOf('end $$;', code.indexOf('career_outcomes_area_key')))
  expect(block.indexOf('if exists (select 1 from destination.career_outcomes) then')).toBeLessThan(block.indexOf('drop constraint career_outcomes_edition_id_country_id_occupation_code_key'))
  expect(code.match(/\bdrop\b/g).length).toBe(1)
})

test('the importer upserts on the G-1 key and carries scheme, area, period, edition and attribution; md5-guarded', () => {
  expect(code).toContain("select pg_temp.edit_all('security.destination_import_v1(jsonb)', '974b8dcebd6125197d5012a8c52f1378', 'abf584051fa4d9e7c5d6201425878f6d',")
  expect(code).toContain('on conflict (edition_id, country_id, occupation_scheme, occupation_code, geography_level, state_code, locality_id) do update set')
  expect(code).toContain("upper(btrim(r->>'occupation_scheme'))")
  expect(code).toContain("coalesce(nullif(btrim(r->>'geography_level'), ''), 'national')")
  const repl = code.slice(code.indexOf('$n2$'), code.lastIndexOf('$n2$'))
  expect(repl).toContain('on conflict (edition_id, country_id, occupation_scheme, occupation_code, geography_level, state_code, locality_id)')
  expect(repl).not.toContain('on conflict (edition_id, country_id, occupation_code)')
})

test('the v3 destination read returns geography_level and state_code (additive; no v2 object touched)', () => {
  expect(code).toContain("select pg_temp.edit_all('security.destination_read_v1(jsonb,integer,integer)', 'f89256d82bb43f9f16868b126c3586f4', '40b256e6aed77969fac06c2b15249626',")
  expect(code).toContain("'geography_level', q.geography_level, 'state_code', q.state_code,")
  expect(code).not.toMatch(/public\.website_v2_|zoho_edge_|website_api_v2_/)
})
