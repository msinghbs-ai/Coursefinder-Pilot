// CF-247 Decision 222 (v2.15.149): Fetch an area works on the course-page sweep; Websites to find in Layer 4; worker
// errors say what to do; the AI tuition check is called with a 5-minute wait; the tuition hand-off picks pages faster.
import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import { errorReading, errorSteps } from '../../src/lib/workerErrors.js'
import { PAGES } from '../../src/nav-map.js'

const MIG = 'supabase/migrations/20261002182000_cf247_fetch_area_sweep_websites.sql'

test('migration: sweep-based Fetch an area, Websites to find, dispatch wait and faster hand-off, behind md5 guards', async () => {
  const m = await fs.readFile(MIG, 'utf8')
  for (const g of ['ae4f50b65a29f416b92b80504db42bed', '93aa3ce4766a49c9393d16c5ab058826']) expect(m).toContain(g)
  expect(m).toContain("case when p_function='layer3-work-dispatch' then 300000 else 120000 end")
  expect(m).toContain(`p.candidates->'fee'->'candidates' @> '[{"international": true}]'::jsonb`)
  expect(m).toContain('create or replace function public.admin_coverage_fetch_area')
  expect(m).toContain("'Fetch an area', auth.uid()")
  expect(m).toContain("now() - interval '7 days'")
  expect(m).toContain("perform public.admin_provider_edit(p_provider_id, 'set_core'")
  expect(m).toContain("perform public.admin_provider_edit(p_provider_id, 'set_course_finder'")
  expect(m).toContain("v_rank < 4 then raise exception 'Pipeline Operator role or above required'")
  expect(m).not.toMatch(/\bdrop\s|delete\s+from|truncate|on delete cascade/i)
  expect(PAGES.layer4.tabs.map(t => t.key)).toContain('websites')
})

test('worker errors: each reading says what to do', () => {
  const dispatch = { function: 'layer3-work-dispatch', timed_out: true, status: null, message: 'Timeout of 120000 ms reached', count: 4 }
  expect(errorReading(dispatch)).toContain('carries on')
  expect(errorSteps(dispatch)).toMatch(/^Nothing to do/)
  const boot = { function: 'coverage-sweep', status: 503, message: '{"code":"BOOT_ERROR","message":"Function failed to start"}', count: 1 }
  expect(errorReading(boot)).toContain('could not start')
  expect(errorSteps(boot)).toMatch(/^Nothing to do if it happened once/)
  expect(errorSteps({ ...boot, count: 6 })).toContain('switch this job off')
  const slow = { function: 'coverage-sweep', status: 500, message: 'svc_coverage_tuition_handoff_next: canceling statement due to statement timeout', count: 1 }
  expect(errorReading(slow)).toContain('database took too long')
  expect(errorSteps(slow)).toMatch(/^Nothing to do/)
})

test.describe('mocked browser', () => {
  // v2.15.200 (Decision 254): the Fetch an area screen is retired from Layer 2 (unused for 30 days). Its database function stays.

  test('Websites to find: what was tried, enter and save a website', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-4-review?tab=websites')
    const w = page.locator('[data-websites-to-find]')
    const row = w.locator('[data-website-row="prov-macewan"]')
    await expect(row).toContainText('DLI O19092022262')
    await expect(row.getByRole('link', { name: 'https://www.macewan.ca/' })).toBeVisible()
    await row.getByRole('textbox', { name: 'Website for Grant MacEwan University' }).fill('https://www.macewan.ca')
    await row.getByRole('button', { name: 'Save' }).click()
    await expect(w.getByRole('status')).toContainText('Grant MacEwan University: website saved')
    await expect(w.locator('[data-website-row="prov-macewan"]')).toHaveCount(0)
  })

  test('Live activity: worker errors say what to do', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#live-activity')
    await expect(page.locator('[data-error-todo]').first()).toContainText('What to do:')
  })
})
