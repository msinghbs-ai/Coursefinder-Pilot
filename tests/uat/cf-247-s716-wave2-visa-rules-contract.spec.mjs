// Guards: next-wave visa rules (Platform Admin 19 Nov 2026 06:45 and 06:50): editions publish only with approved open terms (GB OGL v3.0, US public domain; NZ pending), monthly or month-based figures are kept as quoted text (never written as annual or years), and the first runs go through the standard Layer 1 scheduler an hour apart from the LIN 19/198 run.
// CF-247 S716. supabase/migrations/20261119082000_cf247_wave2_visa_rules_editions_facts.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { extractFact, htmlToText } from '../../supabase/functions/_shared/cf247-page-facts.js'

const M = fs.readFileSync('supabase/migrations/20261119082000_cf247_wave2_visa_rules_editions_facts.sql', 'utf8')
const code = M.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')

test('terms: GB and US approved, NZ pending until confirmed', () => {
  expect(code).toContain("'Source: GOV.UK (UK Visas and Immigration). Contains public sector information licensed under the Open Government Licence v3.0.', 'approved'")
  expect(code).toContain("'Source: U.S. Citizenship and Immigration Services, uscis.gov (U.S. Government work, public domain).', 'approved'")
  expect(code).toContain("'Source: Immigration New Zealand, immigration.govt.nz. Reuse terms to be confirmed.', 'pending'")
  expect(code).toContain("raise exception 'post-check: NZ terms must stay pending until confirmed'")
})

test('the patterns read the official wording; monthly and month figures are text', () => {
  const uk = extractFact(htmlToText('<ul><li>£1,529 per month (for up to 9 months) for courses in London</li><li>£1,171 per month (for up to 9 months) for courses outside London</li></ul>'),
    { kind: 'text', pattern: '£\\s?[0-9],[0-9]{3} per month \\(for up to 9 months\\) for courses outside London', flags: 'i' })
  expect(uk.found).toBe(true)
  expect(uk.raw).toContain('£1,171 per month')
  const nz = extractFact(htmlToText('<li>NZD $20,000 for each year, if you are studying for 1 year or more, or</li>'),
    { kind: 'amount', pattern: 'NZD\\s?\\$?\\s?([0-9]{2},[0-9]{3})\\s+for each year', flags: 'i', min: 15000, max: 40000 })
  expect(nz.value).toBe(20000)
  expect(code).toContain("'text', 'post_study_work', 'F-1 Optional Practical Training (OPT) length'")
})

test('first runs through the Layer 1 scheduler, an hour apart; data only', () => {
  expect(code).toContain("set next_verification_at = now() + interval '55 minutes'")
  expect(code).not.toMatch(/create table|create or replace function/i)
  expect(code).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(code).toContain('v_drift := security.consumer_api_check_v1();')
})
