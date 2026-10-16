// CF-247 (S49): Zoho API v2 on its own URL and keys. Platform Admin, 16 Oct 2026 09:43: "create separate API URL and Key for Zoho V2 API and
// keep it separate from Website API URL ... with summary and stat collection as well"; 09:55: "a separate URL for each API version going
// forward ... not with contracts calling in the URL". Decisions: keys "Creator + CRM sync"; "CSV seed + sync feed"; "Public + named contacts".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execSync } from 'node:child_process'

const fix = fs.readFileSync('supabase/migrations/20261016010000_cf247_api_data_fixes.sql', 'utf8')
const mig = fs.readFileSync('supabase/migrations/20261016020000_cf247_zoho_api_v2.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/zoho-api-v2/index.ts', 'utf8')
const deploy = fs.readFileSync('.github/workflows/deploy-edge-functions.yml', 'utf8')
const nav = fs.readFileSync('src/nav-map.js', 'utf8')
const settingsUi = fs.readFileSync('src/SettingsRegister.jsx', 'utf8')

test('data fixes: the latest year\'s fee in the projection; freshness is not a change', () => {
  expect(fix).toContain("(array_agg(f.amount order by f.fee_year desc nulls last, f.amount) filter(where f.basis in ('annual','indicative_annual')))[1] annual_amount,")
  expect(fix).not.toMatch(/^\s+min\(f\.amount\) filter/m)
  expect(fix).toContain("h := case when v is null then null else md5((v - 'generated_at' - 'freshness')::text) end;")
  expect(fix).toContain("update pipeline.website_sync_items set hash = md5((item - 'generated_at' - 'freshness')::text) where item is not null and removed_at is null;")
})

test('its own URL, its own keys, no contract field; v1 and the website untouched', () => {
  expect(deploy).toContain('[zoho-api-v2]=false')
  expect(fn).toContain('const API_VERSION = "zoho-v2";')
  expect(fn).not.toContain('body.contract')
  expect(fn).toContain('svc.rpc("zoho_v2_auth", { p_token_sha256: await sha256Hex(supplied) })')
  expect(fn).not.toMatch(/website_v2_|zoho_edge_/)
  for (const a of ['reference', 'search', 'course', 'courses', 'providers', 'provider', 'campuses', 'contacts', 'rankings', 'scholarships', 'scholarship', 'statistics', 'sync', 'export', 'report'])
    expect(fn).toContain(`"${a}"`)
  // keys: two consumers, only hashes in the repository
  expect(mig).toMatch(/\('zoho_creator_v2', 'zoho', 'v2', 'Zoho Creator app[^']*', '[0-9a-f]{64}'/)
  expect(mig).toMatch(/\('zoho_crm_sync_v2', 'zoho', 'v2', 'Zoho CRM sync[^']*', '[0-9a-f]{64}'/)
  expect(execSync('git grep -l "cfz2_" -- . ":!tests/uat/cf-247-s49-zoho-api-v2-contract.spec.mjs" || true').toString().trim()).toBe('')
  expect(mig).toContain("select * into k from private.api_keys where platform = 'zoho' and api_version = 'v2' and enabled and token_sha256 = lower(coalesce(p_token_sha256, ''));")
})

test('every call is logged and summed daily; limits are settings', () => {
  expect(fn).toContain('await svc.rpc("zoho_v2_log", {')
  expect(fn.match(/return fail\(|return finish\(/g).length).toBeGreaterThan(15)
  expect(fn).not.toMatch(/new Response\((?!text)/)
  expect(mig).toContain("select cron.schedule('api-usage-rollup', '4-59/15 * * * *', 'select security.api_usage_rollup_v1()');")
  expect(mig).toContain("delete from pipeline.api_requests where at < now() - make_interval(days => security.pipeline_num_v1('zoho.log_keep_days', 90)::int);")
  for (const k of ['zoho.rate_per_minute', 'zoho.page_max', 'zoho.sync_page_max', 'zoho.sync_item_unit_bytes', 'zoho.sync_countries', 'zoho.logo_link_days', 'zoho.logo_renew_before_days', 'zoho.log_keep_days', 'batch.zoho_sync_check'])
    expect(mig).toContain(`('pipeline', '${k}', `)
  expect(mig).toContain("'zoho.sync_countries', 'Countries in the Zoho change stream and CSV'")
  expect(nav).toContain("apiUsage: { label: 'API usage', slug: 'api-usage'")
  expect(settingsUi).toContain("const yn=s.kind==='boolean',ls=s.kind==='list',n=Number(v)")
})

test('what Zoho asked for: details in search results, provider by name or CRICOS, English bands, CRICOS-keyed stream and CSV', () => {
  expect(mig).toContain("v_band_max numeric := nullif(f->>'english_band_max','')::numeric;")
  expect(mig).toContain("and (v_pname is null or d.provider_name ilike '%'||v_pname||'%')")
  expect(mig).toContain("jsonb_agg(security.zoho_v2_course_extra_v1(api.website_v2_course_item(x.id, v_cities, v_postcodes), x.id) order by x.ord)")
  expect(mig).toContain("'cricos_course_code', (select upper(cr.registration_code) from catalogue.course_registrations cr")
  expect(mig).toContain("declare v_all text[] := array['provider', 'campus', 'contact', 'course'];")
  expect(mig).toContain("'type', case cp.kind when 'regulatory_peo' then 'head_of_institution' when 'public_general' then 'general' else cp.kind end,")
  expect(mig).toContain("v_head := 'course_id,cricos_course_code,title,provider_id,cricos_provider_code,provider_name,")
  expect(fn).toContain('"content-disposition": `attachment; filename="${name}"`')
  // its own change stream, so a Zoho delta never depends on the website's
  expect(mig).toContain("nextval('pipeline.zoho_sync_seq')")
  expect(mig).toContain("select cron.schedule('zoho-sync-check', '* * * * *', 'select security.zoho_sync_check_v1(security.pipeline_num_v1(''batch.zoho_sync_check'', 1500)::int)');")
})

test.describe('mocked browser', () => {
  test('Operations › API usage shows keys, days, actions and errors', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_api_usage', r => r.fulfill({ json: {
      days: 14,
      keys: [{ key_name: 'zoho_creator_v2', platform: 'zoho', api_version: 'v2', consumer: 'Zoho Creator app', enabled: true, rate_per_minute: 120, last_used_at: '2026-10-16T01:00:00Z' },
             { key_name: 'zoho_crm_sync_v2', platform: 'zoho', api_version: 'v2', consumer: 'Zoho CRM sync', enabled: true, rate_per_minute: 120, last_used_at: null }],
      daily: [{ day: '2026-10-16', platform: 'zoho', api_version: 'v2', key_name: 'zoho_creator_v2', action: 'search', calls: 40, ok: 38, client_errors: 1, rate_limited: 0, server_errors: 1, avg_ms: 420, p95_ms: 900, max_ms: 1200, items: 380, bytes: 900000, last_at: '2026-10-16T01:00:00Z' }],
      recent_errors: [{ at: '2026-10-16T00:59:00Z', key_name: 'zoho_creator_v2', action: 'search', status: 400, error_code: 'INVALID_INPUT', request_id: 'abc' }], last_hour: [] } }))
    await page.goto('/#api-usage')
    await expect(page.getByRole('heading', { name: 'API usage' }).first()).toBeVisible()
    await expect(page.locator('.cf-api-keys')).toContainText('zoho_crm_sync_v2')
    await expect(page.locator('.cf-api-keys')).toContainText('Never')
    await expect(page.locator('.cf-api-days')).toContainText('40')
    await expect(page.locator('.cf-api-errors')).toContainText('INVALID_INPUT')
  })
})

test('CSV seed then sync: the export gives the cursor to continue from', () => {
  const cur = fs.readFileSync('supabase/migrations/20261016030000_cf247_zoho_export_sync_cursor.sql', 'utf8')
  expect(cur).toContain("v_at bigint := (select coalesce(max(z.seq), 0) from pipeline.zoho_sync_items z);")
  expect(cur).toContain("'sync_cursor', rtrim(translate(replace(encode(convert_to(jsonb_build_object('v', 1, 'm', 'delta', 'a', v_at,")
  expect(fn).toContain('"x-sync-cursor": String(obj.sync_cursor ?? "")')
})

test('the CSV export comes in pages within the API time limit', () => {
  const pg = fs.readFileSync('supabase/migrations/20261016040000_cf247_zoho_export_pages.sql', 'utf8')
  expect(pg).toContain("v_lim int := greatest(security.pipeline_num_v1('zoho.export_page_rows', 3000)::int, 1);")
  expect(pg).toContain("order by z.item->'provider'->>'name', z.item->>'title', z.item_key limit v_lim offset v_off) x;")
  expect(pg).toContain("'has_more', v_off + coalesce(v_n, 0) < v_total,")
  expect(pg).toContain("set status = 'retiring', replaced_by = 'public.zoho_v2_export_page(text, integer)'")
  expect(fn).toContain('fn = "zoho_v2_export_page"; args = { p_entity: e, p_page: page };')
  expect(fn).toContain('"x-has-more": String(obj.has_more ?? false)')
})

test('website v2 at its own URL, in parallel: same functions, own key, logged; wix-course-api untouched', () => {
  const wfn = fs.readFileSync('supabase/functions/website-api-v2/index.ts', 'utf8')
  const wmig = fs.readFileSync('supabase/migrations/20261016050000_cf247_website_api_v2_url.sql', 'utf8')
  expect(deploy).toContain('[website-api-v2]=false')
  expect(wfn).toContain('const API_VERSION = "website-v2";')
  expect(wfn).not.toContain('body.contract')
  expect(wfn).toContain('svc.rpc("website_api_v2_auth", { p_token_sha256: await sha256Hex(supplied) })')
  expect(wfn).toContain('await svc.rpc("website_api_v2_log", {')
  for (const f of ['website_v2_reference', 'website_v2_course_search', 'website_v2_providers', 'website_v2_rankings', 'website_v2_scholarships', 'website_v2_course', 'website_v2_provider', 'website_v2_scholarship', 'website_v2_sync'])
    expect(wfn).toContain(`fn = "${f}"`)
  expect(wfn).not.toMatch(/new Response\((?!text)/)
  expect(wmig).toMatch(/\('website_developer_v2', 'website', 'v2', 'Website \(Wix\) developer', '[0-9a-f]{64}'/)
  expect(wmig).toContain("where platform = 'website' and api_version = 'v2' and enabled")
  expect(wmig).toContain("security.pipeline_num_v1('website.rate_per_minute', 300)")
  expect(execSync('git grep -l "cfw2_" -- . ":!tests/uat/cf-247-s49-zoho-api-v2-contract.spec.mjs" || true').toString().trim()).toBe('')
  // the contract path on the old URL is unchanged by this change
  expect(execSync('git diff --name-only origin/main -- supabase/functions/wix-course-api || true').toString().trim()).toBe('')
})
