// Guards: Platform Admin directive 10 Nov 2026 14:02 (AER source recovery: the EXISTING Data Delivery panel shows eligible providers, sources recovered, remaining gaps by route, parked holds, last and next run and blockers): a figure the server did not send is Not measured, never 0.
// Desktop project (chromium-desktop). Mocked admin; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockDataDelivery, DATA_DELIVERY } from './support/data-delivery-mock.mjs'

const OPERATIONS = '/#layer-2-discovery?tab=operations'
const AER = {
  known: true, counted_at: new Date().toISOString(), unit: 'providers',
  coverage: { eligible: 1180, with_source: 640, source_read: 610, with_active_rows: 120, waiting_for_layer4: 90, active_course_rows: 1304, active_matrix_rows: 663, proposed_course_rows: 310, counted_at: new Date().toISOString() },
  sources: { total: 700, by_status: { read: 610 }, stored_find: { switch_on: false, providers_checked: 0, sources_attached: 0 } },
  gaps: [
    { route: 'course_pages_waiting', providers: 875, courses_waiting: 7746, parked: false, example_reason: '12 course pages are stored', next_action: 'Scheduled entry reading reads them while Layer 4 has room.' },
    { route: 'nothing_stored', providers: 373, courses_waiting: null, parked: true, example_reason: 'Nothing is stored to read', next_action: 'Parked. A new page search or a person adds the page.' }],
  other_findings: [{ cause: 'source_unreadable', findings: 12 }],
  parked: { items: 213, by_rule: [{ class: 'aer_row_limit', items: 151, providers: 20, reason: 'row limit', next_action: 'Platform Admin sets a row limit' }] },
  last_run: { ran_at: new Date().toISOString(), course_reads: 0, corrections: 0, matrix_pages: 0, layer4_waiting: 605, back_pressure: true, parked_not_counted: 213 },
  jobs: [{ job: 'aer-scheduled-read', active: true, schedule: '13 * * * *', next_run: new Date(Date.now() + 3600e3).toISOString() }, { job: 'aer-source-stored-find', active: false, schedule: '37 * * * *', next_run: null }],
  blockers: ['Layer 4 is full for entry requirements: 605 items waiting against the limit of 600 (parked holds not counted: 213)'],
}
const withAer = (aer_sources) => ({ ...DATA_DELIVERY, streams: [...DATA_DELIVERY.streams, { ...DATA_DELIVERY.streams[0], stream: 'aer', title: 'Academic entry requirements (AER)', provider_ai: undefined, stages: undefined, aer_sources }] })
async function open(page, payload) {
  await mockAdmin(page); await mockLaneFunnels(page); await mockDataDelivery(page, payload)
  await page.goto(OPERATIONS)
  await expect(page.locator('[data-dd-stream="aer"]')).toBeVisible({ timeout: 20_000 })
}

test('AER: eligible providers, sources, remaining gaps by route, parked holds with their reason, last and next run, blockers', async ({ page }) => {
  await open(page, withAer(AER))
  const box = page.locator('[data-dd-stream="aer"] [data-dd-aer-sources="known"]')
  await expect(page.locator('[data-dd-stream="aer"]')).toHaveAttribute('open', '')
  await expect(box.locator('[data-dd-stage-n="aer_eligible"]')).toHaveText('1,180')
  await expect(box.locator('[data-dd-stage-n="aer_with_source"]')).toHaveText('640')
  await expect(box.locator('[data-dd-stage-n="aer_with_active"]')).toHaveText('120')
  await expect(box.locator('[data-dd-stage-n="aer_active_course_rows"]')).toHaveText('1,304')
  await expect(box.locator('[data-dd-aer-stored-find]')).toContainText('off')
  await expect(box.locator('[data-dd-aer-gap="course_pages_waiting"]')).toContainText('875')
  await expect(box.locator('[data-dd-aer-gap="course_pages_waiting"]')).toContainText('7,746 courses')
  await expect(box.locator('[data-dd-aer-gap="nothing_stored"]')).toContainText('Parked')
  await expect(box.locator('[data-dd-aer-parked] li').first()).toContainText('row limit'); await expect(box.locator('[data-dd-aer-parked] li').first()).toContainText('151')
  await expect(box.locator('[data-dd-aer-last-run]')).toContainText('parked not counted 213')
  await expect(box.locator('[data-dd-aer-jobs]')).toContainText('paused')
  await expect(box.locator('[data-dd-aer-blockers]')).toContainText('Layer 4 is full')
})

test('AER: a missing block or a count that failed is Not measured as a whole; a missing figure is Not measured, never 0', async ({ page }) => {
  await open(page, withAer(undefined))
  await expect(page.locator('[data-dd-aer-sources="unknown"]')).toContainText('Not measured')
  const p2 = await page.context().newPage()
  await mockAdmin(p2); await mockLaneFunnels(p2); await mockDataDelivery(p2, withAer({ known: false, reason: 'canceling statement due to statement timeout' }))
  await p2.goto(OPERATIONS)
  await expect(p2.locator('[data-dd-aer-sources="unknown"]')).toContainText('statement timeout', { timeout: 20_000 })
  const p3 = await page.context().newPage()
  await mockAdmin(p3); await mockLaneFunnels(p3); await mockDataDelivery(p3, withAer({ ...AER, coverage: { eligible: 1180 }, last_run: {}, gaps: [] }))
  await p3.goto(OPERATIONS)
  const box = p3.locator('[data-dd-aer-sources="known"]')
  await expect(box).toBeVisible({ timeout: 20_000 })
  await expect(box.locator('[data-dd-stage-n="aer_with_source"]')).toHaveText('Not measured')
  await expect(box.locator('[data-dd-aer-last-run]')).toContainText('Not measured')
})
