// Guards: F-OPS.17 to F-OPS.21 (Platform Admin P0 26 Nov 2026 13:07, "Complete Data Delivery Frontend"): the Autonomous PIM block inside the existing Data Delivery panel shows overall, country and domain coverage, the stage funnel, gains, throughput and measured clearance, last and next processing, scheduler and lease state, AI and Firecrawl use and human interventions from `pim`; a figure that is not counted is labelled, never 0; it adds no control.
// Desktop project (chromium-desktop, 1440 x 900). Mocked admin plus tests/uat/support/pim-mock.mjs; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockPim, PIM, PIM_FIELDS } from './support/pim-mock.mjs'

const OPERATIONS = '/#layer-2-discovery?tab=operations'
async function open(page, opts) {
  await mockAdmin(page); await mockLaneFunnels(page)
  const m = await mockPim(page, opts)
  await page.goto(OPERATIONS)
  const pim = page.locator('[data-dd-pim]')
  await expect(pim).toBeVisible({ timeout: 20_000 })
  await expect(pim.locator('[data-pim-matrix]')).toBeVisible()
  return { pim, ...m }
}

test.describe('Autonomous PIM inside Data Delivery', () => {
  test('it is inside the Data Delivery panel on Operations, not a new tab, and adds no control that changes data', async ({ page }) => {
    const { pim } = await open(page)
    expect(await pim.evaluate((el) => !!el.closest('[data-data-delivery]'))).toBe(true)
    await expect(page.locator('[data-dd-pim]')).toHaveCount(1)
    await expect(pim.locator('input[type=text], textarea, [data-pim-save], [data-pim-apply]')).toHaveCount(0)
    for (const v of ['matrix', 'requests', 'refresh']) await expect(pim.locator(`[data-pim-tab="${v}"]`)).toBeVisible()
  })

  test('overall funnel is the sum over the rows, canonical coverage then work items, with held as review plus no source found', async ({ page }) => {
    const { pim } = await open(page)
    const sum = (k) => PIM_FIELDS.reduce((a, r) => a + (Number(r[k]) || 0), 0)
    const fmt = (n) => n.toLocaleString('en-AU')
    const stages = await pim.locator('[data-pim-funnel] [data-pim-stage]').evaluateAll((els) => els.map((e) => e.getAttribute('data-pim-stage')))
    expect(stages).toEqual(['applicable', 'completed', 'backlog', 'queued', 'running', 'held', 'failed']) // s1218: canonical coverage first, then work items
    await expect(pim.locator('[data-pim-stage="applicable"] strong')).toHaveText(fmt(sum('applicable')))
    await expect(pim.locator('[data-pim-stage="backlog"] strong')).toHaveText(fmt(sum('backlog')))
    await expect(pim.locator('[data-pim-stage="held"] strong')).toHaveText(fmt(sum('review') + sum('no_source_found')))
    await expect(pim.locator('[data-pim-stage="completed"] strong')).toHaveText(fmt(sum('held')))
    await expect(pim.locator('[data-pim-funnel-note]')).toContainText('not parts of the backlog')
  })

  test('country selector comes from the rows, narrows the funnel to that country, and names the country', async ({ page }) => {
    const { pim } = await open(page)
    const options = await pim.locator('[data-pim-country] option').allTextContents()
    expect(options[0]).toBe('All countries')
    expect(options.length - 1).toBe(new Set(PIM_FIELDS.map((r) => r.country)).size)
    await pim.locator('[data-pim-country]').selectOption('NZ')
    const nz = PIM_FIELDS.filter((r) => r.country === 'NZ')
    await expect(pim.locator('[data-pim-stage="applicable"] strong')).toHaveText(nz.reduce((a, r) => a + r.applicable, 0).toLocaleString('en-AU'))
    await expect(pim.locator('[data-pim-scope]')).toContainText('New Zealand')
    await expect(pim.locator('[data-pim-fields] [data-pim-country-row]').first()).toHaveAttribute('data-pim-country-row', 'NZ')
  })

  test('domains come from the field register and the matrix has one row per domain with a column per country', async ({ page }) => {
    const { pim, reg } = await open(page)
    expect(reg.calls).toBe(1)
    const rows = await pim.locator('[data-pim-domain-row]').evaluateAll((els) => els.map((e) => e.getAttribute('data-pim-domain-row')))
    expect(rows).toEqual(expect.arrayContaining(['Entry', 'Course page', 'Dates', 'Location', 'Study', 'Cost']))
    const heads = await pim.locator('[data-pim-matrix] thead th').allTextContents()
    expect(heads).toEqual(expect.arrayContaining(['Domain', 'All countries', 'Australia', 'New Zealand', 'Canada']))
    // CA registered tuition applies to no course: shown as none apply, never 0%
    await expect(pim.locator('[data-pim-domain-row="Cost"] [data-pim-cell="CA"]')).toContainText('None apply')
    await expect(pim.locator('[data-pim-domain-row="Cost"] [data-pim-cell="AU"]')).toContainText('No field of this kind')
  })

  test('the measure switch changes the matrix and a cell opens that country and domain', async ({ page }) => {
    const { pim } = await open(page)
    const entryAll = pim.locator('[data-pim-domain-row="Entry"] [data-pim-cell="all"]')
    await expect(entryAll).toContainText('%')
    await pim.locator('[data-pim-measure]').selectOption('canonical')
    await expect(entryAll).toContainText('Mixed bases') // s1218: entry rows (canonical basis) and English (enrich items) are not added
    await expect(pim.locator('[data-pim-domain-row="Course page"] [data-pim-cell="all"]')).toContainText('+54')
    await pim.locator('[data-pim-measure]').selectOption('backlog')
    await expect(pim.locator('[data-pim-measure-help]')).toContainText('still hold no value')
    await pim.locator('[data-pim-domain-row="Entry"] [data-pim-cell="NZ"]').click()
    await expect(pim.locator('[data-pim-country]')).toHaveValue('NZ')
    await expect(pim.locator('[data-pim-fields-title]')).toContainText('Entry in New Zealand')
    await expect(pim.locator('[data-pim-fields] [data-pim-field="academic_entry"]')).toBeVisible()
  })

  test('clearance is the measured figure, a field with no gain says Not measured with the reason, and no roll-up invents one', async ({ page }) => {
    const { pim } = await open(page)
    await pim.locator('[data-pim-country]').selectOption('AU')
    const row = pim.locator('[data-pim-fields] [data-pim-field="academic_entry"]')
    await pim.locator('[data-pim-domain="Entry"]').click()
    await expect(row.locator('[data-label="Clearance"]')).toContainText('28 d') // 677.1 h
    await pim.locator('[data-pim-domain="Location"]').click()
    const campus = pim.locator('[data-pim-fields] [data-pim-field="campus"]')
    await expect(campus.locator('[data-label="Clearance"] [data-pim-unknown]')).toContainText('Not measured')
    await expect(campus.locator('[data-label="Clearance"]')).toContainText('Nothing gained in the window')
    // the roll-up shows the longest measured field and says how many have no estimate, never a blended guess
    await expect(pim.locator('[data-pim-gains]')).toContainText('longest measured field')
    await expect(pim.locator('[data-pim-clearance]')).toHaveAttribute('data-pim-clearance', '385080')
    await expect(pim.locator('[data-pim-gains]')).toContainText('years')
  })

  test('a scope where nothing was gained shows Not measured for clearance, not 0 or a guess', async ({ page }) => {
    const none = PIM_FIELDS.map((r) => ({ ...r, canonical_gain_window: 0, published_gain_window: 0, throughput_per_hour: 0, clearance_hours: null }))
    const { pim } = await open(page, { pim: { ...PIM, fields: none } })
    await expect(pim.locator('[data-pim-gains] [data-pim-unknown]').filter({ hasText: 'gained a value in the window' })).toContainText('Not measured')
    await expect(pim.locator('[data-pim-clearance]')).toHaveCount(0)
  })

  test('processing: last and next run, jobs, leases with the recovery sentence, and the worker heartbeat is labelled not measured', async ({ page }) => {
    const { pim } = await open(page)
    const p = pim.locator('[data-pim-processing]')
    await expect(p.locator('[data-pim-last-run]')).toBeVisible()
    await expect(p.locator('[data-pim-next-run]')).toBeVisible()
    await expect(p.locator('[data-pim-leases="0"]')).toBeVisible()
    await expect(p).toContainText('taken back by the next worker claim')
    await expect(p).toContainText('Worker heartbeat')
    await expect(p.locator('[data-pim-unknown]').last()).toContainText('Not measured')
    for (const j of ['enrich-plan-run', 'enrich-plan-auto', 'field-gap-queue']) await expect(pim.locator(`[data-pim-job="${j}"]`)).toBeVisible()
  })

  test('AI and Firecrawl use, and the human interventions with a link to Layer 4 Review', async ({ page }) => {
    const { pim } = await open(page)
    await expect(pim.locator('[data-pim-ai-attempts]')).toHaveText('8,554')
    await expect(pim.locator('[data-pim-ai-cost]')).toContainText('4.50')
    await expect(pim.locator('[data-pim-fc-calls]')).toHaveText('781')
    await expect(pim.locator('[data-pim-enrich-review]')).toHaveText('1,838')
    await expect(pim.locator('[data-pim-l4-total]')).toHaveText('944')
    const link = pim.locator('[data-pim-l4] a').first()
    await expect(link).toHaveAttribute('href', /#layer-4-review/)
    await expect(pim.locator('[data-pim-link="layer4"]')).toHaveAttribute('href', /#layer-4-review/)
    await expect(pim.locator('[data-pim-link="jobs"]')).toHaveAttribute('href', /#scheduled-jobs/)
    await expect(pim.locator('[data-pim-link="operations"]')).toHaveAttribute('href', /#layer-2-discovery/)
  })

  test('missing AI spend is Not measured, not $0', async ({ page }) => {
    const { pim } = await open(page, { pim: { ...PIM, ai: { attempts: 10, failed: 1, cost_usd: null } } })
    await expect(pim.locator('[data-pim-consumption] [data-pim-unknown]').first()).toContainText('Not measured')
    await expect(pim.locator('[data-pim-ai-cost]')).toHaveCount(0)
  })

  test('snapshot age is shown, and a failed count keeps the last good figures marked Stale with the error', async ({ page }) => {
    const { pim } = await open(page, { pim: { ...PIM, snapshot_error: 'statement timeout', snapshot_failed_at: '2026-11-26T02:30:00+00:00' } })
    await expect(pim.locator('[data-pim-snapshot-at]')).toBeVisible()
    await expect(pim.locator('[data-pim-snapshot-error]')).toContainText('statement timeout')
    await expect(pim.locator('[data-pim-snapshot-error]')).toContainText('last good figures')
    await expect(pim.locator('[data-pim-stamp] .cf-chip')).toContainText('Stale')
    await expect(pim.locator('[data-pim-stage="applicable"] strong')).not.toHaveText('0')
  })

  test('a read with no pim says Not available and shows no figure', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page)
    const { DATA_DELIVERY, mockDataDelivery } = await import('./support/data-delivery-mock.mjs')
    await mockDataDelivery(page, DATA_DELIVERY)
    await page.goto(OPERATIONS)
    const pim = page.locator('[data-dd-pim]')
    await expect(pim).toBeVisible({ timeout: 20_000 })
    await expect(pim.locator('[data-pim-unknown]')).toContainText('Not available')
    await expect(pim.locator('[data-pim-funnel]')).toHaveCount(0)
  })

  test('if the field register cannot be read the domains fall back to one group and the error is said', async ({ page }) => {
    const { pim } = await open(page, { register: 'fail' })
    await expect(pim.locator('[data-pim-register-error]')).toBeVisible()
    await expect(pim.locator('[data-pim-domain-row]')).toHaveCount(1)
    await expect(pim.locator('[data-pim-stage="applicable"] strong')).toBeVisible()
  })
})

test.describe('Requests & feedback and Refresh & maintenance views', () => {
  test('requests: with no request register read the view says Not available and shows no status, weight or coverage', async ({ page }) => {
    const { pim } = await open(page)
    await pim.locator('[data-pim-tab="requests"]').click()
    const v = pim.locator('[data-pim-panel="requests"]')
    await expect(v.locator('[data-pim-requests-unavailable] [data-pim-unknown]')).toContainText('Not available')
    await expect(v).toContainText('interface 6')
    await expect(v.locator('[data-pim-requests]')).toHaveCount(0)
    await expect(v).toContainText('gap register is never shown')
    await v.locator('[data-pim-goto="matrix"]').click()
    await expect(pim.locator('[data-pim-panel="matrix"]')).toBeVisible()
  })

  test('requests: when the read supplies requests, status sits beside separate coverage figures and a missing figure is Not measured', async ({ page }) => {
    const requests = [{ id: 'WR-12', title: 'Entry requirements', scope: 'academic_entry · AU, NZ', status: 'Partly delivered', weight: 2, canonical_pct: 39.8, consumer_pct: null, fresh_pct: 100, clarification: null }]
    const { pim } = await open(page, { pim: { ...PIM, requests } })
    await pim.locator('[data-pim-tab="requests"]').click()
    const r = pim.locator('[data-pim-request="WR-12"]')
    await expect(r.locator('[data-label="Status"]')).toContainText('Partly delivered')
    await expect(r.locator('[data-label="Canonical coverage"]')).toContainText('39.8%')
    await expect(r.locator('[data-label="Consumer coverage"] [data-pim-unknown]')).toContainText('Not measured')
    await expect(r.locator('[data-label="Freshness"]')).toContainText('100%')
  })

  test('refresh: freshness by field, source outcomes with protected holds, excluded gaps as workload, and the lifecycle tables', async ({ page }) => {
    const { pim } = await open(page)
    await pim.locator('[data-pim-tab="refresh"]').click()
    const v = pim.locator('[data-pim-panel="refresh"]')
    await expect(v.locator('[data-pim-refresh-meaning]')).toContainText('not by country')
    const desc = v.locator('[data-pim-refresh-field="description"]')
    await expect(desc.locator('[data-label="Due to be verified"]')).toHaveText('40')
    await expect(desc.locator('[data-label="Fresh"]')).toContainText('99.8%')
    await expect(v.locator('[data-pim-source="blocked"] [data-label="Protected hold"]')).toHaveText('Yes')
    await expect(v.locator('[data-pim-excluded-meaning]')).toContainText('workload, not delivered data')
    await expect(v.locator('[data-pim-excluded="eligible"] strong')).toHaveText('147,495')
    await expect(v.locator('[data-pim-academic]')).toContainText('refresh (PIM step 5)')
    await expect(v.locator('[data-pim-scholarships]')).toContainText('889')
    await expect(v.locator('[data-pim-replacement]')).toContainText('1,773')
  })

  test('the existing Data Delivery streams and recovery still render beside the PIM block', async ({ page }) => {
    await open(page)
    await expect(page.locator('[data-dd-stream]').first()).toBeVisible()
    await expect(page.locator('[data-dd-refresh]')).toBeVisible()
  })
})
