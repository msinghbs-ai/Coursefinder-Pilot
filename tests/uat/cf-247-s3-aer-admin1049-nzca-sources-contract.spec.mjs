// Guards: Admin #1049 finite named NZ/CA AER Wave 1, Steps 1-2 only; official provider, source scope, G3, manual locks, cron and no CA wide settings.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const sql=fs.readFileSync('supabase/migrations/20261129032000_cf247_s3_aer_1049_nzca_source_candidates.sql','utf8')
test('source candidates only, 21 safe named NZ/CA providers, no admission or scheduling changes',()=>{
  const ids=[...sql.matchAll(/\('([0-9a-f-]{36})'::uuid,'(?:NZ|CA)','https?:\/\//g)].map(x=>x[1])
  expect(ids).toHaveLength(21)
  expect(new Set(ids).size).toBe(21)
  // The three old URLs are not academic entry sources usable for international admission.
  for(const wrong of ['tpp.ac.nz/study-and-employment-pathways/print','bcito.org.nz/find-a-trade/carpentry/','auroracollege.nt.ca/wp-content/uploads/2026/03/AC_academic_calendar_26-27_v2.9.pdf']) expect(sql).not.toContain(wrong)
  expect(sql).toContain('cotr.bc.ca/enrolment-services/registration-and-admissions/course-equivalency/')
  expect(sql).toContain('bcit.ca/programs/airline-and-flight-operations-commercial-pilot-fixed-wing-diploma-full-time-100adipma/')
  expect(sql).toContain('jibc.ca/procedure/admissions')
  expect(sql).toContain('security.aer_source_check_v1')
  expect(sql).toContain("check_result->>'ownership'<>'official_host'")
  expect(sql).toContain("c.iso_alpha2=r.country")
  expect(sql).toContain("r.country in ('NZ','CA')")
  expect(sql).toContain('security.consumer_api_check_v1')
  expect(sql).toContain("on conflict(provider_id,url) do nothing")
  expect(sql).toContain("cron.job where active")
  expect(sql).not.toMatch(/(?:cron\.schedule|create\s+(?:function|table)|alter\s+table|update\s+pipeline\.platform_toolset_settings|catalogue\.provider_entry_matrix|catalogue\.course_entry_requirements)/i)
})
