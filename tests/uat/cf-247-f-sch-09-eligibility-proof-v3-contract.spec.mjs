// Guards: F-SCH.01 proof v2 shadow review (12 Nov 2026 19:58): a linked general admissions page is not a scholarship's eligibility, and a sentence naming international candidates is not a domestic-only proof; unsupported claims stay protected (directive 12 Nov 2026 16:12 §5)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113065000_cf247_sch_eligibility_proof_v3.sql', 'utf8')
// the rule's two expressions, as they will run (Postgres ~* with \m \M word edges, rendered here as \b)
const pg = (re) => new RegExp(re.replace(/\\m|\\M/g, '\\b'), 'i')
const LINKED_OK = pg('(scholar|award|bursar|grant|prize|stipend|terms|condition|eligib|rules|funding|fee[-_]?waiver)')
const LINKED_GENERAL = pg('(how[-_]to[-_]apply|/admissions?([-/_]|$)|apply[-_]now|/apply(/|$))')
const linkedRefused = (u) => !LINKED_OK.test(u) || LINKED_GENERAL.test(u)
const MIXED = pg('\\m(international|overseas|non[- ]?residents?)\\M')

test('the review\'s wrong proofs are refused by the rule; true ones are kept', () => {
  expect(linkedRefused('https://www.auarts.ca/future-students/how-to-apply/how-to-apply-for-a-bachelors-degree')).toBe(true)
  expect(linkedRefused('https://www.uts.edu.au/for-students/admissions-entry/how-to-apply')).toBe(true)
  expect(linkedRefused('https://www.example.edu.au/scholarships/global-excellence/terms-and-conditions')).toBe(false)
  expect(linkedRefused('https://www.example.ac.nz/awards/eligibility-rules')).toBe(false)
  expect(MIXED.test('You must be an Australian citizen, permanent resident or an onshore international candidate.')).toBe(true)
  expect(MIXED.test('Be a Canadian citizen or permanent resident')).toBe(false)
  expect(MIXED.test('Eligible citizenship Australian citizen, Permanent resident')).toBe(false)
})

test('migration 20261113065000: md5-guarded, the expressions tested above, shadow kept, shadow proofs evaluated again', () => {
  expect(m).toContain("'8a72bff9ffae9c512007402f90b73c06'")
  expect(m).toContain("coalesce(v_url, '') !~* '(scholar|award|bursar|grant|prize|stipend|terms|condition|eligib|rules|funding|fee[-_]?waiver)'")
  expect(m).toContain("coalesce(v_url, '') ~* '(how[-_]to[-_]apply|/admissions?([-/_]|$)|apply[-_]now|/apply(/|$))') then 'linked_page_not_scholarship'")
  expect(m).toContain("coalesce(r.result->>'audience_quote', '') ~* '\\m(international|overseas|non[- ]?residents?)\\M' then 'mixed_audience'")
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings/i)
  expect(m).toContain("where outcome = 'proven' and applied->>'mode' = 'shadow';")
})
