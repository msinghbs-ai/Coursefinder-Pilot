// Guards: F-OPS.03A (Platform Admin P0, 9 Nov 2026 21:28): an always-visible, live Data Delivery summary at the TOP of Layer 2/3 > Operations: coverage, 24 h and 7 d net gains, Website/Zoho, queue, holds with exact reasons, speed, last/next run, automatic recovery; unknown is never 0; a green job that admitted nothing is flagged; drill-down into the catalogues; refreshes itself.
// Desktop project (chromium-desktop). Mocked admin (tests/uat/support/admin-mock.mjs plus data-delivery-mock.mjs); nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockDataDelivery, DATA_DELIVERY, THREE_ALERTS, withStages, STAGES, PROVIDER_AI, withProviderAi } from './support/data-delivery-mock.mjs'

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
    expect(first, 'Data delivery is the first element of the Operations page body, above the notice strip').toBe(true)
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

  test('it is above the alert cards and inside the first screen at 1280 x 900 with three alert cards shown', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 900 })
    await open(page)
    const alerts = page.locator(THREE_ALERTS)
    await expect.poll(() => alerts.count()).toBeGreaterThanOrEqual(3)
    const m = await page.evaluate((sel) => {
      const h = document.querySelector('[data-data-delivery] h3').getBoundingClientRect()
      const a = document.querySelector(sel).getBoundingClientRect()
      const row = document.querySelector('[data-dd-stream]').getBoundingClientRect()
      return { header: h.top, headerBottom: h.bottom, alert: a.top, row: row.top, rowBottom: row.bottom, vh: window.innerHeight }
    }, THREE_ALERTS)
    expect(m.header, 'panel header above the first alert card').toBeLessThan(m.alert)
    expect(m.headerBottom).toBeLessThan(m.vh)
    expect(m.row, 'the first stream row starts inside the first screen').toBeLessThan(m.vh - 150)
  })

  test('queue and hold figures show Stale with when they were counted and the error, so a stalled lane-funnel job cannot look current', async ({ page }) => {
    const payload = JSON.parse(JSON.stringify(DATA_DELIVERY))
    const pd = payload.streams.find((x) => x.stream === 'pdesc')
    const t = new Date(Date.now() - 95 * 60000).toISOString()
    pd.queue.parts[0] = { ...pd.queue.parts[0], stale: true, measured_at: t, error: null }
    pd.holds.parts[0] = { ...pd.holds.parts[0], stale: false, measured_at: new Date().toISOString(), error: 'canceling statement due to statement timeout' }
    await open(page, payload)
    const q = page.locator('[data-dd-stream="pdesc"] [data-dd-cell="queue"] [data-dd-part="queued"]')
    await expect(q).toContainText('Stale')
    await expect(q.locator('[data-dd-part-stale]')).toContainText('counted')
    const h = page.locator('[data-dd-stream="pdesc"] [data-dd-cell="holds"] [data-dd-part="held"]')
    await expect(h).toContainText('Stale')
    await expect(h.locator('[data-dd-part-stale]')).toContainText('the latest count failed (canceling statement due to statement timeout)')
    await expect(page.locator('[data-dd-stream="pdesc"] [data-dd-cell="queue"] [data-dd-part-stale]')).toHaveCount(1)
    await expect(page.locator('[data-dd-stream="int"] [data-dd-part-stale]')).toHaveCount(0)
  })

  test('recovery reads Paused for a paused primary job and Stalled for a job that runs but admits nothing; the chip is not clipped', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 900 })
    await open(page)
    const sch = page.locator('[data-dd-stream="sch"] [data-dd-recovery]')
    await expect(sch).toHaveAttribute('data-dd-recovery', 'paused')
    await expect(sch).toContainText('scholarship-read is paused')
    const int = page.locator('[data-dd-stream="int"] [data-dd-recovery]')
    await expect(int).toHaveAttribute('data-dd-recovery', 'stalled')
    await expect(int).toContainText('admitted nothing')
    const clipped = await page.evaluate(() => [...document.querySelectorAll('[data-dd-recovery] .cf-chip')].filter((c) => c.scrollWidth > c.clientWidth + 1).map((c) => c.textContent))
    expect(clipped, 'no recovery chip is cut off').toEqual([])
  })

  test('a stale run history summary (the data-delivery job has not run) is shown on the runs cell', async ({ page }) => {
    const payload = JSON.parse(JSON.stringify(DATA_DELIVERY))
    const pd = payload.streams.find((x) => x.stream === 'pdesc')
    Object.assign(pd.jobs, { history_stale: true, history_measured_at: new Date(Date.now() - 3 * 3600000).toISOString(), history_error: null })
    await open(page, payload)
    await expect(page.locator('[data-dd-stream="pdesc"] [data-dd-history-stale]')).toContainText('run history counted')
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

  test('course description stages: five stages, machine and person counts apart, courses not served to the Website on their own line, Zoho not counted (never 0)', async ({ page }) => {
    await open(page, withStages())
    const cd = page.locator('[data-dd-stream="cdesc"]')
    await expect(cd).toHaveAttribute('open', '')
    const box = cd.locator('[data-dd-stages="known"]')
    await expect(box).toBeVisible()
    await expect(box.locator('[data-dd-stage]')).toHaveCount(5)
    const n = (k) => box.locator(`[data-dd-stage-n="${k}"]`)
    for (const [k, v] of Object.entries({ proposals_from_a_stored_page: '9', waiting_in_layer4: '5', held_behind_provider_cap: '1', held_by_a_check: '1', declined_by_machine: '5', by_machine: '3', by_person: '1', withdrawn: '1', described_courses: '5', described_other_route: '1', website_published: '1', unpublished_course: '4' })) await expect(n(k).first(), k).toHaveText(v)
    await expect(n('by_machine')).toHaveAttribute('data-dd-actor', 'machine')
    await expect(n('by_person')).toHaveAttribute('data-dd-actor', 'person')
    await expect(n('declined_by_machine')).toHaveAttribute('data-dd-actor', 'machine')
    await expect(box.locator('[data-dd-decline-reasons] li').first()).toContainText('wrong page kind')
    await expect(box.locator('[data-dd-decline-reasons] li').first()).toContainText('5')
    await expect(box.locator('[data-dd-stage-row="website_published"]')).toContainText('served to the Website')
    await expect(box.locator('[data-dd-stage-row="unpublished_course"]')).toContainText('not served to the Website (provider hidden or blocked in Layer 4)')
    await expect(box.locator('[data-dd-stage-row="unpublished_course"]')).not.toContainText('unpublished')
    const zoho = box.locator('[data-dd-stage-row="zoho"]')
    await expect(zoho).toContainText('Not counted')
    await expect(zoho).toContainText('no description field')
    await expect(zoho.locator('strong'), 'Zoho is not shown as a number').toHaveCount(0)
    await expect(box.locator('[data-dd-readback]')).toContainText('matched 3')
    await expect(box.locator('[data-dd-readback]')).toContainText('not the same as listed and published')
    await expect(box.locator('[data-dd-stages-stamp]')).toContainText('Counted live at')
    // the other streams carry no stage block
    await expect(page.locator('[data-dd-stages]')).toHaveCount(1)
  })

  test('course description stages: a stage that could not be counted says so with the reason, a missing figure is Not measured, never 0', async ({ page }) => {
    await open(page, withStages({ known: false, reason: 'The stage counts could not be read: canceling statement due to statement timeout' }))
    const box = page.locator('[data-dd-stream="cdesc"] [data-dd-stages="unknown"]')
    await expect(box).toContainText('Not counted')
    await expect(box).toContainText('could not be read')
    await expect(box.locator('[data-dd-stage-n]')).toHaveCount(0)
    const partial = { ...STAGES, admitted: { ...STAGES.admitted, by_person: null }, consumers: { ...STAGES.consumers, website_published: null } }
    const page2 = await page.context().newPage()
    await mockAdmin(page2); await mockLaneFunnels(page2); await mockDataDelivery(page2, withStages(partial))
    await page2.goto(OPERATIONS)
    const b2 = page2.locator('[data-dd-stream="cdesc"] [data-dd-stages="known"]')
    await expect(b2).toBeVisible({ timeout: 20_000 })
    await expect(b2.locator('[data-dd-stage-n="by_person"]')).toHaveText('Not measured')
    await expect(b2.locator('[data-dd-stage-n="website_published"]')).toHaveText('Not measured')
    await expect(b2.locator('[data-dd-stage-n="by_machine"]')).toHaveText('3')
  })
  test('course description flow: the eligible denominator, kept admissions, declines and holds by cause, reads against the limit and the blocker; a missing flow key is Not measured, never 0 (CF-247 F-CDESC, 10 Nov 2026)', async ({ page }) => {
    await open(page, withStages())
    const box = page.locator('[data-dd-stream="cdesc"] [data-dd-flow="known"]')
    await expect(box).toBeVisible()
    for (const [k, v] of Object.entries({ flow_eligible: '30', flow_never_read: '20', flow_waiting: '5', flow_held_cap: '2', flow_held_check: '2', flow_read_other: '1', flow_declined: '5', flow_admitted_24h: '3', flow_admitted_7d: '7', flow_withdrawn_7d: '1', flow_retained: '6', flow_reads_today: '4', flow_full: '1', flow_parked: '5' })) await expect(box.locator(`[data-dd-stage-n="${k}"]`), k).toHaveText(v)
    await expect(box.locator('[data-dd-stage-n="flow_declined"]')).toHaveAttribute('data-dd-actor', 'machine')
    await expect(box.locator('[data-dd-flow-causes="declined"] li').first()).toContainText('wrong page kind')
    await expect(box.locator('[data-dd-flow-causes="held"] li').first()).toContainText('unsupported claim')
    await expect(box.locator('[data-dd-stage-row="flow_reads_today"]')).toContainText('daily limit of 500')
    await expect(box.locator('[data-dd-flow-run]')).toContainText('Automatic admission on')
    await expect(box.locator('[data-dd-flow-blocker]')).toContainText('every place taken')
    // the five stages are unchanged
    await expect(page.locator('[data-dd-stream="cdesc"] [data-dd-stage]')).toHaveCount(5)
    // an older server sends no flow key: Not measured as a whole, and no figure is shown as 0
    const { flow, ...old } = STAGES
    const page2 = await page.context().newPage()
    await mockAdmin(page2); await mockLaneFunnels(page2); await mockDataDelivery(page2, withStages(old))
    await page2.goto(OPERATIONS)
    const b2 = page2.locator('[data-dd-stream="cdesc"] [data-dd-flow="unknown"]')
    await expect(b2).toBeVisible({ timeout: 20_000 })
    await expect(b2).toContainText('Not measured')
    await expect(b2.locator('[data-dd-stage-n]')).toHaveCount(0)
    await expect(page2.locator('[data-dd-stream="cdesc"] [data-dd-stage-n="by_machine"]')).toHaveText('3')
    // a flow that is known but lacks one figure shows that figure as Not measured
    const part = { ...STAGES, flow: { ...STAGES.flow, gain: { ...STAGES.flow.gain, retained_total: null } } }
    const page3 = await page.context().newPage()
    await mockAdmin(page3); await mockLaneFunnels(page3); await mockDataDelivery(page3, withStages(part))
    await page3.goto(OPERATIONS)
    await expect(page3.locator('[data-dd-flow="known"] [data-dd-stage-n="flow_retained"]')).toHaveText('Not measured', { timeout: 20_000 })
  })
  test('provider descriptions: AI cost and remaining allowance, admissions by route (machine rule and person apart) and the Basic to Enriched outcome, counted live (CF-247 F-PDESC, 10 Nov 2026)', async ({ page }) => {
    await open(page, withProviderAi())
    const pd = page.locator('[data-dd-stream="pdesc"]')
    await expect(pd).toHaveAttribute('open', '')
    const box = pd.locator('[data-dd-provider-ai="known"]')
    await expect(box).toBeVisible()
    await expect(box.locator('[data-dd-provider-ai-stamp]')).toContainText('Counted live at')
    await expect(box.locator('[data-dd-pdesc-stage]')).toHaveCount(3)
    // 1 AI cost: spent, reserved, ceiling, remaining allowance (the ceiling less spent less reserved), the day against the daily guard, the estimated settlements
    const money = (k) => box.locator(`[data-dd-money="${k}"]`).first()
    await expect(money('spent')).toHaveText('US$0.28'); await expect(box.locator('[data-dd-stage-row="ai_spent"]')).toContainText('187 paid calls')
    await expect(money('reserved')).toHaveText('US$0.14'); await expect(box.locator('[data-dd-stage-row="ai_reserved"]')).toContainText('19 reads')
    await expect(money('ceiling')).toHaveText('US$0.75')
    await expect(money('remaining')).toHaveText('US$0.33')
    await expect(money('today')).toHaveText('US$0.19')
    await expect(box.locator('[data-dd-daily]')).toContainText('Daily guard US$1.00'); await expect(box.locator('[data-dd-daily]')).toContainText('left today US$0.68')
    const settled = box.locator('[data-dd-stage-row="ai_settled"]')
    await expect(settled).toContainText('Estimated'); await expect(settled.locator('[data-dd-stage-n="settled_reads"]')).toHaveText('60'); await expect(settled.locator('[data-dd-settled]')).toContainText('US$0.18'); await expect(settled.locator('[data-dd-settled]')).toContainText('estimated')
    // 2 admitted, by route: the machine rule and a person are labelled apart
    const n = (k) => box.locator(`[data-dd-stage-n="${k}"]`)
    for (const [k, v] of Object.entries({ ai_first_description: '2', ai_upgrade: '0', registry_fact: '1,088', by_person: '0', withdrawn: '0' })) await expect(n(k), k).toHaveText(v)
    for (const k of ['ai_first_description', 'ai_upgrade', 'registry_fact', 'withdrawn']) await expect(n(k)).toHaveAttribute('data-dd-actor', 'machine')
    await expect(n('by_person')).toHaveAttribute('data-dd-actor', 'person')
    await expect(box.locator('[data-dd-stage-row="by_person"]')).toContainText('Person')
    await expect(box.locator('[data-dd-stage-row="registry_fact"]')).toContainText('Machine rule')
    // 3 Basic to Enriched: upgraded, still held, upgrade reads waiting, upgrade reads held by rule (the rule with its count; the exact reason on hover)
    for (const [k, v] of Object.entries({ upgrade_admitted: '0', basic_profiles_held: '1,088', upgrade_queued: '9', upgrade_held: '8' })) await expect(n(k), k).toHaveText(v)
    const holds = box.locator('[data-dd-upgrade-holds] li')
    await expect(holds).toHaveCount(3)
    await expect(holds.first()).toContainText('provider name not proved'); await expect(holds.first()).toContainText('6')
    await expect(holds.first().locator('span')).toHaveAttribute('title', /does not prove the provider's current full institutional identity/)
    await expect(box.locator('[data-dd-upgrade-off]')).toHaveCount(0)
    // only the provider stream carries the box, and the course stages box is not touched
    await expect(page.locator('[data-dd-provider-ai]')).toHaveCount(1)
  })

  test('provider descriptions: a missing block is Not measured as a whole, a count that failed says why, a missing figure is Not measured and never 0, a switched-off upgrade lane says so', async ({ page }) => {
    // an older server: no provider_ai key at all
    await open(page)
    const pd = page.locator('[data-dd-stream="pdesc"]')
    await pd.locator('summary').click()
    await expect(pd.locator('[data-dd-provider-ai="unknown"]')).toContainText('Not measured')
    await expect(pd.locator('[data-dd-provider-ai="unknown"] [data-dd-money], [data-dd-provider-ai="unknown"] [data-dd-stage-n]')).toHaveCount(0)
    // a count that failed
    const p2 = await page.context().newPage()
    await mockAdmin(p2); await mockLaneFunnels(p2); await mockDataDelivery(p2, withProviderAi({ known: false, reason: 'The provider AI and upgrade counts could not be read: canceling statement due to statement timeout' }))
    await p2.goto(OPERATIONS)
    const failed = p2.locator('[data-dd-stream="pdesc"] [data-dd-provider-ai="unknown"]')
    await expect(failed).toBeVisible({ timeout: 20_000 })
    await expect(failed).toContainText('could not be read')
    // figures the server did not send (null or absent): Not measured, never 0; the lane switched off says so
    const partial = { ...PROVIDER_AI, ai: { ...PROVIDER_AI.ai, remaining_usd: null, daily_guard_usd: null, daily_remaining_usd: null, settled_estimated_usd: null }, admitted: { ...PROVIDER_AI.admitted, by_person: null, ai_first_description: undefined }, upgrade: { ...PROVIDER_AI.upgrade, lane_on: false, queued_reads: 0, held_reads: null, top_hold_rules: [] } }
    const p3 = await page.context().newPage()
    await mockAdmin(p3); await mockLaneFunnels(p3); await mockDataDelivery(p3, withProviderAi(partial))
    await p3.goto(OPERATIONS)
    const b3 = p3.locator('[data-dd-stream="pdesc"] [data-dd-provider-ai="known"]')
    await expect(b3).toBeVisible({ timeout: 20_000 })
    await expect(b3.locator('[data-dd-money="remaining"]')).toHaveText('Not measured')
    await expect(b3.locator('[data-dd-daily]')).toContainText('Daily guard: Not measured')
    await expect(b3.locator('[data-dd-settled]')).toContainText('Amount: Not measured')
    for (const k of ['by_person', 'ai_first_description', 'upgrade_held']) await expect(b3.locator(`[data-dd-stage-n="${k}"]`), k).toHaveText('Not measured')
    await expect(b3.locator('[data-dd-stage-n="registry_fact"]')).toHaveText('1,088')
    await expect(b3.locator('[data-dd-upgrade-off]')).toContainText('switched off')
    await expect(b3.locator('[data-dd-stage-n="upgrade_queued"]')).toHaveText('0')
    await expect(b3.locator('[data-dd-upgrade-holds]')).toHaveCount(0)
  })
})
