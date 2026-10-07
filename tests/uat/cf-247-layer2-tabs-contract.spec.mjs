// v2.15.128 Layer 2 split into tabs: Overview, Fetch an area, History, Source profiles. Duplicate panels removed.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

test('tabs and removed duplicates', () => {
  expect(PAGES.layer2.tabs.map(t => t.label)).toEqual(['Adapters', 'Adapter builder', 'Scholarships']) // v2.15.200 Decision 254: Overview, Fetch an area, History and Source profiles retired; v2.15.211 Adapter builder
  // v2.15.214: the retired Layer 2 screens (layer2-operations-entry.jsx, EnrichmentOperations.jsx) are deleted, not just unrouted.
  for (const f of ['src/layer2-operations-entry.jsx', 'src/EnrichmentOperations.jsx']) expect(fs.existsSync(f)).toBe(false)
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
