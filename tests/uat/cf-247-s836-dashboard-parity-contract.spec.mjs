// Guards: Platform Admin 20 Nov 2026 14:40 (S1-UI-Parity s836; mockup s820-s827): the Dashboard is the role line, the five KPI cards and Active failures,
// then Continue where you left off (the 3 most recent); the legacy sections are gone; the spend card shows the US$14.00 daily cap and its bar; Active
// failures lists genuine failures and warnings only, never the coverage or progress watchdogs.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { dashboardFailures } from '../../src/health-exec.js'
import { spendOf, withBudgetCap } from '../../src/lib/ops-pulse.js'

const SRC = fs.readFileSync('src/Dashboard.jsx', 'utf8'), DB = SRC.split('\n').filter((l) => !l.trim().startsWith('//')).join('\n') // the code, not its history comments
const MIG = fs.readFileSync('supabase/migrations/20261120145000_cf247_s836_s838_rule_groups_pulse_rates.sql', 'utf8')

test('s836: the legacy sections are removed and the order is role line, pulse cards and failures, then Continue (3)', () => {
  for (const gone of ['function Approvals', 'function OperatorToday', 'admin_waiting_read', 'Waiting for your approval', 'Waiting for you', 'data-db-also', 'Layer 2/3 › Operations'])
    expect(DB, gone).not.toContain(gone)
  const body = DB.slice(DB.indexOf('export default function Dashboard('))
  const at = (s) => body.indexOf(s)
  expect(at('<RoleLine')).toBeLessThan(at('<DashboardPulse')); expect(at('<DashboardPulse')).toBeLessThan(at('<ContinueWhereLeft'))
  expect(DB).toContain('const RECENT_SHOWN=3'); expect(DB).toContain('items=(all||[]).slice(0,RECENT_SHOWN)')
  expect(DB).toContain('{rank>=4&&<DashboardFailures health={h}/>}')
})

test('s836: the daily cap comes from ai_daily_ceiling_usd (pulse fragment, md5-guarded) and from the budgets check when the pulse has none', () => {
  expect(MIG).toContain("$n$'cap_usd', coalesce(h.detail->'ai_daily_ceiling_usd', h.detail->'openrouter_daily_ceiling_usd'),$n$")
  expect(MIG).toContain("pg_temp.cf_edit_def('security.ops_pulse_refresh_v1()'::regprocedure, '8aa5a729fc1f07f06543a6ab057c1a72',")
  const health = { checks: [{ key: 'budgets', detail: { ai_daily_ceiling_usd: 14, openrouter_spend_24h_usd: 3.3431 } }] }
  const p = withBudgetCap({ stages: [], budget: { spend_usd: 3.3431, cap_usd: null } }, health)
  expect(spendOf(p)).toMatchObject({ text: 'US$3.34', capText: 'of the US$14.00 daily cap', pct: 24 })
  expect(withBudgetCap({ stages: [], budget: { cap_usd: 20 } }, health).budget.cap_usd).toBe(20)  // a stored cap wins
  expect(spendOf(withBudgetCap({ stages: [], budget: {} }, {})).capText).toBe('cap not set')        // nothing measured stays unknown
})

const ISSUES = [
  { check_key: 'consumer_snapshot:failing', severity: 'critical', title: 'Consumer API: 1 probe(s) failing (search_master_page2)', detail: {} },
  { check_key: 'queue_watch:fee_reader', severity: 'warning', title: 'Fee reader (AI): stuck', detail: { reason: '12 waiting and nothing finished since 02:00' } },
  { check_key: 'search_probe:slow', severity: 'warning', title: 'Course search took 6016 ms (limit 3,000 ms)', detail: {} },
  { check_key: 'cron:failed:admission-rule-runner', severity: 'warning', title: 'Scheduled job "admission-rule-runner" failed 0 of 60 run(s) in the last hour; 3 failure(s) in the last 24 hours', detail: { job: 'admission-rule-runner' } },
  { check_key: 'cron:failed:coverage-reconcile', severity: 'warning', title: 'Scheduled job "coverage-reconcile" failed 1 of 1 run(s) in the last hour; 2 failure(s) in the last 24 hours; the last run failed', detail: { job: 'coverage-reconcile' } },
  { check_key: 'db_capacity:size', severity: 'warning', title: 'Database is 7108 MB, over the high level of 6144 MB', detail: {} },
  { check_key: 'field_stalled:AU', severity: 'warning', title: 'Australia: 6 field(s) below target and not moving', detail: {} },
  { check_key: 'field_stalled:no_reader', severity: 'info', title: 'Fields with a target but no reader yet', detail: {} },
  { check_key: 'layer3_budget', severity: 'warning', title: 'Layer 3 budget', detail: {} }]

test('s836: Active failures are genuine failures and warnings only (no watchdog, no job whose last run worked, no note, no Layer 3)', () => {
  const rows = dashboardFailures({ issues: ISSUES })
  expect(rows.map((r) => r.key)).toEqual(['consumer_snapshot:failing', 'queue_watch:fee_reader', 'search_probe:slow', 'cron:failed:coverage-reconcile', 'db_capacity:size'])
  expect(rows[0]).toMatchObject({ tone: 'critical', title: 'Website API: a check is failing' })
  expect(rows[1]).toMatchObject({ kind: 'stuck', title: 'Fee reader (AI) is stuck' })
  expect(rows.find((r) => r.key === 'search_probe:slow').title).toBe('Course search took 6016 ms')
  for (const r of rows) expect(r.href).toMatch(/^#(platform-health|scheduled-jobs)$/)
  expect(dashboardFailures({})).toEqual([])
})

const PULSE = {
  status: 'critical', critical: 1, warning: 5, blockers: 1, layer4_waiting: 46, layer4_by_kind: { provider_description: 30 },
  budget: { spend_usd: 3.3431 }, completeness: { AU: { completeness: 71.4 }, NZ: { completeness: 58 }, CA: { completeness: 44.2 } }, refreshed_at: '2026-11-20T00:05:00Z',
  stages: [1, 2, 3, 4].map((n) => ({ stage: n, status: n === 2 ? 'warning' : 'ok', checks: 2, queued: 1,
    attention: n === 2 ? [{ key: 'field_stalled', label: 'Fields below target are moving', status: 'warning' }, { key: 'queue_watch', label: 'Work queues are moving (progress watchdog)', status: 'warning' }] : [] }))
}

test.describe('mocked browser', () => {
  test('Dashboard (Platform Admin): cards at the top, the cap and its bar, genuine failures only, Continue below with 3 items', async ({ page }) => {
    await mockAdmin(page)
    await page.route('**/rest/v1/rpc/admin_read', async (route) => {
      const body = route.request().postDataJSON() || {}
      if ((body.p_operation || body.operation) !== 'platform_health') return route.fallback()
      return route.fulfill({ json: { generated_at: '2026-11-20T00:05:00Z', overall: 'critical', counts: { critical: 1, warning: 5, info: 1 }, issues: ISSUES, history: [], pulse: PULSE, pulse_source: 'snapshot',
        checks: [{ key: 'budgets', area: 'budgets', label: 'Budgets', status: 'ok', detail: { ai_daily_ceiling_usd: 14, openrouter_spend_24h_usd: 3.3431 }, checked_at: '2026-11-20T00:05:00Z' }] } })
    })
    await page.addInitScript(() => { for (const k of Object.keys(localStorage)) if (/recent/i.test(k)) localStorage.removeItem(k) })
    await page.goto('/#dashboard')
    await expect(page.locator('[data-db-pulse] [data-kpi]')).toHaveCount(5)
    await expect(page.locator('[data-kpi="spend"]')).toContainText('of the US$14.00 daily cap')
    await expect(page.locator('[data-kpi="spend"] .op-meter')).toHaveCount(1)
    const fails = page.locator('[data-db-failures]')
    await expect(fails.locator('li')).toHaveCount(5)
    await expect(fails).not.toContainText('Fields below target are moving'); await expect(fails).not.toContainText('Work queues are moving')
    await expect(fails).toContainText('Fee reader (AI) is stuck')
    for (const gone of ['[data-db-approvals]', '[data-db-waiting]', '[data-db-also]']) await expect(page.locator(gone)).toHaveCount(0)
    await expect(page.getByText('Waiting for your approval')).toHaveCount(0)
    const order = await page.evaluate(() => [...document.querySelectorAll('[data-db-role], [data-db-pulse], [data-db-failures], [data-db-recent]')].map((e) =>
      e.hasAttribute('data-db-role') ? 'role' : e.hasAttribute('data-db-pulse') ? 'pulse' : e.hasAttribute('data-db-failures') ? 'failures' : 'recent'))
    expect(order).toEqual(['role', 'pulse', 'failures', 'recent'])
  })
})
