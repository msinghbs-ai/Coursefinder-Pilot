// v2.15.129 Layer 4 review queue: even status tiles, clearer filter labels, Bulk decisions (renamed from Batches)
// without the scholarship scope cohorts (decided on Scholarships › Course links) or the older generic cohorts.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

test('source: renamed view, compact sections, pointer to Course links', () => {
  const s = fs.readFileSync('src/m2-3-intelligence-entry.jsx', 'utf8')
  expect(s).toContain("['batches','Bulk decisions']")
  expect(s).toContain("<Layer4MassOperations embedded sections={['departures','quality','history']}/>")
  expect(s).toContain('comes from the study levels, fields and courses its own page names') // v2.15.174: Course links retired
  expect(s).not.toContain('Scholarship scope batches and audit history')
})

test.describe('mocked browser', () => {
  // v2.15.300 (Platform Admin, 20 Oct 2026, "Old Layer 4 tabs now"): the Review queue retired; course links and provider departures are Inbox kinds
  test('the Review queue address opens the Inbox on course links', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-4-review?tab=review')
    await expect(page).toHaveURL(/#layer-4-review\?kind=course_link$/)
    await expect(page.getByRole('tab', { name: 'Review queue' })).toHaveCount(0)
  })
})
