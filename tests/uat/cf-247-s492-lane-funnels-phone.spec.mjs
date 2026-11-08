// Guards: CF-247 OPS/UI mandate (Platform Admin 8 Nov 2026 14:06): the lane funnels on Operations and the Firecrawl allowance card work at phone width (desktop and phone operation tested, G4 @responsive on the phone project only)
// These tests run on the phone project only (chromium-mobile, Pixel 7, 412 px; `@responsive`). Each first asserts it really is at phone width.
// Mocked admin (tests/uat/support/admin-mock.mjs plus lane-funnel-mock.mjs); nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'

const PHONE_MAX = 480
const TAP_MIN = 44 // the lane funnels set 44 px tap targets (lane-funnels.css)
async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

test.describe('lane funnels on a phone @responsive', () => {
  test('lanes read as cards: state, transfer and published are labelled, a lane opens, and the page never scrolls sideways', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page)
    const w = await atPhoneWidth(page)
    await page.goto('/#layer-2-discovery?tab=operations')
    const root = page.locator('[data-lane-funnels]')
    await expect(root).toBeVisible()
    await root.scrollIntoViewIfNeeded()
    const fee = root.locator('[data-lf-lane="fee"]')
    // the column header row is hidden on a phone; every figure carries its own label
    await expect(root.locator('.lf-head')).toBeHidden()
    await expect(fee.locator('summary [data-label="Transfer (24 h)"]')).toBeVisible()
    await expect(fee.locator('summary [data-label="Published (24 h)"]')).toHaveText(/unknown/)
    const sb = await fee.locator('summary').boundingBox()
    expect(sb.x).toBeGreaterThanOrEqual(-1)
    expect(sb.x + sb.width).toBeLessThanOrEqual(w + 1)
    expect(sb.height, 'tap target').toBeGreaterThanOrEqual(TAP_MIN)
    await fee.locator('summary').click()
    await expect(fee.locator('[data-lf-three]')).toBeVisible()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('an open lane: stage rows stack with labels, the job controls are tap targets and the reason is asked before anything is sent', async ({ page }) => {
    await mockAdmin(page, { rank: 6 }); const calls = await mockLaneFunnels(page)
    const w = await atPhoneWidth(page)
    await page.goto('/#layer-2-discovery?tab=operations&lane=fee')
    const fee = page.locator('[data-lf-lane="fee"]')
    await expect(fee.locator('[data-lf-three]')).toBeVisible()
    const unc = fee.locator('[data-lf-stage="uncounted"]')
    await unc.scrollIntoViewIfNeeded()
    await expect(unc.locator('td[data-label="Now"]')).toHaveText(/unknown/)
    const pause = fee.locator('[data-lf-job="fee-reader"]').getByRole('button', { name: 'Pause' })
    await pause.scrollIntoViewIfNeeded()
    const pb = await pause.boundingBox()
    expect(pb.height, 'tap target').toBeGreaterThanOrEqual(TAP_MIN)
    expect(pb.x + pb.width).toBeLessThanOrEqual(w + 1)
    page.once('dialog', (d) => d.dismiss())
    await pause.click()
    expect(calls).toHaveLength(0)
    page.once('dialog', (d) => d.accept('Paused from my phone for the check'))
    await pause.click()
    await expect.poll(() => calls.length).toBe(1)
    expect(calls[0]).toMatchObject({ p_job: 'fee-reader', p_action: 'pause' })
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('Firecrawl allowance and spend: the tiles and tables fit the phone, credits only', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page)
    const w = await atPhoneWidth(page)
    await page.goto('/#models-services?tab=firecrawl')
    const card = page.locator('[data-fc-acceptance]')
    await expect(card).toBeVisible()
    await card.getByRole('button', { name: /Firecrawl allowance and spend/ }).click()
    const rem = card.locator('[data-fc-tile="remaining"]')
    await expect(rem).toContainText('100,228 credits')
    const b = await rem.boundingBox()
    expect(b.x).toBeGreaterThanOrEqual(-1)
    expect(b.x + b.width).toBeLessThanOrEqual(w + 1)
    await expect(card.locator('[data-fc-group="reads"]')).toBeVisible()
    await expect(card).not.toContainText(/\$|AUD|USD/)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })
})
