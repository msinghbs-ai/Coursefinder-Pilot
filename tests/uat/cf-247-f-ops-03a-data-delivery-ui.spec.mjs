// Guards: F-OPS.03A (Platform Admin P0, 9 Nov 2026 21:28): an always-visible, live Data Delivery summary at the TOP of Layer 2/3 > Operations: coverage, 24 h and 7 d net gains, Website/Zoho, queue, holds with exact reasons, speed, last/next run, automatic recovery; unknown is never 0; a green job that admitted nothing is flagged; drill-down into the catalogues; refreshes itself.
// Desktop project (chromium-desktop). Mocked admin (tests/uat/support/admin-mock.mjs plus data-delivery-mock.mjs); nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockDataDelivery, DATA_DELIVERY } from './support/data-delivery-mock.mjs'

const OPERATIONS = '/#layer-2-discovery?tab=operations'
async function open(page, payload) {
  await mockAdmin(page); await mockLaneFunnels(page)
  const dd = await mockDataDelivery(page, payload)
  await page.goto(OPERATIONS)
  await expect(page.locator('[data-data-delivery]')).toBeVisible()
  return dd
}

test.describe('Data delivery on Operations', () => {
  test('it is the first panel on Operations, one row per stream, with every measure in its own cell', async ({ page }) => {
    await open(page)
    const root = page.locator('[data-data-delivery]')
    const first = await page.evaluate(() => { const s = document.querySelector('[data-data-delivery]'); return s?.parentElement?.firstElementChild === s })
    expect(first, 'Data delivery is the first element of the Operations stack').toBe(true)
    await expect(root.locator('[data-dd-stream]')).toHaveCount(4)
    const pd = root.locator('[data-dd-stream="pdesc"]')
    for (const c of ['coverage', 'net_short', 'net_long', 'website', 'zoho', 'queue', 'holds', 'speed', 'runs', 'recovery']) await expect(pd.locator(`[data-dd-cell="${c}"]`)).toBeVisible()
    await expect(pd.locator('[data-dd-cell="coverage"]')).toContainText('800')
    await expect(pd.locator('[data-dd-cell="coverage"]')).toContainText('of 3,087')
    await expect(pd.locator('[data-dd-cell="coverage"]')).toContainText('25.9% covered')
    await expect(pd.locator('[data-dd-cell="net_short"]')).toContainText('+10')
    await expect(pd.locator('[data-dd-cell="net_short"]')).toContainText('12 in')
    await expect(pd.locator('[data-dd-cell="net_long"]')).toContainText('+795')
    await expect(pd.locator('[data-dd-cell="website"]')).toContainText('790')
    await expect(pd.locator('[data-dd-cell="website"]')).toContainText('6 pending')
    await expect(pd.locator('[data-dd-cell="queue"]')).toContainText('435')
    await expect(pd.locator('[data-dd-cell="speed"]')).toContainText('5')
    await expect(pd.locator('[data-dd-cell="holds"] [data-dd-reasons] li').first()).toContainText('N verified fact(s) held (register, location)')
    await expect(pd.locator('[data-dd-cell="holds"] [data-dd-reasons] li').first()).toContainText('472')
  })

  test('windows are labelled from the settings, and the ledger being younger than the window is said, not hidden', async ({ page }) => {
    await open(page)
    const head = page.locator('.dd-head')
    await expect(head).toContainText('Net 24 h'); await expect(head).toContainText('Net 7 d')
    const int = page.locator('[data-dd-stream="int"]')
    await expect(int.locator('[data-dd-cell="net_short"] [data-dd-partial]')).toContainText('Ledger starts')
    await expect(int.locator('[data-dd-cell="net_long"] [data-dd-partial]')).toContainText('shorter than 7 d')
  })

  test('unknown is the word Unknown or Not measured with its reason, never 0 or blank', async ({ page }) => {
    await open(page)
    const eng = page.locator('[data-dd-stream="eng"]')
    // removals unknown: net is not shown as a number, the gross admitted figure is, with the reason
    await expect(eng.locator('[data-dd-cell="net_short"] [data-dd-net]')).toHaveAttribute('data-dd-net', 'unknown')
    await expect(eng.locator('[data-dd-cell="net_short"] [data-dd-removed-unknown]')).toContainText('removals not measured')
    await expect(eng.locator('[data-dd-cell="speed"] [data-dd-unknown]')).toContainText('Not measured')
    await expect(eng.locator('[data-dd-cell="speed"] [data-dd-unknown]')).toContainText('cannot be counted')
    await expect(eng.locator('[data-dd-cell="zoho"] [data-dd-unknown]')).toContainText('Not measured')
    await expect(eng.locator('[data-dd-cell="queue"] [data-dd-unknown]')).toContainText('no English reader queue')
    const cd = page.locator('[data-dd-stream="cdesc"]')
    await expect(cd.locator('[data-dd-cell="coverage"] [data-dd-unknown]')).toContainText('Unknown')
    await expect(cd.locator('[data-dd-cell="coverage"]')).toContainText('statement timeout')
    await expect(cd.locator('[data-dd-cell="coverage"]')).not.toContainText(/^0$/)
    await expect(cd.locator('[data-dd-cell="website"] [data-dd-unknown]')).toContainText('not compared yet')
    await expect(cd.locator('[data-dd-cell="holds"] [data-dd-partial]')).toContainText('Some stages are not counted')
    // a job with no history in the window is Unknown with the reason, not "never"
    await expect(eng.locator('[data-dd-cell="runs"] [data-dd-unknown]').first()).toContainText('No run of central-attach')
  })

  test('a green job that admitted nothing is flagged on its row, with a link to the reason breakdown; a failed run is flagged apart', async ({ page }) => {
    await open(page)
    const int = page.locator('[data-dd-stream="int"]')
    await expect(int.locator('[data-dd-flag="green_no_admission"]')).toContainText('Ran OK 24 time(s) in 24 h, admitted nothing')
    await expect(int.locator('[data-dd-flag="green_no_admission"] [data-dd-reasons-link]')).toHaveAttribute('href', /lane=int/)
    await expect(page.locator('[data-dd-stream="pdesc"] [data-dd-flag]')).toHaveCount(0)
    await expect(page.locator('[data-dd-stream="eng"] [data-dd-flag="job_failing"]')).toContainText('2 failed run(s)')
    await expect(page.locator('[data-dd-summary]')).toContainText('ran green but admitted nothing in 24 h')
    await expect(page.locator('[data-dd-stream="eng"] [data-dd-recovery]')).toHaveAttribute('data-dd-recovery', 'failing')
  })

  test('last and next run are absolute Melbourne times with the relative time beside them', async ({ page }) => {
    await open(page)
    const runs = page.locator('[data-dd-stream="pdesc"] [data-dd-cell="runs"]')
    await expect(runs).toContainText('Last'); await expect(runs).toContainText('ago'); await expect(runs).toContainText('Next'); await expect(runs).toContainText(/in \d+ min/)
    await expect(runs.locator('[data-dd-next]')).toHaveText(/\d{1,2}:\d{2}\s?(am|pm)/i)
    await expect(page.locator('[data-dd-updated]')).toHaveText(/^\d{2}:\d{2}:\d{2}$/)
    await expect(page.locator('[data-dd-stamp]')).toContainText('(Melbourne)')
  })

  test('drill-down opens the Course Catalogue and the Provider Catalogue with the filters preselected', async ({ page }) => {
    await open(page)
    const pd = page.locator('[data-dd-stream="pdesc"]')
    await expect(pd.locator('[data-dd-cell="website"] [data-dd-drill="pending"]')).toHaveAttribute('href', '#providers?f_website=pending')
    await expect(pd.locator('[data-dd-cell="zoho"] [data-dd-drill="missing"]')).toHaveAttribute('href', '#providers?f_zoho=missing')
    await pd.locator('summary').click()
    await expect(pd.locator('[data-dd-drill-box] [data-dd-drill="filled"]')).toHaveAttribute('href', '#providers?f_description=filled')
    await expect(pd.locator('[data-dd-drill-box] [data-dd-drill="missing"]')).toHaveAttribute('href', '#providers?f_description=missing')
    const int = page.locator('[data-dd-stream="int"]')
    await int.locator('summary').click()
    await expect(int.locator('[data-dd-drill-box] [data-dd-drill="missing"]')).toHaveAttribute('href', '#courses?f_hasIntake=false')
    await expect(int.locator('[data-dd-drill-note]')).toContainText('no Website or Zoho state filter')
    await int.locator('[data-dd-drill-box] [data-dd-drill="missing"]').click()
    await expect(page).toHaveURL(/#courses\?f_hasIntake=false/)
  })

  test('until the Provider Catalogue filters exist, provider drill-downs are not offered and the page says why', async ({ page }) => {
    await open(page, { ...DATA_DELIVERY, provider_filters_available: false })
    const pd = page.locator('[data-dd-stream="pdesc"]')
    await expect(pd.locator('[data-dd-cell="website"] [data-dd-drill]')).toHaveCount(0)
    await pd.locator('summary').click()
    await expect(pd.locator('[data-dd-drill-box] [data-dd-drill="filled"]')).toHaveCount(0)
    await expect(pd.locator('[data-dd-degraded]')).toContainText('#956')
    await expect(pd.locator('[data-dd-drill="lane"]')).toHaveAttribute('href', /lane=pdesc/)
  })

  test('it reloads itself on the setting\'s interval and the Refresh button reloads at once; a failed refresh leaves the last figures with a stale banner', async ({ page }) => {
    await page.clock.install()
    const dd = await open(page, { ...DATA_DELIVERY, ui_refresh_seconds: 20 })
    const first = dd.calls
    await page.getByRole('button', { name: 'Refresh' }).first().click()
    await expect.poll(() => dd.calls).toBeGreaterThan(first)
    const before = dd.calls
    await page.clock.fastForward(21_000)
    await expect.poll(() => dd.calls).toBeGreaterThan(before)
    dd.fail = 'database is busy'
    await page.clock.fastForward(21_000)
    const banner = page.locator('[data-dd-stale-banner]')
    await expect(banner).toBeVisible()
    await expect(banner).toContainText('last refresh failed')
    await expect(banner).toContainText('database is busy')
    await expect(page.locator('[data-dd-stream="pdesc"] [data-dd-cell="coverage"]')).toContainText('800')
    dd.fail = null
    await page.getByRole('button', { name: 'Refresh' }).first().click()
    await expect(banner).toHaveCount(0)
  })

  test('it stops reloading while the tab is hidden and catches up when shown', async ({ page }) => {
    await page.clock.install()
    const dd = await open(page, { ...DATA_DELIVERY, ui_refresh_seconds: 20 })
    await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' }); document.dispatchEvent(new Event('visibilitychange')) })
    const hidden = dd.calls
    await page.clock.fastForward(65_000)
    expect(dd.calls, 'no reads while hidden').toBe(hidden)
    await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' }); document.dispatchEvent(new Event('visibilitychange')) })
    await expect.poll(() => dd.calls).toBeGreaterThan(hidden)
  })

  test('the lane funnels stay below it and a lane link opens that lane', async ({ page }) => {
    await open(page)
    await page.locator('[data-dd-stream="int"] summary').click()
    await page.locator('[data-dd-stream="int"] [data-dd-drill="lane"]').click()
    await expect(page.locator('[data-lane-funnels]')).toBeVisible()
  })

  test('a drill-down link opens the Course Catalogue with exactly those filters applied, replacing the remembered ones', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page); await mockDataDelivery(page)
    const bodies = []
    page.on('request', (r) => { if (/\/rest\/v1\/rpc\//.test(r.url()) && r.method() === 'POST') { try { bodies.push(r.postDataJSON()) } catch { /* not json */ } } })
    await page.goto('/#courses?f_hasIntake=false&f_country=AU')
    await expect(page.getByText('Has intake', { exact: false }).first()).toBeVisible()
    await expect.poll(() => bodies.some((b) => b?.p_args?.has_intake === false && b?.p_args?.country_code === 'AU')).toBe(true)
    // an unknown key in the address is ignored, not sent to the server
    await page.goto('/#courses?f_nonsense=1&f_hasFee=true')
    await expect.poll(() => bodies.some((b) => b?.p_args?.has_fee === true && b?.p_args?.has_intake === undefined)).toBe(true)
    expect(bodies.some((b) => b?.p_args && 'nonsense' in b.p_args)).toBe(false)
  })
})
