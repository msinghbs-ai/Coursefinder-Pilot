// Guards: Decision 269 (SS-020 step 1, Platform Admin 3 Nov 2026 22:05 "Approve all, build in order"): dead admin sections retire and no working control is lost
// CF-247 SS-020 step 1. Admin docs/platform/ui-audit/2026-11-03-admin-menu-build-prompt.md step 1 and the keep-merge-retire review section 5:
// the Layer 3 AI area (Automations) and the Layer 3 block (Health checks), the Serper, ScrapingBee and Search pass cards, the dropped
// acquisition providers, the Go-live Layer 3 model profiles and dropped-provider gates, Progress "Courses with each field", and the Health
// checks Capacity link. Rows and history stay in the database; the migration re-areas three live jobs and records the register rows only.
// Refresh schedules and one-off runs is parked (DECISION REQUIRED — SS-020: it holds the only Layer 1 cadence control).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { RETIRED_FETCHERS, RETIRED_TOOLSETS, isRetiredFetcher } from '../../src/retired-services.js'
import { PAGES } from '../../src/nav-map.js'

const read = (p) => fs.readFileSync(p, 'utf8')
const MIG = read('supabase/migrations/20261104182000_cf247_ss020_step1_retire_dead_sections.sql')

test('migration: the Layer 3 AI jobs move area and keep running; retirements are register rows only', () => {
  expect(MIG).toContain("update pipeline.automation_catalogue set area = 'Course pages'\n where jobname in ('coverage-ai-match-prepare', 'coverage-ai-match') and area = 'Layer 3 AI';")
  expect(MIG).toContain("update pipeline.automation_catalogue set area = 'Admission'\n where jobname = 'fee-period-settle' and area = 'Layer 3 AI';")
  expect(MIG).not.toMatch(/cron\.(unschedule|alter_job)|set enabled\s*=\s*false|update pipeline\.layer2_acquisition_providers/i)
  // pipeline.search_pass_links is written by Firecrawl course-page finding: it is not retired
  expect(MIG).not.toContain("('table', 'pipeline.search_pass_links'")
  for (const n of ["'public.admin_search_pass_start'", "'security.toolset_pass_backlog'", "'toolset-runner'", "'pipeline.toolset_sample_runs'", "'Platform health › Health checks › Layer 3 block'"]) expect(MIG).toContain(n)
  expect(MIG).toMatch(/still read by security\.toolset_sample_notices_v1/)
})

test('retired services: one list for Toolsets, Fetchers, Settings and the Go-live checklist', () => {
  expect([...RETIRED_TOOLSETS]).toEqual(['serper', 'scrapingbee'])
  for (const k of ['scraperapi', 'scrape-do', 'zenrows', 'parsebot']) expect(RETIRED_FETCHERS.has(k)).toBe(true)
  expect(isRetiredFetcher({ provider_key: 'firecrawl' })).toBe(false)
  expect(isRetiredFetcher({ provider_key: 'direct-http' })).toBe(false)
  for (const f of ['src/Toolsets.jsx', 'src/layer2-provider-entry.jsx', 'src/platform-maturity-entry.jsx', 'src/EnvironmentMigrationWorkspace.jsx']) expect(read(f)).toContain("from'./retired-services'")
  expect(read('src/platform-maturity-entry.jsx')).not.toContain('Layer 3 model profiles" items')
  expect(read('src/Toolsets.jsx')).not.toMatch(/function (SearchPass|SampleRuns|KeyPlan)\b/)
})

test('step 1 changes no role: the pages it touched keep their minimum roles', () => {
  expect(PAGES.services.min).toBe(3)
  expect(PAGES.migration.min).toBe(6)
  expect(PAGES.health.tabs.find((t) => t.key === 'checks').min).toBe(3)
  expect(PAGES.coverage.tabs.find((t) => t.key === 'attributes').min).toBe(1)
})

test('browser: Health checks shows no Layer 3 block and links Capacity to the Go-live checklist', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#platform-health')
  const main = page.locator('main')
  await expect(main.getByText('Layer 4 review backlog grew by 809')).toBeVisible()
  await expect(main).not.toContainText('Layer 3')
  await expect(main).not.toContainText('stuck in reserved/interpreting')
  await expect(main.getByText('Layer 2 and 4 queues').first()).toBeVisible()
  const src = read('src/PlatformHealth.jsx')
  expect(src).toContain("db_capacity:['#environment-migration','Go-live checklist › Capacity']")
  expect(src).not.toContain('tab=readiness')
})

test('browser: Fetchers and the Go-live checklist list only the providers in use', async ({ page }) => {
  await mockAdmin(page)
  const providers = [
    { id: 'p1', provider_key: 'firecrawl', display_name: 'Firecrawl', adapter_type: 'browser_api', enabled: true, credential_configured: true, capabilities: {} },
    { id: 'p2', provider_key: 'direct-http', display_name: 'Direct HTTP', adapter_type: 'direct_http', enabled: true, auth_scheme: 'none', capabilities: {} },
    { id: 'p3', provider_key: 'zenrows', display_name: 'ZenRows (JS render + premium proxy)', adapter_type: 'scraper_api', enabled: false, capabilities: {} },
    { id: 'p4', provider_key: 'serper', display_name: 'Serper (web search)', adapter_type: 'structured_api_proxy', enabled: true, capabilities: {} },
  ]
  const gates = { source_gates: [], scraper_gates: providers.map((p) => ({ provider_id: p.id, provider_key: p.provider_key, provider_name: p.display_name, state: 'registered', enabled: p.enabled })),
    ai_gates: [{ profile_id: 'a1', profile_code: 'layer3-intake-v1', state: 'registered', enabled: false }] }
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async (route) => {
    const op = (route.request().postDataJSON() || {}).p_operation
    if (op === 'layer2_acquisition_providers') return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(providers) })
    if (op === 'platform_environment_gates') return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(gates) })
    return route.fallback()
  })
  await page.goto('/#models-services?tab=fetchers')
  const list = page.locator('.l2p-provider-list')
  await expect(list).toContainText('Firecrawl')
  await expect(list).toContainText('Direct HTTP')
  await expect(list).not.toContainText('ZenRows')
  await expect(list).not.toContainText('Serper')
  await page.goto('/#environment-migration')
  await expect(page.getByText('Layer 2 acquisition providers')).toBeVisible()
  await expect(page.locator('main')).not.toContainText('Layer 3 model profiles')
  await expect(page.locator('main')).not.toContainText('layer3-intake-v1')
  await expect(page.locator('main')).not.toContainText('ZenRows (JS render')
})
