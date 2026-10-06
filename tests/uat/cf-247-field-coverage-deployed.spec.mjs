import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment, clickPrimaryNav } from './support/runtime-evidence.mjs'

async function finish(testInfo, runtime) { await attachRuntimeEvidence(testInfo, runtime); assertNoServerErrors(runtime) }

test.describe('CF-247 per-field coverage panel @deployed', () => {
  test.beforeAll(async () => { await writeRunEnvironment({ suite: 'cf-247-field-coverage', change_control: 'CF-CHG-20260915-247' }) })

  test('Coverage > Attributes opens with the 80% target panel for intakes, English and fees', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      await loginAsUatUser(page)
      await clickPrimaryNav(page, 'Completeness')
      await page.locator('.cf-page-tabs [role="tab"]').filter({ hasText: 'Attributes' }).first().click({ timeout: DETERMINISTIC_UI_TIMEOUT })
      const panel = page.locator('[data-field-target]')
      await expect(panel.getByRole('heading', { name: /Coverage against the 80% target, by field/ })).toBeVisible({ timeout: DETERMINISTIC_UI_TIMEOUT })
      for (const label of ['Intakes / start dates', 'English requirements', 'Provider tuition (fee year)']) await expect(panel.getByText(label).first()).toBeVisible()
      await expect(panel.locator('.cc-target')).toHaveCount(3)
      await expect(panel.locator('tbody tr')).toHaveCount(3)
      await milestoneScreenshot(page, testInfo, 'cf247-field-coverage-panel')
    } finally { await finish(testInfo, runtime) }
  })
})
