// Guards: F-SCH stated award value from verified benefits (Platform Admin S2-Scholarship directive 13 Nov 2026 14:50 §4; Developer Requirements v2.26 F-SCH.13): an empty canonical value is filled once from the scholarship's own verified version 3 benefits, never over a lock or an existing value; publication stays with the existing checks
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113320000_cf247_sch_value_from_verified_benefits.sql', 'utf8')
const fn = m.slice(m.indexOf('create or replace function security.scholarship_value_from_benefits_v1'), m.indexOf('comment on function security.scholarship_value_from_benefits_v1'))

test('only an empty value, never over a lock, only the scholarship\'s own verified reader benefits', () => {
  expect(fn).toContain("if s.award_value_type in ('percentage', 'fixed_amount') or coalesce(s.award_amount, s.award_percentage) is not null then return '{}'; end if;")
  expect(fn).toContain("from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = p_scholarship")
  expect(fn).toContain("where cv.scholarship_id = p_scholarship and cv.notes like 'sch-extract-v3:%'")
  // a tuition percentage first, then the largest amount with a currency; under 50 is a page placeholder
  expect(fn).toContain("order by (cv.coverage_type = 'tuition_fees' and cv.percentage is not null) desc, cv.percentage desc nulls last, cv.amount desc nulls last")
  expect(fn).toMatch(/cv\.amount >= 50 and cv\.currency_code is not null\)\)\s+-- fixed:/)
  // the change is recorded with its extraction, quote and rule
  expect(fn).toContain("'rule', 'value_from_verified_benefit', 'extraction', b.extraction_id")
})

test('publication is not decided here; the detail apply calls it; one backfill; no consumer object', () => {
  expect(fn).not.toMatch(/publication_status\s*=/)
  expect(m).toContain("select pg_temp.edit_n('security.scholarship_detail_apply_v1(bigint)', 'a9288404514058b9d126baf5511b827d', array[")
  expect(m).toContain('v_done := v_done || security.scholarship_value_from_benefits_v1(s.id);')
  expect(m).toContain("'value_from_verified_benefits_backfill'")
  expect(m).not.toMatch(/create or replace function (api\.|public\.website_|public\.zoho_)/i)
  expect(m).toContain('revoke all on function security.scholarship_value_from_benefits_v1(uuid) from public, anon, authenticated;')
})
