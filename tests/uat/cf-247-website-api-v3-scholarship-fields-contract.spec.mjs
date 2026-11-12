// Guards: Website API v3 scholarship detail fields (F-SCH developer field contract, Platform Admin 12 Nov 2026 20:19; moved to v3 by Platform Admin 12 Nov 2026 22:37, Decision 277): v3 only, v2 keys never replaced
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113240000_cf247_website_api_v3_scholarship_fields.sql', 'utf8')
const KEYS = ['description', 'award_type', 'sponsor', 'programme', 'award_code', 'benefits', 'application', 'award_duration', 'academic_year',
  'excluded_nationality_codes', 'nationality_regions']

test('the eleven detail fields are added in v3, md5-guarded against the WP-1.2 definition', () => {
  expect(m).toContain("md5(pg_get_functiondef('public.website_v3_scholarship_item(jsonb)'::regprocedure)) <> 'd6df05bd54b5fef9b4e508893470ba75'")
  for (const k of KEYS) expect(m).toContain(`'${k}', `)
  expect(m).toContain("'application', jsonb_build_object(\n        'method', ")
  expect(m).toContain("cv.notes like 'sch-extract-v3:%'") // only verified benefits from the detail fill
})

test('v2 keys win and the R24 status keeps its live rule', () => {
  expect(m).toContain("return v_more || p_item || jsonb_build_object('nationality_eligibility_status', v_status);")
  expect(m).toContain("and r.field_code in ('nationalities', 'nationality', 'citizenship_eligibility', 'audience', 'student_type'))")
  expect(m).toContain("else 'unknown' end;") // an empty list is never unrestricted
})

test('only the v3 item function is replaced; the v2 draft migration is not brought in', () => {
  const created = [...m.matchAll(/create or replace function ([a-z_0-9.]+)/g)].map(x => x[1])
  expect(created).toEqual(['public.website_v3_scholarship_item'])
  expect(fs.existsSync('supabase/migrations/20261113069000_cf247_website_api_v2_scholarship_fields.sql')).toBe(false)
})
