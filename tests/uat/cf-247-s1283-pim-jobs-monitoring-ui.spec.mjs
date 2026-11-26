// Guards: SS-Programme-Control 26 Nov 2026 22:51 "Complete job and lane monitoring UI" (backend s1176, Pilot #1693) and the rule that the frontend uses the backend's classification: Data Delivery shows the backend-classified summary (states, counts by component type, attention items with the exact reason, snapshot freshness) in place of the all-rows worker table, and Scheduled jobs › Automations shows every component of public.admin_pim_jobs_v1 with search, filters, pagination and a drill-down (heartbeat, last and next run, outcomes, duration). Desktop project; mocked admin plus tests/uat/support/pim-mock.mjs; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockPim, mockPimJobs, JOBS, JOBS_NOT_COUNTED } from './support/pim-mock.mjs'

async function openDelivery(page) {
  await page.clock.setFixedTime(new Date('2026-11-26T12:00:00Z'))
  await mockAdmin(page); await mockLaneFunnels(page); await mockPim(page)
  await page.goto('/#layer-2-discovery?tab=operations')
  const s = page.locator('[data-pjm-summary]')
  await expect(s).toBeVisible({ timeout: 20_000 })
  return s
}
async function openMonitor(page, opts) {
  await page.clock.setFixedTime(new Date('2026-11-26T12:00:00Z'))
  await mockAdmin(page); await mockLaneFunnels(page); await mockPim(page)
  const c = await mockPimJobs(page, opts)
  await page.goto('/#scheduled-jobs?tab=automations')
  const m = page.locator('[data-pjm-monitor]')
  await expect(m).toBeVisible({ timeout: 20_000 })
  return { m, c }
}

test.describe('Data Delivery: backend-classified jobs summary', () => {
  test('shows the snapshot time, the backend state counts, counts by component type and no 138-row worker table', async ({ page }) => {
    const s = await openDelivery(page)
    await expect(s.locator('[data-pjm-as-at]')).toBeVisible()
    await expect(s.locator('[data-pjm-state="degraded"]')).toContainText('2')
    await expect(s.locator('[data-pjm-state="active"]')).toContainText('191')
    await expect(s.locator('[data-pjm-state="retired"]')).toContainText('85')
    await expect(s.locator('[data-pjm-type="cron"]')).toContainText('133')
    await expect(s.locator('[data-pjm-type="rollup"]')).toContainText('Rollup target')
    await expect(page.locator('[data-pim-workers]')).toHaveCount(0)
  })

  test('attention items carry the backend reason and findings; a state tile filters them; search narrows them', async ({ page }) => {
    const s = await openDelivery(page)
    const a = s.locator('[data-pjm-attention] > li')
    await expect(a).toHaveCount(3)
    await expect(a.first()).toContainText('coursefinder-data-quality-overview-refresh')
    await expect(a.first().locator('[data-pjm-reason]')).toHaveText('stalled: no run for 3 schedule periods')
    await expect(a.first()).toContainText('Often deferred')
    await s.locator('[data-pjm-state="held"] button').click()
    await expect(a).toHaveCount(2)
    await s.locator('[data-pjm-search]').fill('budget')
    await expect(a).toHaveCount(1)
    await expect(a.first()).toContainText('logo-find')
    await s.locator('[data-pjm-search]').fill('nothing matches this')
    await expect(s.locator('[data-pjm-attn-empty]')).toContainText('No attention item matches')
  })

  test('the full list is one link to Scheduled jobs', async ({ page }) => {
    const s = await openDelivery(page)
    await expect(s.locator('[data-pjm-open-full]')).toHaveAttribute('href', /#scheduled-jobs/)
  })
})

test.describe('Scheduled jobs › Automations: job and lane monitoring', () => {
  test('reads admin_pim_jobs_v1 once per visit, shows freshness, state counts and the first page of 20 sorted most severe first', async ({ page }) => {
    const { m, c } = await openMonitor(page)
    await expect(m.locator('[data-pjm-as-at]')).toBeVisible()
    await expect(m.locator('[data-pjm-count]')).toContainText('35 of 35')
    const rows = m.locator('[data-pjm-row]')
    await expect(rows).toHaveCount(20)
    await expect(rows.first()).toHaveAttribute('data-pjm-row-state', 'degraded')
    await expect(rows.first()).toContainText('stalled: no run for 3 schedule periods')
    const reads = c.calls
    expect(reads, 'the snapshot is read on entry').toBeGreaterThanOrEqual(1)
    await m.locator('[data-pjm-search]').fill('filler')
    await m.getByLabel('State').selectOption('active')
    await m.locator('.pjm-pager button', { hasText: 'Next' }).click()
    expect(c.calls, 'searching, filtering and paging are done on the loaded snapshot, never another read').toBe(reads)
  })

  test('pagination moves through every component without showing them all at once', async ({ page }) => {
    const { m } = await openMonitor(page)
    await expect(m.locator('.pjm-pager')).toContainText('Page 1 of 2')
    await m.locator('.pjm-pager button', { hasText: 'Next' }).click()
    await expect(m.locator('[data-pjm-row]')).toHaveCount(15)
    await expect(m.locator('.pjm-pager')).toContainText('Page 2 of 2')
  })

  test('search and filters narrow the list, show how many match and clear again', async ({ page }) => {
    const { m } = await openMonitor(page)
    await m.locator('[data-pjm-search]').fill('logo')
    await expect(m.locator('[data-pjm-row]')).toHaveCount(1)
    await expect(m.locator('[data-pjm-count]')).toContainText('1 of 35 components match')
    await m.locator('[data-pjm-clear]').click()
    await expect(m.locator('[data-pjm-row]')).toHaveCount(20)
    await m.getByLabel('Type').selectOption('lane')
    await expect(m.locator('[data-pjm-row]')).toHaveCount(2)
    await m.getByLabel('Type').selectOption('')
    await m.getByLabel('Finding').selectOption('circuit_open')
    await expect(m.locator('[data-pjm-row]')).toHaveCount(1)
    await m.locator('[data-pjm-clear]').click()
    await m.getByLabel('24 h outcome').selectOption('deferred')
    await expect(m.locator('[data-pjm-row]')).toHaveCount(1)
    await m.locator('[data-pjm-state="shadow"] button').click()
    await expect(m.locator('[data-pjm-empty]')).toContainText('No component matches')
    await m.locator('[data-pjm-empty] button').click()
    await expect(m.locator('[data-pjm-row]')).toHaveCount(20)
  })

  test('the drill-down shows reason, heartbeat, last and next run, outcome classes, duration and average time; unrecorded figures say so, never 0', async ({ page }) => {
    const { m } = await openMonitor(page)
    const key = 'rollup:coursefinder-data-quality-overview-refresh'
    await m.locator(`[data-pjm-toggle="${key}"]`).click()
    const d = m.locator(`[data-pjm-detail="${key}"]`)
    await expect(d).toContainText('stalled: no run for 3 schedule periods')
    await expect(d).toContainText('Heartbeat')
    await expect(d).toContainText('Next run')
    await expect(d.getByText('in 10 min'), 'a future time reads as a wait, not the date twice').toBeVisible()
    await expect(d.locator('[data-pjm-window="24 hours"] [data-pjm-outcome="deferred"]')).toHaveText('910')
    await expect(d.locator('[data-pjm-window="7 days"] [data-pjm-outcome="unmeasured"]')).toHaveText('100')
    await expect(d.locator('[data-pjm-window="24 hours"]')).toContainText('1.4 s')
    await expect(d).toContainText('9 s')
    await m.locator(`[data-pjm-toggle="${key}"]`).click()
    await expect(d).toHaveCount(0)
    await m.locator('[data-pjm-toggle="cron:41"]').click()
    const j = m.locator('[data-pjm-detail="cron:41"]')
    await expect(j).toContainText('timed out')
    await expect(j.locator('.pjm-nr').first()).toBeVisible()
    await expect(j.locator('[data-pjm-window="24 hours"]')).toContainText('0')
  })

  test('labels are the backend\'s own words: an idle component stays Idle, a held one carries its reason, a shadow one says Shadow', async ({ page }) => {
    const { m } = await openMonitor(page)
    await m.locator('[data-pjm-clear]').count()
    await m.getByLabel('Type').selectOption('lane')
    await expect(m.locator('[data-pjm-row-state="idle"]')).toContainText('idle by design: nothing queued')
    await expect(m.locator('[data-pjm-row-state="held"]')).toContainText('held: budget gate')
    await m.getByLabel('Type').selectOption('rule')
    await expect(m.locator('[data-pjm-row-state="shadow"]')).toContainText('Shadow')
  })

  test('the AI table does not present the backend\'s not-OK count, and the spend note states it is not split per component', async ({ page }) => {
    const { m } = await openMonitor(page)
    await m.locator('[data-pjm-toolset] summary').click()
    await expect(m.locator('[data-pjm-toolset]')).toContainText('not split per component')
    await expect(m.locator('[data-pjm-ai-note]')).toContainText('not shown')
    await expect(m.locator('[data-pjm-toolset]')).not.toContainText('Not OK')
  })

  test('a failed read shows the error with Try again; a not-yet-counted snapshot says so', async ({ page }) => {
    const bad = await openMonitor(page, { jobs: 'fail' })
    await expect(bad.m.locator('[data-pjm-read-error]')).toContainText('jobs read unavailable')
    await expect(bad.m.locator('[data-pjm-read-error] button')).toBeVisible()
  })

  test('a snapshot that has not been counted yet says so instead of showing 0', async ({ page }) => {
    const { m } = await openMonitor(page, { jobs: JOBS_NOT_COUNTED })
    await expect(m.locator('[data-pjm-not-counted]')).toContainText('not counted the jobs yet')
    await expect(m.locator('[data-pjm-row]')).toHaveCount(0)
  })

  test('a stale snapshot (last count failed) keeps the last good figures and says Stale with the reason', async ({ page }) => {
    const { m } = await openMonitor(page, { jobs: { ...JOBS, error: 'statement timeout', failed_at: '2026-11-26T11:55:00+00:00' } })
    await expect(m.locator('[data-pjm-fresh]')).toContainText('Stale')
    await expect(m.locator('[data-pjm-error]')).toHaveText('statement timeout')
    await expect(m.locator('[data-pjm-row]')).toHaveCount(20)
  })
})
