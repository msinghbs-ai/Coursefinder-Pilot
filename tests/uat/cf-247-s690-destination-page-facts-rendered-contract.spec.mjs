// Guards: destination page facts (Platform Admin 18 Nov 2026 17:55): Home Affairs pages read rendered through Firecrawl /v1/scrape (JS rendering, onlyMainContent), spent and logged through the database; JSA Table 1 mapped from its real headings; Fair Work and QILT untouched; Run now without a migration.
// CF-247 S690. supabase/migrations/20261118220000_cf247_destination_page_facts_rendered_read.sql, layer1-destination-geo-loader v1.3.0, .github/workflows/destination-run-now.yml.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { firecrawlScrapeBody, headerSample, isEarnings, isEmployed, parseOccupationGrid } from '../../supabase/functions/_shared/cf247-page-facts.js'

const M = fs.readFileSync('supabase/migrations/20261118220000_cf247_destination_page_facts_rendered_read.sql', 'utf8')
const E = fs.readFileSync('supabase/functions/layer1-destination-geo-loader/index.ts', 'utf8')
const W = fs.readFileSync('.github/workflows/destination-run-now.yml', 'utf8')

test('the rendered read: Firecrawl /v1/scrape with the main content only, spent first and logged, evidence kept', () => {
  expect(firecrawlScrapeBody('https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500'))
    .toEqual({ url: 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500', formats: ['html', 'markdown'], onlyMainContent: true })
  expect(E).toContain('const VERSION = "layer1-destination-geo-loader-v1.3.0";')
  expect(E).toContain('await fetch("https://api.firecrawl.dev/v1/scrape", {')
  expect(E).toContain('if (!await rpc(service, "svc_fc_spend", { p_units: 1, p_purpose: "destination_page_facts", p_provider_id: null, p_url: pageUrl })) {')
  expect(E).toContain('await rpc(service, "svc_fc_call_log", { p: { run_id: runId, use_case: "destination_page_facts", endpoint: "v1/scrape", url: pageUrl,')
  expect(E).toContain('signal: AbortSignal.timeout(90000), // fixed: API time-out')
  expect(E).toContain('const rendered = list.some((f) => f.read_mode === "rendered");')
  expect(E).toContain('const path = `destination/page-facts/${host}/${hash}${rendered ? ".rendered" : ""}.html`;')
})

test('JSA Table 1: two-row headings are read with the cell above, measures by what they are; shares, ages and hours never', () => {
  const g = [['Table 1 - Overview'], [], ['', '', '', 'Employment', '', 'Earnings'],
    ['OSCA level', 'OSCA code', 'Occupation name', 'Number', 'Female (%)', 'Median weekly ($)', 'Median age'],
    [5, '261313', 'Software Engineer', 120000, '20%', 2500, 35], [1, '1', 'Managers', 1, 1, 1, 1], [4, '2613', 'Software and Applications Programmers', '150,000', '', '2,300', 36]]
  const p = parseOccupationGrid(g)
  expect(p.header).toMatchObject({ row: 3, code: 'OSCA code', title: 'Occupation name', employed: 'Employment Number', earnings: 'Earnings Median weekly ($)', earnings_period: 'weekly' })
  expect(p.rows).toEqual([
    { code: '261313', title: 'Software Engineer', median_weekly_earnings: 2500, employment_count: 120000 },
    { code: '2613', title: 'Software and Applications Programmers', median_weekly_earnings: 2300, employment_count: 150000 },
  ])
  expect(isEarnings('Median annual income ($)')).toBe(true)
  expect(isEarnings('Earnings Median age')).toBe(false)
  expect(isEarnings('Median weekly earnings growth (%)')).toBe(false)
  expect(isEmployed('Employed persons')).toBe(true)
  expect(isEmployed('Employment share (%)')).toBe(false)
  expect(isEmployed('Average weekly hours worked by employed persons')).toBe(false)
  expect(parseOccupationGrid([['Back to Contents'], ['OSCA level', 'OSCA code', 'Occupation name', 'Skill level', 'Occupation overview']]).rows).toEqual([])
  expect(headerSample([[''], ['x'], ['Table 5'], [''], ['OSCA level', 'OSCA code', 'Occupation name']])[2]).toEqual(['OSCA level', 'OSCA code', 'Occupation name'])
})

test('the migration: read mode as data, md5-guarded edits, Fair Work and QILT untouched, nothing dropped', () => {
  expect(M).toContain("alter table destination.page_facts add column if not exists read_mode text not null default 'static';")
  expect(M).toContain("select pg_temp.cf_edit('public.svc_destination_page_facts_v1()'::regprocedure, 'eaa186dda4d71541842a02f431667ded',")
  expect(M).toContain("select pg_temp.cf_edit('security.destination_page_facts_load_v1(jsonb)'::regprocedure, 'fefa5c5a27511fe2ca015e9f3c3992d8',")
  expect(M).toContain("raise exception 'post-check: Fair Work stays restricted'")
  expect(M).toContain("raise exception 'post-check: QILT stays gated'")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(M).not.toMatch(/website_v2_|website_edge_|zoho_edge_|website_api_v2_/)
})

test('Run now without a migration: the typed project ref, destination jobs only, read back', () => {
  expect(W).toContain('if [ -z "${{ vars.SUPABASE_PROJECT_REF }}" ] || [ "$REF" != "${{ vars.SUPABASE_PROJECT_REF }}" ]; then')
  expect(W).toContain('options: [destination-page-facts-load, destination-climate-load, destination-abs-load]')
  expect(W).toContain("security.destination_job_run_now_v1('$JOB'")
  expect(W).not.toMatch(/insert into|update |delete from/i)
})
