// Decision 214: Live activity - what runs at each layer now, what is left, what runs next, what waits for a person.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

test('next run from pg_cron schedules (UTC) and job state wording', async () => {
  const src = fs.readFileSync('src/LiveActivity.jsx', 'utf8')
  expect(src).toContain("adminRead('live_activity',{})")
  expect(src).toContain('const REFRESH_MS=20000')
  const m = fs.readFileSync('supabase/migrations-archive/20261002180800_cf247_live_activity.sql', 'utf8')
  expect(m).toContain("if p_operation='live_activity' then return security.admin_live_activity_v1(); end if;")
  expect(m).toContain('grant execute on function security.admin_live_activity_v1() to authenticated;')
  expect(m).toContain("if v is distinct from '37a306b7181912d59ee61b2f8cd53c04' then raise exception")
  const r = fs.readFileSync('supabase/migrations-archive/20261002180600_cf247_scholarship_discovery_refill.sql', 'utf8')
  expect(r).toContain("cron.schedule('scholarship-discover-refill', '23 * * * *'")
  expect(fs.readFileSync('.github/workflows/release-currentness-deployed.yml', 'utf8')).toContain('grep -qF "${expected}" "$RUNNER_TEMP/probe.js"')
})

test('browser: needs-a-person tiles, states by layer, next run and filter', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#live-activity')
  const la = page.locator('[data-live-activity]')
  await expect(la.locator('[data-need="scholarships_ready"]')).toContainText('344')
  await expect(la.locator('[data-job="scholarship-discover"]')).toContainText('Working')
  await expect(la.locator('[data-job="scholarship-discover"]')).toContainText('94 providers left')
  await expect(la.locator('[data-job="scholarship-discover"]')).toContainText('items 21')
  await expect(la.locator('[data-job="coverage-read"]')).toContainText('Running now')
  await expect(la.locator('[data-job="coverage-find-site"]')).toContainText('Paused')
  await expect(la.locator('[data-job="evidence-link-index"]')).toContainText('Failing')
  await expect(la.locator('[data-job="scholarship-read"]')).toContainText('Up to date')
  await la.getByLabel('Only what is busy or needs attention').check()
  await expect(la.locator('[data-job="scholarship-read"]')).toHaveCount(0)
  await expect(la.locator('[data-job="evidence-link-index"]')).toHaveCount(1)
  await la.locator('[data-need="fee_schedules"]').click()
  await expect(page).toHaveURL(/#coverage\?tab=attributes/)
})
