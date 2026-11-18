// Guards: API v3 read path, PR D (Platform Admin 18 Nov 2026 17:55; API v3 data admission plan section 3): v3 campuses carry is_primary and primary_basis, v3 destination careers carry employment_count; additions to v3 only, v2 and the frozen consumer API untouched.
// CF-247 S711. supabase/migrations/20261119042000_cf247_v3_read_path_primary_basis_employment.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119042000_cf247_v3_read_path_primary_basis_employment.sql', 'utf8')

test('md5-guarded additions on the v3 course and provider campuses and the v3 careers', () => {
  expect(M).toContain("select pg_temp.cf_edit('security.course_v3_fields_v1(jsonb,uuid)'::regprocedure, 'c9f20991af5606d99280a737bee4c9c7',")
  expect(M).toContain("select pg_temp.cf_edit('public.website_v3_provider_item(jsonb)'::regprocedure, '9fa6d618d17b0d182495efc050943f79',")
  expect(M).toContain("'is_primary', coalesce(k.is_primary, false), 'primary_basis', k.primary_basis,")
  expect(M).toContain("select pg_temp.cf_edit('security.destination_read_v1(jsonb,integer,integer)'::regprocedure, '40b256e6aed77969fac06c2b15249626',")
  expect(M).toContain("'employment_count', q.employment_count")
})

test('v2 and the frozen consumer API are not touched; drift is checked', () => {
  expect(M).not.toMatch(/website_v2_|website_edge_|zoho_edge_|website_api_v2_|svc_website_settings_v1/)
  expect(M).toContain('v_c := security.consumer_api_check_v1();')
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})
