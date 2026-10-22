// CF-247 v2.15.301 (Platform Admin, 20 Oct 2026 19:23 "Ask me nav menu wise and its tab wise questions ... keep, move or retire";
// answers 19:2x; 19:31 "Go"): the menu decisions. Moves keep their role gates; every old address opens the new place.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, SECTIONS, resolveTarget, canOpen, allowedTabs } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')
const to = (t, q = {}) => { const r = resolveTarget(t, new URLSearchParams(q)); return [r.page, r.tab, Object.fromEntries(r.params)] }

test('menu: 19 pages (was 23); Sources, API usage, Data model and Storage & retention left the menu', () => {
  const inMenu = SECTIONS.flatMap(s => s.pages)
  expect(inMenu.length).toBe(19)
  for (const gone of ['sources', 'apiUsage', 'dataModel', 'retention']) { expect(PAGES[gone]).toBeUndefined(); expect(inMenu).not.toContain(gone) }
  expect(SECTIONS.find(s => s.label === 'Data pipeline').pages).toEqual(['coverage', 'layer1', 'layer2', 'layer4'])
  expect(PAGES.scholarships.tabs.map(t => t.key)).toEqual(['list', 'coverage'])
  expect(PAGES.coverage.tabs.map(t => t.key)).toEqual(['courses', 'attributes', 'progress'])
  expect(PAGES.layer2.tabs.map(t => t.key)).toEqual(['operations', 'flags', 'universities', 'plan', 'build', 'builder', 'enrich', 'scholarships'] /* v2.15.306: Enrichment plan */)
  expect(PAGES.health.tabs.map(t => [t.key, t.min])).toEqual([['checks', 3], ['queues', 3], ['storage', 6]])
  expect(PAGES.environment.tabs.map(t => [t.key, t.min])).toEqual([['settings', 6], ['api', 4], ['backup', 6]]) // v2.15.310: Backup & restore
  expect(PAGES.rankings.tabs.map(t => t.key)).toEqual(['overview', 'compare', 'qilt', 'prisms', 'datasets'])
  expect(PAGES.reference.tabs).toBeUndefined()
  expect(PAGES.layer1.tabs).toBeUndefined()
})

test('old addresses open the new places', () => {
  expect(to('scholarships', { tab: 'extraction' })).toEqual(['services', 'ai', {}])
  expect(to('reference-data', { tab: 'imports', system: 'qs' })).toEqual(['rankings', 'datasets', { system: 'qs' }])
  expect(to('reference-data', { tab: 'dates' })).toEqual(['reference', '', { type: 'dates' }])
  expect(to('reference-data', { tab: 'links' })).toEqual(['reference', '', { type: 'links' }])
  expect(to('important-dates')).toEqual(['reference', '', { type: 'dates' }])
  expect(to('coverage', { tab: 'flags' })).toEqual(['layer2', 'flags', {}])
  expect(to('coverage', { tab: 'progress', view: 'running' })).toEqual(['jobs', 'tasks', {}])
  expect(to('coverage', { tab: 'progress', view: 'levers' })).toEqual(['environment', 'settings', {}])
  expect(to('coverage', { tab: 'progress', view: 'journeys' })).toEqual(['coverage', 'progress', { view: 'journeys' }])
  expect(to('layer-1-register', { tab: 'scholarships' })).toEqual(['layer2', 'scholarships', {}])
  expect(to('layer-1-register', { tab: 'operations' })).toEqual(['layer1', '', {}])
  expect(to('pipeline-sources')).toEqual(['layer1', '', { layer: 'all' }])
  expect(to('sources')).toEqual(['layer1', '', { layer: 'all' }])
  expect(to('platform-health', { tab: 'readiness' })).toEqual(['migration', '', {}])
  expect(to('api-usage')).toEqual(['environment', 'api', {}])
  expect(to('storage-retention')).toEqual(['health', 'storage', {}])
  expect(to('data-model')).toEqual(['coverage', 'attributes', {}])
})

test('role gates are kept: Operators see API usage only on Settings; Curators see Reference data, Flags and Scholarship extraction', () => {
  expect(allowedTabs(PAGES.environment, 4).map(t => t.key)).toEqual(['api'])
  expect(canOpen('environment', 3)).toBe(false)
  expect(allowedTabs(PAGES.health, 5).map(t => t.key)).toEqual(['checks', 'queues'])
  expect(allowedTabs(PAGES.services, 3).map(t => t.key)).toEqual(['ai'])
  expect(canOpen('reference', 3)).toBe(true)
  expect(canOpen('layer1', 3)).toBe(false)
  expect(allowedTabs(PAGES.layer2, 3).map(t => t.key)).toContain('flags')
  const main = read('src/mature-main.jsx')
  expect(main).toContain('{rank>=4&&<AiConfig onError={err}/>}')
  expect(main).toContain('{rank>=4&&<section data-ranking-imports>')
  expect(main).not.toContain("case'dataModel'")
  expect(main).not.toContain('function Attributes(')
})

test('the register migration retires the moved screens and changes nothing else', () => {
  const m = read('supabase/migrations/20261020110000_cf247_menu_decisions.sql')
  expect(m).toMatch(/^-- Replaces: /m)
  expect(m).toMatch(/^-- Retires: /m)
  for (const s of ['Scholarships › Extraction', 'Coverage & completeness › Flags', 'Layer 1 Register › Scholarships', 'Platform health › Capacity', 'Data model', 'Storage & retention', 'API usage']) expect(m).toContain(`('${s}', `)
  expect(m).not.toMatch(/^\s*(drop|truncate|delete)\b/im)
  expect(m).not.toMatch(/create (or replace )?function/i)
})

test.describe('mocked browser', () => {
  test('Reference data: one list with a type filter', async ({ page }) => {
    await mockAdmin(page)
    page.on('dialog', d => d.accept())
    await page.goto('/#reference-data')
    await expect(page.locator('[data-reference-list="all"]')).toBeVisible()
    await expect(page.locator('[data-key-dates]')).toBeVisible()
    await expect(page.locator('[data-reference-sources]')).toBeVisible()
    await page.locator('[data-reference-type="links"]').click()
    await expect(page).toHaveURL(/#reference-data\?type=links$/)
    await expect(page.locator('[data-key-dates]')).toHaveCount(0)
    await expect(page.locator('[data-reference-sources]')).toBeVisible()
    await page.goto('/#reference-data?tab=dates')
    await expect(page.locator('[data-reference-list="dates"]')).toBeVisible()
    await expect(page.locator('[data-reference-sources]')).toHaveCount(0)
  })

  test('Layer 1: one Sources page, registers first; All layers lists every source', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-1-register')
    await expect(page.getByRole('tab')).toHaveCount(0)
    await expect(page.locator('[data-sources-page="registers"] [data-l1-sources]')).toBeVisible()
    await page.locator('[data-sources-layer="all"]').click()
    await expect(page).toHaveURL(/#layer-1-register\?layer=all$/)
    await expect(page.locator('[data-sources-page="all"]')).toBeVisible()
    await expect(page.locator('[data-l1-sources]')).toHaveCount(0)
  })

  test('Layer 2/3 › Scholarships shows finding (was Layer 1) and reading', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery?tab=scholarships')
    const m = page.locator('[data-scholarships-merged]')
    await expect(m.locator('[data-scholarship-layer="1"]')).toBeVisible()
    await expect(m.locator('[data-scholarship-layer="2"]')).toBeVisible()
    await expect(m.locator('[data-sl-countries]')).toBeVisible()
  })

  test('a Curator sees Scholarship extraction on Models & services › AI, without the AI configuration', async ({ page }) => {
    await mockAdmin(page, { rank: 3 })
    await page.goto('/#scholarships?tab=extraction')
    await expect(page).toHaveURL(/#models-services\?tab=ai$/)
    await expect(page.locator('[data-scholarship-extraction-moved]')).toBeVisible()
    await expect(page.locator('[data-ai-config]')).toHaveCount(0)
  })

  test('Storage & retention is a Platform health tab; Capacity is on the Go-live checklist', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#platform-health')
    await expect(page.getByRole('tab')).toHaveText(['Health checks', 'Work queues', 'Storage & retention'])
    await page.goto('/#platform-health?tab=readiness')
    await expect(page).toHaveURL(/#environment-migration$/)
    await expect(page.locator('[data-golive-capacity]')).toBeVisible()
  })
})
