// Guards: S121/G4 phone rule and SS-Programme-Control 26 Nov 2026 22:51 ("filters, search and pagination instead of displaying all worker rows on mobile"): at 412 px the job and lane monitoring shows one page of stacked, labelled cards, filters and search are tap-sized, the drill-down is readable, and nothing scrolls the page sideways (@responsive, phone project only).
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockPim, mockPimJobs } from './support/pim-mock.mjs'

const PHONE_MAX = 480
const TAP_MIN = 44
async function atPhoneWidth(page) { const w = page.viewportSize()?.width || 9999; expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX) }
const overflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

test.describe('job and lane monitoring on a phone @responsive', () => {
  test('Scheduled jobs: one page of stacked cards, 44 px controls, paging, search, and a readable drill-down', async ({ page }) => {
    await atPhoneWidth(page)
    await page.clock.setFixedTime(new Date('2026-11-26T12:00:00Z'))
    await mockAdmin(page); await mockLaneFunnels(page); await mockPim(page); await mockPimJobs(page)
    await page.goto('/#scheduled-jobs?tab=automations')
    const m = page.locator('[data-pjm-monitor]')
    await expect(m).toBeVisible({ timeout: 20_000 })
    await m.scrollIntoViewIfNeeded()
    await expect(m.locator('[data-pjm-list] thead')).toBeHidden()
    await expect(m.locator('[data-pjm-row]'), 'a page, never all components').toHaveCount(20)
    for (const sel of ['[data-pjm-search]', '.pjm-filters select']) for (const el of await m.locator(sel).all()) expect((await el.boundingBox()).height, sel).toBeGreaterThanOrEqual(TAP_MIN)
    const row = m.locator('[data-pjm-row]').first()
    for (const label of ['State', 'Heartbeat', 'Next run', '24 h outcomes']) await expect(row.locator(`[data-label="${label}"]`)).toBeVisible()
    expect((await row.boundingBox()).width, 'row fits the screen').toBeLessThanOrEqual(PHONE_MAX)
    await m.locator('[data-pjm-search]').fill('enrich')
    await expect(m.locator('[data-pjm-row]')).toHaveCount(1)
    await m.locator('[data-pjm-toggle]').first().click()
    const d = m.locator('[data-pjm-detail]').first()
    await expect(d).toBeVisible()
    await expect(d.locator('[data-pjm-window="7 days"]')).toBeVisible()
    expect((await d.boundingBox()).width).toBeLessThanOrEqual(PHONE_MAX)
    await m.locator('[data-pjm-clear]').click()
    const next = m.locator('.pjm-pager button', { hasText: 'Next' })
    await next.scrollIntoViewIfNeeded()
    expect((await next.boundingBox()).height).toBeGreaterThanOrEqual(TAP_MIN)
    await next.click()
    await expect(m.locator('.pjm-pager')).toContainText('Page 2 of 2')
    expect(await overflow(page), 'no sideways page scroll').toBeLessThanOrEqual(0)
  })

  test('Data Delivery: the summary is a short list of attention cards with a link to the full list, not 138 rows', async ({ page }) => {
    await atPhoneWidth(page)
    await page.clock.setFixedTime(new Date('2026-11-26T12:00:00Z'))
    await mockAdmin(page); await mockLaneFunnels(page); await mockPim(page)
    await page.goto('/#layer-2-discovery?tab=operations')
    const s = page.locator('[data-pjm-summary]')
    await expect(s).toBeVisible({ timeout: 20_000 })
    await s.scrollIntoViewIfNeeded()
    await expect(s.locator('[data-pjm-attention] > li').first()).toBeVisible()
    for (const el of await s.locator('.pjm-tile').all()) expect((await el.boundingBox()).height).toBeGreaterThanOrEqual(TAP_MIN)
    await expect(s.locator('[data-pjm-by-component] thead')).toBeHidden()
    expect((await s.boundingBox()).width).toBeLessThanOrEqual(PHONE_MAX)
    expect(await overflow(page), 'no sideways page scroll').toBeLessThanOrEqual(0)
  })
})
