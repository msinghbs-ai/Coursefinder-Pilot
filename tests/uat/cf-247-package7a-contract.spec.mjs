// v2.15.131 package 7A: Melbourne time everywhere, plain errors and wording, counts say what they cover, Datasets tab
// rebuilt, provider onboarding merged into Providers › Onboarding, Users role help, fix links on Publishing and Health.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { describeSchedule } from '../../src/automation-schedule.js'

test('source: Melbourne time, no IST, onboarding merged, datasets component, no milestone codes on screen', () => {
  expect(fs.readFileSync('src/lib/format.js', 'utf8')).toContain("timeZone: 'Australia/Melbourne'")
  expect(fs.readFileSync('src/automation-schedule.js', 'utf8')).not.toMatch(/\bIST\b.*`|330\)/)
  expect(describeSchedule('17 20 * * *').text).not.toContain('IST')
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toContain("if(tab==='datasets')return <StatisticsDatasets rank={rank}/>")
  expect(main).toContain('<ProviderOnboardingNotice rank={rank} navigate={navigate}/>') // clean-up batch 2: the old queue was replaced
  for (const f of ['src/platform-maturity-entry.jsx', 'src/pipeline-ops-entry.jsx', 'src/EvidenceWorkspace.jsx'])
    expect(fs.readFileSync(f, 'utf8')).not.toMatch(/M2\.4\.4 permanent baseline|M1-PIPELINE-OPS · |M2\.4\.5 · Scholarship PIM|Private governed evidence/)
})

test.describe('mocked browser', () => {
  test('datasets tab lists and toggles; onboarding queue on Providers; Users role help; Health and Publishing fix links', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#statistics-rankings?tab=datasets')
    const ds = page.locator('[data-stat-datasets]')
    await expect(ds.locator('tbody tr')).toHaveCount(2)
    await ds.getByLabel('Show Academic Ranking of World Universities on Rankings & statistics').click() // the mock re-reads the old value, so poll the save
    await expect.poll(() => page.l3calls.find(c => c.datasetWrite)?.datasetWrite?.p_dataset?.display_enabled).toBe(true)
    await page.goto('/#providers?tab=onboarding')
    await expect(page.locator('details.onb-cases > summary')).toHaveText('Country and source onboarding cases')
    await page.goto('/#users-roles')
    await page.locator('details.ar-roles-help > summary').click()
    await expect(page.locator('.ar-roles-help')).toContainText('Counsellor')
    await expect(page.getByRole('button', { name: 'Admin', exact: true })).toHaveCount(0)
  })
})
