// Guards: F-OPS.17, F-OPS.18, F-OPS.21 (SS-Programme-Control 26 Nov 2026 15:46, "Complete remaining PIM frontend integration"; backend s1175): the Autonomous PIM block shows the deployed `pim.operations` fields as delivered (worker status and stalled processing, verified consumer read-back per stream and country, freshness by country) and keeps the request register and verified feedback labelled Not available with the backend's reason. Streams are never added together; a missing figure is Not measured, never 0.
// Desktop project (chromium-desktop, 1440 x 900). Mocked admin plus tests/uat/support/pim-mock.mjs (operations shaped like the live s1175 read); nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockPim, PIM, PIM_NO_OPERATIONS, OPERATIONS, OPERATIONS_HEALTHY } from './support/pim-mock.mjs'

async function open(page, opts) {
  await page.clock.setFixedTime(new Date('2026-11-26T02:10:00Z')) // the mock's times are fixed, so ages and staleness are too
  await mockAdmin(page); await mockLaneFunnels(page)
  const m = await mockPim(page, opts)
  await page.goto('/#layer-2-discovery?tab=operations')
  const pim = page.locator('[data-dd-pim]')
  await expect(pim).toBeVisible({ timeout: 20_000 })
  await expect(pim.locator('[data-pim-matrix]')).toBeVisible()
  return { pim, ...m }
}

test.describe('worker status and stalled processing', () => {
  test('the Processing block keeps the stalled count the backend judges by each job\'s own schedule; the 138-row worker table is gone (s1283)', async ({ page }) => {
    const { pim } = await open(page)
    const p = pim.locator('[data-pim-processing]')
    await expect(p.locator('[data-pim-stalled="1"]')).toHaveText('1')
    await expect(p.locator('[data-pim-stalled="1"]').locator('xpath=..')).toContainText('of 3 scheduled jobs')
    await expect(pim.locator('[data-pim-workers]')).toHaveCount(0)
    await expect(pim.locator('[data-pim-worker]')).toHaveCount(0)
  })

  test('with every worker on time the stalled count is a measured 0, not Not measured', async ({ page }) => {
    const { pim } = await open(page, { pim: { ...PIM, operations: OPERATIONS_HEALTHY } })
    await expect(pim.locator('[data-pim-processing] [data-pim-stalled="0"]')).toHaveText('0')
  })

  test('without operations (the read before s1175) stalled processing and the jobs summary say Not available and show no count', async ({ page }) => {
    const { pim } = await open(page, { pim: PIM_NO_OPERATIONS })
    const p = pim.locator('[data-pim-processing]')
    await expect(p.locator('[data-pim-stalled]')).toHaveCount(0)
    await expect(p.locator('div').filter({ hasText: /^Stalled workers/ }).locator('[data-pim-unknown]')).toContainText('Not measured')
    await expect(pim.locator('[data-pim-workers]')).toHaveCount(0)
    await expect(pim.locator('[data-pjm-summary="none"]')).toContainText('Not available')
    await expect(pim.locator('[data-pim-consumer]')).toHaveCount(0)
    await expect(pim.locator('[data-pim-panel="matrix"]')).toContainText('The PIM snapshot carries no consumer read-back yet')
  })
})

test.describe('verified consumer read-back', () => {
  test('per stream and country: matched out of expected with pending, missing and not served kept apart, and streams are not added', async ({ page }) => {
    const { pim } = await open(page)
    const t = pim.locator('[data-pim-consumer]')
    await expect(pim.locator('[data-pim-consumer-meaning]')).toContainText('never added together')
    const au = t.locator('[data-pim-consumer-stream="disc"][data-pim-consumer-country="AU"]')
    await expect(t.locator('[data-pim-consumer-stream="int"] [data-label="Stream"]')).toContainText('Intake dates and deadlines') // the title comes from the streams in the read, not a typed list
    await expect(au.locator('[data-label="Stream"]')).toContainText('Disc') // a stream the read does not title falls back to its id, never a blank
    await expect(au.locator('[data-label="Country"]')).toHaveText('Australia')
    await expect(au.locator('[data-label="Expected"]')).toHaveText('1,200')
    await expect(au.locator('[data-label="Website"] [data-pim-matched="1100"]')).toBeVisible()
    await expect(au.locator('[data-label="Website"]')).toContainText('91.7% of expected')
    await expect(au.locator('[data-label="Website"]')).toContainText('60 pending · 20 missing · 20 not served')
    await expect(au.locator('[data-label="Zoho"] [data-pim-matched="1090"]')).toBeVisible()
    // two streams in one country are separate rows; there is no total row across streams
    await expect(t.locator('[data-pim-consumer-country="AU"]')).toHaveCount(3)
    await expect(t.locator('tbody tr')).toHaveCount(5 /* disc AU, NZ; int AU; sch AU; fee error */)
    await expect(t).not.toContainText('Total')
  })

  test('a stream the read does not measure for Zoho shows Not measured for Zoho and still shows the website figures', async ({ page }) => {
    const { pim } = await open(page)
    const sch = pim.locator('[data-pim-consumer-stream="sch"][data-pim-consumer-country="AU"]')
    await expect(sch.locator('[data-label="Zoho"] [data-pim-unknown]')).toContainText('Not measured')
    await expect(sch.locator('[data-label="Zoho"]')).toContainText('Zoho read-back is not counted for this stream')
    await expect(sch.locator('[data-label="Zoho"] [data-pim-matched]')).toHaveCount(0)
    await expect(sch.locator('[data-label="Website"] [data-pim-matched="700"]')).toBeVisible()
  })

  test('a stream whose read failed shows the error and how old the last read is, with no figures', async ({ page }) => {
    const { pim } = await open(page)
    const fee = pim.locator('[data-pim-consumer-stream="fee"][data-pim-consumer-error]')
    await expect(fee).toContainText('Could not be read: read timed out')
    await expect(fee).toContainText('last read')
    await expect(fee.locator('[data-pim-matched]')).toHaveCount(0)
  })

  test('the read column says how old each stream is and flags a stale one against the stale-after minutes of the read', async ({ page }) => {
    const operations = { ...OPERATIONS, consumer: OPERATIONS.consumer.map((c) => (c.stream === 'sch' ? { ...c, measured_at: '2026-11-26T00:00:00+00:00' } : c)) }
    const { pim } = await open(page, { pim: { ...PIM, operations } })
    const fresh = pim.locator('[data-pim-consumer-stream="int"][data-pim-consumer-country="AU"] [data-label="Read"]')
    await expect(fresh).toContainText('9 min ago')
    await expect(fresh).not.toContainText('Stale')
    const old = pim.locator('[data-pim-consumer-stream="sch"][data-pim-consumer-country="AU"] [data-label="Read"]')
    await expect(old).toContainText('2 h ago')
    await expect(old).toContainText('Stale')
  })

  test('the Gains panel points to the per-stream read-back instead of a Not measured tile that says it is elsewhere', async ({ page }) => {
    const { pim } = await open(page)
    const verified = pim.locator('[data-pim-gain-group-shared]').filter({ hasText: 'Verified consumer delivery' })
    await expect(verified).toContainText('Verified consumer read-back below')
    await expect(verified).toContainText('not a delivery check')
  })
})

test.describe('freshness by country', () => {
  test('a table by country and field shows held, due and fresh; the country filter narrows it; a measured none-held says None held', async ({ page }) => {
    const { pim } = await open(page)
    await pim.locator('[data-pim-tab="refresh"]').click()
    const v = pim.locator('[data-pim-panel="refresh"]')
    const t = v.locator('[data-pim-fresh-by-country]')
    const au = t.locator('[data-pim-fresh-row="AU-description"]')
    await expect(au.locator('[data-label="Country"]')).toHaveText('Australia')
    await expect(au.locator('[data-label="Values held"]')).toHaveText('12,685')
    await expect(au.locator('[data-label="Due to be verified"]')).toHaveText('40')
    await expect(au.locator('[data-label="Fresh"]')).toContainText('99.7%')
    await expect(t.locator('[data-pim-fresh-row="CA-campus"] [data-label="Fresh"]')).toContainText('None held')
    await expect(t.locator('tbody tr')).toHaveCount(4)
    await v.locator('[data-pim-fresh-country]').selectOption('NZ')
    await expect(t.locator('tbody tr')).toHaveCount(1)
    await expect(t.locator('[data-pim-fresh-row="NZ-description"] [data-label="Fresh"]')).toContainText('99.3%')
    // the by-field table (all countries) is still there and keeps the oldest verified date, which is not counted by country
    await expect(v.locator('[data-pim-refresh-field="description"]')).toBeVisible()
    await expect(v).toContainText('not by country')
  })

  test('without freshness by country the view says Not available and does not invent a country split', async ({ page }) => {
    const { pim } = await open(page, { pim: PIM_NO_OPERATIONS })
    await pim.locator('[data-pim-tab="refresh"]').click()
    const v = pim.locator('[data-pim-panel="refresh"]')
    await expect(v.locator('[data-pim-fresh-by-country]')).toHaveCount(0)
    await expect(v).toContainText('Freshness by country')
    await expect(v.locator('[data-pim-unknown]').filter({ hasText: 'Not available' }).first()).toBeVisible()
  })
})

test.describe('request register and verified feedback stay unavailable', () => {
  test('the Requests & feedback view says Not available, gives the backend reason, and shows no status, weight or coverage', async ({ page }) => {
    const { pim } = await open(page)
    await pim.locator('[data-pim-tab="requests"]').click()
    const v = pim.locator('[data-pim-panel="requests"]')
    await expect(v.locator('[data-pim-requests-unavailable] [data-pim-unknown]')).toContainText('Not available')
    await expect(v.locator('[data-pim-requests-reason]')).toContainText('No registered database source holds the StudySearch request register')
    await expect(v.locator('[data-pim-requests]')).toHaveCount(0)
    await expect(v).toContainText('No authoritative source for verified feedback has been resolved')
    await expect(v).not.toContainText('Fixed')
  })
})

test.describe('helper snapshots and no regressions', () => {
  test('the other Data Delivery counts are listed with their age and a failed one is flagged with its last good result kept', async ({ page }) => {
    const { pim } = await open(page)
    const line = pim.locator('[data-pim-helper-snapshots]')
    await expect(line).toContainText('each kept as its last good result')
    await expect(line.locator('[data-pim-helper-snapshot="aer"]')).toHaveAttribute('data-pim-helper-state', 'ok')
    await expect(line.locator('[data-pim-helper-snapshot="intake"]')).toHaveAttribute('data-pim-helper-state', 'error')
    await expect(line.locator('[data-pim-helper-snapshot="intake"]')).toContainText('Last count failed')
  })

  test('no control is added: the PIM block still has only its tabs and the country and measure selectors, and the screen makes no extra request', async ({ page }) => {
    const { pim, dd } = await open(page)
    await expect(pim.locator('[data-pim-tab]')).toHaveCount(3)
    await expect(pim.locator('input:not([data-pjm-search]), textarea'), 'the only input is the read-only jobs search (s1283)').toHaveCount(0)
    expect(dd.calls, 'one Data Delivery read serves the whole block').toBeLessThanOrEqual(2)
  })
})
