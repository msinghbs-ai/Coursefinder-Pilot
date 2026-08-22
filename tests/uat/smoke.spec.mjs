import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

test.describe('CourseFinder local browser smoke @smoke', () => {
  test('login shell renders without a server-side failure', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      await writeRunEnvironment({ suite: 'local-smoke' })
      await page.goto('/')
      await expect(page.locator('input[type="email"]').first()).toBeVisible()
      await expect(page.locator('input[type="password"]').first()).toBeVisible()
      await expect(page.getByRole('button', { name: /^sign in$/i })).toBeVisible()
      expect(runtime.serverErrors, `Unexpected HTTP 5xx responses: ${JSON.stringify(runtime.serverErrors)}`).toEqual([])
    } finally {
      await attachRuntimeEvidence(testInfo, runtime)
    }
  })
})
