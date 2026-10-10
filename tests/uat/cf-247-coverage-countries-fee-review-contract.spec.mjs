// Decision 213: course-page pattern requests retired; fee schedules approved in bulk, reviewed row by row, closable when
// there is nothing to add; Coverage & completeness by country and university.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('database: patterns cancelled (kept), fee schedules waiting first, coverage by country with md5 guards', () => {
  const m = read('supabase/migrations-archive/20261002180500_cf247_coverage_countries_fee_review_patterns.sql')
  expect(m).toContain("set status = 'cancelled', schedule_error = 'retired (Decision 213)")
  expect(m).toContain("order by (f.decision is null) desc, f.read_at desc")
  expect(m).toContain('create table if not exists pipeline.course_coverage_daily_by_country')
  expect(m).toContain("partition by min(country_code)")
  expect(m).toContain("if p_operation in ('course_coverage','course_coverage_courses','course_coverage_providers') then")
  for (const h of ['f4ce745bd0f8a28537cf42d90a4f06cc', 'd1f1c69a15d659a8cb3f50488219343d', '00b8068b7aad60f332eb5d0057dfae9a', 'd3be4b3fd26dd3c70a2e56daceeed3c9', 'e4ed662e9f99d15cf65138c8624e73b2', '9b52ca165865fc62d56a2d18c681dd5c'])
    expect(m).toContain(`if v is distinct from '${h}' then raise exception`)
  for (const w of ['delete from', 'drop ', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(w)
})

test('browser: fee schedules - select all waiting, approve selected; a schedule with nothing to add can be closed', async ({ page }) => {
  await mockAdmin(page)
  page.on('dialog', d => d.accept())
  await page.goto('/#layer-4-review?tab=attributes')
  const fsx = page.locator('[data-fee-schedules]')
  await expect(fsx.locator('[data-doc="fs1"]')).toBeVisible()
  await fsx.getByLabel('Select every waiting schedule').check()
  await expect(fsx.locator('[data-fee-bulk]')).toContainText('1 selected')
  await fsx.getByRole('button', { name: 'Approve selected' }).click()
  await expect.poll(() => page.l3calls.filter(c => c.feeDecide).map(c => c.feeDecide)).toEqual([{ p_source_id: 'fs1', p_action: 'approve', p_note: null }])
  await fsx.getByLabel('Show schedules').selectOption('decided')
  await expect(fsx.locator('[data-doc="fs1"]')).toHaveCount(0)
  await expect(fsx.locator('[data-doc="fs2"]')).toContainText('20 fees added')
})

test('browser: coverage opens on all countries; country and university filters reach the server', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#coverage')
  await expect(page.locator('[data-count-scope]')).toContainText('in every country')
  await page.getByLabel('Coverage country').selectOption('NZ')
  await expect.poll(() => (page.readCalls || []).some(b => b.p_operation === 'course_coverage' && b.p_args?.country === 'NZ')).toBe(true)
  await page.getByLabel('Find a university or provider').fill('mon')
  await page.getByRole('button', { name: /Monash University/ }).click()
  await expect(page.locator('[data-provider-filter]')).toContainText('Monash University')
  await expect.poll(() => (page.readCalls || []).some(b => b.p_operation === 'course_coverage' && b.p_args?.provider === 'prov-monash')).toBe(true)
})
