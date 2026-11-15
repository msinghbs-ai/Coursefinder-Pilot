// Guards: Services & limits at a glance and the Settings Integrations tab (Platform Admin 16 Nov 2026 07:41 and 08:22): one compact row per outside service (Firecrawl, Direct HTTP, OpenRouter) shows its status, switch and the credit or cap left without opening anything; each service card keeps its switch, limits and settings in a closed Details fold drawn only when opened, and a link to something inside a service (?at=, ?card=) opens that fold; Environment & integrations (keys, platform resources, services overview) is Settings › Integrations, not part of the Settings tab
// CF-247 S556. src/mature-main.jsx (ServicesSummary, ServicesLimits, the environment page), src/nav-map.js. Mocked REST responses: nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const SRC = fs.readFileSync('src/mature-main.jsx', 'utf8')
const BUDGETS = { firecrawl_monthly_limit: 100000, firecrawl_used_this_month: 71005, firecrawl_stop_at_remaining: 2000, openrouter: { remaining_usd: 19.08, observed_at: '2026-11-16T00:10:00Z' } }

async function withBudgets(page) {
  await mockAdmin(page)
  const reads = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_pipeline_settings_read', route => { reads.push(1); return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ budgets: BUDGETS }) }) })
  return reads
}

test('source: the summary reads the services list and the pipeline budgets once; the Firecrawl and Direct read bodies sit in folds', () => {
  const fn = SRC.slice(SRC.indexOf('function ServicesSummary()'), SRC.indexOf('function ServicesLimits('))
  expect(fn).toContain("supabase.rpc('admin_services_read'),supabase.rpc('admin_pipeline_settings_read')")
  for (const k of ["['firecrawl','Firecrawl'", "['direct-http','Direct HTTP'", "['openrouter','OpenRouter'"]) expect(fn).toContain(k)
  expect(SRC).toContain("fold('firecrawl','firecrawl',()=>")
  expect(SRC).toContain("fold('direct','direct',()=>")
  expect(SRC).toContain("const target=['card','at','tab','setting'].map(k=>routeParams?.get?.(k)||'').join(' ')")
})

test('browser: three rows show the switch and what is left; the folds start closed and draw nothing until opened', async ({ page }) => {
  await withBudgets(page)
  await page.goto('/#models-services')
  const s = page.locator('[data-services-summary]')
  await expect(s.locator('[data-service-summary]')).toHaveCount(3)
  const fc = s.locator('[data-service-summary="firecrawl"]')
  await expect(fc).toContainText('On')
  await expect(fc.locator('[data-summary-status]')).toContainText('Test passed')
  await expect(fc).toContainText('28,995 of 100,000 credits left this month (stops at 2,000)')
  await expect(s.locator('[data-service-summary="direct-http"]')).toContainText('Unknown') // not in the fixture's services list
  await expect(s.locator('[data-service-summary="direct-http"] [data-summary-status]')).toContainText('Not registered')
  const or = s.locator('[data-service-summary="openrouter"]')
  await expect(or).toContainText('US$19.08 balance at the last reading')
  await expect(or.locator('a')).toHaveAttribute('href', '#models-services?tab=ai')
  for (const id of ['firecrawl', 'direct']) await expect(page.locator(`[data-fold="service-details:${id}"]`)).not.toHaveAttribute('open', '')
  await expect(page.locator('[data-search-cap]')).toHaveCount(0)
  await expect(page.locator('[data-fold="service-details:firecrawl"] > summary')).toHaveText('Details')
  await page.locator('[data-fold="service-details:firecrawl"] > summary').click()
  await expect(page.locator('[data-service-card="firecrawl"] [data-search-cap]')).toBeVisible()
  await expect(page.locator('[data-fold="service-details:direct"]')).not.toHaveAttribute('open', '')
})

test('browser: a link into a service opens its fold', async ({ page }) => {
  await withBudgets(page)
  await page.goto('/#models-services?card=services.toolsets,services.toolset.firecrawl&at=services.toolset.firecrawl')
  await expect(page.locator('[data-fold="service-details:firecrawl"]')).toHaveAttribute('open', '')
  await expect(page.locator('[data-card="services.toolset.firecrawl"]')).toBeVisible()
  await expect(page.locator('[data-fold="service-details:direct"]')).not.toHaveAttribute('open', '')
})

test('browser: with no budgets returned the rows say so instead of waiting', async ({ page }) => {
  await mockAdmin(page)
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_pipeline_settings_read', route => route.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ code: 'P0001', message: 'not allowed' }) }))
  await page.goto('/#models-services')
  await expect(page.locator('[data-service-summary="firecrawl"]')).toContainText('—')
  await expect(page.locator('[data-service-summary="openrouter"]')).toContainText('No balance reading: see the AI tab')
})

test('Settings › Integrations holds Environment & integrations; the Settings tab is the settings only, with a link', async ({ page }) => {
  const { PAGES, hrefFor } = await import('../../src/nav-map.js')
  expect(PAGES.environment.tabs.map(t => [t.key, t.label, t.min])).toContainEqual(['integrations', 'Integrations', 6])
  expect(hrefFor('environment', 'integrations')).toBe('#environment?tab=integrations')
  expect(SRC).toContain("if(tab==='integrations')return rank>=6?<div className=\"m-page-stack\" data-settings-integrations><EnvironmentMigrationWorkspace rank={rank} onError={onError} view=\"integrations\"/></div>:null")
  expect(SRC).not.toContain('<PipelineSettings onError={err}/><EnvironmentMigrationWorkspace')
  await mockAdmin(page)
  await page.goto('/#environment')
  await expect(page.locator('[data-integrations-moved] a')).toHaveAttribute('href', '#environment?tab=integrations')
  await expect(page.locator('[data-settings-integrations]')).toHaveCount(0)
  await page.locator('[data-integrations-moved] a').click()
  await expect(page.locator('[data-settings-integrations]')).toBeVisible()
  await expect(page.getByRole('tab', { name: 'Integrations' })).toHaveAttribute('aria-selected', 'true')
})
