// Guards: CF-247 F-AER.05 (feature acceptance contract: the academic entry requirements university drill-down shows pending, readiness, next action and its owner, and links to the source, and it works on a phone) and F-OPS.04 (admin drill-down on desktop and phone; a drill-down is read-only)
// These tests run on the phone project only (chromium-mobile, Pixel 7, 412 px; `@responsive`). Each first asserts it really is at phone width.
// Mocked admin (tests/uat/support/admin-mock.mjs); nothing reaches a real backend. The desktop behaviour of the panel is held by s222.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

const PHONE_MAX = 480
async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

const P_RMIT = 'p-rmit', P_DEAKIN = 'p-deakin'
const COVERAGE = {
  as_at: '2026-11-08T05:27:10Z', day: '2026-11-08', job: { active: true, schedule: '27 * * * *' },
  measures: [
    { country: 'ALL', eligible: 1476, discovery_n: 33, extraction_n: 28, admission_n: 7, consumer_n: 21, open_p0: 0, open_p1: 14, open_p2: 1470, detail: {} },
    { country: 'AU', eligible: 1279, discovery_n: 18, extraction_n: 13, admission_n: 2, consumer_n: 6, open_p0: 0, open_p1: 13, open_p2: 1273, detail: {} },
    { country: 'NZ', eligible: 197, discovery_n: 15, extraction_n: 15, admission_n: 5, consumer_n: 15, open_p0: 0, open_p1: 1, open_p2: 197, detail: {} }],
  progress: [], open: { P0: 0, P1: 14, P2: 1470 }, changes_7d: { opened: 0, resolved: 0, reopened: 0 },
  root_causes: [{ code: 'no_source', label: 'No official AER source recorded', severity: 'P2', providers: 1442, findings: 1442, next_action: 'Discovery waves from stored copies, ordered by course count.', owner_role: 'Pipeline Operator' }],
  population: { eligible: 1476, first_run: false, joined: [], left: [], by_country: { AU: { eligible: 1279, baseline: 1279, delta: 0 }, NZ: { eligible: 197, baseline: 197, delta: 0 } } },
  dispositions: { not_discovered: 1427, source_held: 6, awaiting_layer4: 20, active_verified: 13 },
  providers: { total: 1476, offset: 0, page_size: 50, items: [
    { provider_id: P_RMIT, name: 'RMIT University (RMIT)', country: 'AU', priority: 1, disposition: 'source_held', discovery: 'source_read', extraction: 'held', admission: 'active', p0: 0, p1: 8, p2: 1, sources: 36,
      next_action: 'Classify qualification pages (IB, GAC) and read them as qualification rows.', owner_role: 'PIM Admin', primary_url: 'https://www.rmit.edu.au/' },
    { provider_id: P_DEAKIN, name: 'Deakin University (Deakin)', country: 'AU', priority: 7, disposition: 'not_discovered', discovery: 'not_discovered', extraction: 'none', admission: 'none', p0: 0, p1: 0, p2: 1, sources: 0,
      next_action: 'Discovery waves from stored copies, ordered by course count.', owner_role: 'Pipeline Operator' }] },
  alerts: [], weekly_email: false, readiness: { awaiting_human_review: 539 },
}
const DETAIL = { active: { rows: 380, countries: ['IN', 'NP'], qualifications: 40 }, course: { active: 1303, proposed: 807 },
  sources: [{ id: 's-uk', url: 'https://www.rmit.edu.au/uk', title: 'RMIT country equivalency: united-kingdom', status: 'read', shape: 'country_table', reason: 'held_incomplete: 2 of 31 published minimums not read' }],
  findings: [{ id: 1, severity: 'P1', state: 'open', label: 'Published minimums not read', scope: 'RMIT country equivalency: united-kingdom', next_action: 'Extend the table reader', owner_role: 'PIM Admin', reopen_count: 0, first_seen: '2026-11-02T05:27:00Z', last_seen: '2026-11-02T05:27:00Z' }] }

async function openPanel(page, calls) {
  await mockAdmin(page)
  await page.route('**/rest/v1/rpc/admin_aer', (route) => {
    const b = route.request().postDataJSON() || {}; calls.push(b.p_action)
    if (b.p_action === 'coverage_provider') return route.fulfill({ json: DETAIL })
    return route.fulfill({ json: COVERAGE })
  })
  await page.goto('/#coverage?tab=attributes')
  const panel = page.locator('[data-aer-coverage]')
  await expect(panel).toContainText('Academic entry requirements')
  return panel
}

test.describe('academic entry requirements university drill-down on a phone @responsive', () => {
  test('the four measures and the provider list read inside the screen: the page does not scroll sideways and the measures are whole', async ({ page }) => {
    await atPhoneWidth(page)
    const panel = await openPanel(page, [])
    await expect(panel.locator('[data-aer-measure="discovery_n"]')).toContainText('33 of 1,476')
    await expect(panel.locator('[data-aer-measure="consumer_n"]')).toContainText('21 of 1,476')
    await expect(panel.locator(`[data-aer-provider="${P_RMIT}"] [data-aer-disp]`)).toHaveText('Source held')
    await expect(panel.locator(`[data-aer-provider="${P_RMIT}"]`)).toContainText('PIM Admin')
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('opening a university on a phone shows its sources, findings, next action and owner, and asks the server for reads only', async ({ page }) => {
    await atPhoneWidth(page)
    const calls = []
    const panel = await openPanel(page, calls)
    const link = panel.getByRole('button', { name: 'RMIT University (RMIT)' })
    await link.scrollIntoViewIfNeeded()
    const box = await link.boundingBox()
    expect(box, 'the university name is a tap target with a box').toBeTruthy()
    expect(box.height, 'university name tap target (44 px, as the lane funnels)').toBeGreaterThanOrEqual(44)
    await link.click()
    const detail = panel.locator('[data-aer-provider-detail]')
    await expect(detail).toBeVisible()
    await expect(detail).toContainText('380 rows')
    await expect(detail.locator('[data-aer-source="s-uk"] a')).toHaveAttribute('href', 'https://www.rmit.edu.au/uk')
    await expect(detail.locator('[data-aer-finding="open"]')).toContainText('Published minimums not read')
    await expect(detail).toContainText('2 of 31 published minimums not read')
    // the drill-down sits inside the screen and decided nothing: only the coverage reads were asked for
    await detail.scrollIntoViewIfNeeded()
    const db = await detail.boundingBox()
    expect(db.x).toBeGreaterThanOrEqual(-1)
    expect(db.x + db.width).toBeLessThanOrEqual(page.viewportSize().width + 1)
    for (const a of calls) expect(['coverage', 'coverage_provider']).toContain(a)
    expect(calls).toContain('coverage_provider')
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('a university with nothing open reads as such, and closing the drill-down on a phone removes it', async ({ page }) => {
    await atPhoneWidth(page)
    const panel = await openPanel(page, [])
    await expect(panel.locator(`[data-aer-provider="${P_DEAKIN}"]`)).toContainText('Not discovered')
    const link = panel.getByRole('button', { name: 'RMIT University (RMIT)' })
    await link.click()
    await expect(panel.locator('[data-aer-provider-detail]')).toBeVisible()
    await link.click()
    await expect(panel.locator('[data-aer-provider-detail]')).toHaveCount(0)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })
})
