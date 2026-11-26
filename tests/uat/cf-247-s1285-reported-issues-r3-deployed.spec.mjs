// Guards: Reported data issues R3 (SS-Programme-Control 26 Nov 2026 22:52 AEDT), s1285: on the live production Admin, signed in as the Platform Admin and as a Curator-or-above operator, the Layer 4 Reported data issues view opens (read only), shows its figures, the Admin, Portal and Zoho origin choices with counts and the Reported and Resolved states, at desktop width and at phone width (measured), with no sideways scroll; opening it changes nothing
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function measured(page) {
  return page.evaluate(() => ({ innerWidth: window.innerWidth, clientWidth: document.documentElement.clientWidth, scrollWidth: document.documentElement.scrollWidth }))
}

async function reportedView(page, testInfo, who) {
  const runtime = observeRuntime(page)
  await page.goto('/#layer-4-review')
  const panel = page.locator('[data-ri-panel]')
  await expect(panel, 'the Reported data issues view is on Layer 4').toBeVisible({ timeout: 60_000 })
  await expect(panel).toHaveAttribute('data-ri-open', 'false')
  await panel.locator('[data-ri-toggle]').click()
  await expect(panel.locator('[data-ri-figures]')).toBeVisible({ timeout: 45_000 })
  await expect(panel.locator('[data-ri-error]')).toHaveCount(0)
  for (const o of ['all', 'admin', 'portal', 'zoho']) await expect(panel.locator(`[data-ri-origin-pick="${o}"]`), `origin ${o}`).toHaveCount(1)
  for (const s of ['open', 'resolved', 'all']) await expect(panel.locator(`[data-ri-state-pick="${s}"]`), `state ${s}`).toHaveCount(1)
  const figures = (await panel.locator('[data-ri-figures]').innerText()).replace(/\s+/g, ' ')
  const origins = (await panel.locator('[data-ri-origin-pick]').allInnerTexts()).join(' | ')
  await panel.locator('[data-ri-state-pick="all"]').click()
  await expect(panel.locator('[data-ri-state-pick="all"]')).toHaveAttribute('aria-pressed', 'true')
  await expect(panel.locator('[data-ri-list], [data-ri-empty]').first()).toBeVisible({ timeout: 45_000 })
  const items = await panel.locator('[data-ri-item]').count()
  if (items > 0) {
    const first = panel.locator('[data-ri-item]').first()
    await expect(first.locator('[data-ri-evidence]')).toHaveCount(1)
    await first.locator('[data-ri-open]').click()
    await expect(first.locator('[data-ri-trace]')).toBeVisible()
    await expect(first.locator('[data-l4-fold="journey"]')).toBeVisible({ timeout: 30_000 })
  }
  const vp = await measured(page)
  console.log(`s1285 evidence ${testInfo.project.name} ${who}: viewport ${JSON.stringify(vp)}; figures ${figures.slice(0, 260)}; origins ${origins}; reports listed ${items}`)
  expect(vp.scrollWidth, 'no sideways scroll').toBeLessThanOrEqual(vp.clientWidth + 1)
  if (testInfo.project.name === 'chromium-mobile') expect(vp.innerWidth, 'measured phone width').toBeLessThanOrEqual(430)
  await panel.scrollIntoViewIfNeeded()
  await milestoneScreenshot(page, testInfo, `s1285-reported-${who}`)
  await attachRuntimeEvidence(testInfo, runtime)
  assertNoServerErrors(runtime)
}

test.describe('Reported data issues R3 on live Layer 4 @deployed', () => {
  test.beforeAll(async () => {
    if (!process.env.UAT_BASE_URL) throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    await writeRunEnvironment({ suite: 'cf-247-s1285-reported-issues-r3' })
  })
  test('Platform Admin: the view opens with figures, the three origins and the two states', async ({ page }, testInfo) => {
    await loginAsUatUser(page, 6)
    await reportedView(page, testInfo, 'platform-admin')
  })
  test('Pipeline Operator: the same view, read at rank 4', async ({ page }, testInfo) => {
    await loginAsUatUser(page, 4)
    await reportedView(page, testInfo, 'pipeline-operator')
  })
})

// The phone gate runs only @responsive tests; the emulated viewport is checked before any page loads (about:blank lays out at 980 px)
test.describe('phone screens @responsive', () => {
  test('Platform Admin on a phone: the view opens, wraps and does not scroll sideways @deployed', async ({ page }, testInfo) => {
    expect(page.viewportSize()?.width, 'phone viewport').toBeLessThanOrEqual(430)
    if (!process.env.UAT_BASE_URL) throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    await loginAsUatUser(page, 6)
    await reportedView(page, testInfo, 'platform-admin-phone')
  })
})
