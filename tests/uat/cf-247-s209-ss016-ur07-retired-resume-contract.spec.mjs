// Guards: SS-016 UR-07 acceptance (usability review 1 Nov 2026 §4 UR-07 "Accept"; overnight mandate §4): in fixtures, retired and retiring automations show no Resume, run or schedule controls at ranks 5 and 6; an area Resume never switches them on; a single-job Resume reaching the server from an out-of-date screen is refused with the live words and nothing changes; a paused active automation is resumed. The fixture server refuses as security.admin_automation_control_v1 does (md5 71951aa2, read 1 Nov 2026).
import { test, expect } from '@playwright/test'
import { asRole, mockAutomations, LIVE } from './support/role-fixtures.mjs'

test.describe('mocked browser', () => {
  for (const rank of [5, 6]) {
    test(`rank ${rank}: retired jobs have no controls; area Resume switches on only the paused active job`, async ({ page }) => {
      await asRole(page, rank)
      const auto = await mockAutomations(page, rank)
      page.on('dialog', (d) => d.accept())
      await page.goto('/#scheduled-jobs')
      for (const [job, word, by] of [['l4-rule-low-agreement', 'Retired', 'l4-rule-v2'], ['cron-history-trim', 'Retiring', 'hygiene-check']]) {
        const row = page.locator(`tr[data-job="${job}"]`)
        await expect(row).toContainText(word)
        await expect(row.locator(`[data-retired-job="${job}"]`)).toContainText(`replaced by ${by}`)
        await expect(row.getByRole('button')).toHaveCount(0)
        await expect(row.locator('select, input')).toHaveCount(0)
      }
      const area = page.locator('[data-area="Course pages"]')
      await area.getByRole('button', { name: 'Resume area' }).click()
      await expect(page.locator('tr[data-job="coverage-discover"]')).toContainText('Running')
      await expect(page.locator('tr[data-job="l4-rule-low-agreement"]')).toContainText('Retired')
      expect(auto.jobs.find((j) => j.job === 'l4-rule-low-agreement').active).toBe(false)
      expect(auto.jobs.find((j) => j.job === 'coverage-discover').active).toBe(true)
      expect(auto.calls.map((c) => c.p_action)).toEqual(['resume_area'])
    })
  }

  test('a single-job Resume from an out-of-date screen is refused with the live words; nothing changes; an active paused job resumes', async ({ page }) => {
    await asRole(page, 6)
    const auto = await mockAutomations(page, 6, { staleRetired: ['l4-rule-low-agreement'] })
    await page.goto('/#scheduled-jobs')
    const stale = page.locator('tr[data-job="l4-rule-low-agreement"]')
    await stale.getByRole('button', { name: 'Resume' }).click()
    await expect(page.locator('[data-global-error]')).toContainText(LIVE.RETIRED('l4-rule-v2'))
    expect(auto.jobs.find((j) => j.job === 'l4-rule-low-agreement').active).toBe(false)
    await page.locator('[data-global-error] button[aria-label="Dismiss"]').click()
    const paused = page.locator('tr[data-job="coverage-discover"]')
    await paused.getByRole('button', { name: 'Resume' }).click()
    await expect(paused).toContainText('Running')
    expect(auto.calls.map((c) => `${c.p_job}:${c.p_action}`)).toEqual(['l4-rule-low-agreement:resume', 'coverage-discover:resume'])
  })
})
