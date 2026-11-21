// Guards: Platform Admin 21 Nov 2026 13:11 AEDT (S1-RM-Design s935, standing rule "Self-Sustaining API & Key Governance"): Settings › API usage is read from the
// database for every consumer API version (v1, v2, v3 and any later one) and every key, with live 24 h / 7 d / 30 d usage; each (consumer, version) has its own key
// that rotates on its own with a dual-key overlap; v3 signs in and logs with its own key. Nothing about a version is written into the screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261121200000_cf247_s935_api_usage_versions_and_keys.sql', 'utf8')
const code = MIG.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
const UI = fs.readFileSync('src/ApiUsagePanel.jsx', 'utf8')
const W3 = fs.readFileSync('supabase/functions/website-api-v3/index.ts', 'utf8')
const Z3 = fs.readFileSync('supabase/functions/zoho-api-v3/index.ts', 'utf8')

test('s935 register: every consumer API version is a database row; the read path returns registered and unregistered versions and every key store', () => {
  for (const [p, v, e] of [['website', 'v1', 'website-course-api'], ['website', 'v1', 'wix-course-api'], ['zoho', 'v1', 'zoho-course-api'], ['website', 'v2', 'website-api-v2'],
    ['zoho', 'v2', 'zoho-api-v2'], ['website', 'v3', 'website-api-v3'], ['zoho', 'v3', 'zoho-api-v3']]) expect(code).toContain(`('${p}', '${v}', '${e}',`)
  expect(code).toContain('comment on table pipeline.api_versions is')
  // every key store, and versions seen in keys or the log that the register does not name
  for (const s of ['from private.api_keys k', 'from private.website_integration_credentials c', 'from private.zoho_integration_credentials c', "'Not registered in pipeline.api_versions'"]) expect(code).toContain(s)
  for (const w of ["('24h', interval '24 hours')", "('7d', interval '7 days')", "('30d', interval '30 days')", 'percentile_cont(0.95)', "'error_rate'", "'client_errors'", "'server_errors'"]) expect(code).toContain(w)
  expect(code).toContain("'versions', security.api_usage_versions_v1());")
  // the coverage check is a post-check: nothing active is missing from the read path
  expect(code).toContain("if jsonb_array_length(c->'missing_versions') > 0 or jsonb_array_length(c->'missing_keys') > 0 then raise exception")
  expect(code).toContain("if (select count(distinct api_version) from jsonb_to_recordset(security.api_usage_versions_v1()) x(api_version text)) < 3 then raise exception")
})

test('s935 keys: one per (consumer, version); v3 keys start not issued, the website v2 key bridges v3 only as a previous key; rotation names the version', () => {
  expect(code).toContain("'website_developer_v3', 'website', 'v3'")
  expect(code).toContain("replace(key_name, '_v2', '_v3') key_name_v3")
  expect(code).toContain("k.token_sha256, now() + make_interval(days => security.pipeline_num_v1('api.new_key_bridge_days', 14)::int)")
  expect(code).not.toMatch(/token_sha256, enabled, rate_per_minute, note\)\s*select 'website_developer_v3', 'website', 'v3', k\.consumer, k\.token_sha256/)
  expect(code).toContain("select * into k from private.api_keys where platform = p_platform and api_version = p_version and enabled and token_sha256 = v_h;")
  expect(code).toContain("'cf' || case k.platform when 'zoho' then 'z' else 'w' end || regexp_replace(k.api_version, '\\D', '', 'g') || '_'")
  expect(code).toContain("'83e3fb935eb11a3be535c3d26ece1ee8'"); expect(code).toContain("'3aa81da553a96b02861f7b0f69adbeee'")
  expect(code).toContain("raise exception 'post-check: Zoho v3 accepted a v2 key'")
  expect(code).toContain("raise exception 'post-check: the version sign-in accepted another platform''s key'")
})

test('s935 v3 endpoints sign in and log by (consumer, version); v1 and v2 keep their frozen sign-in', () => {
  for (const [src, p] of [[W3, 'website'], [Z3, 'zoho']]) {
    expect(src).toContain(`svc.schema("pipeline").rpc("api_key_auth_v1", { p_platform: "${p}", p_version: "v3",`)
    expect(src).toContain(`svc.schema("pipeline").rpc("api_request_log_v1", { p_platform: "${p}", p_version: "v3",`)
  }
  expect(fs.readFileSync('supabase/functions/website-api-v2/index.ts', 'utf8')).toContain('svc.rpc("website_api_v2_auth"')
  expect(fs.readFileSync('supabase/functions/zoho-api-v2/index.ts', 'utf8')).toContain('svc.rpc("zoho_v2_auth"')
  expect((MIG.match(/consumer_api_check_v1/g) || []).length).toBeGreaterThanOrEqual(2)
  expect((MIG.match(/pipeline\.manual_locks\) <> 7585/g) || []).length).toBe(2)
  expect(code).not.toMatch(/create\s+(or replace\s+)?function\s+public\.|create\s+view\b|\b(drop|delete|truncate)\b|cron\.schedule\(/i)
  expect(MIG).toMatch(/^-- Replaces:/m); expect(MIG).toMatch(/^-- Retires:/m)
})

test('s935 screen: no version written in the code; versions and keys render from the read', () => {
  expect(UI).not.toMatch(/const PLATFORMS\s*=/)
  expect(UI).not.toMatch(/'(Website|Zoho) API v[0-9]'/)
  expect(UI).toContain('versionsOf(d).map(v=>')
  for (const p of ['../../CLAUDE.md', '../../AGENTS.md']) expect(fs.readFileSync(new URL(p, import.meta.url), 'utf8')).toContain('### Standing Rule: Self-Sustaining API & Key Governance')
})

const st = (calls, ok, c4, c5, p95) => ({ calls, ok, client_errors: c4, server_errors: c5, previous_key_calls: 0, error_rate: calls ? (c4 + c5) / calls : null, p95_ms: p95 })
const versions = [
  { platform: 'website', api_version: 'v1', label: 'Website API v1', endpoints: ['website-course-api', 'wix-course-api'], status: 'active', frozen: true, registered: true, logged: false,
    keys: [{ key_name: 'coursefinder_website_wix_pilot_v1', consumer: 'Website integration (v1)', status: 'active', enabled: true, rotatable: false, masked: null, created_at: '2026-09-02T00:03:05Z', rotated_at: '2026-09-05T05:51:13Z', last_used_at: null, stats: null }] },
  { platform: 'website', api_version: 'v2', label: 'Website API v2', endpoints: ['website-api-v2'], status: 'active', frozen: true, registered: true, logged: true,
    keys: [{ key_name: 'website_developer_v2', consumer: 'Website (Wix) developer', status: 'active', enabled: true, rotatable: true, masked: 'cfw2_…4dc4acd4', created_at: '2026-10-16T00:52:32Z', rotated_at: null, last_used_at: '2026-11-20T07:31:22Z',
      stats: { '24h': st(400, 398, 2, 0, 900), '7d': st(4000, 3980, 18, 2, 1200), '30d': st(16087, 16000, 80, 7, 7722) } }] },
  { platform: 'website', api_version: 'v3', label: 'Website API v3', endpoints: ['website-api-v3'], status: 'active', frozen: false, registered: true, logged: true,
    keys: [{ key_name: 'website_developer_v3', consumer: 'Website (Wix) developer', status: 'rotating', enabled: true, rotatable: true, issued: false, masked: 'cfw3_…10207ec5', shares_with: 'website_developer_v2', previous_valid_until: '2026-12-05T02:00:00Z', created_at: '2026-11-21T02:00:00Z', rotated_at: null, last_used_at: null, stats: null },
      { key_name: 'website_developer_v2', consumer: 'Key of v2 used on v3', status: 'other_version', enabled: true, rotatable: false, masked: '…4dc4acd4', last_used_at: '2026-11-20T16:23:56Z', stats: { '30d': st(653, 640, 13, 0, 16089) } }] },
  { platform: 'zoho', api_version: 'v3', label: 'Zoho API v3', endpoints: ['zoho-api-v3'], status: 'active', frozen: false, registered: true, logged: true,
    keys: [{ key_name: 'zoho_creator_v3', consumer: 'Zoho Creator app', status: 'not_issued', enabled: true, rotatable: true, issued: false, masked: 'cfz3_…be252d20', created_at: '2026-11-21T02:00:00Z', rotated_at: null, last_used_at: null, stats: null }] },
  { platform: 'zoho', api_version: 'v4', label: 'Zoho API v4', endpoints: [], status: 'active', frozen: false, registered: false, logged: true,
    keys: [{ key_name: 'zoho_creator_v4', consumer: 'Zoho Creator app', status: 'active', enabled: true, rotatable: true, masked: 'cfz4_…aaaa0000', created_at: '2026-12-01T00:00:00Z', rotated_at: null, last_used_at: null, stats: null }] }]
const keyRow = (k, platform, api_version) => ({ key_name: k.key_name, platform, api_version, consumer: k.consumer, enabled: k.enabled, rate_per_minute: 120, key_hint: 'abcd1234', previous_valid_until: k.previous_valid_until || null, stats: {} })
const read = { days: 14, overlap_hours: 24, can_manage_keys: true, refreshed: { at: '2026-11-21T02:00:00Z', trigger: 'daily' }, daily: [], recent_errors: [], events: [], versions,
  keys: versions.flatMap(v => v.keys.filter(k => k.rotatable).map(k => keyRow(k, v.platform, v.api_version))) }

test.describe('mocked browser', () => {
  test('s935: every version (v1, v2, v3 and an unregistered v4) and every key shows with its status and live usage; v3 keys issue on their own', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_api_usage', r => r.fulfill({ json: read }))
    let rotated = null
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_api_key_rotate', r => { rotated = r.request().postDataJSON(); return r.fulfill({ json: { key_name: rotated.p_key_name, key: 'cfz3_TESTKEY', key_hint: 'ffff0000', previous_valid_until: null, platform: 'zoho' } }) })
    await page.goto('/#api-usage')
    for (const v of versions) await expect(page.locator(`.cf-api-platform[data-platform="${v.platform}"][data-version="${v.api_version}"]`)).toContainText(v.label)
    await expect(page.locator('.cf-api-platform[data-version="v4"]')).toContainText('not registered')
    await expect(page.locator('.cf-api-platform[data-version="v1"]')).toContainText('Not logged')
    const w2 = page.locator('.cf-api-platform[data-platform="website"][data-version="v2"] tr[data-version-key="website_developer_v2"]')
    await expect(w2).toContainText('400 / 4,000 / 16,087'); await expect(w2).toContainText('3,980 / 18 / 2'); await expect(w2).toContainText('cfw2_…4dc4acd4')
    const w3 = page.locator('.cf-api-platform[data-version="v3"][data-platform="website"]')
    await expect(w3.locator('tr[data-version-key="website_developer_v3"]')).toContainText('Rotating / Grace')
    await expect(w3.locator('tr[data-version-key="website_developer_v3"]')).toContainText('website_developer_v2 also works here until')
    await expect(w3.locator('tr[data-version-key="website_developer_v2"]')).toContainText("Earlier version's key used here")
    const z3 = page.locator('.cf-api-platform[data-platform="zoho"][data-version="v3"] tr[data-version-key="zoho_creator_v3"]')
    await expect(z3).toContainText('Not issued')
    await z3.getByRole('button', { name: /Issue key/ }).click()
    await page.getByRole('dialog').getByRole('button', { name: /Rotate|Make/ }).last().click()
    await expect(page.getByTestId('new-key')).toHaveText('cfz3_TESTKEY')
    expect(rotated.p_key_name).toBe('zoho_creator_v3')
  })
})
