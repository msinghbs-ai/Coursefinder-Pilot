// Guards: Platform Admin directive 10 Nov 2026 14:02 (the EXISTING Data Delivery panel, stream "Intake dates and deadlines", shows the eligible denominator, new admissions and retained net gain, skipped causes with the legitimately unresolvable kept apart, consumer publication and the blocker; a figure not counted is Not measured, never 0): the screen draws the additive key intake_delivery. Desktop project; mocked admin, nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'
import { mockDataDelivery, DATA_DELIVERY } from './support/data-delivery-mock.mjs'

const OPERATIONS = '/#layer-2-discovery?tab=operations'
const ago = (m) => new Date(Date.now() - m * 60000).toISOString()
/** exactly the shape security.data_delivery_intake_v1() returns (the fixture's own keys) */
const INTAKE_DELIVERY = {
  known: true, counted_at: ago(0), unit: 'intakes',
  denominator: { active_intakes: 31411, exact_start: 1600, with_deadline: 98, undated: 29811, undated_eligible: 13731, undated_no_decision: 16080, eligible: 15331 },
  admissions: {
    windows: [{ hours: 24, gross: 66, withdrawn: 0, net: 66, new_start: 66, retained_start: 66, new_deadline: 1, retained_deadline: 1 }, { hours: 168, gross: 80, withdrawn: 2, net: 78, new_start: 80, retained_start: 78, new_deadline: 1, retained_deadline: 1 }],
    by_rule: [{ rule: 'page-date-v1', filled: 37, withdrawn: 0 }, { rule: 'calendar-v3', filled: 29, withdrawn: 0 }], last_admitted_at: ago(5), last_processed_at: ago(4) },
  skipped: {
    now: [{ k: 'month_only', n: 8000 }, { k: 'identity', n: 3093 }, { k: 'waiting_for_period', n: 1530 }, { k: 'page_date_waiting', n: 600 }, { k: 'page_only_unproven', n: 39 }],
    window_hours: 24, window_events: 1047, window_intakes: 1047, window: [{ k: 'month_only', n: 838 }, { k: 'identity', n: 77 }] },
  publication: { by_state: [{ state: 'published', n: 1603 }, { state: 'not_checked', n: 3 }], last_checked_at: ago(10) },
  switches: { apply_enabled: true, page_date_admit: true },
  blockers: [{ ord: 3, code: 'page_only_unproven', kind: 'decision', n: 39, text: 'The page prints one date that no approved calendar start shares and the audience is not shown. Held for the Platform Admin’s audience rule.' },
             { ord: 4, code: 'identity', kind: 'source', n: 3093, text: 'The page is not proved to be the course’s own (E16). Held until the course identity is proved.' }],
}
const withIntake = (intake_delivery) => ({ ...DATA_DELIVERY, streams: DATA_DELIVERY.streams.map((s) => (s.stream === 'int' ? { ...s, intake_delivery } : s)) })
async function open(page, payload) {
  await mockAdmin(page); await mockLaneFunnels(page); await mockDataDelivery(page, payload)
  await page.goto(OPERATIONS)
  await expect(page.locator('[data-dd-stream]').first()).toBeVisible({ timeout: 20_000 })
}

/** the stream row is a details element: open it if the page has not remembered it open */
async function openStream(page) {
  const s = page.locator('[data-dd-stream="int"]')
  await expect(s).toBeVisible({ timeout: 20_000 })
  if (!(await s.evaluate((el) => el.open))) await s.locator('summary').click()
  return s
}

test.describe('Data delivery: intake dates and deadlines', () => {
  test('the stream shows the eligible denominator, new and retained admissions, skipped causes apart from the unresolvable, publication and blockers', async ({ page }) => {
    await open(page, withIntake(INTAKE_DELIVERY))
    const s = page.locator('[data-dd-stream="int"]')
    await s.locator('summary').click()
    const box = s.locator('[data-dd-intake-delivery="known"]')
    await expect(box).toBeVisible()
    await expect(box.locator('[data-dd-intake-delivery-stamp]')).toContainText('Counted live at')
    const n = (k) => box.locator(`[data-dd-stage-n="${k}"]`)
    for (const [k, v] of Object.entries({ active_intakes: '31,411', exact_start: '1,600', with_deadline: '98', eligible: '15,331', undated_eligible: '13,731', undated_no_decision: '16,080' })) await expect(n(k), k).toHaveText(v)
    await expect(n('new_start_24')).toHaveText('66')
    await expect(box.locator('[data-dd-intake-window="24"]')).toContainText('retained now 66')
    await expect(box.locator('[data-dd-intake-window="168"]')).toContainText('withdrawn 2')
    await expect(box.locator('[data-dd-intake-window="168"]')).toContainText('net 78')
    await expect(box.locator('[data-dd-stage-row="by_rule"]')).toContainText('page-date-v1: 37 filled')
    // skipped: the legitimately unresolvable, what a run can still take, and what is held for another fix are three lines
    await expect(n('skip_unresolvable')).toHaveText('8,000')
    await expect(n('skip_recoverable')).toHaveText('600')
    await expect(n('skip_held')).toHaveText('4,662')
    await expect(box.locator('[data-dd-intake-skips="unresolvable"]')).toContainText('no day')
    await expect(box.locator('[data-dd-intake-skips="recoverable"]')).toContainText('next hourly run')
    await expect(box.locator('[data-dd-route-off]')).toHaveCount(0)
    await expect(n('skip_window')).toHaveText('1,047')
    // publication and blockers
    await expect(box.locator('[data-dd-intake-publication]')).toContainText('published: 1,603')
    await expect(box.locator('[data-dd-blocker="none"]')).toHaveText('None')
    await expect(box.locator('[data-dd-intake-blockers] li')).toHaveCount(2)
    await expect(box.locator('[data-dd-intake-blockers] li').first()).toContainText('Decision')
    await expect(page.locator('[data-dd-intake-delivery]')).toHaveCount(1)   // only the intake stream carries the box
  })

  test('a missing block is Not measured as a whole, a count that failed says why, a missing figure is Not measured and never 0, a switched-off job is the technical blocker', async ({ page }) => {
    await open(page, DATA_DELIVERY)
    const s = page.locator('[data-dd-stream="int"]')
    await s.locator('summary').click()
    await expect(s.locator('[data-dd-intake-delivery="unknown"]')).toContainText('Not measured')
    await expect(s.locator('[data-dd-intake-delivery="unknown"] [data-dd-stage-n]')).toHaveCount(0)
    const p2 = await page.context().newPage()
    await mockAdmin(p2); await mockLaneFunnels(p2); await mockDataDelivery(p2, withIntake({ known: false, reason: 'the intake delivery counts could not be made: canceling statement due to statement timeout' }))
    await p2.goto(OPERATIONS)
    await openStream(p2)
    const failed = p2.locator('[data-dd-stream="int"] [data-dd-intake-delivery="unknown"]')
    await expect(failed).toBeVisible({ timeout: 20_000 })
    await expect(failed).toContainText('could not be made')
    const partial = { ...INTAKE_DELIVERY, denominator: { ...INTAKE_DELIVERY.denominator, eligible: null, undated_no_decision: undefined }, skipped: { ...INTAKE_DELIVERY.skipped, window_events: null },
      switches: { apply_enabled: false, page_date_admit: false },
      blockers: [{ code: 'job_off', kind: 'technical', n: null, text: 'The intake job is switched off (intake_dates.apply_enabled), so nothing is admitted until the Platform Admin switches it on.' }] }
    const p3 = await page.context().newPage()
    await mockAdmin(p3); await mockLaneFunnels(p3); await mockDataDelivery(p3, withIntake(partial))
    await p3.goto(OPERATIONS)
    await openStream(p3)
    const b3 = p3.locator('[data-dd-stream="int"] [data-dd-intake-delivery="known"]')
    await expect(b3).toBeVisible({ timeout: 20_000 })
    for (const k of ['eligible', 'undated_no_decision', 'skip_window']) await expect(b3.locator(`[data-dd-stage-n="${k}"]`), k).toHaveText('Not measured')
    await expect(b3.locator('[data-dd-stage-n="exact_start"]')).toHaveText('1,600')
    await expect(b3.locator('[data-dd-blocker="technical"]')).toContainText('switched off')
    await expect(b3.locator('[data-dd-route-off]')).toContainText('switched off')
  })
})
