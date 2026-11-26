// Guards: S121/G4 phone rule and SS-Programme-Control 27 Nov 2026 00:09 ("Complete existing Data Delivery integration"): at 412 px the sampled delivery read-back stacks to one readable column per stream, its tables become labelled rows, and nothing scrolls the page sideways (@responsive, phone project only).
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockPim } from './support/pim-mock.mjs'

const PHONE_MAX = 480
test.describe('sampled delivery read-back on a phone @responsive', () => {
  test('streams stack, every figure is labelled and the page does not scroll sideways', async ({ page }) => {
    expect(page.viewportSize()?.width || 9999, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
    await page.clock.setFixedTime(new Date('2026-11-26T13:30:00Z'))
    await mockAdmin(page); await mockLaneFunnels(page); await mockPim(page)
    await page.goto('/#layer-2-discovery?tab=operations')
    const cs = page.locator('[data-cs]')
    await expect(cs).toBeVisible({ timeout: 20_000 })
    await cs.scrollIntoViewIfNeeded()
    const a = cs.locator('[data-cs-stream="aer"]')
    for (const sel of ['[data-cs-population]', '[data-cs-coverage]', '[data-cs-delivery]', '[data-cs-intl]', '[data-cs-last]', '[data-cs-failures]']) await expect(a.locator(sel), sel).toBeVisible()
    expect((await a.boundingBox()).width, 'stream card fits the screen').toBeLessThanOrEqual(PHONE_MAX)
    const reads = a.locator('[data-cs-reads]')
    await reads.scrollIntoViewIfNeeded()
    await expect(reads.locator('thead')).toBeHidden()
    await expect(reads.locator('[data-cs-read="zoho"] [data-label="Matched"]')).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth), 'no sideways page scroll').toBeLessThanOrEqual(0)
  })
})
