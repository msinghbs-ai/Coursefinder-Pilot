// Guards: Platform Admin directive 10 Nov 2026 (CF-247 F-CDESC.06) and S121 (26 Oct 2026 10:49): Fill description / Recheck description work at phone width on the Course catalogue list and the Course detail blade:
// 24 px tap targets, the page never scrolls sideways, the preview and reason fit the screen. Runs on the phone project only (`@responsive`); each test first asserts phone width.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockOnDemand } from './support/cdesc-on-demand-mock.mjs'

const COURSE = '0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5'
const PHONE_MAX = 480, TAP_MIN = 24
const atPhoneWidth = (page) => { const w = page.viewportSize()?.width || 9999; expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX); return w }
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
async function tap(locator, what) { await locator.scrollIntoViewIfNeeded(); const b = await locator.boundingBox(); expect(b, what).toBeTruthy(); expect(Math.min(b.width, b.height), `${what} tap target`).toBeGreaterThanOrEqual(TAP_MIN); return b }

test.describe('Fill / Recheck description on a phone @responsive', () => {
  test('Course catalogue: tick, Fill and Recheck, preview, reason and Queue are reachable and fit; the page does not scroll sideways', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    atPhoneWidth(page)
    const w = 390
    await mockOnDemand(page)
    await page.setViewportSize({ width: 390, height: 844 }) // the narrowest phone the Platform Admin named (390 px); the project default is wider
    await page.goto('/#courses')
    const box = page.locator('.cdod-pick').first()
    await tap(box, 'row tick')
    await box.locator('input').check()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    const fill = page.getByRole('button', { name: 'Fill description' })
    const fb = await tap(fill, 'Fill description')
    expect(fb.x + fb.width).toBeLessThanOrEqual(w + 1)
    await tap(page.getByRole('button', { name: 'Recheck description' }), 'Recheck description')
    await fill.click()
    const panel = page.locator('[data-cdod-panel="fill"]')
    await expect(panel).toContainText('will be queued')
    const pb = await panel.boundingBox()
    expect(pb.x).toBeGreaterThanOrEqual(-1); expect(pb.x + pb.width).toBeLessThanOrEqual(w + 1)
    const reason = panel.getByLabel('Reason'); await tap(reason, 'reason')
    await reason.fill('From my phone')
    await tap(panel.getByRole('button', { name: /^Queue/ }), 'Queue')
    await tap(panel.getByRole('button', { name: 'Close Fill description' }), 'Close preview')
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('Course detail blade: the state block, the buttons and the feed read-back fit the phone; no sideways page scroll', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    const w = atPhoneWidth(page)
    await mockOnDemand(page)
    await page.goto(`/#courses?id=${COURSE}`)
    const block = page.locator('[data-cdod-block]')
    await block.scrollIntoViewIfNeeded()
    await expect(block).toBeVisible()
    for (const n of ['Fill description', 'Check the feeds']) { const b = await tap(block.getByRole('button', { name: n }), n); expect(b.x + b.width).toBeLessThanOrEqual(w + 1) }
    await block.getByRole('button', { name: 'Check the feeds' }).click()
    await expect(block.locator('[data-cdod-feeds]')).toBeVisible()
    const bb = await block.boundingBox()
    expect(bb.x).toBeGreaterThanOrEqual(-1); expect(bb.x + bb.width).toBeLessThanOrEqual(w + 1)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('Course detail blade: Withdraw machine description, its explanation, reason and buttons fit the phone and are tap-sized; no sideways page scroll', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    const w = atPhoneWidth(page)
    const calls = await mockOnDemand(page, { forceState: 'machine_admitted' })
    await page.goto(`/#courses?id=${COURSE}`)
    const block = page.locator('[data-cdod-block]')
    await block.scrollIntoViewIfNeeded()
    const open = await tap(block.getByRole('button', { name: 'Withdraw machine description' }), 'Withdraw machine description')
    expect(open.x + open.width).toBeLessThanOrEqual(w + 1)
    await block.getByRole('button', { name: 'Withdraw machine description' }).click()
    const panel = block.locator('[data-cdod-withdraw-panel]')
    const pb = await panel.boundingBox()
    expect(pb.x).toBeGreaterThanOrEqual(-1); expect(pb.x + pb.width).toBeLessThanOrEqual(w + 1)
    await expect(panel.locator('[data-cdod-withdraw-what]')).toBeVisible()
    const reason = panel.getByLabel('Reason for withdrawing'); await tap(reason, 'reason')
    await reason.fill('From my phone')
    await tap(panel.getByRole('button', { name: 'Cancel' }), 'Cancel')
    await tap(panel.getByRole('button', { name: 'Close Withdraw machine description' }), 'Close')
    const go = panel.getByRole('button', { name: 'Withdraw description' })
    await tap(go, 'Withdraw description')
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    await go.click()
    await expect(panel.locator('[data-cdod-withdraw-done]')).toBeVisible()
    expect(calls.filter((c) => c.name === 'withdraw')).toHaveLength(1)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })
})
