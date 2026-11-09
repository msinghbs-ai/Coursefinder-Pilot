// Guards: F-OPS.04 (Platform Admin, phone acceptance of the F-OPS.03A Data Delivery panel, 9 Nov 2026): at 390 px nothing in the panel makes Operations scroll sideways and every link in it is at least 24 px high (G4 @responsive, phone project only).
// These tests run on the phone project only (chromium-mobile, Pixel 7; `@responsive`). The viewport is set to 390 px and each test first asserts it really is at phone width.
// Mocked admin (tests/uat/support/admin-mock.mjs plus data-delivery-mock.mjs); nothing reaches a real backend.
// Why this spec sits beside cf-247-f-ops-03a-data-delivery-phone: that one measures only the document (which never scrolls; main.m-main does). This one measures the panel against main's visible width.
// It scopes to the Data Delivery panel on purpose: other Operations panels (for example Governed actions) have their own phone work.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockDataDelivery } from './support/data-delivery-mock.mjs'

const PHONE_MAX = 480
// WCAG 2.2 AA target size (2.5.8): at least 24 by 24 CSS pixels.
const LINK_MIN = 24

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
async function openOperationsWithEveryStreamOpen(page) {
  await page.setViewportSize({ width: 390, height: 844 })
  await mockAdmin(page); await mockLaneFunnels(page); await mockDataDelivery(page)
  await atPhoneWidth(page)
  await page.goto('/#layer-2-discovery?tab=operations')
  const root = page.locator('[data-data-delivery]')
  await expect(root).toBeVisible()
  const streams = root.locator('[data-dd-stream]')
  await expect(streams.first()).toBeVisible()
  for (const s of await streams.all()) await s.locator('summary').click()
  return root
}

test.describe('data delivery on a phone, acceptance @responsive', () => {
  test('with every stream open, nothing in the Data Delivery panel reaches past the screen, so it adds no sideways scroll to main, and the country and job tables are stacked', async ({ page }) => {
    const root = await openOperationsWithEveryStreamOpen(page)
    await expect(root.locator('table.dd-countries').first()).toBeVisible()
    const m = await page.evaluate(() => {
      const main = document.querySelector('main.m-main')
      const panel = document.querySelector('[data-data-delivery]')
      const limit = main.getBoundingClientRect().left + main.clientWidth
      const clipped = (e) => { for (let x = e.parentElement; x && x !== panel; x = x.parentElement) if (getComputedStyle(x).overflowX !== 'visible') return true; return false }
      const past = [...panel.querySelectorAll('*')].filter((e) => e.getBoundingClientRect().width > 0 && !clipped(e) && e.getBoundingClientRect().right > limit + 1)
        .map((e) => `${e.tagName}.${String(e.className).slice(0, 30)} right=${Math.round(e.getBoundingClientRect().right)}`)
      return { limit, panelRight: panel.getBoundingClientRect().right, panelOver: panel.scrollWidth - panel.clientWidth, past,
        tables: [...panel.querySelectorAll('table')].map((t) => ({ cls: t.className, width: t.getBoundingClientRect().width, display: getComputedStyle(t).display })) }
    })
    expect(m.panelRight, 'the panel ends inside the screen').toBeLessThanOrEqual(m.limit + 1)
    expect(m.panelOver, 'the panel has no sideways scroll of its own').toBeLessThanOrEqual(0)
    expect(m.past, 'no element of the panel (outside a scroll frame) ends past the screen').toEqual([])
    expect(m.tables.length).toBeGreaterThan(0)
    for (const t of m.tables) {
      expect(t.display, `${t.cls} is stacked`).toBe('block')
      expect(t.width, `${t.cls} is narrower than the screen`).toBeLessThanOrEqual(m.limit)
    }
  })

  test('every link in the panel, including the pending and missing counts in a stream summary, is at least 24 px high', async ({ page }) => {
    const root = await openOperationsWithEveryStreamOpen(page)
    const counts = root.locator('[data-dd-stream] summary a[data-dd-drill]')
    expect(await counts.count(), 'the pending and missing count links are present').toBeGreaterThanOrEqual(4)
    const heights = await root.locator('a').evaluateAll((els) => els.map((a) => ({ text: a.textContent.trim().slice(0, 30), h: a.getBoundingClientRect().height })))
    expect(heights.length).toBeGreaterThan(4)
    for (const l of heights) expect(l.h, `link "${l.text}" is tap-sized`).toBeGreaterThanOrEqual(LINK_MIN)
  })
})
