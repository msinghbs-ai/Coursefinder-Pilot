// Guards: F-OPS.17 (phone width works) and F-OPS.21 (Platform Admin P0 26 Nov 2026 13:07): the Autonomous PIM block in Data Delivery is operable from a phone (G4 @responsive, phone project only).
// These tests run on the phone project only (chromium-mobile, Pixel 7, 412 px; `@responsive`). Each first asserts it really is at phone width. Mocked admin plus pim-mock; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockPim } from './support/pim-mock.mjs'

const PHONE_MAX = 480
const TAP_MIN = 44
async function atPhoneWidth(page) { const w = page.viewportSize()?.width || 9999; expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX); return w }
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
async function open(page) {
  await mockAdmin(page); await mockLaneFunnels(page); await mockPim(page)
  await atPhoneWidth(page)
  await page.goto('/#layer-2-discovery?tab=operations')
  const pim = page.locator('[data-dd-pim]')
  await expect(pim).toBeVisible({ timeout: 20_000 })
  await pim.scrollIntoViewIfNeeded()
  return pim
}

test.describe('Autonomous PIM on a phone @responsive', () => {
  test('the matrix stacks to labelled rows, nothing scrolls the page sideways, and the funnel fits', async ({ page }) => {
    const pim = await open(page)
    const w = await atPhoneWidth(page)
    await expect(pim.locator('[data-pim-matrix] thead')).toBeHidden()
    const row = pim.locator('[data-pim-domain-row="Entry"]')
    await row.scrollIntoViewIfNeeded()
    for (const label of ['Domain', 'All countries', 'Australia', 'New Zealand', 'Canada']) await expect(row.locator(`[data-label="${label}"]`)).toBeVisible()
    expect(await pageOverflow(page), 'no sideways page scroll').toBeLessThanOrEqual(0)
    const f = await pim.locator('[data-pim-funnel]').boundingBox()
    expect(f.width).toBeLessThanOrEqual(w)
  })

  test('tabs, selectors and cells are tap-sized and a cell opens its country and domain', async ({ page }) => {
    const pim = await open(page)
    for (const sel of ['[data-pim-tab="matrix"]', '[data-pim-tab="requests"]', '[data-pim-tab="refresh"]', '[data-pim-country]', '[data-pim-measure]']) {
      const b = await pim.locator(sel).boundingBox()
      expect(b.height, `${sel} height`).toBeGreaterThanOrEqual(TAP_MIN - 1)
    }
    const cell = pim.locator('[data-pim-domain-row="Entry"] [data-pim-cell="NZ"]')
    await cell.scrollIntoViewIfNeeded()
    expect((await cell.boundingBox()).height).toBeGreaterThanOrEqual(TAP_MIN - 1)
    await cell.click()
    await expect(pim.locator('[data-pim-fields-title]')).toContainText('Entry in New Zealand')
    expect(await pageOverflow(page)).toBeLessThanOrEqual(0)
  })

  test('the field table stacks with each figure labelled and Not measured keeps its reason', async ({ page }) => {
    const pim = await open(page)
    await pim.locator('[data-pim-country]').selectOption('AU')
    await pim.locator('[data-pim-domain="Location"]').click()
    const campus = pim.locator('[data-pim-fields] [data-pim-field="campus"]')
    await campus.scrollIntoViewIfNeeded()
    for (const label of ['Applicable', 'Completed', 'Backlog', 'Held', 'Failed', 'Gain', 'Per hour', 'Clearance']) await expect(campus.locator(`[data-label="${label}"]`)).toBeVisible()
    await expect(campus.locator('[data-label="Clearance"]')).toContainText('Nothing gained in the window')
    expect(await pageOverflow(page)).toBeLessThanOrEqual(0)
  })

  test('requests and refresh views read on a phone, and links are tap-sized', async ({ page }) => {
    const pim = await open(page)
    await pim.locator('[data-pim-tab="requests"]').click()
    await expect(pim.locator('[data-pim-requests-unavailable]')).toBeVisible()
    await pim.locator('[data-pim-tab="refresh"]').click()
    await expect(pim.locator('[data-pim-refresh]')).toBeVisible()
    await pim.locator('[data-pim-tab="matrix"]').click()
    const l4 = pim.locator('[data-pim-link="layer4"]')
    await l4.scrollIntoViewIfNeeded()
    expect((await l4.boundingBox()).height).toBeGreaterThanOrEqual(TAP_MIN - 1)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(0)
  })
})
