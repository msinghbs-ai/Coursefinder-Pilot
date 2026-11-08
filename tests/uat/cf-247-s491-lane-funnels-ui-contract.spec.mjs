// Guards: CF-247 OPS/UI mandate (Platform Admin 8 Nov 2026 14:06): every autonomous lane has a funnel on the existing Operations screen (state, next/last run, stage counts, 24 h gains, oldest age, human review, controls with a reason), a green job / stage transfer / published data are three different measures, unknown shows "unknown" never 0, and Firecrawl allowance, live remaining, floor and daily shares show in credits on the existing Services screen
// Desktop project (chromium-desktop). Mocked admin (tests/uat/support/admin-mock.mjs plus lane-funnel-mock.mjs); nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockLaneFunnels } from './support/lane-funnel-mock.mjs'

const OPERATIONS = '/#layer-2-discovery?tab=operations'

test.describe('lane funnels on Operations', () => {
  test('each lane is a row with state, last attempt, transfer, published and waiting-for-a-person figures; unknown is the word unknown, not 0', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page)
    await page.goto(OPERATIONS)
    const root = page.locator('[data-lane-funnels]')
    await expect(root).toBeVisible()
    await expect(root.locator('[data-lf-lane]')).toHaveCount(3)
    const fee = root.locator('[data-lf-lane="fee"]')
    await expect(fee).toHaveAttribute('data-lf-verdict', 'green_no_transfer')
    // the fee lane's job is green but nothing was admitted: transfer is a real 0, published was not counted: unknown
    await expect(fee.locator('[data-lf-transfer]')).toHaveAttribute('data-lf-transfer', '0')
    await expect(fee.locator('[data-lf-published]')).toHaveAttribute('data-lf-published', 'unknown')
    await expect(fee.locator('[data-lf-published]')).toHaveText('unknown')
    await expect(root.locator('[data-lf-lane="aer"] [data-lf-transfer]')).toHaveAttribute('data-lf-transfer', '14')
    await expect(root.locator('[data-lf-stamp]')).toContainText('1 stage not counted (unknown)')
  })

  test('a lane opens to the three measures kept apart, its stages (with the stalled and the never-counted stage marked), the budget and the issues', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page)
    await page.goto(OPERATIONS)
    const aer = page.locator('[data-lf-lane="aer"]')
    await aer.locator('summary').click()
    const three = aer.locator('[data-lf-three]')
    await expect(three).toContainText('Job result')
    await expect(three).toContainText('Stage transfer')
    await expect(three).toContainText('Published (24 h)')
    await expect(aer.locator('[data-lf-budget]')).toContainText('credits')
    await expect(aer.locator('[data-lf-budget]')).not.toContainText('$')
    await expect(aer.locator('[data-lf-issues]')).toContainText('IQ-00313')
    const fee = page.locator('[data-lf-lane="fee"]')
    await fee.locator('summary').click()
    const unc = fee.locator('[data-lf-stage="uncounted"]')
    await expect(unc.locator('[data-lf-n]')).toHaveAttribute('data-lf-n', 'unknown')
    await expect(unc.locator('[data-lf-gain]')).toHaveAttribute('data-lf-gain', 'unknown')
    // withdrawals sit beside gains
    await expect(fee.locator('[data-lf-stage="withdrawn"]')).toBeVisible()
    await expect(fee.locator('[data-lf-stage="human"] [data-lf-drill]')).toHaveAttribute('href', /layer-4/)
    const sch = page.locator('[data-lf-lane="sch"]')
    await sch.locator('summary').click()
    await expect(sch.locator('[data-lf-stage="sch_eligibility"]')).toContainText('Stalled')
  })

  test('switches show on / off / unknown and settings link to the existing Settings screen', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page)
    await page.goto(OPERATIONS)
    const fee = page.locator('[data-lf-lane="fee"]')
    await fee.locator('summary').click()
    await expect(fee.locator('[data-lf-switch="fees.course_pages"]')).toContainText('Off')
    await expect(fee.locator('[data-lf-switch="fees.identity_gate_on"]')).toContainText('Unknown')
    await expect(fee.locator('[data-lf-setting="fees.batch"]')).toContainText('1 to 200')
    await expect(fee.locator('[data-lf-settings-link]')).toHaveAttribute('href', /environment|settings/)
  })

  test('pause, resume and run now use the audited control with a reason; a reason is required; the rank gates the buttons', async ({ page }) => {
    await mockAdmin(page, { rank: 6 }); const calls = await mockLaneFunnels(page)
    await page.goto(OPERATIONS)
    const fee = page.locator('[data-lf-lane="fee"]')
    await fee.locator('summary').click()
    // no reason: nothing is sent
    page.once('dialog', (d) => d.dismiss())
    await fee.locator('[data-lf-job="fee-reader"]').getByRole('button', { name: 'Pause' }).click()
    expect(calls).toHaveLength(0)
    page.once('dialog', (d) => d.accept('Fee reader paused while the rule is checked'))
    await fee.locator('[data-lf-job="fee-reader"]').getByRole('button', { name: 'Pause' }).click()
    await expect.poll(() => calls.length).toBe(1)
    expect(calls[0]).toMatchObject({ p_job: 'fee-reader', p_action: 'pause' })
    expect(calls[0].p_args.reason).toContain('Fee reader paused')
    await expect(fee.locator('[data-lf-job="fee-period-settle"]').getByRole('button', { name: 'Resume' })).toBeVisible()
    await expect(fee.locator('[data-lf-job="fee-period-settle"]').getByRole('button', { name: 'Run now' })).toHaveCount(0)
  })

  test('a Curator (rank 3) can read every lane but has no pause, resume or run-now button', async ({ page }) => {
    await mockAdmin(page, { rank: 3 }); await mockLaneFunnels(page)
    await page.goto(OPERATIONS)
    const fee = page.locator('[data-lf-lane="fee"]')
    await fee.locator('summary').click()
    await expect(fee.locator('[data-lf-jobs] button')).toHaveCount(0)
    await expect(fee.locator('[data-lf-jobs]')).toContainText('Rank 5 or above')
  })

  test('the panel is absent (not an empty frame) when the server returns no lanes', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page, { lanes: { at: new Date().toISOString(), lanes: [] } })
    await page.goto(OPERATIONS)
    await expect(page.locator('[data-lane-funnels]')).toHaveCount(0)
  })
})

test.describe('Firecrawl allowance and spend on Services', () => {
  test('allowance, live remaining (flagged when above plan), last sync, floor, daily shares and usage show in credits, never money', async ({ page }) => {
    await mockAdmin(page); await mockLaneFunnels(page)
    await page.goto('/#models-services?tab=firecrawl')
    const card = page.locator('[data-fc-acceptance]')
    await expect(card).toBeVisible()
    await card.getByRole('button', { name: /Firecrawl allowance and spend/ }).click()
    await expect(card.locator('[data-fc-tile="allowance"]')).toContainText('100,000 credits')
    await expect(card.locator('[data-fc-tile="remaining"]')).toContainText('100,228 credits')
    await expect(card.locator('[data-fc-tile="remaining"]')).toContainText('more credits left than the plan allowance')
    await expect(card.locator('[data-fc-tile="sync"]')).toContainText('firecrawl-credit')
    await expect(card.locator('[data-fc-floor]')).toContainText('20,000')
    await expect(card.locator('[data-fc-group="course_search"]')).toContainText('1,776')
    await expect(card.locator('[data-fc-group="reads"]')).toContainText('1,047')
    await expect(card.locator('[data-fc-usage-group="scholarships"]')).toContainText('unknown')
    await expect(card.locator('[data-fc-purposes]')).toContainText('scrape')
    await expect(card).not.toContainText(/\$|AUD|USD/)
  })
})
