import fs from 'node:fs'
import { test, expect } from '@playwright/test'
import {
  attachRuntimeEvidence,
  assertNoServerErrors,
  loginAsUatUser,
  milestoneScreenshot,
  observeRuntime,
  openDataQuality,
  openRegulatoryFeeSourceNull,
  writeRunEnvironment,
} from './support/runtime-evidence.mjs'

const expectations = JSON.parse(fs.readFileSync(new URL('./expectations.json', import.meta.url), 'utf8'))

async function start(page) {
  await loginAsUatUser(page)
  await openDataQuality(page)
}

async function finish(testInfo, runtime) {
  await attachRuntimeEvidence(testInfo, runtime)
  assertNoServerErrors(runtime)
}

test.describe('CourseFinder deployed Data Quality acceptance @deployed', () => {
  test.beforeAll(async () => {
    if (!process.env.UAT_BASE_URL) throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    if (!process.env.UAT_EMAIL || !process.env.UAT_PASSWORD) throw new Error('UAT_EMAIL and UAT_PASSWORD are required for deployed acceptance.')
    await writeRunEnvironment({
      suite: 'deployed-data-quality',
      expected_au_courses: expectations.catalogue.australia_courses,
      expected_au_nz_courses: expectations.catalogue.au_nz_courses,
      expected_all_country_courses: expectations.catalogue.all_country_courses,
    })
  })

  test('governed regulatory-fee states and every exception row page correctly', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      await start(page)
      await milestoneScreenshot(page, testInfo, 'data-quality-overview')

      const exceptionCount = await openRegulatoryFeeSourceNull(page)
      await expect(page.getByText(new RegExp(`^1–\\d+ of ${exceptionCount.toLocaleString('en-US')}$`))).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'exceptions-page-1')

      const next = page.locator('.dq-pager').getByRole('button', { name: /Next/i })
      await next.click()
      await expect(page.getByText(/^51–\d+ of \d+$/)).toBeVisible()
      await next.click()
      await expect(page.getByText(/^101–\d+ of \d+$/)).toBeVisible()
      await next.click()
      await expect(page.getByText(/^151–\d+ of \d+$/)).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'exceptions-page-4')
    } finally {
      await finish(testInfo, runtime)
    }
  })

  test('exception opens a canonical Course detail', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      await start(page)
      await openRegulatoryFeeSourceNull(page)
      const firstEntity = page.locator('.dq-table tbody .dq-entity-link').first()
      await expect(firstEntity).toBeVisible()
      await firstEntity.click()
      await expect(page).toHaveURL(/#courses\?id=/)
      await expect(page.getByRole('heading', { name: /^(Course description|Registered CRICOS course cost|Regulatory facts)$/ }).first()).toBeVisible({ timeout: 45_000 })
      await milestoneScreenshot(page, testInfo, 'canonical-course-detail')
    } finally {
      await finish(testInfo, runtime)
    }
  })

  test('exception opens a real private Evidence Regulatory Snapshot', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      await start(page)
      await openRegulatoryFeeSourceNull(page)
      const evidenceButton = page.locator('.dq-table tbody').getByRole('button', { name: /^Evidence$/i }).first()
      await expect(evidenceButton).toBeVisible()
      await evidenceButton.click()
      await expect(page).toHaveURL(/#evidence\?evidence_id=/)

      const drawer = page.locator('aside.evidence-drawer')
      await expect(drawer).toBeVisible({ timeout: 45_000 })
      await expect(drawer.getByText(/^Evidence artifact$/i)).toBeVisible()
      await expect(drawer.getByRole('heading', { name: /^Regulatory snapshot$/i }).first()).toBeVisible()
      await expect(drawer.getByText(expectations.evidence.regulatory_snapshot_source, { exact: true }).first()).toBeVisible()
      await expect(drawer.getByText(/^Private evidence boundary$/i)).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'evidence-regulatory-snapshot')
    } finally {
      await finish(testInfo, runtime)
    }
  })
})
