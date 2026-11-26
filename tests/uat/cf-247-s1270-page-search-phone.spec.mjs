// Guards: Platform Admin request 26 Nov 2026 (SS-Programme-Control 17:47, "Searchable Admin page navigation and settings") and S121/G4 (phone tests are @responsive and first assert phone width): the page search is usable on a phone: no sideways scroll, a 44 px field and 44 px result rows, results that fit the screen, and a jump that lands the highlighted control in view below the sticky bar.
// Phone project (chromium-mobile, 412 px). Mocked admin; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockPim } from './support/pim-mock.mjs'

const PHONE_MAX = 480
const bar = (page) => page.locator('[data-page-search]')
const input = (page) => page.locator('[data-page-search-input]')
async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
}
const overflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
const clear = (page, sel) => page.evaluate((s) => { const el = document.querySelector(s); if (!el) return null; const r = el.getBoundingClientRect(); const bar = document.querySelector('[data-page-search]')?.getBoundingClientRect(); return { top: r.top, bottom: r.bottom, barBottom: bar ? bar.bottom : 0, h: innerHeight } }, sel)

test.describe('@responsive page search on a phone', () => {
  test('@responsive Operations: the field is a 44 px target, results are 44 px rows that fit the screen, and the page does not scroll sideways', async ({ page }) => {
    await atPhoneWidth(page)
    await page.clock.setFixedTime(new Date('2026-11-26T02:10:00Z'))
    await mockAdmin(page); await mockLaneFunnels(page); await mockPim(page)
    await page.goto('/#layer-2-discovery?tab=operations')
    await expect(bar(page)).toBeVisible({ timeout: 20_000 })
    expect(await page.evaluate(() => document.documentElement.clientWidth), 'measured, not assumed').toBeLessThanOrEqual(PHONE_MAX)
    expect((await input(page).boundingBox()).height).toBeGreaterThanOrEqual(44)
    expect(await input(page).evaluate((e) => parseFloat(getComputedStyle(e).fontSize)), 'no iOS zoom on focus').toBeGreaterThanOrEqual(16)
    await input(page).fill('workers')
    const rows = page.locator('[data-page-search-results] li[data-ps-id] button')
    await expect(rows.first()).toBeVisible()
    for (const b of await rows.all()) expect((await b.boundingBox()).height).toBeGreaterThanOrEqual(44)
    const panel = await page.locator('[data-page-search-results]').boundingBox()
    expect(panel.x).toBeGreaterThanOrEqual(0)
    expect(panel.x + panel.width).toBeLessThanOrEqual(PHONE_MAX)
    expect(await overflow(page)).toBeLessThanOrEqual(0)
  })

  test('@responsive Operations: choosing a section opens its view, scrolls it clear of the sticky bar and highlights it', async ({ page }) => {
    await atPhoneWidth(page)
    await page.clock.setFixedTime(new Date('2026-11-26T02:10:00Z'))
    await mockAdmin(page); await mockLaneFunnels(page); await mockPim(page)
    await page.goto('/#layer-2-discovery?tab=operations')
    await expect(bar(page)).toBeVisible({ timeout: 20_000 })
    await input(page).fill('freshness by country')
    await page.locator('[data-ps-id="pim:sec:fresh-country"] button').click()
    const t = page.locator('[data-pim-section="fresh-country"]')
    await expect(t).toHaveClass(/ps-hit/)
    await expect(page.locator('[data-page-search-results]')).toHaveCount(0)     // the list closes so the control is not hidden under it
    await expect.poll(async () => { const c = await clear(page, '[data-pim-section="fresh-country"]'); return c && c.top >= c.barBottom - 2 && c.bottom <= c.h }).toBe(true)
    expect(await overflow(page)).toBeLessThanOrEqual(0)
  })

  test('@responsive Settings: a setting found by its key is opened, scrolled to and focused', async ({ page }) => {
    await atPhoneWidth(page)
    await mockAdmin(page)
    await page.goto('/#environment')
    await expect(page.locator('[data-settings-register]').first()).toBeAttached({ timeout: 20_000 })
    await expect(bar(page)).toBeVisible()
    await input(page).fill('batch.coverage_read')
    await page.locator('[data-ps-id="reg-setting:batch.coverage_read"] button').click()
    const row = page.locator('[data-register-setting="batch.coverage_read"]')
    await expect(row).toHaveClass(/ps-hit/)
    await expect.poll(async () => { const c = await clear(page, '[data-register-setting="batch.coverage_read"]'); return c && c.top >= c.barBottom - 2 && c.bottom <= c.h }).toBe(true)
    await expect(row.locator('input').first()).toBeFocused()
    expect(await overflow(page)).toBeLessThanOrEqual(0)
  })
})
