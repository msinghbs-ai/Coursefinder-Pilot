// Guards: DR-16 and F-OPS.21 (SS-Programme-Control 26 Nov 2026 22:51 AEDT, Priority 1): academic entry and course descriptions are verified through the existing website and Zoho consumer reads by a bounded rotating sample, with international applicability; returned, populated, matches, international applicability and delivery are separate; sample figures are never extrapolated to the population.
// s1176b: pipeline.pim_consumer_samples, security.pim_consumer_sample_v1, security.pim_consumer_fields_v1; one block in security.data_delivery_refresh_v1; one key in security.pim_operations_v1.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261130044500_cf247_s1176b_pim_consumer_field_sample.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1176b: reads go through the existing consumer reads; the consumer API is only called', () => {
  for (const f of ['public.website_v2_course(c.stable_key)', 'public.zoho_v2_course(c.stable_key)', 'public.website_v3_course(c.stable_key, v_cc)']) expect(code).toContain(f)
  expect(code).not.toMatch(/create or replace function public\.(website|zoho)_/i)
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
})

test('s1176b: returned, populated, matches, international applicability and delivery are recorded apart', () => {
  for (const k of ["'returned'", "'populated'", "'matches'", "'intl_ok'"]) expect(code).toContain(k)
  expect(code).toContain('delivery_verified boolean')
  expect(code).toContain('intl_verified boolean')
  expect(code).toContain("e.audience in ('international', 'all')")
  expect(code).toContain("e.audience = 'domestic'")
})

test('s1176b: a bounded rotating sample; the report never extrapolates', () => {
  expect(code).toContain("security.pipeline_num_v1('pim.consumer_sample_courses', 2)")
  expect(code).toContain('order by s.checked_at nulls first')
  for (const k of ["'population'", "'sampled_in_window'", "'coverage_in_window'", "'last_checked'", "'oldest_check_in_window'", "'failures_by_reason'", "'latest_failures'"]) expect(code).toContain(k)
  expect(code).toContain('never a population figure')
})

test('s1176b: the student country is read from the data, never written in', () => {
  expect(code).toContain('from catalogue.provider_entry_matrix m where m.provider_id = c.provider_id')
  expect(code).not.toMatch(/'(IN|NP|CN|AU)'/)
})

test('s1176b: background only, on its own run; pim.operations gains one key; no job; nothing dropped', () => {
  expect(code).toContain('perform security.pim_consumer_sample_v1(null);')
  expect(code).toContain('guard: the screen read runs the sample')
  expect(code).toContain("'consumer_fields', security.pim_consumer_fields_v1(),")
  expect(code).toContain("guard: security.pim_operations_v1 is not the s1176 definition")
  expect(code).not.toMatch(/\b(cron\.schedule|cron\.unschedule|cron\.alter_job|truncate|drop\s+(table|function|column|constraint|trigger)|delete\s+from)\b/i)
  expect(MIG).toMatch(/^-- Replaces:/m)
  expect(MIG).toMatch(/^-- Retires:/m)
})
