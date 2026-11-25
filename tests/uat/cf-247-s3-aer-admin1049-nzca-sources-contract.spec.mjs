// Guards: Admin #1049 finite named NZ/CA AER Wave 1, Steps 1-2 only; official provider, source scope, G3, manual locks, cron and no CA wide settings.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const sql=fs.readFileSync('supabase/migrations/20261126230000_cf247_s3_aer_1049_nzca_source_candidates.sql','utf8')
test('source candidates only, 24 unique named NZ/CA providers, no admission or scheduling changes',()=>{
  const ids=[...sql.matchAll(/\('([0-9a-f-]{36})'::uuid,'(?:NZ|CA)','https?:\/\//g)].map(x=>x[1])
  expect(ids).toHaveLength(24)
  expect(new Set(ids).size).toBe(24)
  expect(sql).toContain('security.aer_source_check_v1')
  expect(sql).toContain("check_result->>'ownership'<>'official_host'")
  expect(sql).toContain("c.iso_alpha2=r.country")
  expect(sql).toContain("r.country in ('NZ','CA')")
  expect(sql).toContain('security.consumer_api_check_v1')
  expect(sql).toContain("on conflict(provider_id,url) do nothing")
  expect(sql).toContain("cron.job where active")
  expect(sql).not.toMatch(/(?:cron\.schedule|create\s+(?:function|table)|alter\s+table|update\s+pipeline\.platform_toolset_settings|catalogue\.provider_entry_matrix|catalogue\.course_entry_requirements)/i)
})
