// Decision 214 (Live activity) → v2.15.266: the Live activity page is retired (Platform Admin, 13 Oct 2026); Coverage & completeness ›
// Progress › Running now shows every scheduled job by journey stage, its state, its last result and the universities it works on.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

test('Live activity retired: no page, no menu entry; old addresses redirect to Progress › Running now', async () => {
  expect(fs.existsSync('src/LiveActivity.jsx')).toBe(false)
  const nav = fs.readFileSync('src/nav-map.js', 'utf8')
  expect(nav).not.toMatch(/^\s+activity: \{ label: 'Live activity'/m)
  expect(nav).toContain("'live-activity': { page: 'coverage', tab: 'progress', view: 'running' },")
  expect(nav).toContain("if (hit.view && !p.get('view')) p.set('view', hit.view)")
  // the read it used is still what Running now builds on
  const m = fs.readFileSync('supabase/migrations/20261013012500_cf247_progress_tab.sql', 'utf8')
  expect(m).toContain('v := security.admin_live_activity_v1();')
})

test('browser: Running now shows job states by stage, the busy filter and job rows that expand to universities', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#live-activity')
  await expect(page).toHaveURL(/#coverage\?tab=progress&view=running/)
  const r = page.locator('[data-progress-running]')
  await expect(r.locator('[data-progress-job="coverage-read"]')).toContainText('Running')
  await expect(r.locator('[data-progress-job="evidence-link-index"]')).toContainText('Failing')
  await expect(r.locator('[data-progress-job="coverage-find-site"]')).toContainText('Paused')
  await expect(r.locator('[data-progress-job="scholarship-read"]')).toHaveCount(0) // busy filter on by default
  await r.getByLabel('Only what is busy or needs attention').uncheck()
  await expect(r.locator('[data-progress-job="scholarship-read"]')).toContainText('Waiting')
  await r.locator('[data-progress-job-toggle="scholarship-discover"]').click()
  const unis = r.locator('[data-progress-unis="scholarship-discover"]')
  await expect(unis.locator('[data-progress-uni="prov-monash"]')).toContainText('12 credits')
  await unis.locator('[data-progress-uni="prov-monash"] [data-progress-open-journey]').click()
  await expect(page).toHaveURL(/view=journeys/)
  await expect(page.locator('[data-progress-selected="ob-monash"]')).toBeVisible()
})
