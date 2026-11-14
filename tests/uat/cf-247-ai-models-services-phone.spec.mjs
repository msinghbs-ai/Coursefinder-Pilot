// Guards: Platform Admin 13 Nov 2026 19:14–19:36 — Models & services redesign (one model list, service cascades, caps, prompts, usage; no blank model)
// Platform Admin written review 13 Nov 2026 22:10: "Default to expanded panes on desktop. Allow collapsing, but keep warnings visible." On a
// phone the cards start closed, as every card does, and still show their warnings.
// Phone acceptance of the page (F-OPS.04 pattern; S121/G4: phone tests are @responsive and first assert phone width). It replaces
// cf-247-f-ops-04-ai-config-phone, whose screen (AI & OpenRouter) is retired. Mocked REST; nothing is saved, verified or switched.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockAi } from './support/ai-overview-fixture.mjs'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
const sideScroll = (page) => page.evaluate(() => [...document.querySelectorAll('main, .m-main, [data-ai-page]')].map(el => el.scrollWidth - el.clientWidth).reduce((a, b) => Math.max(a, b), 0))

async function mount(page) {
  await mockAdmin(page, { rank: 6 })
  const ai = await mockAi(page)
  // cards start closed and remember being opened per browser session, so open the four before the page loads
  await page.addInitScript(() => { try { for (const id of ['openrouter', 'models', 'services', 'usage']) window.sessionStorage.setItem(`cf.card.services.ai.${id}`, '1') } catch { /* storage unavailable */ } })
  await page.goto('/#models-services?tab=ai')
  const t = page.locator('[data-ai-page="ready"]')
  await expect(t).toBeVisible({ timeout: 30_000 })
  // open one service with its editor, and one with a stored prompt, so the widest content is on the screen
  await page.locator('[data-ai-service="course_entry_requirements"] .aim-toggle').click()
  await page.locator('[data-ai-edit="course_entry_requirements"]').click()
  await page.getByLabel('Daily cap in US dollars for Course entry requirements').fill('5') // typed only, never saved: the change and reason bar is drawn
  await page.locator('[data-ai-service="provider_description"] .aim-toggle').click()
  await page.locator('[data-ai-service="ops_diagnosis"] .aim-toggle').click()
  await expect(page.locator('[data-ai-editor="course_entry_requirements"]')).toBeVisible()
  return { t, ai }
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Models & services › AI on a phone @responsive', () => {
  test('on a phone the four cards start closed and still show their warnings', async ({ page }) => {
    await atPhoneWidth(page)
    await mockAdmin(page, { rank: 6 }); await mockAi(page)
    await page.goto('/#models-services?tab=ai')
    await expect(page.locator('[data-ai-page="ready"]')).toBeVisible({ timeout: 30_000 })
    await expect(page.locator('[data-ai-pane]')).toHaveCount(4)
    await expect(page.locator('[data-ai-pane] .cf-card-toggle[aria-expanded="true"]')).toHaveCount(0)
    await expect(page.locator('[data-ai-pane="services"] [data-ai-no-model-chip]')).toHaveText('1 with no model')
    await expect(page.locator('[data-ai-pane="openrouter"] [data-ai-caps-chip]')).toBeVisible()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('the four panes, their stacked rows and an open service sit inside the screen, and nothing scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    expect(await page.locator('[data-ai-pane]').evaluateAll(els => els.map(e => e.getAttribute('data-ai-pane')))).toEqual(['openrouter', 'models', 'services', 'usage'])
    const out = []
    for (const sel of ['[data-ai-pane]', '.aim-tile', '.aim-state', '[data-ai-key-controls]', '.aim-setting', '[data-ai-model] td', '[data-ai-service] td', '.aim-chip', '.aim-detail', '.aim-editor', '.aim-steps li', '.aim-add select', '.aim-save', '.aim-prompt', '.aim-strip', '[data-ai-usage] td', '.aim-meta']) {
      const bs = await boxes(page, `[data-ai-page] ${sel}`)
      expect(bs.length, `${sel} is on the screen, so this check measures something`).toBeGreaterThanOrEqual(1)
      for (const b of bs) if (b.x < -1 || b.right > w + 1) out.push(`${sel} "${b.label}" ${Math.round(b.x)}..${Math.round(b.right)}`)
    }
    expect(out, 'blocks that leave the screen').toEqual([])
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    expect(await sideScroll(page), 'no part of the page scrolls sideways').toBeLessThanOrEqual(1)
    // tables are stacked rows: each cell is a block under its column name, and the column head is not drawn
    expect(await page.locator('[data-ai-services] thead').evaluate(el => getComputedStyle(el).display)).toBe('none')
    const cell = page.locator('[data-ai-service="fee_reader"] td[data-label="State"]')
    expect(await cell.evaluate(el => getComputedStyle(el, '::before').content)).toContain('State')
    await expect(cell).toContainText('Held: cap reached')
    // no blank model on a phone either
    await expect(page.locator('[data-ai-service="entry_matrices"] [data-ai-no-model]').first()).toBeVisible()
    await page.locator('[data-ai-usage-pick="day"]').click(); await page.locator('[data-ai-usage-pick="model"]').click()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    expect(await sideScroll(page)).toBeLessThanOrEqual(1)
  })

  test('every control tapped on the page is at least 24 by 24 pixels, and looking changes nothing', async ({ page }) => {
    await atPhoneWidth(page)
    const { ai } = await mount(page)
    const small = []
    let measured = 0
    for (const sel of ['[data-ai-page] button', '[data-ai-page] select', '[data-ai-page] input:not([type="hidden"])', '[data-ai-page] summary', '[data-ai-page] a']) {
      for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    expect(measured, 'controls measured (Refresh, mode, key, Verify, limits, model switches, row toggles, cascade buttons, caps, period and group picks)').toBeGreaterThanOrEqual(40)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
    expect(ai.calls, 'nothing was saved').toEqual([])
    expect((page.l3calls || []).filter((c) => c.toolsets || c.aiConfig), 'no setting, mode or key was changed').toEqual([])
  })
})
