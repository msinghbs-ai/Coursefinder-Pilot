// Guards: CF-247 s955 (Platform Admin 21 Nov 2026 21:15 and 21:45, Lane 1 item 1; REQ-34 / Z2, REQ-35 / Z3; G3): the Zoho API v3 course export keeps every v2 column first and in order and adds TOEFL iBT, Cambridge C1 Advanced, Duolingo and OET (grade and subtest grades) columns; zoho.sync_countries is AU, NZ, CA; Zoho v2 is not changed
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261122030000_cf247_s955_zoho_v3_export_english_tests_sync_countries.sql', 'utf8')
const V2_COURSE = 'course_id,cricos_course_code,title,provider_id,cricos_provider_code,provider_name,study_level,study_area,country_code,states,campus_cities,delivery_modes,duration_months,intake_months,ielts_overall,ielts_band,pte_overall,tuition_annual,tuition_currency,tuition_year,official_url,scholarship_count'
const ADDED = ',toefl_ibt_overall,toefl_ibt_band,cae_overall,cae_band,det_overall,oet_overall,oet_band,oet_grade,oet_subtest_grades'

test('the v3 course file is the v2 columns, unchanged and first, then the English test columns', () => {
  expect(MIG).toContain(`v_head := '${V2_COURSE}'\n         || '${ADDED}';`)
  for (const t of ['TOEFL_IBT', 'CAE', 'DET', 'OET']) expect(MIG).toContain(`security.zoho_v3_english_score_v1(i, '${t}', 'min_overall_score')`)
  expect(MIG).toContain('security.zoho_v2_csv_v1(o.grades), security.zoho_v2_csv_v1(o.subtests)')
  expect(MIG).toContain("if p_entity is distinct from 'course' then return public.zoho_v2_export_page(p_entity, p_page); end if;")
  expect(MIG).toContain("'post-check: the v3 course header does not start with the v2 header")
})

test('Zoho sync countries become AU, NZ and CA, from the AU-only value only', () => {
  expect(MIG).toContain(`set value = '["AU", "NZ", "CA"]'::jsonb`)
  expect(MIG).toContain(`where toolset_key = 'pipeline' and key = 'zoho.sync_countries' and value = '["AU"]'::jsonb;`)
})

test('Zoho v2 and the frozen consumer API are not changed; nothing dropped or scheduled', () => {
  const body = MIG.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
  expect(body).not.toMatch(/create\s+or\s+replace\s+function\s+public\.zoho_v2_|create\s+or\s+replace\s+function\s+public\.(website_v2_|website_edge_|website_api_v2_|zoho_edge_)/i)
  expect(body).not.toMatch(/\bdrop\s+(table|function|view)\b|\bdelete\s+from\b|cron\.schedule\(/i)
  expect(MIG).toContain("'post-check: Zoho v2 export changed'")
  expect(MIG).toContain("(v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48")
  expect(MIG).toMatch(/^-- Replaces: .+$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\./m)
})
