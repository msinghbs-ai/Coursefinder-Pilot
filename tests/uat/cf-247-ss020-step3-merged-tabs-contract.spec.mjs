// Guards: Decision 269 (SS-020 step 3, Platform Admin 3 Nov 2026 22:05): Queues & yield and Services & limits replace four tabs, old addresses land on them, roles unchanged, no control drawn twice
// CF-247 SS-020 step 3. Admin docs/platform/ui-audit/2026-11-03-admin-menu-build-prompt.md step 3 and the keep-merge-retire review C35, C36,
// C45, C46, C47, C48: Platform health › Work queues + Integration queue's Pipeline yield → Queues & yield (key 'queues'); Models & services ›
// Services + Toolsets & limits + Fetchers → Services & limits (key 'services'); AI model switches → AI & OpenRouter. 53 → 51 tabs.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { PAGES, resolveTarget, hrefFor } from '../../src/nav-map.js'

const go = (addr) => { const [a, q] = addr.split('?'); const r = resolveTarget(a, new URLSearchParams(q || '')); return `${r.page}/${r.tab}${r.params.toString() ? '?' + r.params : ''}` }

test('menu: 51 tabs on 20 pages; the merged tabs keep the minimum roles of what they hold', () => {
  expect(Object.values(PAGES).reduce((n, p) => n + (p.tabs ? p.tabs.length : 1), 0)).toBe(51)
  expect(Object.keys(PAGES)).toHaveLength(20)
  expect(PAGES.services.tabs.map((t) => [t.key, t.label, t.min])).toEqual([['services', 'Services & limits', 4], ['ai', 'AI & OpenRouter', 3]])
  expect(PAGES.health.tabs.map((t) => [t.key, t.label, t.min])).toEqual([['checks', 'Health checks', 3], ['queues', 'Queues & yield', 3], ['integration', 'Integration queue', 5], ['storage', 'Storage & retention', 6]])
  // Pipeline yield keeps its PIM Admin minimum inside the tab; the AI model switches keep the Pipeline Operator minimum on the AI tab
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toContain('{rank>=5&&<PipelineYield onError={onError}/>}')
  expect(main).toContain('{rank>=4&&<ModelsServices part="models" onError={err}/>}')
  expect(main).toContain('<ModelsServices part="services" onError={err}/>')
  expect(fs.readFileSync('src/IntegrationQueue.jsx', 'utf8')).not.toContain('<PipelineYield onError={onError}/>')
})

test('LEGACY: every old address of a merged tab lands on its new home', () => {
  expect(go('models-services?tab=limits')).toBe('services/services')
  expect(go('models-services?tab=fetchers')).toBe('services/services')
  expect(go('models-services')).toBe('services/')
  expect(go('scrapers-fetchers')).toBe('services/services')
  expect(go('administration?section=layer2-providers')).toBe('services/services')
  expect(go('platform-health?tab=queues')).toBe('health/queues')
  expect(go('platform-health?tab=integration&view=yield')).toBe('health/queues')
  expect(go('platform-health?tab=integration')).toBe('health/integration')
  expect(hrefFor('services', 'services')).toBe('#models-services')
  for (const f of ['src/CreditBanner.jsx', 'src/FirecrawlWork.jsx', 'src/EnvironmentMigrationWorkspace.jsx', 'src/ModelsServices.jsx']) expect(fs.readFileSync(f, 'utf8')).not.toMatch(/models-services\?tab=(limits|fetchers)/)
})

test('browser: Services & limits holds the page-service switches, toolsets and fetchers; AI & OpenRouter holds the model switches', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#models-services?tab=limits')
  await expect(page).toHaveURL(/#models-services/)
  const tab = page.locator('[data-services-limits]')
  await expect(tab.locator('[data-card="services.fetching"]')).toBeVisible()
  await expect(tab.locator('[data-card="services.ai-models"]')).toHaveCount(0)
  await expect(tab.locator('[data-toolsets]')).toBeVisible()
  await expect(tab.locator('[data-fetchers-merged]')).toBeVisible()
  await expect(page.getByRole('tab', { name: 'Toolsets & limits' })).toHaveCount(0)
  await expect(page.getByRole('tab', { name: 'Fetchers' })).toHaveCount(0)
  await page.goto('/#models-services?tab=ai')
  await expect(page.locator('[data-card="services.ai-models"]')).toBeVisible()
  await expect(page.locator('[data-card="services.fetching"]')).toHaveCount(0)
})

test('browser: Queues & yield shows the work queues and Pipeline yield; Integration queue no longer shows the yield', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#platform-health?tab=queues')
  const t = page.locator('[data-queues-yield]')
  await expect(t).toBeVisible()
  await expect(t.locator('[data-pipeline-yield]')).toBeVisible()
  await page.goto('/#platform-health?tab=integration')
  await expect(page.locator('[data-iq-summary]')).toBeVisible()
  await expect(page.locator('[data-pipeline-yield]')).toHaveCount(0)
})

test('browser: a Curator sees Queues & yield without Pipeline yield (PIM Admin and above, as before)', async ({ page }) => {
  await mockAdmin(page, { rank: 3 })
  await page.goto('/#platform-health?tab=queues')
  await expect(page.locator('[data-queues-yield]')).toBeVisible()
  await expect(page.locator('[data-pipeline-yield]')).toHaveCount(0)
})
