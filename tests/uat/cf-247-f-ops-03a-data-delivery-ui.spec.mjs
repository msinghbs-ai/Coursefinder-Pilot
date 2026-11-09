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
  // the section is also on screen while it reads: wait for the first stream row, which only exists once the answer has arrived
  await expect(page.locator('[data-dd-stream]').first()).toBeVisible({ timeout: 20_000 })
  return dd
}

test.describe('Data delivery on Operations', () => {
  test('it is the first panel on Operations, one row per stream, with every measure in its own cell', async ({ page }) => {
    await open(page)
    const root = page.locator('[data-data-delivery]')
    const first = await page.evaluate(() => { const s = document.querySelector('[data-data-delivery]'); return s?.parentElement?.firstElementChild === s })
    expect(first, 'Data delivery is the first element of the Operations stack').toBe(true)
    await expect(root.locator('[data-dd-stream]')).toHaveCount(6)
    const pd = root.locator('[data-dd-stream="pdesc"]')
    for (const c of ['coverage', 'net_short', 'net_long', 'website', 'zoho', 'queue', 'holds', 'speed', 'runs', 'recovery']) await expect(pd.locator(`[data-dd-cell="${c}"]`)).toBeVisible()
    await expect(pd.locator('[data-dd-cell="coverage"]')).toContainText('800')
    await expect(pd.locator('[data-dd-cell="coverage"]')).toContainText('of 3,087')
    await expect(pd.locator('[data-dd-cell="coverage"]')).toContainText('25.9% covered')
    await expect(pd.locator('[data-dd-cell="net_short"]')).toContainText('+10')
    await expect(pd.locator('[data-dd-cell="net_short"]')).toContainText('12 providers in')
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
    // English has no dated admission ledger: Unknown in both windows with the reason, never a bold 0
    for (const c of ['net_short', 'net_long']) {
      await expect(eng.locator(`[data-dd-cell="${c}"] [data-dd-unknown]`)).toContainText('Unknown')
      await expect(eng.locator(`[data-dd-cell="${c}"]`)).toContainText('course_english_requirements has no created_at')
      await expect(eng.locator(`[data-dd-cell="${c}"] [data-dd-net]`)).toHaveCount(0)
    }
    await expect(eng.locator('[data-dd-cell="speed"] [data-dd-unknown]')).toContainText('Not measured')
    await expect(eng.locator('[data-dd-cell="speed"] [data-dd-unknown]')).toContainText('cannot be counted')
    await expect(eng.locator('[data-dd-cell="zoho"] [data-dd-unknown]')).toContainText('Not measured')
    await expect(eng.locator('[data-dd-cell="queue"] [data-dd-unknown]')).toContainText('no English reader queue')
    const cd = page.locator('[data-dd-stream="cdesc"]')
    // course descriptions: the ledger holds no dated admission, so the admitted count is Unknown in both windows (not 0)
    for (const c of ['net_short', 'net_long']) {
      await expect(cd.locator(`[data-dd-cell="${c}"] [data-dd-admitted-unknown]`)).toContainText('a count of 0 would not be true')
      await expect(cd.locator(`[data-dd-cell="${c}"]`)).not.toContainText(/^\s*0\s*$/)
    }
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
    await expect(int.locator('[data-dd-flag="green_no_admission"]')).toContainText('16174 waiting')
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
    await expect(int.locator('[data-dd-drill-box] [data-dd-drill="missing"]')).toHaveText('Courses with no intake')
    await expect(int.locator('[data-dd-drill-box] [data-dd-drill="filled"]')).toHaveText('Courses with an intake')
    await expect(int.locator('[data-dd-drill-note]')).toContainText('no dated-intake filter')
    await int.locator('[data-dd-drill-box] [data-dd-drill="missing"]').click()
    await expect(page).toHaveURL(/#courses\?f_hasIntake=false/)
  })

  test('until the Provider Catalogue filters exist, provider drill-downs are not offered and the page says why', async ({ page }) => {
    await open(page, { ...DATA_DELIVERY, provider_filters_available: false })
    const pd = page.locator('[data-dd-stream="pdesc"]')
    await expect(pd.locator('[data-dd-cell="website"] [data-dd-drill]')).toHaveCount(0)
    await pd.locator('summary').click()
    await expect(pd.locator('[data-dd-drill-box] [data-dd-drill="filled"]')).toHaveCount(0)
    await expect(pd.locator('[data-dd-degraded]')).toContainText('Provider Catalogue columns release')
    await expect(pd.locator('[data-dd-drill="lane"]')).toHaveAttribute('href', /lane=pdesc/)
  })

  test('it reloads itself on the setting\'s interval and the Refresh button reloads at once; a failed refresh leaves the last figures with a stale banner', async ({ page }) => {
    await page.clock.install()
    const dd = await open(page, { ...DATA_DELIVERY, ui_refresh_seconds: 20 })
    const first = dd.calls
    const refresh = page.locator('[data-dd-refresh]')
    await refresh.click()
    await expect.poll(() => dd.calls, { timeout: 20_000 }).toBeGreaterThan(first)
    await expect(refresh).toBeEnabled({ timeout: 20_000 }) // the read has finished: a tick while one is in flight is skipped by design
    const before = dd.calls
    await page.clock.fastForward(21_000)
    await expect.poll(() => dd.calls, { timeout: 20_000 }).toBeGreaterThan(before)
    await expect(refresh).toBeEnabled({ timeout: 20_000 })
    dd.fail = 'database is busy'
    await page.clock.fastForward(21_000)
    const banner = page.locator('[data-dd-stale-banner]')
    await expect(banner).toBeVisible({ timeout: 20_000 })
    await expect(banner).toContainText('last refresh failed')
    await expect(banner).toContainText('database is busy')
    await expect(page.locator('[data-dd-stream="pdesc"] [data-dd-cell="coverage"]')).toContainText('800', { timeout: 20_000 })
    dd.fail = null
    await expect(refresh).toBeEnabled({ timeout: 20_000 })
    await refresh.click()
    await expect(banner).toHaveCount(0, { timeout: 20_000 })
  })

  test('it stops reloading while the tab is hidden and catches up when shown', async ({ page }) => {
    await page.clock.install()
    const dd = await open(page, { ...DATA_DELIVERY, ui_refresh_seconds: 20 })
    await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' }); document.dispatchEvent(new Event('visibilitychange')) })
    const hidden = dd.calls
    await page.clock.fastForward(65_000)
    expect(dd.calls, 'no reads while hidden').toBe(hidden)
    await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' }); document.dispatchEvent(new Event('visibilitychange')) })
    await expect.poll(() => dd.calls, { timeout: 20_000 }).toBeGreaterThan(hidden)
  })

  test('rows and courses are not mixed unlabelled: intake coverage says rows and that the catalogue has no dated-intake filter; Website and Zoho count courses', async ({ page }) => {
    await open(page)
    const int = page.locator('[data-dd-stream="int"]')
    await expect(int.locator('[data-dd-cell="coverage"]')).toContainText('intake rows')
    await expect(int.locator('[data-dd-cell="coverage"] [data-dd-coverage-note]')).toContainText('no dated-intake filter')
    await expect(int.locator('[data-dd-cell="website"]')).toContainText('courses matched')
    await expect(int.locator('[data-dd-cell="net_long"]')).toContainText('intake events')
    await expect(page.locator('[data-dd-stream="fee"] [data-dd-cell="coverage"]')).toContainText('courses')
    await expect(page.locator('[data-dd-stream="fee"] [data-dd-cell="net_long"]')).toContainText('fee rows')
  })

  test('fees: only the rows created are shown, with no net, because removals are not separable (replaced rows are not removals)', async ({ page }) => {
    await open(page)
    const fee = page.locator('[data-dd-stream="fee"]')
    await expect(fee.locator('[data-dd-cell="net_long"] [data-dd-net]')).toHaveAttribute('data-dd-net', 'unknown')
    await expect(fee.locator('[data-dd-cell="net_long"]')).toContainText('3,095 fee rows in')
    await expect(fee.locator('[data-dd-cell="net_long"] [data-dd-removed-unknown]')).toContainText('no net')
    await expect(fee.locator('[data-dd-cell="net_long"] [data-dd-removed-unknown]')).toContainText('not separable')
    await expect(fee.locator('[data-dd-cell="net_long"]')).not.toContainText(' out')
  })

  test('scholarship Website pending is Not measured, not a literal 0', async ({ page }) => {
    await open(page)
    const sch = page.locator('[data-dd-stream="sch"]')
    await expect(sch.locator('[data-dd-cell="website"] [data-dd-pending-unknown]')).toContainText('pending: not measured')
    await expect(sch.locator('[data-dd-cell="website"]')).not.toContainText('0 pending')
  })

  test('a green job whose queue is empty is still flagged, but reads as information, not an alarm', async ({ page }) => {
    const payload = JSON.parse(JSON.stringify(DATA_DELIVERY))
    const int = payload.streams.find((x) => x.stream === 'int')
    int.queue = { known: true, n: 0, partial: false, parts: [], reasons: [] }
    int.flags = [{ code: 'green_no_admission', severity: 'info', queue_empty: true, text: 'Ran OK 24 time(s) in 24 h, admitted nothing; queue empty, nothing is waiting' }]
    await open(page, payload)
    const flag = page.locator('[data-dd-stream="int"] [data-dd-flag="green_no_admission"]')
    await expect(flag).toBeVisible()
    await expect(flag).toHaveAttribute('data-dd-queue-empty', 'true')
    await expect(flag).toContainText('nothing is waiting')
    await expect(flag).toHaveClass(/tone-neutral/)
  })

  test('a failed recount keeps the last good figures, marked Stale with the error beside them', async ({ page }) => {
    const payload = JSON.parse(JSON.stringify(DATA_DELIVERY))
    const fee = payload.streams.find((x) => x.stream === 'fee')
    Object.assign(fee.coverage, { stale: true, count_error: 'canceling statement due to statement timeout', age_minutes: 41 })
    await open(page, payload)
    const cov = page.locator('[data-dd-stream="fee"] [data-dd-cell="coverage"]')
    await expect(cov).toContainText('27,600')
    await expect(cov).toContainText('Stale')
    await expect(cov.locator('[data-dd-count-error]')).toContainText('statement timeout')
    await expect(cov.locator('[data-dd-count-error]')).toContainText('last good figures')
  })

  test('one hung request does not stop the reloads: it is abandoned after the time-out and the next tick asks again', async ({ page }) => {
    await page.clock.install()
    const dd = await open(page, { ...DATA_DELIVERY, ui_refresh_seconds: 20 })
    dd.hang = true
    const before = dd.calls
    await page.locator('[data-dd-refresh]').click()
    await expect.poll(() => dd.calls, { timeout: 20_000 }).toBeGreaterThan(before)
    await page.clock.fastForward(21_000)
    const banner = page.locator('[data-dd-stale-banner]')
    await expect(banner).toBeVisible({ timeout: 20_000 })
    await expect(banner).toContainText('took too long')
    dd.hang = false
    await expect(page.locator('[data-dd-refresh]')).toBeEnabled({ timeout: 20_000 })
    await page.clock.fastForward(21_000)
    await expect(banner).toHaveCount(0, { timeout: 20_000 })
  })

  test('between 641 and 1100 px the eleven columns become labelled blocks: no sideways scroll and every cell wide enough to read', async ({ page }) => {
    for (const width of [641, 800, 1100]) {
      await page.setViewportSize({ width, height: 900 })
      await open(page)
      const m = await page.evaluate(() => {
        const cells = [...document.querySelectorAll('[data-dd-stream="pdesc"] > summary .dd-cell')]
        return { overflow: document.documentElement.scrollWidth - window.innerWidth, narrowest: Math.min(...cells.map((c) => c.getBoundingClientRect().width)), cells: cells.length, head: getComputedStyle(document.querySelector('.dd-head')).display }
      })
      expect(m.overflow, `no sideways scroll at ${width}px`).toBeLessThanOrEqual(1)
      expect(m.cells).toBe(10)
      expect(m.narrowest, `the narrowest cell at ${width}px`).toBeGreaterThanOrEqual(120)
      expect(m.head, `the eleven-column header is hidden at ${width}px`).toBe('none')
      await page.unrouteAll({ behavior: 'ignoreErrors' })
    }
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
