// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; IQ-00053 worker output families) and S121/G4 (phone tests are @responsive and first assert phone width). Layer 2/3 › Universities (AdaptersWorkspace) with the shared mocked admin REST; nothing reaches a real backend.
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
  await page.goto('/#layer-2-discovery?tab=universities')
  const w = page.locator('[data-adapters-workspace]')
  await expect(w.locator('[data-adapters-tally]')).toBeVisible()
  await expect(w.locator('[data-adapter-row]').first()).toBeVisible()
  return w
}

// Boxes of the visible controls inside a scope. Inline links in a sentence are exempt (WCAG 2.5.8 inline exception).
async function controls(scope, selector) {
  return scope.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null && !el.closest('p, li, small')).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Layer 2/3 › Universities (Adapters) on a phone @responsive', () => {
  test('the list, filters and rows fit the phone and the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    const ws = await mount(page)
    for (const sel of ['.m-panel', '.adp-filters', '.adp-row']) {
      const boxes = await controls(ws, sel)
      expect(boxes.length, `${sel} is on the screen, so this check measures something`).toBeGreaterThanOrEqual(1)
      for (const b of boxes) {
        expect(b.x, `${sel} "${b.label}" starts inside the screen`).toBeGreaterThanOrEqual(-1)
        expect(b.right, `${sel} "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
      }
    }
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every filter, row control and tick box a Platform Admin taps is at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    const ws = await mount(page)
    const small = []
    let measured = 0
    for (const sel of ['select', 'input[type="search"]', 'input[type="checkbox"]', 'button', 'a[href]']) {
      for (const b of await controls(ws, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    expect(measured, 'controls measured').toBeGreaterThanOrEqual(8)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
  })

  test('opening a row shows its detail inside the screen, and the detail controls are tappable', async ({ page }) => {
    const w = await atPhoneWidth(page)
    const ws = await mount(page)
    const row = ws.locator('[data-adapter-row]').first()
    await row.locator('.adp-row-head .adp-row-name').click()
    await expect(row.locator('[data-adapter-detail]')).toBeVisible()
    const small = []
    for (const sel of ['button', 'select', 'input[type="checkbox"]']) {
      for (const b of await controls(row.locator('[data-adapter-detail]'), sel)) {
        expect(b.right, `detail ${sel} "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
        if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`)
      }
    }
    expect(small, 'detail controls below the WCAG 2.2 AA target size').toEqual([])
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('ticking a row opens the bulk bar inside the screen; filtering still works', async ({ page }) => {
    const w = await atPhoneWidth(page)
    const ws = await mount(page)
    await ws.locator('[data-adapter-row] input[type="checkbox"]').first().check()
    const bar = ws.locator('[data-adapters-bulk]')
    await expect(bar).toBeVisible()
    for (const b of await controls(bar, 'button')) expect(b.right, `bulk "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
    await ws.getByRole('combobox', { name: 'Provider kind' }).selectOption('any')
    await expect(ws.locator('[data-adapters-tally]')).toContainText('4 shown of 4')
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })
})
