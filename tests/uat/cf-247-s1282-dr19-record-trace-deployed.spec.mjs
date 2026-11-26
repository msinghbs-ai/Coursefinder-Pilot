// Guards: DR-19 increments 2 to 4 (SS-Programme-Control 26 Nov 2026 22:52 AEDT; autonomous production UAT, Platform Admin 26 Nov 2026 17:39), s1282: on the live production Admin, signed in as the Platform Admin, Data Delivery's PIM drill opens a provider's records for a field by diagnosis class, a record opens its trace with the seven facts, and the course record drawer's Field processing status and diagnosis fold opens, at desktop and phone width (measured) with no sideways scroll; read only
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

const OPERATIONS = '/#layer-2-discovery?tab=operations'
const FACTS = ['returned', 'populated', 'verified', 'international', 'admission', 'delivery', 'gain']

async function measured(page) {
  return page.evaluate(() => ({ innerWidth: window.innerWidth, clientWidth: document.documentElement.clientWidth, scrollWidth: document.documentElement.scrollWidth, devicePixelRatio: window.devicePixelRatio }))
}

async function drillAndDrawer(page, testInfo, who) {
  const runtime = observeRuntime(page)
  await page.goto(OPERATIONS)
  const drill = page.locator('[data-dd-pim] [data-rt-drill]').first()
  await expect(drill, 'the PIM records drill is shown').toBeVisible({ timeout: 90_000 })
  await drill.locator('[data-rt-drill-toggle]').click()
  await expect(drill).toHaveAttribute('data-rt-open', 'true')
  // the field list comes from the field register, read when the drill opens: wait for the option before choosing it
  await expect(drill.locator('[data-rt-field-select] option[value="description"]')).toHaveCount(1, { timeout: 30_000 })
  await drill.locator('[data-rt-field-select]').selectOption('description')
  await drill.locator('[data-rt-provider-search]').fill('Lincoln University')
  const hit = drill.locator('.rt-hits button').first()
  await expect(hit).toBeVisible({ timeout: 30_000 })
  await hit.click()
  const classes = drill.locator('[data-rt-class-pick]')
  await expect(classes.first(), 'diagnosis classes for the provider').toBeVisible({ timeout: 60_000 })
  await classes.first().click()
  const rec = drill.locator('[data-rt-record]').first()
  await expect(rec).toBeVisible({ timeout: 60_000 })
  await rec.locator('summary').click()
  const field = rec.locator('[data-rt-field="description"]')
  // the trace or its error, whichever comes first; an error is printed before the test fails on it
  await expect(rec.locator('[data-rt-field="description"], [data-rt-error]').first(), 'the record trace for the field').toBeVisible({ timeout: 60_000 })
  if (await rec.locator('[data-rt-error]').count()) console.log(`s1282 evidence ${testInfo.project.name} ${who} record trace error: ${(await rec.locator('[data-rt-error]').innerText()).slice(0, 300)}`)
  await expect(rec.locator('[data-rt-error]'), 'the record trace reads without an error').toHaveCount(0)
  await expect(field).toBeVisible()
  for (const k of FACTS) await expect(field.locator(`[data-rt-fact="${k}"]`), `fact ${k}`).toHaveCount(1)
  await expect(drill.locator('[data-rt-error]')).toHaveCount(0)
  let vp = await measured(page)
  console.log(`s1282 evidence ${testInfo.project.name} ${who} drill: viewport ${JSON.stringify(vp)}; classes ${(await classes.allInnerTexts()).join(' | ').slice(0, 200)}; record class ${await rec.getAttribute('data-rt-record')} ${(await field.getAttribute('data-rt-class'))}`)
  expect(vp.scrollWidth, 'no sideways scroll (drill)').toBeLessThanOrEqual(vp.clientWidth + 1)
  await field.scrollIntoViewIfNeeded()
  await milestoneScreenshot(page, testInfo, `s1282-drill-${who}`)
  // the same course in the course record drawer
  await rec.locator('[data-rt-open-course]').click()
  const fold = page.locator('[data-rt-fold="course"]').first()
  await expect(fold, 'the course drawer field status fold').toBeVisible({ timeout: 90_000 })
  await fold.locator('summary').click()
  await expect(fold.locator('[data-rt-counts]')).toBeVisible({ timeout: 60_000 })
  await expect(fold.locator('[data-rt-error]')).toHaveCount(0)
  await fold.locator('.rt-show button').nth(1).click()  // All fields
  const fields = fold.locator('[data-rt-field]')
  expect(await fields.count(), 'every registered field is listed').toBeGreaterThan(5)
  for (const k of FACTS) await expect(fields.first().locator(`[data-rt-fact="${k}"]`), `drawer fact ${k}`).toHaveCount(1)
  vp = await measured(page)
  console.log(`s1282 evidence ${testInfo.project.name} ${who} drawer: viewport ${JSON.stringify(vp)}; ${(await fold.locator('[data-rt-counts]').innerText()).replace(/\s+/g, ' ').slice(0, 200)}; fields ${await fields.count()}`)
  expect(vp.scrollWidth, 'no sideways scroll (drawer)').toBeLessThanOrEqual(vp.clientWidth + 1)
  if (testInfo.project.name === 'chromium-mobile') expect(vp.innerWidth, 'measured phone width').toBeLessThanOrEqual(430)
  await fold.scrollIntoViewIfNeeded()
  await milestoneScreenshot(page, testInfo, `s1282-drawer-${who}`)
  await attachRuntimeEvidence(testInfo, runtime)
  assertNoServerErrors(runtime)
}

test.describe('DR-19 record trace on the live Admin @deployed', () => {
  test.beforeAll(async () => {
    if (!process.env.UAT_BASE_URL) throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    await writeRunEnvironment({ suite: 'cf-247-s1282-dr19-record-trace' })
  })
  test('Platform Admin: Data Delivery drill to a record trace, then the course record drawer', async ({ page }, testInfo) => {
    test.setTimeout(240_000)
    await loginAsUatUser(page, 6)
    await drillAndDrawer(page, testInfo, 'platform-admin')
  })
})

// The phone gate runs only @responsive tests; the emulated viewport is checked before any page loads (about:blank lays out at 980 px)
test.describe('phone screens @responsive', () => {
  test('Platform Admin on a phone: the drill and the drawer fold open without sideways scroll @deployed', async ({ page }, testInfo) => {
    test.setTimeout(240_000)
    expect(page.viewportSize()?.width, 'phone viewport').toBeLessThanOrEqual(430)
    if (!process.env.UAT_BASE_URL) throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    await loginAsUatUser(page, 6)
    await drillAndDrawer(page, testInfo, 'platform-admin-phone')
  })
})
