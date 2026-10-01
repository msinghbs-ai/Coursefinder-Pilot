// v2.15.129 Layer 4 review queue: even status tiles, clearer filter labels, Bulk decisions (renamed from Batches)
// without the scholarship scope cohorts (decided on Scholarships › Course links) or the older generic cohorts.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

test('source: renamed view, compact sections, pointer to Course links', () => {
  const s = fs.readFileSync('src/m2-3-intelligence-entry.jsx', 'utf8')
  expect(s).toContain("['batches','Bulk decisions']")
  expect(s).toContain("<Layer4MassOperations embedded sections={['departures','quality','history']}/>")
  expect(s).toContain('href="#scholarships?tab=links"')
  expect(s).not.toContain('Scholarship scope batches and audit history')
})

test.describe('mocked browser', () => {
  test('tiles, filter labels and the bulk view', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-4-review')
    await expect(page.locator('.l4-status .cf-metric')).toHaveCount(4)
    await expect(page.getByRole('button', { name: 'All tasks (1,803)' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Everyone' })).toBeVisible()
    await expect(page.locator('.l4d-queue')).toContainText('Yours')
    await expect(page.locator('.l4d-queue')).toContainText('With someone else')
    await page.getByRole('button', { name: 'Bulk decisions' }).click()
    await expect(page.getByText('120 × Intakes')).toBeVisible()
    const more = page.getByRole('tablist', { name: 'More bulk work' })
    await expect(more.getByRole('button')).toHaveText(['Provider departures', 'Errors & improvements', 'Decision history'])
    await expect(page.getByRole('link', { name: 'Scholarships › Course links' })).toBeVisible()
    await expect(page.getByText('Scholarship Course-scope review')).toHaveCount(0)
  })
})
