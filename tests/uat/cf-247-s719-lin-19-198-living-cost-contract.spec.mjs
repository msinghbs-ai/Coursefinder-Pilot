// Guards: Home Affairs financial-capacity living cost (Platform Admin 19 Nov 2026 06:41 and 06:45): LIN 19/198 is registered in the Layer 1 Register under Australia before it is read, its fact and the Home Affairs Step by step tab state the same rule, two sources that disagree are held for a person, a successor edition carries one read date and every source's attribution, and a tab page is read whole.
// CF-247 S719. supabase/migrations/20261119075000_cf247_lin_19_198_living_cost.sql, supabase/functions/_shared/cf247-page-facts.js (loader v1.5.0).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { firecrawlScrapeBody, extractFact, htmlToText } from '../../supabase/functions/_shared/cf247-page-facts.js'

const M = fs.readFileSync('supabase/migrations/20261119075000_cf247_lin_19_198_living_cost.sql', 'utf8')
const loader = fs.readFileSync('supabase/functions/layer1-destination-geo-loader/index.ts', 'utf8')

test('a page address that names a tab is read whole; every other page keeps main content', () => {
  expect(firecrawlScrapeBody('https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500#HowTo').onlyMainContent).toBe(false)
  expect(firecrawlScrapeBody('https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500').onlyMainContent).toBe(true)
  expect(loader).toContain('const VERSION = "layer1-destination-geo-loader-v1.5.0";')
})

test('the instrument pattern reads the primary-applicant amount, not the partner or child amounts', () => {
  const html = '<p>(ii) the following living costs and expenses:</p><p>(A) if the primary applicant intends to stay in Australia for a period of 12 months or more—AUD29,710 (primary applicant annual living costs); and</p><p>(B) for a spouse or de facto partner—AUD10,394 (annual living costs)</p>'
  const r = extractFact(htmlToText(html), { kind: 'amount', pattern: 'AUD\\s?([0-9]{2},[0-9]{3})\\s*\\(primary applicant annual living costs\\)', flags: 'i', anchor: 'primary applicant annual living costs' })
  expect(r.found).toBe(true)
  expect(String(r.raw ?? r.value)).toMatch(/29,?710/)
  expect(r.quote).toContain('AUD29,710 (primary applicant annual living costs)')
})

test('registered in the Layer 1 Register under Australia first, with authority, domains, format, cadence and licence', () => {
  expect(M).toContain("'LIN 19/198 Evidence of Financial Capacity (Subclass 500 and 590)'")
  expect(M).toContain("'source_system', 'DESTINATION'")
  expect(M).toContain("array['legislation.gov.au', 'www.legislation.gov.au']")
  expect(M).toContain("'licence', 'CC BY 4.0'")
  expect(M).toMatch(/'rules', true, false, 30, 30, 20, 60, true, null/)
  expect(M).toContain("where iso_alpha2 = 'AU'")
})

test('the load function: one read date, merged attribution, the rule names its page, disagreement is held', () => {
  expect(M).toContain("select pg_temp.cf_edit_many('security.destination_page_facts_load_v1(jsonb)'::regprocedure, '47cf7bd563d3c1638d727fd419d1f30c',")
  expect(M).toContain("regexp_replace(e.edition_label, '\\s\\(read [^)]*\\)$', '')")
  expect(M).toContain("coalesce(src.metadata->>'attribution', '') <> ''")
  expect(M).toContain("source_url = fd->>'page_url',")
  expect(M).toContain("last_status = 'held', last_reason = 'Two official sources for this rule give different values; a person decides'")
})

test('no new table or function; nothing dropped or deleted; consumer API checked', () => {
  const code = M.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
  expect(code).not.toMatch(/create table|create or replace function (public|security|pipeline|destination)\./i)
  expect(code).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(code).toContain('v_drift := security.consumer_api_check_v1();')
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: /m)
})
