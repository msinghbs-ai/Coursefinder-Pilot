// CF-247 (S50): API console for both API version URLs. Platform Admin, 16 Oct 2026 14:31: "Create me a ui to check stats on Both APIs with
// relevant metrics/API calls or statistics, success & failure, last login, full sync, delta sync, bandwidth, load size etc. be able to rotate
// their keys. and on Demand fresh statistics by pressing a button, otherwise get refresh daily basis."
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261016060000_cf247_api_console.sql', 'utf8')
const zoho = fs.readFileSync('supabase/functions/zoho-api-v2/index.ts', 'utf8')
const web = fs.readFileSync('supabase/functions/website-api-v2/index.ts', 'utf8')
const ui = fs.readFileSync('src/ApiUsagePanel.jsx', 'utf8')

test('statistics refresh daily and on demand; per key for 24 hours, 7 days and 30 days', () => {
  expect(mig).toContain("select cron.schedule('api-usage-rollup', '20 13 * * *', 'select security.api_usage_refresh_v1(''daily'')');")
  expect(mig).toContain("return security.api_usage_refresh_v1('on_demand');")
  expect(mig).toContain("(values ('24h', interval '1 day'), ('7d', interval '7 days'), ('30d', interval '30 days'))")
  for (const k of ["'success_rate'", "'bytes'", "'max_bytes'", "'last_call_at'", "'last_ok_at'", "'full_load_pages'", "'delta_calls'", "'last_full_load'", "'previous_key_last_at'"])
    expect(mig).toContain(k)
  expect(ui).toContain("supabase.rpc('admin_api_usage_refresh')")
})

test('sync calls are logged as full-load start, page, end or delta; the old key is logged apart', () => {
  for (const fn of [zoho, web]) {
    expect(fn).toContain('action = obj.mode === "delta" ? "sync_delta" : obj.full_load_complete === true ? "sync_full_end" : first ? "sync_full_start" : "sync_full";')
    expect(fn).toContain('if (id.previous === true) keyName = `${baseKey}#previous`;')
    expect(fn).toMatch(/_rate", \{ p_key_name: baseKey,/)
  }
})

test('rotation: a random key made in the database, shown once, only its hash kept; old key works for the overlap', () => {
  expect(mig).toContain("rtrim(translate(encode(extensions.gen_random_bytes(30), 'base64'), '+/', '-_'), '=')")
  expect(mig).toContain("v_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');")
  expect(mig).toContain("if security.current_role_rank() < 6 then raise exception 'platform_admin role required'")
  expect(mig).toContain("and previous_valid_until > now()")
  expect(mig).toContain("'api.key_rotate_overlap_hours'")
  // the key itself is never written to a table: events keep no key or hash
  const events = mig.slice(mig.indexOf('create table if not exists pipeline.api_key_events'), mig.indexOf("comment on table pipeline.api_key_events"))
  expect(events).not.toMatch(/token|sha256/)
  expect(mig).not.toMatch(/insert into pipeline\.api_key_events\([^)]*key\b[^_]/)
  expect(ui).toContain('This is the only time the key is shown: it is not stored anywhere.')
})

const stats = (calls, ok) => ({ calls, ok, client_errors: calls - ok, rate_limited: 0, server_errors: 0, success_rate: calls ? Math.round(1000 * ok / calls) / 10 : null,
  bytes: 5242880, avg_bytes: 20480, max_bytes: 614400, items: 900, avg_ms: 410, p95_ms: 900, last_call_at: '2026-10-16T03:00:00Z', last_ok_at: '2026-10-16T03:00:00Z',
  last_error_at: '2026-10-16T02:00:00Z', last_error_code: 'INVALID_INPUT', full_load_pages: 260, full_load_bytes: 104857600, full_loads_completed: 1, delta_calls: 12, delta_items: 40,
  delta_bytes: 20480, last_delta_at: '2026-10-16T02:30:00Z', exports: 9, export_bytes: 7900000, searches: 20, previous_key_calls: 0, previous_key_last_at: null,
  last_full_load: { started_at: '2026-10-16T01:00:00Z', finished_at: '2026-10-16T01:05:00Z', pages: 260, items: 41700, bytes: 104857600, seconds: 300 }, last_full_load_started_at: '2026-10-16T01:00:00Z' })
const read = manage => ({ days: 14, overlap_hours: 24, can_manage_keys: manage,
  refreshed: { at: '2026-10-16T03:10:00Z', trigger: 'on_demand', elapsed_ms: 120, by: 'admin@example.com' },
  keys: [
    { key_name: 'zoho_crm_sync_v2', platform: 'zoho', api_version: 'v2', consumer: 'Zoho CRM sync', enabled: true, rate_per_minute: 120, key_hint: 'b401f0d6', last_used_at: '2026-10-16T03:00:00Z', rotated_at: null, previous_valid_until: null, stats: { '24h': stats(40, 38), '7d': stats(100, 96), '30d': stats(100, 96) } },
    { key_name: 'website_developer_v2', platform: 'website', api_version: 'v2', consumer: 'Website (Wix) developer', enabled: true, rate_per_minute: 300, key_hint: '4dc4acd4', last_used_at: null, rotated_at: null, previous_valid_until: null, stats: {} }],
  daily: [{ day: '2026-10-16', platform: 'zoho', api_version: 'v2', key_name: 'zoho_crm_sync_v2', action: 'sync_full', calls: 40, ok: 38, client_errors: 2, rate_limited: 0, server_errors: 0, avg_ms: 420, p95_ms: 900, max_ms: 1200, items: 380, bytes: 900000, last_at: '2026-10-16T03:00:00Z' }],
  recent_errors: [], events: [] })

test.describe('mocked browser', () => {
  test('both APIs with success, failures, bandwidth, last call, full loads and deltas; refresh on demand', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 6 })
    let refreshed = 0
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_api_usage', r => r.fulfill({ json: read(true) }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_api_usage_refresh', r => { refreshed++; return r.fulfill({ json: { at: '2026-10-16T03:20:00Z', trigger: 'on_demand' } }) })
    await page.goto('/#api-usage')
    await expect(page.locator('.cf-api-asof')).toContainText('Statistics as of')
    await expect(page.locator('.cf-api-platform[data-platform="zoho"]')).toContainText('96.0%')
    await expect(page.locator('.cf-api-platform[data-platform="website"]')).toContainText('Never')
    const row = page.locator('.cf-api-keys tr[data-key="zoho_crm_sync_v2"]')
    await expect(row).toContainText('5 MB')
    await expect(row).toContainText('last INVALID_INPUT')
    await expect(page.locator('.cf-api-sync')).toContainText('41,700')
    await expect(page.locator('.cf-api-sync')).toContainText('5 min')
    await page.getByRole('button', { name: 'Refresh statistics now' }).click()
    await expect.poll(() => refreshed).toBe(1)
  })

  test('rotate shows the new key once; switch off asks first', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 6 })
    let rotate = null
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_api_usage', r => r.fulfill({ json: read(true) }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_api_key_rotate', r => { rotate = r.request().postDataJSON(); return r.fulfill({ json: { key_name: 'zoho_crm_sync_v2', key: 'TESTONLY-new-key-value', key_hint: 'abcd1234', previous_valid_until: '2026-10-17T03:00:00Z', platform: 'zoho' } }) })
    await page.goto('/#api-usage')
    await page.locator('.cf-api-keys tr[data-key="zoho_crm_sync_v2"]').getByRole('button', { name: 'Rotate' }).click()
    await expect(page.getByRole('dialog', { name: 'Rotate zoho_crm_sync_v2' })).toBeVisible()
    await page.getByLabel('Hours the old key keeps working').fill('12')
    await page.getByRole('button', { name: 'Rotate key' }).click()
    await expect(page.getByTestId('new-key')).toHaveText('TESTONLY-new-key-value')
    expect(rotate).toEqual({ p_key_name: 'zoho_crm_sync_v2', p_overlap_hours: 12, p_note: null })
    await page.getByRole('button', { name: 'I have stored it' }).click()
    await expect(page.getByTestId('new-key')).toHaveCount(0)
    await page.locator('.cf-api-keys tr[data-key="website_developer_v2"]').getByRole('button', { name: 'Switch off' }).click()
    await expect(page.getByRole('dialog', { name: 'Switch off website_developer_v2' })).toBeVisible()
  })

  test('below Platform Admin: statistics only, no key actions', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_api_usage', r => r.fulfill({ json: read(false) }))
    await page.goto('/#api-usage')
    await expect(page.locator('.cf-api-keys')).toContainText('zoho_crm_sync_v2')
    await expect(page.getByRole('button', { name: 'Rotate' })).toHaveCount(0)
    await expect(page.getByText('Rotating and switching keys is for the Platform Admin.')).toBeVisible()
  })
})
