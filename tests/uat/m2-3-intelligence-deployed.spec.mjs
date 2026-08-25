import { test, expect } from '@playwright/test'
import {
  attachRuntimeEvidence,
  assertNoServerErrors,
  loginAsUatUser,
  milestoneScreenshot,
  observeRuntime,
  writeRunEnvironment,
} from './support/runtime-evidence.mjs'

async function finish(testInfo, runtime) {
  await attachRuntimeEvidence(testInfo, runtime)
  assertNoServerErrors(runtime)
}

async function openWorkspace(page) {
  await loginAsUatUser(page)
  const launcher = page.getByRole('button', { name: /M2\.3 Intelligence/i })
  await expect(launcher).toBeVisible({ timeout: 45_000 })
  await launcher.click()
  await expect(page.getByRole('dialog', { name: 'M2.3 Intelligence' })).toBeVisible()
}

test.describe('CourseFinder deployed M2.3 intelligence acceptance @deployed', () => {
  test.beforeAll(async () => {
    if (!process.env.UAT_BASE_URL) throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    if (!process.env.UAT_EMAIL || !process.env.UAT_PASSWORD) throw new Error('UAT_EMAIL and UAT_PASSWORD are required for deployed acceptance.')
    await writeRunEnvironment({ suite: 'deployed-m2-3-intelligence', change_control: 'CF-CHG-20260825-038' })
  })

  test('governed Layer 3 profile is visible and remains paused before provider benchmark', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      await openWorkspace(page)
      await expect(page.getByText('openrouter-free-router-v1', { exact: true })).toBeVisible()
      await expect(page.getByText('Paused', { exact: true })).toBeVisible()
      await expect(page.getByText(/Pending Credentials And Benchmark/i)).toBeVisible()
      await expect(page.getByText(/Unchanged Evidence is rejected before an LLM call/i)).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'm2-3-layer3-paused-profile')
    } finally {
      await finish(testInfo, runtime)
    }
  })

  test('terminal Layer 4 and refresh intelligence workspaces are exposed without hidden approval UI', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      await openWorkspace(page)
      await page.getByRole('button', { name: 'Layer 4', exact: true }).click()
      await expect(page.getByRole('heading', { name: 'Terminal human resolution', exact: true })).toBeVisible()
      await page.getByRole('button', { name: 'Refresh', exact: true }).click()
      await expect(page.getByRole('heading', { name: 'Source/entity freshness policies', exact: true })).toBeVisible()
      await expect(page.getByRole('heading', { name: 'Targeted refresh queue', exact: true })).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'm2-3-layer4-refresh')
    } finally {
      await finish(testInfo, runtime)
    }
  })

  test('Important Links and Important Dates retain governance messaging', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      await openWorkspace(page)
      await page.getByRole('button', { name: 'Important Links', exact: true }).click()
      await expect(page.getByRole('heading', { name: 'Important Links directory', exact: true })).toBeVisible()
      await page.getByRole('button', { name: 'Important Dates', exact: true }).click()
      await expect(page.getByRole('heading', { name: 'Important Dates registry', exact: true })).toBeVisible()
      await expect(page.getByText(/Vague wording is retained as vague; an exact timestamp is never manufactured/i)).toBeVisible()
      await expect(page.getByText(/Country-reference events cannot trigger ingestion/i)).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'm2-3-important-links-dates')
    } finally {
      await finish(testInfo, runtime)
    }
  })
})
