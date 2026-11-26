// Guards: SS-Programme-Control 27 Nov 2026 00:09 "Complete existing Data Delivery integration" (backend s1176b, Pilot #1699): Data Delivery shows pim.operations.consumer_fields inside the Verified consumer read-back section (no new screen): canonical population, sampled coverage, verified delivery, international applicability, failure reasons and the last verification time, counted on the sampled courses only, never extrapolated, and a figure the backend does not record is never shown as 0. Desktop project; mocked admin plus tests/uat/support/pim-mock.mjs; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockPim, PIM, OPERATIONS } from './support/pim-mock.mjs'

async function open(page, operations = OPERATIONS) {
  await page.clock.setFixedTime(new Date('2026-11-26T13:30:00Z'))
  await mockAdmin(page); await mockLaneFunnels(page); await mockPim(page, { pim: { ...PIM, operations } })
  await page.goto('/#layer-2-discovery?tab=operations')
  const cs = page.locator('[data-cs], [data-cs-none]')
  await expect(cs).toBeVisible({ timeout: 20_000 })
  return page.locator('[data-dd-pim]')
}

test('academic entry: population, sampled coverage, verified delivery, international applicability, failures and last verification, each on the sampled courses', async ({ page }) => {
  const pim = await open(page)
  const a = pim.locator('[data-cs-stream="aer"]')
  await expect(a).toContainText('Academic entry')
  await expect(a.locator('[data-cs-population]')).toContainText('10,192')
  await expect(a.locator('[data-cs-coverage]')).toContainText('7 of 10,192 courses (0.07%)')
  await expect(a.locator('[data-cs-coverage]')).toContainText('A sample, not the population')
  await expect(a.locator('[data-cs-delivery]')).toContainText('6 of the 7 sampled courses')
  await expect(a.locator('[data-cs-intl]')).toContainText('6 of the 7 sampled courses')
  await expect(a.locator('[data-cs-last]')).toContainText('26 Nov 2026')
  await expect(a.locator('[data-cs-failures]')).toContainText('Zoho not matching: 1')
  await expect(a.locator('[data-cs-failures]')).toContainText('Website serves domestic only row: 1')
  await expect(a.locator('[data-cs-failures]')).toContainText('2 sampled courses with a failure')
  await expect(a.locator('[data-cs-latest]')).toContainText('course:cricos:00020g:103424h')
  await expect(a.locator('[data-cs-read="website_v3_international"]')).toContainText('7')
})

test('descriptions: no international check is recorded, so it says Not checked, not 0; no failures reads as measured none', async ({ page }) => {
  const pim = await open(page)
  const d = pim.locator('[data-cs-stream="cdesc"]')
  await expect(d).toContainText('Course descriptions')
  await expect(d.locator('[data-cs-intl] [data-cs-unknown]')).toContainText('Not checked')
  await expect(d.locator('[data-cs-intl]')).not.toContainText(/\b0 of\b/)
  await expect(d.locator('[data-cs-failures]')).toContainText('None in the sample')
  await expect(d.locator('[data-cs-reads]')).not.toContainText('No domestic-only row')
  await expect(d.locator('[data-cs-delivery]')).toContainText('7 of the 7 sampled courses')
})

test('nothing is extrapolated: no verified figure is shown as a share of the population, and the sample is kept apart from it', async ({ page }) => {
  const pim = await open(page)
  const text = await pim.locator('[data-cs]').innerText()
  expect(text).not.toMatch(/\b(estimated|projected|about [\d,]+ (courses|of))\b/i)
  expect((text.match(/%/g) || []).length, 'only the backend coverage is a percentage, once per stream').toBe(2)
})

test('a snapshot with no consumer_fields says Not available; a stream with no recorded figures says Not recorded, never 0', async ({ page }) => {
  const { consumer_fields, ...without } = OPERATIONS
  const none = await open(page, without)
  await expect(none.locator('[data-cs-none]')).toContainText('Not available')
})

test('a stream whose figures are all null reads Not recorded or Never checked, not 0', async ({ page }) => {
  const empty = { ...OPERATIONS, consumer_fields: { ...OPERATIONS.consumer_fields, streams: { aer: { population: null, sampled_in_window: null, delivery_verified: null, international_verified: null, last_checked: null, failures_by_reason: null, latest_failures: null, checked: null } } } }
  const pim = await open(page, empty)
  const a = pim.locator('[data-cs-stream="aer"]')
  for (const sel of ['[data-cs-population]', '[data-cs-coverage]', '[data-cs-delivery]', '[data-cs-failures]']) await expect(a.locator(sel).locator('[data-cs-unknown]'), sel).toBeVisible()
  await expect(a.locator('[data-cs-last] [data-cs-unknown]')).toContainText('Never checked')
  await expect(a).not.toContainText(/\b0 of\b/)
})
