// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; IQ-00046/47/56 source and read reliability, Reference data › Key dates) and S121/G4 (phone tests are @responsive and first assert phone width). Reference data › Key dates (KeyDates: list, Add date form, edit drawer) with mocked REST responses; nothing reaches a real backend. Nothing is saved, cancelled or added; no consumer API (G3) change.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

async function mount(page) {
  await mockAdmin(page)
  await page.goto('/#reference-data?tab=dates')
  await expect(page.locator('[data-key-dates] tbody tr')).toHaveCount(2)
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.getClientRects().length > 0).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Reference data › Key dates on a phone @responsive', () => {
  test('the list fits the phone: its table scrolls in its own frame and the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    const frames = await page.locator('[data-key-dates]').evaluate((t) => {
      const p = t.closest('.cf-table-wrap')
      return { frameClient: p.clientWidth, overflowX: getComputedStyle(p).overflowX, tableWidth: t.getBoundingClientRect().width }
    })
    expect(frames.frameClient, 'table frame fits the phone').toBeLessThanOrEqual(w)
    if (frames.tableWidth > frames.frameClient) expect(['auto', 'scroll'], `table (frame ${frames.frameClient}, table ${Math.round(frames.tableWidth)}) scrolls in its own frame`).toContain(frames.overflowX)
    const outside = []
    for (const sel of ['.m-panel', '.cf-table-wrap']) {
      const bs = await boxes(page, sel)
      expect(bs.length, `${sel} is on the screen`).toBeGreaterThanOrEqual(1)
      for (const b of bs) if (b.x < -1 || b.right > w + 1) outside.push(`${sel} ${Math.round(b.x)}..${Math.round(b.right)}`)
    }
    expect(outside, 'blocks that leave the screen').toEqual([])
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every control a Platform Admin taps on the list and the Add date form is at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page)
    await page.getByRole('button', { name: /Add date/ }).first().click()
    await expect(page.locator('[data-add-date]')).toBeVisible()
    const small = []
    let measured = 0
    for (const sel of ['[data-key-dates] button', '[data-key-dates] a', '.rs-check input', '[data-add-date] button', '[data-add-date] input', '[data-add-date] select', '.pg-views button']) {
      const bs = await boxes(page, sel)
      measured += bs.length
      for (const b of bs) if (b.w < TAP_MIN || b.h < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`)
    }
    expect(measured, 'controls were measured').toBeGreaterThanOrEqual(10)
    expect(small, 'controls under 24 px').toEqual([])
  })

  test('the Add date form and the edit drawer fit the phone; the drawer closes and nothing is saved', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    const saves = []
    page.on('request', (r) => { if (/admin_key_date_(save|action)/.test(r.url())) saves.push(r.url()) })
    await page.getByRole('button', { name: /Add date/ }).first().click()
    for (const b of await boxes(page, '[data-add-date] .rs-add-grid > *, [data-add-date] .l3c-actions > *')) {
      expect(b.x, `form field "${b.label}"`).toBeGreaterThanOrEqual(-1)
      expect(b.right, `form field "${b.label}"`).toBeLessThanOrEqual(w + 1)
    }
    await page.locator('[data-add-date]').getByRole('button', { name: 'Cancel' }).click()
    await page.locator('[data-key-dates]').getByRole('button', { name: 'Edit QILT GOS 2026 release' }).click()
    const dr = page.locator('[data-date-drawer]')
    await expect(dr).toBeVisible()
    const d = await boxes(page, '[data-date-drawer]')
    expect(d[0].x, 'drawer starts on the screen').toBeGreaterThanOrEqual(-1)
    expect(d[0].right, 'drawer ends on the screen').toBeLessThanOrEqual(w + 1)
    for (const b of await boxes(page, '[data-date-drawer] button, [data-date-drawer] select, [data-date-drawer] a')) {
      expect(b.w >= TAP_MIN && b.h >= TAP_MIN, `drawer control "${b.label}" is ${Math.round(b.w)}x${Math.round(b.h)}`).toBe(true)
    }
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    await dr.getByRole('button', { name: 'Close' }).click()
    await expect(dr).toHaveCount(0)
    expect(saves, 'nothing was saved, cancelled or added').toEqual([])
  })
})
