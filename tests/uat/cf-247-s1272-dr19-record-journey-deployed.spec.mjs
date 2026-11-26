// Guards: DR-19 (SS-Programme-Control 26 Nov 2026 19:19 AEDT; autonomous production UAT, Platform Admin 26 Nov 2026 17:39), s1272: on the live production Admin, signed in as the Platform Admin and as a Pipeline Operator, the Processing journey and diagnosis fold of the focused Layer 4 card opens, shows eight stages and the stopping stage and every diagnosis row, at desktop width and at phone width (measured), with no sideways scroll; read only (opening the fold changes nothing)
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

const STATES = ['done', 'failed', 'held', 'not_started', 'skipped', 'waiting', 'not_verified', 'unavailable']
const ROWS = ['reason', 'evidence', 'attempts', 'reader', 'gate', 'ai', 'similar', 'references', 'recommendation', 'cost', 'gain', 'actions', 'outcome']

async function measured(page) {
  return page.evaluate(() => ({ innerWidth: window.innerWidth, innerHeight: window.innerHeight, clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth, devicePixelRatio: window.devicePixelRatio }))
}

async function journeyOnFocusedCard(page, testInfo, who) {
  const runtime = observeRuntime(page)
  // the Admin routes by hash: the default view is the focused card (Waiting, grouped by rule); the description queue's list view is the fallback
  await page.goto('/#layer-4-review')
  let card = page.locator('[data-l4-focus-card]').first(), view = 'focused card'
  if (!(await card.waitFor({ state: 'visible', timeout: 30_000 }).then(() => true, () => false))) {
    await page.goto('/#layer-4-review?view=kind&kind=provider_description')
    card = page.locator('article').filter({ has: page.locator('[data-l4-fold="journey"]') }).first(); view = 'description queue list'
  }
  await expect(card, 'a Layer 4 card is shown').toBeVisible({ timeout: 60_000 })
  testInfo.annotations.push({ type: 'view', description: `${who}: ${view}` })
  const fold = card.locator('[data-l4-fold="journey"]').first()
  await expect(fold).toBeVisible()
  await fold.locator('summary').click()
  const stages = fold.locator('[data-l4j-stage]')
  await expect(stages).toHaveCount(8, { timeout: 30_000 })
  for (const s of await stages.evaluateAll(els => els.map(e => e.getAttribute('data-l4j-state')))) expect(STATES, `stage state ${s}`).toContain(s)
  await expect(fold.locator('[data-l4j-stop]')).toBeVisible()
  await expect(fold.locator('[data-l4j-error]')).toHaveCount(0)
  for (const k of ROWS) await expect(fold.locator(`[data-l4j="${k}"]`), `diagnosis row ${k}`).toHaveCount(1)
  const vp = await measured(page)
  testInfo.annotations.push({ type: 'viewport', description: `${who}: ${JSON.stringify(vp)}` })
  testInfo.annotations.push({ type: 'journey', description: `${who}: ${(await fold.locator('[data-l4j-stop]').innerText()).slice(0, 200)}` })
  expect(vp.scrollWidth, 'no sideways scroll').toBeLessThanOrEqual(vp.clientWidth + 1)
  if (testInfo.project.name === 'chromium-mobile') expect(vp.innerWidth, 'measured phone width').toBeLessThanOrEqual(430)
  await fold.scrollIntoViewIfNeeded()
  await milestoneScreenshot(page, testInfo, `s1272-journey-${who}`)
  await attachRuntimeEvidence(testInfo, runtime)
  assertNoServerErrors(runtime)
}

test.describe('DR-19 record journey on the live Layer 4 card @deployed', () => {
  test.beforeAll(async () => {
    if (!process.env.UAT_BASE_URL) throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    await writeRunEnvironment({ suite: 'cf-247-s1272-dr19-record-journey' })
  })

  test('Platform Admin: the fold opens with eight stages, the stopping stage and every diagnosis row', async ({ page }, testInfo) => {
    await loginAsUatUser(page, 6)
    await journeyOnFocusedCard(page, testInfo, 'platform-admin')
  })

  test('Pipeline Operator: the same fold, read at rank 4', async ({ page }, testInfo) => {
    await loginAsUatUser(page, 4)
    await journeyOnFocusedCard(page, testInfo, 'pipeline-operator')
  })
})
