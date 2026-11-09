// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; IQ-00053 worker output families, AI use and spend visibility) and S121/G4 (phone tests are @responsive and first assert phone width). Models & services › AI & OpenRouter (balance, guards per AI use, central pages model, profiles), mocked REST; nothing is saved, verified or switched. Reads the screen only; no consumer API (G3) change.
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
  await page.goto('/#models-services?tab=ai')
  const t = page.locator('[data-ai-config]')
  await expect(t).toBeVisible()
  for (const id of ['services.ai.openrouter', 'services.ai.uses', 'services.ai.profiles']) {
    const card = t.locator(`[data-card="${id}"]`)
    if (await card.locator('.cf-card-toggle[aria-expanded="false"]').count()) await card.locator('.cf-card-toggle').click()
  }
  await expect(t.locator('[data-ai-openrouter]')).toBeVisible()
  return t
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Models & services › AI & OpenRouter on a phone @responsive', () => {
  test('the account, guards table and profiles sit inside the screen, and the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    const t = await mount(page)
    const out = []
    for (const sel of ['[data-ai-openrouter]', '[data-ai-openrouter] > div', '[data-ai-key]', '[data-ai-central]', '[data-ai-adapter]', '.cf-table-wrap']) {
      const bs = await boxes(page, `[data-ai-config] ${sel}`)
      expect(bs.length, `${sel} is on the screen, so this check measures something`).toBeGreaterThanOrEqual(1)
      for (const b of bs) if (b.x < -1 || b.right > w + 1) out.push(`${sel} "${b.label}" ${Math.round(b.x)}..${Math.round(b.right)}`)
    }
    expect(out, 'blocks that leave the screen').toEqual([])
    await expect(t.locator('[data-ai-use="central_ai"]')).toBeAttached()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every control a Platform Admin taps is at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    const t = await mount(page)
    const small = []
    let measured = 0
    for (const sel of ['[data-ai-config] button', '[data-ai-config] select', '[data-ai-config] input:not([type="hidden"])', '[data-ai-config] summary']) {
      for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    expect(measured, 'controls measured (mode, floor, key, Verify, guards, central model, Refresh, Show)').toBeGreaterThanOrEqual(8)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
    await expect(t).toBeVisible()
    expect((page.l3calls || []).filter((c) => c.toolsets || c.aiConfig), 'nothing was saved, verified or switched').toEqual([])
  })
})
