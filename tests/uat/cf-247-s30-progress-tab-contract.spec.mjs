// CF-247 v2.15.266 (S30): Coverage & completeness › Progress. Platform Admin, 13 Oct 2026: "Show the adapter and scholarship journey and
// progress I can follow on the UI ... what is running, and where we can tweak or run on demand ... make sure redundant UI screens and
// controls are retired." Mock-up approved; "proceed with Progress tab, as v2.15.266".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const mig = fs.readFileSync('supabase/migrations/20261013012500_cf247_progress_tab.sql', 'utf8')
const read = f => fs.readFileSync(f, 'utf8')

test('migration: hourly snapshot kept 90 days, catalogued job, one read for four views, nothing dropped', () => {
  expect(mig).toContain("delete from pipeline.progress_snapshots where at < now() - interval '90 days';")
  expect(mig).toContain("select cron.schedule('progress-snapshot', '9 * * * *', 'select security.progress_snapshot_v1()');")
  expect(mig).toMatch(/insert into pipeline\.automation_catalogue\(jobname[^)]*\)\s*values \('progress-snapshot'/)
  expect(mig).toContain("cron.alter_job(job_id := (select jobid from cron.job where jobname = 'onboarding-pilot-snapshot'), active := false)")
  for (const v of ['overview', 'journeys', 'running', 'running_unis', 'levers']) expect(mig).toContain(`p_view = '${v}'`)
  expect(mig).toContain("if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception")
  expect(mig).not.toMatch(/^\s*(drop|truncate)\b/im)
  expect(mig).not.toMatch(/^delete\b/im) // only the snapshot function removes its own old rows
})

test('retired: Live activity page, Pilot panel, Dashboard health strip, Layers and Recent activity, Task manager Running now', () => {
  expect(fs.existsSync('src/LiveActivity.jsx')).toBe(false)
  const dash = read('src/Dashboard.jsx')
  for (const gone of ['db-health', 'title="Layers"', 'title="Recent activity"', "adminRead('platform_health')", "adminRead('layer_status_summary')"]) expect(dash).not.toContain(gone)
  expect(dash).toContain('data-dashboard-progress')
  const ob = read('src/ProviderOnboarding.jsx')
  expect(ob).not.toContain('export function Pilot(')
  expect(ob).not.toContain('data-onboarding-progress-link') // v2.15.300: the Onboarding list retired
  const tm = read('src/AdminTasks.jsx')
  expect(tm).not.toContain('function RunningNow(')
  expect(tm).toContain('data-task-running-link')
  expect(read('src/nav-map.js')).toContain("{ key: 'progress', label: 'Progress', min: 3 },")
})

test.describe('mocked browser', () => {
  test('Overview: group picker, needs attention, stages that open Journeys, fields when picked → now, budget and trend', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#coverage?tab=progress')
    const o = page.locator('[data-progress-overview]')
    await expect(o.locator('[data-progress-tile="universities"]')).toContainText('1,201')
    await expect(o.locator('[data-progress-need="stop:nothing_ready"]')).toContainText('41')
    await expect(o.locator('[data-progress-need="firecrawl:2:daily:scholarships:2026-10-13"]')).toContainText('3500 of 3500')
    await expect(o.locator('[data-progress-share="scholarships"]')).toContainText('100% of 3,500')
    await o.locator('[data-progress-group="top"]').click()
    await expect(o.locator('[data-progress-field="intakes"]')).toContainText('55% → 55%')
    await expect(o.locator('[data-progress-tile="scholarships"]')).toContainText('883')
    await o.locator('[data-progress-stage="admit_scholarships"]').click()
    await expect(page).toHaveURL(/view=journeys/)
    await expect(page).toHaveURL(/stage=admit_scholarships/)
  })

  test('Journeys (as the mock-up): sorted by courses, stage pills, fields, scholarship journey, held up by; a row opens its steps and actions', async ({ page }) => {
    page.on('dialog', d => d.accept('Adapter checked: vu.edu.au'))
    await mockAdmin(page)
    await page.goto('/#coverage?tab=progress&view=journeys')
    const j = page.locator('[data-progress-journeys]')
    await expect(j.locator('[data-progress-count]')).toContainText('3 universities · sorted by courses')
    await expect(j.locator('[data-progress-row="prov-vu"]')).toContainText('Search held for a check')
    await expect(j.locator('[data-progress-row="prov-vu"] [data-progress-next]')).toHaveText('Search again')
    await expect(j.locator('[data-progress-row="prov-alpha"]')).toContainText('Too few course pages')
    await expect(j.locator('[data-progress-row="prov-monash"] [data-progress-sch]')).toContainText('Found 74 · AI 12 waiting · published 61')
    await expect(j.locator('[data-progress-row="prov-monash"]')).toContainText('86% intakes · 96% English · 100% fee · 52% delivery')
    await expect(j.locator('[data-progress-row="prov-monash"] .pg-pills > span.is-done')).toHaveCount(6)
    await j.getByLabel('Held up by').selectOption('search')
    await expect(j.locator('[data-progress-row]')).toHaveCount(1)
    await j.getByLabel('Held up by').selectOption('')
    await j.locator('[data-progress-row="prov-vu"]').getByRole('button', { name: 'Victoria University' }).click()
    const sel = j.locator('[data-progress-selected="ob-vu"]')
    await expect(sel.locator('[data-progress-steps]')).toContainText('Queued first')
    await expect(sel).toContainText('Find scholarships now')
    await expect(sel).toContainText('Read course pages again')
    await expect(sel).toContainText('Qualify adapter')
    await sel.locator('[data-progress-search-again]').click()
    await expect.poll(() => page.l3calls.find(c => c.fcResume)).toEqual({ fcResume: 'prov-vu', reason: 'Adapter checked: vu.edu.au' })
  })

  test('Running now: schedules in words; a job with no university activity lists the universities at its stage', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#coverage?tab=progress&view=running')
    await expect(page).toHaveURL(/#scheduled-jobs\?tab=tasks$/) // v2.15.301: Running now retired from Progress; the board is Task manager's
    const r = page.locator('[data-progress-running]')
    await expect(r.locator('[data-progress-job="scholarship-discover"]')).toContainText('every 10 min')
    await r.locator('[data-progress-job-toggle="coverage-read"]').click()
    await expect(r.locator('[data-progress-unis-fallback]')).toContainText('now at this stage of the journey (2 Prepare)')
    await expect(r.locator('[data-progress-unis="coverage-read"] [data-progress-uni="prov-alpha"]')).toContainText('at this stage now')
  })

  // v2.15.301 (Platform Admin, 20 Oct 2026, "Retire Running now and Levers"): Progress has Overview and Journeys; Levers opens Settings
  test('Progress has two views; the Levers address opens Settings', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#coverage?tab=progress')
    await expect(page.locator('.pg-views a')).toHaveText(['Overview', 'Journeys'])
    await expect(page.locator('[data-progress-levers]')).toHaveCount(0)
    await page.goto('/#coverage?tab=progress&view=levers')
    await expect(page).toHaveURL(/#environment$/)
  })

  test('Dashboard keeps Waiting for you and the four tiles, and links to Progress; Task manager links to Running now', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#dashboard')
    await expect(page.locator('[data-dashboard-progress] a').first()).toHaveAttribute('href', '#coverage?tab=progress')
    await expect(page.locator('[data-dashboard-progress] a').nth(1)).toHaveAttribute('href', '#layer-2-discovery') // v2.15.301: what is running
    await expect(page.locator('.db-health')).toHaveCount(0)
    await page.goto('/#scheduled-jobs?tab=tasks')
    await expect(page.locator('[data-task-running-link] a')).toHaveAttribute('href', '#layer-2-discovery') // v2.15.301
    await expect(page.locator('[data-running-now]')).toHaveCount(0)
  })
})
