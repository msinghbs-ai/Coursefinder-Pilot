// v2.15.128 Layer 2 split into tabs: Overview, Fetch an area, History, Source profiles. Duplicate panels removed.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES } from '../../src/nav-map.js'
import { mockAdmin } from './support/admin-mock.mjs'

test('tabs and removed duplicates', () => {
  expect(PAGES.layer2.tabs.map(t => t.label)).toEqual(['Overview', 'Fetch an area', 'History', 'Source profiles'])
  const w = fs.readFileSync('src/layer2-operations-entry.jsx', 'utf8')
  for (const gone of ['Effective acquisition policy', 'Results / Data Quality', '<h2>Evidence</h2>', 'l2o-kpis']) expect(w).not.toContain(gone)
  const e = fs.readFileSync('src/EnrichmentOperations.jsx', 'utf8')
  expect(e).not.toContain('Metrics are observational')
  expect(e).not.toContain("'CF-CHG-20260915-245'")
})

test.describe('mocked browser', () => {
  test('each tab shows its own part', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery')
    const ops = page.locator('[data-cf245-enrichment-operations="true"]')
    await expect(ops.getByRole('heading', { name: 'Coverage and what is left' })).toBeVisible()
    await expect(ops.locator('.eops-hourly thead th')).toHaveCount(9)
    await expect(ops).toContainText('Passed to Layer 3 (AI)')
    await page.getByRole('tab', { name: 'Fetch an area' }).click()
    // Decision 222: Fetch an area shows where the area stands in the course-page sweep
    await expect(page.locator('[data-fetch-area]')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Start production enrichment' })).toHaveCount(0)
    await page.getByRole('tab', { name: 'History' }).click()
    // Decision 220: History shows each country's daily progress; the retired pipeline's run and fetch lists are gone.
    await expect(page.getByRole('heading', { name: 'Daily progress' })).toBeVisible()
    await expect(page.locator('[data-l2-daily] tbody tr').first()).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Recent page fetches' })).toHaveCount(0)
    await expect(page.locator('[data-l2-latest-terminal]')).toHaveCount(0)
    await expect(page.getByRole('heading', { name: 'Recent execution trace' })).toBeVisible()
  })
})
