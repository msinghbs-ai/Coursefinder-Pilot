// Guards: Platform Admin 20 Nov 2026 10:07 (s817/s818): Platform Health leads with a plain-English executive view (overall health, AI spend in the last 24
// hours against the daily cap, active blockers, Layer 4 review items with a link) and Needs attention (only failed jobs, stuck work and connections down);
// every check, raw job name, schedule and error text stays under Technical details. Read from the existing platform_health payload; nothing new is read.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { execSummary, needsAttention } from '../../src/health-exec.js'

const H = { overall: 'critical', generated_at: '2026-11-20T00:00:00Z', counts: { critical: 2, warning: 11, info: 1 }, history: [],
  checks: [{ key: 'budgets', area: 'budgets', label: 'Budgets', status: 'ok', detail: { ai_daily_ceiling_usd: 14, openrouter_spend_24h_usd: 2.5884 }, checked_at: '2026-11-20T00:00:00Z' },
    { key: 'layer_queues', area: 'Layer 4', label: 'Layer 4 queue', status: 'ok', detail: { pending: 3257, oldest: '2026-10-25T07:52:35Z' }, checked_at: '2026-11-20T00:00:00Z' }],
  issues: [
    { id: 1, severity: 'critical', check_key: 'cron:failed:scholarship-coverage-classify', area: 'scheduled jobs', title: 'Scheduled job "scholarship-coverage-classify" failed 1 of 1 run(s) in the last hour; 5 failure(s) in the last 24 hours; the last run failed', detail: { job: 'scholarship-coverage-classify', schedule: '29 * * * *', last_error: 'ERROR:  canceling statement due to statement timeout' } },
    { id: 2, severity: 'critical', check_key: 'consumer_snapshot:failing', area: 'search/API', title: 'Consumer API: 1 probe(s) failing (search_master_page2)', detail: { failing: ['search_master_page2'] } },
    { id: 3, severity: 'warning', check_key: 'queue_watch:fee_reader', area: 'coverage sweep', title: 'Fee reader (AI): stuck', detail: { reason: '1 waiting and nothing finished since 20 Nov 01:41', resolve: '#layer-2-discovery?tab=operations' } },
    { id: 4, severity: 'warning', check_key: 'cron:failed:admission-rule-runner-c', area: 'scheduled jobs', title: 'Scheduled job "admission-rule-runner-c" failed 0 of 59 run(s) in the last hour; 7 failure(s) in the last 24 hours', detail: { job: 'admission-rule-runner-c' } },
    { id: 5, severity: 'warning', check_key: 'db_capacity:size', area: 'storage/DB', title: 'Database is 7079 MB, over the high level of 6144 MB', detail: {} }] }

test('the summary and the attention list are worked out from the existing payload, in plain words, without job names, schedules or error text', () => {
  expect(execSummary(H)).toMatchObject({ overall: 'critical', spend: 2.5884, cap: 14, blockers: 2, layer4: 3257 })
  const items = needsAttention(H)
  expect(items.map((x) => x.title)).toEqual(['The hourly scholarship classifier failed on its last run', 'Website API: a check is failing', 'Fee reader (AI) is stuck'])
  for (const x of items) { expect(`${x.title} ${x.why}`).not.toMatch(/canceling statement|\* \* \*|29 \* \* \* \*|cron:|_v1|admission-rule-runner/) }
  expect(items[0].why).toBe('It ran out of time; 5 failures in the last 24 hours.')
  expect(needsAttention({ issues: [] })).toEqual([])
  expect(needsAttention({ issues: [{ severity: 'warning', check_key: 'layer_queues:layer3_reserved', title: '1 Layer 3 work item(s) stuck in reserved/interpreting' }] })).toEqual([])  // retired Layer 3 checks stay out
  const PH = fs.readFileSync('src/PlatformHealth.jsx', 'utf8')
  expect(PH).toContain("<details className=\"ph-tech\" data-ph-technical>")
  expect(PH).not.toMatch(/adminRead\('platform_exec|admin_platform_exec/)          // no new read
})

test('Platform Health opens on the executive view; the technical sections are folded under Technical details', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await mockAdmin(page, { rank: 6 })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async (route) => (route.request().postDataJSON() || {}).p_operation === 'platform_health' ? route.fulfill({ json: H }) : route.fallback())
  await page.goto('/#platform-health')
  const exec = page.locator('[data-ph-exec]')
  await expect(exec.locator('[data-ph-exec-overall]')).toContainText('Something is broken')
  await expect(exec.locator('[data-ph-exec-spend]')).toContainText('US$2.59')
  await expect(exec.locator('[data-ph-exec-spend]')).toContainText('of the US$14 daily cap (18%)')
  await expect(exec.locator('[data-ph-exec-blockers]')).toContainText('2')
  await expect(exec.locator('[data-ph-exec-layer4]')).toContainText('3,257')
  await expect(exec.locator('[data-ph-exec-layer4-link]')).toHaveAttribute('href', '#layer-4-review')
  const att = page.locator('[data-ph-attention]')
  await expect(att.locator('[data-ph-attention-item]')).toHaveCount(3)
  await expect(att).toContainText('The hourly scholarship classifier failed on its last run')
  await expect(att).not.toContainText('canceling statement')
  await expect(page.locator('[data-ph-technical]')).not.toHaveAttribute('open', '')
  await expect(page.locator('.ph-checks')).toBeHidden()
  await page.locator('[data-ph-technical] > summary').click()
  await expect(page.locator('.ph-checks')).toBeVisible()
})
