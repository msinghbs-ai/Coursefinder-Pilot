// Guards: CF-247 S121 (Platform Admin 26 Oct 2026 10:49): the three screens the Platform Admin operates from a phone work at phone width — Course catalogue list, Course detail blade, Layer 4 Review
// These tests run on the phone project only (chromium-mobile, Pixel 7, 412 px; `@responsive`). Each one first asserts that it really is at
// phone width, so a configuration change cannot quietly turn them into desktop checks; S120 also fails if the phone filter or these three
// tests go. Mocked admin (tests/uat/support/admin-mock.mjs); nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

const COURSE = '0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5'
const PHONE_MAX = 480
// WCAG 2.2 AA target size (2.5.8): at least 24 by 24 CSS pixels. Measured 26 Oct 2026: Layer 4 choice buttons 25 px high, Filters 31 px,
// detail close 32+ px; raising Layer 4 choices to 44 px is proposed in the governance record, not done here.
const TAP_MIN = 24

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
// the page itself never scrolls sideways; a wide table scrolls inside its own frame
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
async function inView(locator, width) {
  await locator.scrollIntoViewIfNeeded()
  const b = await locator.boundingBox()
  expect(b, 'element has a box').toBeTruthy()
  expect(b.x).toBeGreaterThanOrEqual(-1)
  expect(b.x + b.width).toBeLessThanOrEqual(width + 1)
  return b
}

test.describe('phone screens @responsive', () => {
  test('Course catalogue list: search, filters and the first course reachable; no sideways page scroll; the table scrolls in its own frame', async ({ page }) => {
    await mockAdmin(page)
    const w = await atPhoneWidth(page)
    await page.goto('/#courses')
    await expect(page.getByRole('heading', { name: 'Course catalogue' })).toBeVisible()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    await inView(page.getByPlaceholder(/Search Course, Provider/), w)
    const filters = page.getByRole('button', { name: 'Filters' })
    const fb = await inView(filters, w)
    expect(fb.height, 'tap target').toBeGreaterThanOrEqual(TAP_MIN)
    const firstRow = page.locator('.m-table-wrap table.m-table tbody tr').first()
    await expect(firstRow).toBeVisible()
    await firstRow.scrollIntoViewIfNeeded()
    const wrap = page.locator('.m-table-wrap').first()
    const frame = await wrap.evaluate((el) => ({ client: el.clientWidth, scroll: el.scrollWidth, overflowX: getComputedStyle(el).overflowX }))
    expect(frame.client).toBeLessThanOrEqual(w)
    if (frame.scroll > frame.client) expect(['auto', 'scroll']).toContain(frame.overflowX)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('Course detail blade: fills the phone width, close is a tap target, values and the official page reachable, closing returns to the list', async ({ page }) => {
    await mockAdmin(page)
    const w = await atPhoneWidth(page)
    await page.goto(`/#courses?id=${COURSE}`)
    const close = page.getByRole('button', { name: /Close Course detail/i })
    await expect(close).toBeVisible()
    const cb = await inView(close, w)
    expect(Math.min(cb.width, cb.height), 'tap target').toBeGreaterThanOrEqual(TAP_MIN)
    const blade = page.locator('.m-drawer-course').first()
    const bb = await blade.boundingBox()
    expect(bb.width).toBeGreaterThanOrEqual(w * 0.9)
    expect(bb.x + bb.width).toBeLessThanOrEqual(w + 1)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    await expect(page.getByText('Course detail', { exact: true })).toBeVisible()
    const values = page.locator('[data-editor="course"]')
    await inView(values, w)
    await inView(values.getByText('Official course page', { exact: true }), w)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    await close.click()
    await expect(page.getByRole('heading', { name: 'Course catalogue' })).toBeVisible()
  })

  test('Layer 4 Review: a university opens, a choice shows what happens next, the reason and confirm fit the screen and decide', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    const w = await atPhoneWidth(page)
    const kinds = { pages_not_found: { label: 'Course pages not found', order: 4, choices: [
      { key: 'release', label: 'Release and try again', rank: 4, returns: 'The hold is released; the site is mapped again and onboarding starts again' }] } }
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON(); calls.push(b)
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 4, total: 1, universities: 1, late: 0, by_kind: { pages_not_found: { n: 1 } } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p1', name: 'Holmes Institute', country: 'AU', courses: 25, n: 1, oldest: '2026-10-19T20:00:00Z', late: false, by_kind: { pages_not_found: 1 } }] } })
      if (b.p_action === 'items') return route.fulfill({ json: { total: 1, items: [
        { kind: 'pages_not_found', ref: '9', provider_id: 'p1', why: 'Re-find wave 1: the site map returned no course pages.', created_at: '2026-10-19T20:00:00Z', late: false, detail: { flag_id: 9 } }] } })
      if (b.p_action === 'decide') return route.fulfill({ json: { ok: true, returns: 'The hold is released; the site is mapped again and onboarding starts again' } })
      return route.fulfill({ json: {} })
    })
    await page.goto('/#layer-4-review')
    await expect(page.locator('[data-l4-inbox]')).toBeVisible()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    const item = page.locator('[data-l4-item="pages_not_found"]')
    await expect(item).toContainText('Re-find wave 1')
    const choice = item.locator('[data-l4-choice="release"]')
    const chb = await inView(choice, w)
    expect(chb.height, 'tap target').toBeGreaterThanOrEqual(TAP_MIN)
    await choice.click()
    await expect(item).toContainText('What happens next')
    const reason = item.getByLabel('Reason')
    await inView(reason, w)
    await reason.fill('Website checked from my phone')
    const confirm = item.locator('[data-l4-confirm]')
    await inView(confirm, w)
    await confirm.click()
    await expect(page.getByRole('status')).toContainText('Done.')
    expect(calls.find((c) => c.p_action === 'decide').p_args).toMatchObject({ kind: 'pages_not_found', ref: '9', choice: 'release', reason: 'Website checked from my phone' })
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })
})
