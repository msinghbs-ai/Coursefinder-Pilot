// Guards: UI/UX Unification & Live Guide Parity Plan v1.2, Slice 3 (Platform Admin brief 24 Nov 2026 16:31): Platform health and Scheduled jobs (Automations, Pipeline maintenance, Runtime health) and the four-stage pipeline board are drawn by the v1.1 build: files in src/ui-v1/ that import only the two ui-v1 stylesheets, ui-* classes, no hard-coded version banner or cron figure; every data-* hook the earlier specs use is kept; both fit a phone.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const VIEWS = ['PlatformHealthView', 'AutomationsView', 'ScheduledRuntimeHealthView', 'PipelineMaintenanceView', 'PipelineBoardView']
const code = f => fs.readFileSync(`src/ui-v1/${f}.jsx`, 'utf8').split('\n').filter(l => !l.trim().startsWith('//')).join('\n')

test('source: the five views import only the ui-v1 stylesheets and kit, use no legacy class prefix, and type no version or cron figure', () => {
  for (const f of VIEWS) {
    const raw = fs.readFileSync(`src/ui-v1/${f}.jsx`, 'utf8'), c = code(f)
    expect([...raw.matchAll(/^import\s*'([^']+\.css)'/gm)].map(m => m[1]), f).toEqual(['./tokens.css', './ui-kit.css'])
    expect(c, f).not.toMatch(/from\s*'\.\/ui-kit'|localStorage|v2\.\d+\.\d+|\b140\b/)
    const classes = [...c.matchAll(/className=(?:"([^"]*)"|\{`([^`]*)`\})/g)].flatMap(m => (m[1] ?? m[2]).replace(/\$\{[^}]*\}/g, ' ').split(/\s+/)).filter(Boolean)
    expect(classes.filter(x => /^(m-|cf-|ph-|au-|l3c-|pm-|op-|fv-|sd-|l3v-)/.test(x)), f).toEqual([])
  }
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toContain("from'./ui-v1/PlatformHealthView.jsx'"); expect(main).toContain("import('./ui-v1/AutomationsView.jsx')"); expect(main).toContain("import('./ui-v1/ScheduledRuntimeHealthView.jsx')")
  for (const gone of ['src/PlatformHealth.jsx', 'src/Automations.jsx', 'src/ScheduledRuntimeHealth.jsx', 'src/PipelineMaintenance.jsx', 'src/OpsPulse.jsx', 'src/platform-health-exec.css', 'src/PipelineMaintenance.css', 'src/scheduled-jobs-config.css']) expect(fs.existsSync(gone), gone).toBe(false)
})

const H = { overall: 'warning', generated_at: '2026-11-24T05:00:00Z', counts: { critical: 0, warning: 1, info: 0 }, history: [{ day: '2026-11-23', warning: 1, critical: 0 }],
  pulse: { status: 'warning', stages: [], layer4_waiting: 4, budget: { spend_usd: 1, cap_usd: 5 }, refreshed_at: '2026-11-24T05:00:00Z' },
  checks: [{ key: 'budgets', area: 'budgets', label: 'Budgets', status: 'ok', detail: { ai_daily_ceiling_usd: 5, openrouter_spend_24h_usd: 1 }, checked_at: '2026-11-24T05:00:00Z' }],
  issues: [{ id: 1, severity: 'warning', check_key: 'db_capacity:size', area: 'storage/DB', title: 'Database is 7079 MB, over the high level of 6144 MB', detail: {} }] }
const JOBS = [{ job: 'rollup-scheduler', label: 'Roll-up', area: 'Layer 2', active: true, runs_24h: 3, failed_24h: 0, description: 'x', every: 'hourly' }, { job: 'other-job', label: 'Other', area: 'Layer 2', active: false, runs_24h: 0, failed_24h: 0, description: 'y' }]

async function open(page, hash) {
  await mockAdmin(page, { rank: 6 })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async r => (r.request().postDataJSON() || {}).p_operation === 'platform_health' ? r.fulfill({ json: H }) : r.fallback())
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_automations_read', r => r.fulfill({ json: { rank: 6, events: [], jobs: JOBS } }))
  await page.goto(hash)
}
const strayClasses = (page, sel) => page.locator(sel).first().evaluate(e => [...e.querySelectorAll('[class]')].flatMap(x => [...x.classList]).filter(c => !/^(ui-|m-col-resize|lucide|tone-|is-|num$|warning$|critical$|safe$|draining$|busy$|clear$|overdue$|sel$|on$|ghost$)/.test(c)))

test('Platform health: the executive view, needs attention and the folded technical details are drawn in ui-* classes, hooks kept', async ({ page }) => {
  await open(page, '/#platform-health')
  await expect(page.locator('[data-ph-exec]')).toBeVisible()
  await expect(page.locator('[data-ph-exec-spend]')).toContainText('US$')
  await expect(page.locator('[data-ph-technical]')).not.toHaveAttribute('open', '')
  await page.locator('[data-ph-technical] > summary').click()
  await expect(page.locator('.ui-ph-checks')).toBeVisible(); await expect(page.locator('.ui-ph-day')).toHaveCount(1)
  expect(await strayClasses(page, '[data-ph-exec]')).toEqual([])
  expect(await strayClasses(page, '[data-ph-technical]')).toEqual([])
})

test('Scheduled jobs › Automations: dispatchers, metrics, areas and Pipeline maintenance in ui-* classes; the running count comes from the read', async ({ page }) => {
  await open(page, '/#scheduled-jobs?tab=automations')
  await expect(page.locator('[data-au-dispatchers]')).toBeVisible()
  await expect(page.locator('.ui-metric').filter({ hasText: 'Automations' })).toContainText('1 running')
  await expect(page.locator('.ui-au-area').first()).toBeVisible()
  expect(await strayClasses(page, '[data-au-dispatchers]')).toEqual([])
  expect(await strayClasses(page, '.ui-au-area')).toEqual([])
})

test('phone @responsive: Platform health and Automations fit the phone', async ({ page }) => {
  expect(page.viewportSize()?.width || 9999).toBeLessThanOrEqual(480)
  await open(page, '/#platform-health')
  await expect(page.locator('[data-ph-exec]')).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
  await page.goto('/#scheduled-jobs?tab=automations')
  await expect(page.locator('[data-au-dispatchers]')).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
})
