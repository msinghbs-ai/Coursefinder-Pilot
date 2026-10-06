// v2.15.128 Layer 2 split into tabs: Overview, Fetch an area, History, Source profiles. Duplicate panels removed.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

test('tabs and removed duplicates', () => {
  expect(PAGES.layer2.tabs.map(t => t.label)).toEqual(['Adapters', 'Scholarships']) // v2.15.200 Decision 254: Overview, Fetch an area, History and Source profiles retired
  const w = fs.readFileSync('src/layer2-operations-entry.jsx', 'utf8')
  for (const gone of ['Effective acquisition policy', 'Results / Data Quality', '<h2>Evidence</h2>', 'l2o-kpis']) expect(w).not.toContain(gone)
  const e = fs.readFileSync('src/EnrichmentOperations.jsx', 'utf8')
  expect(e).not.toContain('Metrics are observational')
  expect(e).not.toContain("'CF-CHG-20260915-245'")
})

test.describe('mocked browser', () => {
  test('Adapters is the first tab and the retired tabs open it', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery')
    await expect(page.locator('[data-adapters-workspace]')).toBeVisible()
    await expect(page.getByRole('tab', { name: 'Adapters' })).toHaveAttribute('aria-selected', 'true')
    for (const gone of ['Overview', 'Fetch an area', 'History', 'Source profiles']) await expect(page.getByRole('tab', { name: gone })).toHaveCount(0)
    await expect(page.getByRole('tab', { name: 'Scholarships' })).toBeVisible()
    for (const old of ['start', 'history', 'profiles', 'operations']) {
      await page.goto(`/#layer-2-discovery?tab=${old}`)
      await expect(page.locator('[data-adapters-workspace]')).toBeVisible()
    }
    await page.goto('/#coverage?tab=universities')
    await expect(page.locator('[data-adapters-workspace]')).toBeVisible()
  })
})
