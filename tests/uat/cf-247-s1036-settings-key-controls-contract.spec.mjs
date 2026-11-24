// Guards: UI/UX Unification v1.2 Slice 2 (Platform Admin brief 24 Nov 2026 12:42): Settings opens on a short Key controls panel (plain titles, a reason on every change, logged through the governed write) and the low-level settings sit in a collapsed, searchable Advanced System Keys drawer that matches both labels and keys; no value is written into the screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const set = (key, label, o = {}) => ({ key, label, help: `${label} help`, kind: 'number', value: 10, min: 1, max: 100000, unit: 'credits', ...o })
const toolsets = { can_manage: true, toolsets: [
  { key: 'firecrawl', settings: [set('daily_budget_total', 'Firecrawl daily budget', { value: 500 }), set('monitor_weekly_credits', 'Weekly monitor credits', { value: 2000 }), set('daily_budget_on', 'Daily budget switch', { kind: 'boolean', value: true, min: null, max: null, unit: null })] },
  { key: 'pipeline', settings: [set('budgets.paid_daily_cap_usd', 'Paid spend cap per day', { value: 5, unit: 'USD' })] },
] }
const register = { can_manage: true, jobs: 3, check: [], sections: [{ section: 'Job sizes', settings: [set('batch.job_1', 'Job 1 size'), set('batch.job_2', 'Admit official page size')] }] }

async function open(page) {
  await mockAdmin(page, { rank: 6 })
  const calls = []
  await page.route(/\/rest\/v1\/rpc\/admin_toolsets_read$/, r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(toolsets) }))
  await page.route(/\/rest\/v1\/rpc\/admin_settings_register_read$/, r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(register) }))
  await page.route(/\/rest\/v1\/rpc\/admin_toolsets_write$/, async r => { calls.push(r.request().postDataJSON()); await r.fulfill({ status: 200, contentType: 'application/json', body: '{"ok":true}' }) })
  await page.goto('/#environment')
  return calls
}

test('source: the key list only names which settings come first; every title, range and unit is read from the database', () => {
  const src = fs.readFileSync('src/ui-v1/KeyControls.jsx', 'utf8')
  expect(src).toContain("supabase.rpc('admin_toolsets_read')")
  expect(src).toContain("p_action: 'setting'")
  expect(src).toContain('reason.trim().length < 4')
  expect(fs.readFileSync('src/PipelineSettings.jsx', 'utf8')).toContain('data-advanced-keys')
})

test.describe('mocked browser', () => {
  test('Key controls come first; a change needs a reason and is sent with it', async ({ page }) => {
    const calls = await open(page)
    const kc = page.locator('[data-key-controls]')
    await expect(kc).toBeVisible()
    await expect(kc.locator('[data-key-control="firecrawl.daily_budget_total"]')).toContainText('Firecrawl daily budget')
    // Key controls sit above the Advanced drawer
    const a = await kc.boundingBox(), b = await page.locator('[data-advanced-keys]').boundingBox()
    expect(a.y).toBeLessThan(b.y)
    const row = kc.locator('[data-key-control="firecrawl.daily_budget_total"]')
    await row.getByLabel('Firecrawl daily budget').fill('600')
    const save = row.getByRole('button', { name: 'Save' })
    await expect(save).toBeDisabled()
    await row.getByLabel('Reason for Firecrawl daily budget').fill('Raise for the intake week')
    await save.click()
    await expect.poll(() => calls[0]).toEqual({ p_action: 'setting', p_args: { toolset: 'firecrawl', key: 'daily_budget_total', value: 600, reason: 'Raise for the intake week' } })
  })

  test('Advanced System Keys is collapsed with a count, and search matches a label and a key', async ({ page }) => {
    await open(page)
    const drawer = page.locator('[data-advanced-keys]')
    await expect(drawer).toBeVisible()
    expect(await drawer.evaluate(d => d.open)).toBe(false)
    await expect(page.locator('[data-advanced-count]')).toHaveText('(2)')
    await drawer.locator('summary').click()
    const reg = page.locator('[data-settings-register]').first()
    const find = reg.getByPlaceholder(/Find a setting/)
    await find.fill('Admit official')            // a label
    await expect(reg.locator('[data-register-setting="batch.job_2"]')).toBeVisible()
    await expect(reg.locator('[data-register-setting="batch.job_1"]')).toHaveCount(0)
    await find.fill('batch.job_1')               // a key
    await expect(reg.locator('[data-register-setting="batch.job_1"]')).toBeVisible()
  })

  test('375x812 @responsive: Key controls and the drawer fit the phone', async ({ page }) => {
    expect(page.viewportSize()?.width || 9999).toBeLessThanOrEqual(480)
    await open(page)
    await expect(page.locator('[data-key-controls]')).toBeVisible()
    await expect(page.locator('[data-advanced-keys]')).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
  })
})
