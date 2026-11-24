// Guards: Settings Hub (Phase 3; v2.16.11 tabs, Platform Admin 16 Nov 2026 07:41: one group drawn at a time, opening on the settings a person changed of the UI/UX and settings simplification; Platform Admin 16 Nov 2026 05:12 decisions 2 and 4, 05:23): the settings sit in five groups (AI & Models, Schedulers & Cadence, Circuit Breakers, Consumer APIs, Pipeline steps) from pipeline.settings_hub_groups; a setting can be found by name, key or what uses it, or by "changed by a person"; Consumer APIs (Website API, Zoho API) is read-only until the Platform Admin unlocks an approved change, the write refuses and records a change without the unlock, and the unlock is kept in the log
// CF-247 S552. Migration 20261116040000_cf247_settings_hub and src/SettingsRegister.jsx. Mocked REST responses: nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const M = fs.readFileSync('supabase/migrations-archive/20261116040000_cf247_settings_hub.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const UI = fs.readFileSync('src/SettingsRegister.jsx', 'utf8')

test('the five groups live beside the settings; Website API and Zoho API are Consumer APIs; nothing is renamed', () => {
  expect(code).toContain("hub_group text not null check (hub_group in ('AI & Models', 'Schedulers & Cadence', 'Circuit Breakers', 'Consumer APIs', 'Pipeline steps'))")
  expect(code).toContain("('pipeline', 'Website API', 'Consumer APIs')")
  expect(code).toContain("('pipeline', 'Zoho API', 'Consumer APIs')")
  expect(code).toContain("comment on table pipeline.settings_hub_groups is '")
  expect(code).toContain("raise exception 'post-check: a setting outside the Website API and Zoho API sections is in Consumer APIs';")
  expect(code).not.toMatch(/update pipeline\.platform_toolset_settings/)
})

test('the write refuses and records a Consumer APIs change without the unlock; the unlock is kept in the log; both edits md5-guarded', () => {
  expect(code).toContain("pg_temp.cf_g2_edit('public.admin_toolsets_write(text,jsonb)', '55e3818580f3eab117734e9307150283', 'consumer_api_read_only'")
  expect(code).toContain("pg_temp.cf_g2_edit('public.admin_settings_register_read()', 'c3e4f273e08c7b348da6de1764205fc8', 'settings_hub_group_v1'")
  expect(M).toContain("if security.settings_hub_group_v1(v_set.toolset_key, v_set.section) = ''Consumer APIs'' and coalesce(p_args->>''unlock'', '''') <> ''consumer_api'' then")
  expect(M).toContain("values (''toolsets'', ''refused'', v_set.toolset_key || ''.'' || v_set.key,")
  expect(M).toContain("return jsonb_build_object(''ok'', false, ''refused'', ''consumer_api_read_only''")
  expect(M).toContain("''reason'', v_reason, ''unlock'', p_args->>''unlock'')")
  expect(UI).toContain("...(unlock?{unlock:'consumer_api'}:{})")
})

const register = {
  can_manage: true, jobs: 89, check: [],
  sections: [
    { section: 'Job sizes', hub_group: 'Schedulers & Cadence', read_only: false, settings: [
      { key: 'batch.coverage_admit', label: 'Admit official page and English', help: 'Courses admitted in each run.', kind: 'number', value: 500, min: 10, max: 5000, unit: 'courses a run', used_by: 'coverage-admit', changed: true, reason: 'Smaller runs', updated_at: '2026-11-10T00:00:00Z' },
      { key: 'batch.coverage_read', label: 'Read course pages', help: '', kind: 'number', value: 60, min: 10, max: 200, unit: 'pages', used_by: 'coverage-read', changed: false }] },
    { section: 'Alerts', hub_group: 'Circuit Breakers', read_only: false, settings: [
      { key: 'alerts.max_attempts', label: 'Alerts: tries to deliver', help: '', kind: 'number', value: 3, min: 1, max: 10, unit: 'tries', used_by: 'security.alert_delivery_take_v1', changed: false }] },
    { section: 'Onboarding', settings: [
      { key: 'onboarding.proposal_wait_minutes', label: 'Onboarding: an adapter proposal not finished is retried after', help: '', kind: 'number', value: 30, min: 5, max: 1440, unit: 'minutes', used_by: 'security.provider_onboarding_step_v1', changed: false }] },
    { section: 'Zoho API', hub_group: 'Consumer APIs', read_only: true, settings: [
      { key: 'zoho.page_max', label: 'Zoho: page size', help: '', kind: 'number', value: 100, min: 10, max: 500, unit: 'rows', used_by: 'zoho-api-v2', changed: false }] }]
}

test.describe('mocked browser', () => {
  test('five groups; find a setting; changed by a person; Consumer APIs read-only until unlocked, then the unlock is sent', async ({ page }) => {
    await mockAdmin(page)
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_settings_register_read', route => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(register) }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_toolsets_write', async route => { calls.push(route.request().postDataJSON()); return route.fulfill({ status: 200, contentType: 'application/json', body: '{"ok":true}' }) })
    await page.goto('/#environment')
    await page.locator('[data-advanced-keys] > summary').click() // the register sits in the Advanced System Keys drawer
    const reg = page.locator('[data-settings-register]').first()
    // v2.16.11: the groups are tabs, one drawn at a time; it opens on the settings a person changed
    for (const g of ['Edited', 'Schedulers & Cadence', 'Circuit Breakers', 'Consumer APIs', 'Pipeline steps']) await expect(reg.locator(`[data-hub-tab="${g}"]`)).toBeVisible()
    await expect(reg.locator('[data-hub-tab="AI & Models"]')).toHaveCount(0)
    await expect(reg.locator('[data-hub-group]')).toHaveCount(1)
    await expect(reg.locator('[data-hub-group="Edited"] [data-register-setting="batch.coverage_admit"]')).toBeVisible()
    await expect(reg.locator('[data-register-section]')).toHaveCount(0)
    await reg.locator('[data-hub-tab="Pipeline steps"]').click()
    await expect(reg.locator('[data-hub-group]')).toHaveCount(1)
    await expect(reg.locator('[data-hub-group="Pipeline steps"] [data-register-section="Onboarding"]')).toHaveCount(1)
    await expect(reg.locator('[data-register-section="Job sizes"]')).toHaveCount(0)
    await reg.locator('[data-hub-tab="Consumer APIs"]').click()
    await expect(reg.locator('[data-hub-group="Consumer APIs"]')).toContainText('Read-only')

    await reg.getByLabel('Find a setting').fill('delivery_take')
    await expect(reg.locator('[data-hub-results] [data-register-setting]')).toHaveCount(1)
    await expect(reg.locator('[data-hub-results] [data-register-setting="alerts.max_attempts"]')).toBeVisible()
    await reg.getByLabel('Find a setting').fill('')
    await reg.getByLabel('Changed by a person only').check()
    await expect(reg.locator('[data-hub-results] [data-register-setting]')).toHaveCount(1)
    await expect(reg.locator('[data-hub-results] [data-register-setting="batch.coverage_admit"]')).toBeVisible()
    await reg.getByLabel('Changed by a person only').uncheck()

    const sec = reg.locator('[data-register-section="Zoho API"]')
    await sec.locator('.cf-card-toggle').click()
    const row = sec.locator('[data-register-setting="zoho.page_max"]')
    await expect(row.locator('input[type="number"]')).toHaveCount(0)
    await sec.locator('[data-consumer-unlock="Zoho API"] input').check()
    await row.getByLabel('Zoho: page size').fill('200')
    await row.getByLabel('Reason').fill('Approved by the Platform Admin for the Zoho sync')
    await row.getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => calls[0]).toEqual({ p_action: 'setting', p_args: { toolset: 'pipeline', key: 'zoho.page_max', value: 200, reason: 'Approved by the Platform Admin for the Zoho sync', unlock: 'consumer_api' } })
  })
})
