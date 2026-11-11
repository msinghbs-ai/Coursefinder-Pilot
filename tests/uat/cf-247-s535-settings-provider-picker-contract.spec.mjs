// Guards: CF-247 F-OPS (Platform Admin 11 Nov 2026 14:38 AEDT "RMIT added, there has to be better way in UI rather that using the provider's ID"): a list setting of provider ids is shown by provider name and providers are added by name on Settings › Pipeline settings; the value saved is the same list of ids, with a reason.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { isProviderIdList } from '../../src/lib/settings-list.js'

const MIG = fs.readFileSync('supabase/migrations/20261111235500_cf247_settings_provider_picker.sql', 'utf8')
const UI = fs.readFileSync('src/SettingsRegister.jsx', 'utf8')
const PICK = fs.readFileSync('src/ProviderListPicker.jsx', 'utf8')
const MONASH = '543b87b8-f0dd-4bc7-80d6-76252cfaabec'
const RMIT = '8e1adb6c-e069-43db-9584-bd054255e702'
const SWIN = '22657140-1cb0-4fa7-91df-90518ea8b35b'

test('a provider-id list is recognised by its unit or by every value being a provider id; other lists stay typed', () => {
  expect(isProviderIdList({ kind: 'list', unit: 'provider ids', value: [] })).toBe(true)
  expect(isProviderIdList({ kind: 'list', unit: 'universities', value: [MONASH, RMIT] })).toBe(true)
  expect(isProviderIdList({ kind: 'list', unit: 'providers', value: [] })).toBe(false)
  expect(isProviderIdList({ kind: 'list', unit: 'provider=rows', value: [`${RMIT}=19`] })).toBe(false)
  expect(isProviderIdList({ kind: 'list', unit: 'countries', value: ['AU', 'NZ'] })).toBe(false)
  expect(isProviderIdList({ kind: 'number', unit: 'provider ids', value: 3 })).toBe(false)
})

test('the read names ids and finds active providers by name; it is read only and needs a StudySearch role', () => {
  expect(MIG).toContain('create or replace function public.admin_provider_pick_v1(p_query text default null, p_ids uuid[] default null)')
  expect(MIG).toContain("if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;")
  expect(MIG).toContain("where p.lifecycle_status = 'active'")
  expect(MIG).toContain('limit 20) z) end);  -- fixed: one display page of search results')
  expect(MIG).toContain('revoke all on function public.admin_provider_pick_v1(text, uuid[]) from public, anon;')
  expect(MIG).not.toMatch(/\b(insert|update|delete)\s+(into\s+)?(catalogue|pipeline)\./i)
  expect(MIG).toMatch(/^-- Replaces: nothing\.$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\.$/m)
  expect(UI).toContain('const pv=isProviderIdList(s)')
  expect(UI).toContain('<ProviderListPicker value={v} onChange={setV} label={s.label}')
  expect(UI).toContain('pv?<ProviderNames value={s.value}/>')
  expect(PICK).toContain("supabase.rpc('admin_provider_pick_v1',args)")
})

test.describe('mocked browser', () => {
  test('Settings › Pipeline settings: providers shown by name, one added by name and one removed, saved as ids with a reason', async ({ page }) => {
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_settings_register_read', (route) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({
      can_manage: true, check: [], jobs: 90,
      sections: [{ section: 'Intake dates', settings: [
        { key: 'intake_dates.nearest_start_providers', label: 'Intake dates: providers using the nearest start', help: 'Providers (ids) for which Rule B may admit dates. Empty: Rule B admits for no provider and only the shadow is computed.', kind: 'list', value: [MONASH, RMIT], min: 0, max: null, unit: 'provider ids', used_by: 'security.intake_dates_plan_v3', reason: 'update the providers', updated_at: '2026-11-11T03:37:19Z' }] }] }) }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_pick_v1', async (route) => {
      const a = route.request().postDataJSON() || {}
      const all = [{ id: MONASH, name: 'Monash University', country: 'AU' }, { id: RMIT, name: 'RMIT University (RMIT)', country: 'AU' }, { id: SWIN, name: 'Swinburne University of Technology', country: 'AU' }]
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({
        named: all.filter((p) => (a.p_ids || []).includes(p.id)),
        found: a.p_query ? all.filter((p) => p.name.toLowerCase().includes(String(a.p_query).toLowerCase())) : [] }) })
    })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_toolsets_write', async (route) => { calls.push(route.request().postDataJSON()); return route.fulfill({ status: 200, contentType: 'application/json', body: '{"ok":true}' }) })
    await page.goto('/#environment')
    const sec = page.locator('[data-register-section="Intake dates"]')
    await sec.locator('.cf-card-toggle').click()
    const row = sec.locator('[data-register-setting="intake_dates.nearest_start_providers"]')
    await expect(row.locator(`[data-provider-chip="${MONASH}"]`)).toContainText('Monash University (AU)')
    await expect(row.locator(`[data-provider-chip="${RMIT}"]`)).toContainText('RMIT University (RMIT) (AU)')
    await expect(row).not.toContainText(MONASH)
    await row.getByLabel('Add a provider to Intake dates: providers using the nearest start').fill('swin')
    await row.getByRole('option', { name: /Swinburne University of Technology/ }).click()
    await expect(row.locator(`[data-provider-chip="${SWIN}"]`)).toContainText('Swinburne University of Technology')
    await row.getByRole('button', { name: 'Remove Monash University' }).click()
    await expect(row.locator(`[data-provider-chip="${MONASH}"]`)).toHaveCount(0)
    const save = row.getByRole('button', { name: 'Save' })
    await expect(save).toBeDisabled()
    await row.getByLabel('Reason').fill('Add Swinburne after its shadow audit; Monash paused')
    await save.click()
    await expect.poll(() => calls[0]).toEqual({ p_action: 'setting', p_args: { toolset: 'pipeline', key: 'intake_dates.nearest_start_providers', value: [RMIT, SWIN], reason: 'Add Swinburne after its shadow audit; Monash paused' } })
  })
})
