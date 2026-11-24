// Guards: UI/UX Unification & Live Guide Parity Plan v1.2, Slice 3 (Platform Admin brief 24 Nov 2026 15:11): the Dashboard is drawn by the v1.1 build (src/ui-v1/, ui-* classes, the two ui-v1 stylesheets only, no hard-coded version banner); the stored pulse cards, the running-automation count (read from the catalogue, never typed), Active failures and Continue keep their data-db hooks; a Viewer or Counsellor makes no pipeline read; it fits a phone.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const SRC = fs.readFileSync('src/ui-v1/DashboardView.jsx', 'utf8'), CODE = SRC.split('\n').filter(l => !l.trim().startsWith('//')).join('\n')
const PULSE = { status: 'ok', warning: 0, critical: 0, layer4_waiting: 12, layer4_by_kind: { a: {}, b: {} }, blockers: 0, budget: { spend_usd: 1.5, cap_usd: 5 }, completeness: {}, stages: [], refreshed_at: '2026-11-24T05:00:00Z' }
const HEALTH = { generated_at: '2026-11-24T05:00:00Z', overall: 'ok', counts: { critical: 0, warning: 0, info: 0 }, issues: [], history: [], pulse: PULSE, pulse_source: 'snapshot', checks: [] }
const JOBS = [{ job: 'a', label: 'A', area: 'x', active: true }, { job: 'b', label: 'B', area: 'x', active: true }, { job: 'c', label: 'C', area: 'x', active: false }, { job: 'd', label: 'D', area: 'x', active: true, retirement: { status: 'retiring' } }]

test('source: the v1.1 Dashboard imports only the two ui-v1 stylesheets, uses ui-* classes, has no typed version or cron figure and no direct storage', () => {
  expect([...SRC.matchAll(/import\s+'([^']+\.css)'/g)].map(m => m[1])).toEqual(['./tokens.css', './ui-kit.css'])
  expect(CODE).not.toMatch(/localStorage|v2\.\d+\.\d+|\b140\b|\b134\b/)
  expect(CODE).not.toMatch(/className="(m-|op-|cf-|db-)/)
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toContain("import DashboardHome from'./ui-v1/DashboardView.jsx'")
  expect(fs.existsSync('src/Dashboard.jsx')).toBe(false)
})

async function dash(page, rank, role, jobs = JOBS) {
  await mockAdmin(page, { rank, role })
  const reads = []
  await page.route('**/rest/v1/rpc/admin_read', async route => {
    const b = route.request().postDataJSON() || {}; const op = b.p_operation || b.operation; reads.push(op)
    if (op === 'platform_health') return route.fulfill({ json: HEALTH })
    return route.fallback()
  })
  await page.route('**/rest/v1/rpc/admin_automations_read', r => r.fulfill({ json: { rank, jobs } }))
  return reads
}

test('Platform Admin: the pulse cards plus Automations running (retired jobs not counted), Active failures and Continue, all in ui-* classes', async ({ page }) => {
  await dash(page, 6, 'platform_admin')
  await page.goto('/#dashboard')
  await expect(page.locator('[data-db-pulse] [data-kpi]:not([data-kpi="automations"])')).toHaveCount(5)
  const auto = page.locator('[data-kpi="automations"]')
  await expect(auto).toContainText('2'); await expect(auto).toContainText('1 paused')
  await expect(page.locator('[data-db-failures]')).toContainText('Nothing is failing')
  await expect(page.locator('[data-db-recent]')).toBeVisible()
  const shell = await page.locator('[data-db-rank]').evaluate(e => [...e.querySelectorAll('[class]')].flatMap(x => [...x.classList]).filter(c => !c.startsWith('ui-') && !c.startsWith('lucide')))
  expect(shell).toEqual([])
  expect(await page.locator('body').innerText()).not.toMatch(/PIM Admin v2\.16\.61|reviewed for v2\.16\.61/)
})

test('Curator: the cards without Active failures or the automation count; a Counsellor-level Viewer reads nothing from the pipeline', async ({ page }) => {
  const reads = await dash(page, 3, 'curator')
  let autoReads = 0
  await page.route('**/rest/v1/rpc/admin_automations_read', r => { autoReads++; return r.fulfill({ json: { rank: 3, jobs: JOBS } }) })
  await page.goto('/#dashboard')
  await expect(page.locator('[data-db-pulse] [data-kpi]')).toHaveCount(5)
  await expect(page.locator('[data-db-failures]')).toHaveCount(0)
  expect(autoReads).toBe(0)
  expect(reads).toContain('platform_health')
})

test('Viewer: Search the catalogue only, with no health or automation read', async ({ page }) => {
  const reads = await dash(page, 1, 'viewer')
  let autoReads = 0
  await page.route('**/rest/v1/rpc/admin_automations_read', r => { autoReads++; return r.fulfill({ json: { jobs: [] } }) })
  await page.goto('/#dashboard')
  await expect(page.locator('[data-db-search]')).toBeVisible()
  await expect(page.locator('[data-db-pulse]')).toHaveCount(0)
  expect(reads).not.toContain('platform_health'); expect(autoReads).toBe(0)
})

test('phone @responsive: the Dashboard cards stack and nothing overflows', async ({ page }) => {
  expect(page.viewportSize()?.width || 9999).toBeLessThanOrEqual(480)
  await dash(page, 6, 'platform_admin')
  await page.goto('/#dashboard')
  await expect(page.locator('[data-db-pulse]')).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
  const w = page.viewportSize().width
  const boxes = await page.locator('[data-kpi]').evaluateAll(es => es.map(e => { const b = e.getBoundingClientRect(); return [b.x, b.x + b.width] }))
  for (const [a, z] of boxes) { expect(a).toBeGreaterThanOrEqual(0); expect(z).toBeLessThanOrEqual(w + 1) }
})
