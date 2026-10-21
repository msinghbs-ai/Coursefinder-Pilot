// v2.15.128 Layer 2 split into tabs: Overview, Fetch an area, History, Source profiles. Duplicate panels removed.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

test('tabs and removed duplicates', () => {
  expect(PAGES.layer2.tabs.map(t => t.label)).toEqual(['Operations', 'Flags', 'Universities', 'Enrichment plan', 'Build adapter', 'Enrich fields', 'Scholarships', 'Adapter builder'] /* v2.15.306 */) // v2.15.300: Layer 2/3, Operations first, the builder opens from a row // v2.15.287: Build adapter (Decision 267) // v2.15.200 Decision 254: Overview, Fetch an area, History and Source profiles retired; v2.15.211 Adapter builder
  // v2.15.214: the retired Layer 2 screens (layer2-operations-entry.jsx, EnrichmentOperations.jsx) are deleted, not just unrouted.
  for (const f of ['src/layer2-operations-entry.jsx', 'src/EnrichmentOperations.jsx']) expect(fs.existsSync(f)).toBe(false)
})

test.describe('mocked browser', () => {
  test('Operations is the first tab, the builder is not in the tab bar, and the retired tabs open Universities', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery')
    await expect(page.locator('[data-layer23-operations]')).toBeVisible()
    await expect(page.getByRole('tab', { name: 'Operations' })).toHaveAttribute('aria-selected', 'true')
    await expect(page.getByRole('tab', { name: 'Adapter builder' })).toHaveCount(0)
    for (const gone of ['Overview', 'Fetch an area', 'History', 'Source profiles']) await expect(page.getByRole('tab', { name: gone })).toHaveCount(0)
    await expect(page.getByRole('tab', { name: 'Scholarships' })).toBeVisible()
    for (const old of ['start', 'history', 'profiles', 'adapters', 'onboarding']) {
      await page.goto(`/#layer-2-discovery?tab=${old}`)
      await expect(page.locator('[data-adapters-workspace]')).toBeVisible()
    }
    await page.goto('/#coverage?tab=universities')
    await expect(page.locator('[data-adapters-workspace]')).toBeVisible()
  })
})
