// Guards: F-OPS.03A (Platform Admin P0, 9 Nov 2026 21:28): the Data Delivery summary at the top of Operations is operable from a phone (G4 @responsive, phone project only).
// These tests run on the phone project only (chromium-mobile, Pixel 7, 412 px; `@responsive`). Each first asserts it really is at phone width.
// Mocked admin (tests/uat/support/admin-mock.mjs plus data-delivery-mock.mjs); nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockDataDelivery } from './support/data-delivery-mock.mjs'

const PHONE_MAX = 480
const TAP_MIN = 44
async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

test.describe('data delivery on a phone @responsive', () => {
  test('streams read as cards: each figure carries its label, unknown keeps its reason, the flag is visible, and the page never scrolls sideways', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page); await mockDataDelivery(page)
    const w = await atPhoneWidth(page)
    await page.goto('/#layer-2-discovery?tab=operations')
    const root = page.locator('[data-data-delivery]')
    await expect(root).toBeVisible()
    await expect(root.locator('.dd-head')).toBeHidden()
    const int = root.locator('[data-dd-stream="int"]')
    await int.scrollIntoViewIfNeeded()
    for (const label of ['Coverage', 'Net 24 h', 'Net 7 d', 'Website', 'Zoho', 'Queue', 'Holds and reasons', 'Speed', 'Last and next run', 'Automatic recovery']) await expect(int.locator(`summary [data-label="${label}"]`)).toBeVisible()
    await expect(int.locator('[data-dd-flag="green_no_admission"]')).toBeVisible()
    await expect(root.locator('[data-dd-stream="eng"] [data-dd-cell="speed"] [data-dd-unknown]')).toContainText('Not measured')
    expect(await pageOverflow(page), 'no sideways page scroll').toBeLessThanOrEqual(0)
    const box = await int.locator('summary').boundingBox()
    expect(box.width).toBeLessThanOrEqual(w)
  })

  test('a stream opens to its detail, the drill links and the refresh button are tap-sized, and the tables stack', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page); await mockDataDelivery(page)
    await atPhoneWidth(page)
    await page.goto('/#layer-2-discovery?tab=operations')
    const root = page.locator('[data-data-delivery]')
    await expect(root).toBeVisible()
    const refresh = root.locator('[data-dd-refresh]')
    expect((await refresh.boundingBox()).height).toBeGreaterThanOrEqual(TAP_MIN - 1)
    const pd = root.locator('[data-dd-stream="pdesc"]')
    await pd.locator('summary').click()
    const link = pd.locator('[data-dd-drill-box] [data-dd-drill="missing"]')
    await link.scrollIntoViewIfNeeded()
    expect((await link.boundingBox()).height).toBeGreaterThanOrEqual(TAP_MIN - 1)
    await expect(pd.locator('.dd-body table thead').first()).toBeHidden()
    await expect(pd.locator('.dd-body td[data-label="Job"]').first()).toBeVisible()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(0)
  })
})
