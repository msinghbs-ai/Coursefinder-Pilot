// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; IQ-00046/47/56 source and read reliability) and S121/G4 (phone tests are @responsive and first assert phone width). Reference data › Reference sources (list, filters, an opened row with its form), mocked REST; nothing is saved, checked or retired. Reads the screen only; no consumer API (G3) change.
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
  await mockAdmin(page, { rank: 6 })
  await page.goto('/#reference-data?tab=links')
  const t = page.locator('[data-reference-sources]')
  await expect(t.locator('[data-site]').first()).toBeVisible()
  return t
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Reference data › Reference sources on a phone @responsive', () => {
  test('the list, its filters and the metrics fit the phone, and the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    const t = await mount(page)
    const out = []
    for (const sel of ['[data-reference-sources]', '[data-reference-sources] .xl-row', '[data-reference-sources] .xl-toolbar']) {
      const bs = await boxes(page, sel)
      expect(bs.length, `${sel} is on the screen, so this check measures something`).toBeGreaterThanOrEqual(1)
      for (const b of bs) if (b.x < -1 || b.right > w + 1) out.push(`${sel} "${b.label}" ${Math.round(b.x)}..${Math.round(b.right)}`)
    }
    expect(out, 'blocks that leave the screen').toEqual([])
    await expect(t.locator('.xl-head')).toBeHidden() // columns stack on a phone; each cell carries its own label
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every control a Platform Admin taps is at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    const t = await mount(page)
    const small = []
    let measured = 0
    for (const sel of ['[data-reference-sources] button', '[data-reference-sources] select', '[data-reference-sources] input[type="checkbox"]', '[data-reference-sources] input[type="search"]']) {
      for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    expect(measured, 'controls measured (row openers, switches, filters, Check all, Add site)').toBeGreaterThanOrEqual(8)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
    await expect(t).toBeVisible()
  })

  test('an opened row and its form sit inside the screen, with Save, Check now and Retire reachable', async ({ page }) => {
    const w = await atPhoneWidth(page)
    const t = await mount(page)
    await t.getByRole('button', { name: 'Open Hotcourses Abroad' }).click()
    const form = t.locator('[data-site-form="r1"]')
    await expect(form).toBeVisible()
    const out = []
    for (const sel of ['[data-site-form="r1"] input:not([type="checkbox"])', '[data-site-form="r1"] select', '[data-site-form="r1"] button', '[data-reference-sources] .xl-body .xl-actions button', '[data-reference-sources] .xl-body a']) {
      for (const b of await boxes(page, sel)) {
        if (b.x < -1 || b.right > w + 1) out.push(`${sel} "${b.label}" ${Math.round(b.x)}..${Math.round(b.right)}`)
        if (sel.includes('button') && Math.min(b.w, b.h) < TAP_MIN) out.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)} under ${TAP_MIN} px`)
      }
    }
    expect(out, 'form controls outside the screen or under the touch floor').toEqual([])
    await expect(t.getByRole('button', { name: 'Check now' })).toBeVisible()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    expect((page.l3calls || []).filter((c) => c.refSave || c.refAction), 'nothing was saved, checked or retired').toEqual([])
  })
})
