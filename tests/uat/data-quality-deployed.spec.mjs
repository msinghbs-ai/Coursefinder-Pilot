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
const fee = expectations.data_quality.regulatory_fee

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

  test('governed regulatory-fee states and all 191 exception rows page correctly', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      await start(page)
      await expect(page.getByText(/Aggregate snapshot computed at .*refreshed off-peak daily and after explicit post-ingestion refresh; exception drill-down is live\./)).toBeVisible()
      const card = page.locator('section.dq-domain-card').filter({ has: page.getByRole('heading', { name: 'Regulatory fee', exact: true }) })
      await expect(card.getByTitle(`Present: ${fee.present.toLocaleString('en-US')}`)).toBeVisible()
      await expect(card.getByTitle(`Source-null: ${fee.source_null.toLocaleString('en-US')}`)).toBeVisible()
      await expect(card.getByTitle(`Not applicable: ${fee.not_applicable.toLocaleString('en-US')}`)).toBeVisible()
      await expect(card.getByTitle(`Zero: ${fee.zero.toLocaleString('en-US')}`)).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'data-quality-overview')

      await openRegulatoryFeeSourceNull(page, fee)
      await expect(page.getByText('1–50 of 191', { exact: true })).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'exceptions-page-1')

      const next = page.locator('.dq-pager').getByRole('button', { name: /Next/i })
      await next.click()
      await expect(page.getByText('51–100 of 191', { exact: true })).toBeVisible()
      await next.click()
      await expect(page.getByText('101–150 of 191', { exact: true })).toBeVisible()
      await next.click()
      await expect(page.getByText('151–191 of 191', { exact: true })).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'exceptions-page-4')
    } finally {
      await finish(testInfo, runtime)
    }
  })

  test('exception opens a canonical Course detail', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      await start(page)
      await openRegulatoryFeeSourceNull(page, fee)
      const firstEntity = page.locator('.dq-table tbody .dq-entity-link').first()
      await expect(firstEntity).toBeVisible()
      await firstEntity.click()
      await expect(page).toHaveURL(/#courses\?id=/)
      await expect(page.getByRole('heading', { name: 'Fees', exact: true })).toBeVisible({ timeout: 45_000 })
      await milestoneScreenshot(page, testInfo, 'canonical-course-detail')
    } finally {
      await finish(testInfo, runtime)
    }
  })

  test('exception opens a real private Evidence Regulatory Snapshot', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      await start(page)
      await openRegulatoryFeeSourceNull(page, fee)
      const evidenceButton = page.locator('.dq-table tbody').getByRole('button', { name: /^Evidence$/i }).first()
      await expect(evidenceButton).toBeVisible()
      await evidenceButton.click()
      await expect(page).toHaveURL(/#evidence\?evidence_id=/)

      const drawer = page.locator('aside.evidence-drawer')
      await expect(drawer).toBeVisible({ timeout: 45_000 })
      await expect(drawer.getByText(/^Evidence artifact$/i)).toBeVisible()
      await expect(drawer.getByRole('heading', { name: 'Regulatory Snapshot', exact: true })).toBeVisible()
      await expect(drawer.getByText(expectations.evidence.regulatory_snapshot_source, { exact: true }).first()).toBeVisible()
      await expect(drawer.getByText(/^Private evidence boundary$/i)).toBeVisible()
      await milestoneScreenshot(page, testInfo, 'evidence-regulatory-snapshot')
    } finally {
      await finish(testInfo, runtime)
    }
  })
})
