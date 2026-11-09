// Guards: Platform Admin decision 9 Nov 2026 19:18 AEDT (formal G3 authorisation of Website API v2 R23/R24, release step 1 of 2): the approval setting is defined at 0 (not approved) by its own migration and changed to 1 only on Settings with a reason
// CF-247 Website API v2 R23/R24, release step 1 of 2 (Platform Admin decision 9 Nov 2026 19:18 AEDT: formal G3 authorisation; "apply the required
// approval setting through the authorised, audited mechanism"). Migration 20261109160000 (Pilot PR 945) refuses to apply unless the setting
// api.v2_r23_r24_approved is 1, and a missing setting reads 0. This migration defines the setting at 0 so it can be changed on Settings >
// Pipeline settings (public.admin_toolsets_write 'setting', Platform Admin only, reason required, kept in pipeline.admin_control_events).
// The migration here approves nothing: it changes no behaviour and no consumer API object.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const FILE = '20261109155000_cf247_r23_r24_approval_setting.sql'
const m = fs.readFileSync(`supabase/migrations/${FILE}`, 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('the setting is defined at 0 (not approved), with a label, range, unit, section and used_by line; it never overwrites a value already set', () => {
  expect(code(m).match(/insert into pipeline\.platform_toolset_settings/g)).toHaveLength(1)
  expect(m).toContain("values ('pipeline', 'api.v2_r23_r24_approved', 'Website API v2 R23/R24 consumer change: approved', 'number', '0'::jsonb, 0, 1, 'on (1) / off (0)', 307, 'Website API',")
  expect(m).toContain("'migration 20261109160000 (G3 approval gate for Website API v2 R23/R24)'")
  expect(m).toContain('on conflict (toolset_key, key) do nothing;')
  expect(m).toMatch(/^-- Replaces: nothing$/m)
  expect(m).toMatch(/^-- Retires: nothing$/m)
})

test('the migration approves nothing and touches nothing else: no update, delete, drop, function, table, job or consumer API object; it sorts before the consumer change', () => {
  expect(code(m)).not.toMatch(/\b(update|delete|drop|truncate|alter|create)\b/i)
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\.(website|zoho)/)
  expect(code(m)).not.toMatch(/'1'|\b1::jsonb|to_jsonb\(1\)/)   // the value 1 is only ever written by a Platform Admin on Settings
  const mig = fs.readdirSync('supabase/migrations').filter((f) => f.endsWith('.sql')).sort()
  expect(mig.filter((f) => f.startsWith('20261109155000'))).toEqual([FILE])
  expect('20261109155000' < '20261109160000').toBe(true)
  expect(mig.indexOf(FILE)).toBeGreaterThan(mig.indexOf('20261109150000_cf247_aer_selector_fix.sql'))
})

test.describe('mocked browser', () => {
  test('Settings > Pipeline settings lists the setting under Website API; changing it to 1 needs a reason and is written by the audited route', async ({ page }) => {
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_settings_register_read', (route) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({
      can_manage: true, check: [], jobs: 90,
      sections: [{ section: 'Website API', settings: [
        { key: 'api.v2_r23_r24_approved', label: 'Website API v2 R23/R24 consumer change: approved', help: '1 = approved.', kind: 'number', value: 0, min: 0, max: 1, unit: 'on (1) / off (0)', used_by: 'migration 20261109160000 (G3 approval gate for Website API v2 R23/R24)', reason: 'Defined at 0', updated_at: '2026-11-09T09:00:00Z' }] }] }) }))
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_toolsets_write', async (route) => { calls.push(route.request().postDataJSON()); return route.fulfill({ status: 200, contentType: 'application/json', body: '{"ok":true}' }) })
    await page.goto('/#environment')
    const sec = page.locator('[data-register-section="Website API"]')
    await sec.locator('.cf-card-toggle').click()
    const row = sec.locator('[data-register-setting="api.v2_r23_r24_approved"]')
    await expect(row).toContainText('Used by: migration 20261109160000')
    await expect(row.locator('.sr-range')).toHaveText('0 to 1')
    const input = row.getByLabel('Website API v2 R23/R24 consumer change: approved')
    await expect(input).toHaveValue('0')
    await input.fill('1')
    const save = row.getByRole('button', { name: 'Save' })
    await expect(save).toBeDisabled()
    await row.getByLabel('Reason').fill('Platform Admin formal G3 authorisation 9 Nov 2026 19:18 AEDT')
    await save.click()
    await expect.poll(() => calls[0]).toEqual({ p_action: 'setting', p_args: { toolset: 'pipeline', key: 'api.v2_r23_r24_approved', value: 1, reason: 'Platform Admin formal G3 authorisation 9 Nov 2026 19:18 AEDT' } })
  })
})
