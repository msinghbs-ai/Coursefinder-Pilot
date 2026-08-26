import { test, expect } from '@playwright/test'
import {
  attachRuntimeEvidence,
  assertNoServerErrors,
  clickPrimaryNav,
  loginAsUatUser,
  milestoneScreenshot,
  observeRuntime,
  writeRunEnvironment,
} from './support/runtime-evidence.mjs'

async function finish(testInfo, runtime) {
  await attachRuntimeEvidence(testInfo, runtime)
  assertNoServerErrors(runtime)
}

async function openWorkspace(page, targetTab='Layer 3') {
  await loginAsUatUser(page)
  const navLabel = targetTab === 'Layer 4' ? 'Layer 4 — Human Resolution' : targetTab === 'Onboarding' ? 'Onboarding' : 'Layer 3 — AI Interpretation'
  await clickPrimaryNav(page, navLabel)
  const dialog = page.getByRole('dialog', { name: 'M2.3 Intelligence' })
  await expect(dialog).toBeVisible({ timeout: 45_000 })
  if (!['Layer 3','Layer 4','Onboarding'].includes(targetTab)) {
    await dialog.locator('nav').getByRole('button', { name: targetTab, exact: true }).click()
  }
  return dialog
}

test.describe('CourseFinder deployed M2.3 intelligence acceptance @deployed', () => {
  test.beforeAll(async () => {
    if (!process.env.UAT_BASE_URL) throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    if (!process.env.UAT_EMAIL || !process.env.UAT_PASSWORD) throw new Error('UAT_EMAIL and UAT_PASSWORD are required for deployed acceptance.')
    await writeRunEnvironment({ suite: 'deployed-m2-3-intelligence-v2', change_control: 'CF-CHG-20260825-036/037/038 + CF-CHG-20260826-040' })
  })

  test('governed Layer 3 profile exposes the benchmark-passed pinned model and is executable', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      const dialog = await openWorkspace(page, 'Layer 3')
      const profileCard = dialog.getByRole('article').filter({ hasText: 'openrouter-free-router-v1' })
      await expect(profileCard.getByText('openrouter-free-router-v1', { exact: true })).toBeVisible()
      await expect(profileCard).toContainText('nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free')
      await expect(profileCard.getByText('Enabled', { exact: true })).toBeVisible()
      await expect(profileCard).toContainText(/Validation:\s*Benchmark Passed/i)
      await expect(profileCard.getByRole('button', { name: 'Pause', exact: true })).toBeVisible()
      await expect(dialog.getByText(/Unchanged Evidence is rejected before an LLM call/i)).toBeVisible()
      await expect(dialog.getByText(/Server credentials are never browser-visible/i)).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'm2-3-layer3-benchmark-passed-profile')
    } finally {
      await finish(testInfo, runtime)
    }
  })

  test('terminal Layer 4 and refresh intelligence workspaces expose governed context and bounded targets', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      const dialog = await openWorkspace(page, 'Layer 4')
      const tabs = dialog.locator('nav')
      await expect(dialog.getByRole('heading', { name: 'Terminal human resolution', exact: true })).toBeVisible()
      await expect(dialog.getByPlaceholder(/prioritise unresolved field/i)).toBeVisible()
      await tabs.getByRole('button', { name: 'Refresh', exact: true }).click()
      await expect(dialog.getByRole('heading', { name: 'Source/entity freshness policies', exact: true })).toBeVisible()
      await expect(dialog.getByRole('heading', { name: 'Targeted refresh queue', exact: true })).toBeVisible()
      await expect(dialog.getByRole('heading', { name: 'Downstream Search refresh signals', exact: true })).toBeVisible()
      await expect(dialog.getByText('UNBOUNDED', { exact: true })).toHaveCount(0)
      await milestoneScreenshot(page, testInfo, 'm2-3-layer4-refresh')
    } finally {
      await finish(testInfo, runtime)
    }
  })

  test('Important Links and Important Dates retain source precision and governance messaging', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      const dialog = await openWorkspace(page, 'Important Links')
      const tabs = dialog.locator('nav')
      await expect(dialog.getByRole('heading', { name: 'Important Links directory', exact: true })).toBeVisible()
      await tabs.getByRole('button', { name: 'Important Dates', exact: true }).click()
      await expect(dialog.getByRole('heading', { name: 'Important Dates registry', exact: true })).toBeVisible()
      await expect(dialog.getByText('2026-11-30', { exact: true })).toBeVisible()
      await expect(dialog.getByText('2027-02-22', { exact: true })).toBeVisible()
      await expect(dialog.getByText(/Vague wording is retained as vague; an exact timestamp is never manufactured/i)).toBeVisible()
      await expect(dialog.getByText(/Date-only sources use date-only storage/i)).toBeVisible()
      await expect(dialog.getByText(/Country-reference events cannot trigger ingestion/i)).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'm2-3-important-links-dates')
    } finally {
      await finish(testInfo, runtime)
    }
  })

  test('reusable onboarding workspace exposes the accepted lifecycle and governed audit boundary', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      const dialog = await openWorkspace(page, 'Onboarding')
      await expect(dialog.getByRole('heading', { name: 'Country / Provider / Course Onboarding', exact: true })).toBeVisible()
      await expect(dialog.getByText(/Shared canonical lifecycle only/i)).toBeVisible()
      const stage = dialog.getByLabel('Stage')
      for (const value of ['draft','source_qualification','adapter_assessment','schema_assessment','l1_uat','l2_uat','l3_ready','operational_certification','production_promotion_ready']) {
        await expect(stage.getByRole('option', { name: value, exact: true })).toHaveCount(1)
      }
      await expect(dialog.getByRole('heading', { name: 'Create governed onboarding case', exact: true })).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'm2-3-onboarding-lifecycle')
    } finally {
      await finish(testInfo, runtime)
    }
  })
})
