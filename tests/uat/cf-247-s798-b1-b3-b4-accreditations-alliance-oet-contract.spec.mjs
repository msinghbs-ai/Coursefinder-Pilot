// Guards: Platform Admin 20 Nov 2026 05:42 AEDT (chat S1-Build, s798; decisions B1, B3 and B4): AACSB and EQUIS loaded from the bodies' own pages with the 13 AMBA rows approved, Double and Triple Crown derived on API v3, IRU renamed the 2050 Alliance with ACU and VU added (Charles Darwin not a member), and English grades shown on v3 as held, never derived.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261120080000_cf247_s798_b1_b3_b4_accreditations_alliance_oet.sql', 'utf8')
const body = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('B1: every row names its body page; only AACSB, EQUIS and AMBA count towards a crown; AMBA rows are approved', () => {
  const rows = body.match(/\('(AACSB|EQUIS)', '[0-9a-f-]{36}'::uuid, (null|'[^']*(?:''[^']*)*'), '(https:\/\/[^']+)'\)/g) || []
  expect(rows.filter((r) => r.startsWith("('AACSB'"))).toHaveLength(58)
  expect(rows.filter((r) => r.startsWith("('EQUIS'"))).toHaveLength(31)
  for (const r of rows.filter((x) => x.startsWith("('EQUIS'"))) expect(r).toContain('efmdglobal.org/accreditations-assessments/business-schools/equis/equis-accredited-schools/')
  expect(body).toContain("select case count(distinct a.body_code) when 3 then 'triple_crown' when 2 then 'double_crown' end")
  expect(body).toContain("and a.body_code in ('AACSB', 'EQUIS', 'AMBA')")
  expect(body).toContain("where body_code = 'AMBA' and status = 'under_review';")
  expect(body).not.toContain('6e83a7d7-27d5-476f-a6d9-bc03a04c42d2')   // the University of New Brunswick: a non-accredited AACSB member
})

test('B3: the 2050 Alliance keeps its code, adds ACU and VU, and never Charles Darwin', () => {
  expect(body).toContain("set name = '2050 Alliance'")
  expect(body).toContain("where code = 'au_iru' and name = 'Innovative Research Universities';")
  expect(body).toContain("('030992c3-72c6-452d-8a3b-10ceb0fd77f2'::uuid), ('bac82321-ded7-4e10-a71d-b18f3ae4d1c7'::uuid)")
  expect(body).toContain("raise exception 'post-check: Charles Darwin is not a member'")
  expect(body).toContain("'s798_2050_alliance'")
})

test('B4 and the v3 answers: grades as held, the crown, and the study load basis; v2 untouched', () => {
  expect(body).toContain("select pg_temp.cf_edit_def('public.website_v3_provider_item(jsonb)'::regprocedure, '3a48ac0a47003837dda85d6db3773f19',")
  expect(body).toContain("select pg_temp.cf_edit_def('security.course_v3_fields_v1(jsonb,uuid)'::regprocedure, '705df909b55e06f8c57c160fce5f6721',")
  expect(body).toContain("jsonb_build_object('score_grade', r.score_grade, 'subtest_grades', r.subtest_grades)")
  expect(body).toContain("jsonb_build_object('score_grade', null, 'subtest_grades', null)")
  expect(body).toContain("when v_load_src = 'register' and v_load_ev is null then 'register_rule'")
  expect(body).toContain("'accreditation_crown', security.provider_accreditation_crown_v1(v_provider));")
  expect(body).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1/)
  expect(body).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
