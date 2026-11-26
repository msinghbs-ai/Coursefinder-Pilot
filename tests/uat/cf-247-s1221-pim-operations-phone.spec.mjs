// Guards: F-OPS.17 and F-OPS.21 (SS-Programme-Control 26 Nov 2026 15:46, 412 px): the worker status, verified consumer read-back and freshness-by-country tables added by s1221 stack to labelled rows on a phone, nothing scrolls the page sideways, and every control is tap-sized (G4 @responsive, phone project only).
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
  await page.clock.setFixedTime(new Date('2026-11-26T02:10:00Z'))
  await mockAdmin(page); await mockLaneFunnels(page); await mockPim(page)
  await atPhoneWidth(page)
  await page.goto('/#layer-2-discovery?tab=operations')
  const pim = page.locator('[data-dd-pim]')
  await expect(pim).toBeVisible({ timeout: 20_000 })
  await pim.scrollIntoViewIfNeeded()
  return pim
}
async function expectStacked(table) {
  await expect(table.locator('thead')).toBeHidden()
  const w = await table.evaluate((t) => t.getBoundingClientRect().width)
  expect(w, 'table fits the screen').toBeLessThanOrEqual(PHONE_MAX)
}

test.describe('PIM operations on a phone @responsive', () => {
  test('worker table stacks to labelled rows and the stalled worker is readable at 412 px', async ({ page }) => {
    const pim = await open(page)
    await atPhoneWidth(page)
    const t = pim.locator('[data-pim-workers]')
    await t.scrollIntoViewIfNeeded()
    await expectStacked(t)
    const row = t.locator('[data-pim-worker="enrich-plan-auto"]')
    for (const label of ['Worker', 'State', 'Last success', 'Last start', 'Failed in 24 h', 'Schedule']) await expect(row.locator(`[data-label="${label}"]`)).toBeVisible()
    await expect(row.locator('[data-label="State"]')).toContainText('Stalled')
    await expect(row.locator('[data-label="Last success"]')).toContainText('Never')
    expect(await pageOverflow(page), 'no sideways page scroll').toBeLessThanOrEqual(0)
  })

  test('consumer read-back stacks per stream and country with every figure and its split visible, and an errored stream shows its reason', async ({ page }) => {
    const pim = await open(page)
    const t = pim.locator('[data-pim-consumer]')
    await t.scrollIntoViewIfNeeded()
    await expectStacked(t)
    const au = t.locator('[data-pim-consumer-stream="disc"][data-pim-consumer-country="AU"]')
    for (const label of ['Stream', 'Country', 'Expected', 'Website', 'Zoho', 'Read']) await expect(au.locator(`[data-label="${label}"]`)).toBeVisible()
    await expect(au.locator('[data-label="Website"]')).toContainText('60 pending · 20 missing · 20 not served')
    const sch = t.locator('[data-pim-consumer-stream="sch"]')
    await expect(sch.locator('[data-label="Zoho"] [data-pim-unknown]')).toContainText('Not measured')
    const fee = t.locator('[data-pim-consumer-error]')
    await fee.scrollIntoViewIfNeeded()
    await expect(fee).toContainText('read timed out')
    for (const r of await t.locator('tbody tr').all()) { const b = await r.boundingBox(); expect(b.width, 'row inside the screen').toBeLessThanOrEqual(PHONE_MAX) }
    expect(await pageOverflow(page), 'no sideways page scroll').toBeLessThanOrEqual(0)
  })

  test('freshness by country stacks, its country selector is tap-sized, and the helper-count line wraps inside the screen', async ({ page }) => {
    const pim = await open(page)
    await pim.locator('[data-pim-tab="refresh"]').click()
    const v = pim.locator('[data-pim-panel="refresh"]')
    const sel = v.locator('[data-pim-fresh-country]')
    await sel.scrollIntoViewIfNeeded()
    expect((await sel.boundingBox()).height).toBeGreaterThanOrEqual(TAP_MIN - 1)
    const t = v.locator('[data-pim-fresh-by-country]')
    await expectStacked(t)
    const row = t.locator('[data-pim-fresh-row="AU-description"]')
    for (const label of ['Field', 'Country', 'Values held', 'Due to be verified', 'Fresh']) await expect(row.locator(`[data-label="${label}"]`)).toBeVisible()
    await sel.selectOption('NZ')
    await expect(t.locator('tbody tr')).toHaveCount(1)
    const line = await pim.locator('[data-pim-helper-snapshots]').boundingBox()
    expect(line.width).toBeLessThanOrEqual(PHONE_MAX)
    expect(await pageOverflow(page), 'no sideways page scroll').toBeLessThanOrEqual(0)
  })

  test('the request register reason and the verified-feedback label are readable and the Requests tab is tap-sized', async ({ page }) => {
    const pim = await open(page)
    const tab = pim.locator('[data-pim-tab="requests"]')
    expect((await tab.boundingBox()).height).toBeGreaterThanOrEqual(TAP_MIN - 1)
    await tab.click()
    const v = pim.locator('[data-pim-panel="requests"]')
    await expect(v.locator('[data-pim-requests-reason]')).toBeVisible()
    await expect(v).toContainText('No authoritative source for verified feedback')
    expect(await pageOverflow(page), 'no sideways page scroll').toBeLessThanOrEqual(0)
  })
})
