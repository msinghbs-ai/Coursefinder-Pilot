// CF-247 v2.15.277 (S39): Platform Admin, 14 Oct 2026 20:43: "For ranking, we can pass it on v2 api and for logos we can pass it on as file
// links to be stored in wix platform with maximun validity. And subsequent api requests only pass changed data unless queried for full load."
// Decisions: approved to display; logo links 1 year, renewed in the delta; a new sync action with a cursor. Website API v2 is additive only.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const mig = fs.readFileSync('supabase/migrations/20261014110000_cf247_website_sync_and_display_terms.sql', 'utf8')
const edge = fs.readFileSync('supabase/functions/wix-course-api/index.ts', 'utf8')

test('display terms come from two Yes/No settings, not a fixed value in five functions', () => {
  expect(mig).toContain("('pipeline', 'website.rankings_display_approved', 'Website: rankings approved for display'")
  expect(mig).toContain("('pipeline', 'website.logos_display_approved', 'Website: logos approved for display'")
  expect((mig.match(/'terms_status', security\.website_terms_status_v1\('rankings'\)/g) || []).length).toBe(4)
  expect((mig.match(/'terms_status', security\.website_terms_status_v1\('logos'\)/g) || []).length).toBe(1)
  // every replaced website function is md5-guarded before and checked after
  for (const f of ['api.website_v2_provider_logo(uuid)', 'public.website_v2_rankings(jsonb,integer,integer)', 'public.website_v2_reference()']) expect((mig.match(new RegExp(f.replace(/[().]/g, '\\$&'), 'g')) || []).length).toBeGreaterThanOrEqual(2)
  expect(mig).not.toMatch(/^(drop|delete|truncate)\b/im)
})

test('sync: full load by pages, then only changes with removals, by an opaque cursor; change check is a catalogued job sized by a setting', () => {
  expect(mig).toContain('CREATE OR REPLACE FUNCTION public.website_v2_sync(p_cursor text DEFAULT NULL::text, p_full boolean DEFAULT false, p_entities text[] DEFAULT NULL::text[], p_page_size integer DEFAULT NULL::integer)')
  expect(mig).toContain("and (v_mode = 'delta' or (i.removed_at is null and i.seq <= v_s))")
  expect(mig).toContain("jsonb_build_object('entity', z.entity, 'id', z.item_key, 'seq', z.seq, 'change', 'remove')")
  expect(mig).toContain("when v_mode = 'full' then jsonb_build_object('v', 1, 'm', 'delta', 'a', v_s, 'e', to_jsonb(v_e))")
  expect(mig).toContain("if p_entity = 'course' then v := case when p_ref is null then null else api.website_v2_course_item(p_ref, null, null) end;")
  expect(mig).toContain("h := case when v is null then null else md5((v - 'generated_at')::text) end;")
  expect(mig).toContain("elsif e = 'logo' and it.seq_at < now() - v_renew then")
  expect(mig).toContain("select cron.schedule('website-sync-check', '* * * * *', 'select security.website_sync_check_v1(security.pipeline_num_v1(''batch.website_sync_check'', 600)::int)');")
  expect(mig).toContain("values ('website-sync-check', 'Search and API', 40,")
  expect(mig).toContain("grant execute on function public.website_v2_sync(text, boolean, text[], integer) to service_role;")
  // fix: checked_through stays null until every chosen entity has finished a pass
  expect(fs.readFileSync('supabase/migrations/20261014111500_cf247_website_sync_checked_through.sql', 'utf8')).toContain("'checked_through', (select case when bool_or(s.last_cycle_at is null) then null else min(s.last_cycle_at) end")
})

test('edge: sync is added at the end of the actions; logo link validity is read from the setting', () => {
  expect(edge).toContain('const V2_ACTIONS = ["reference","search","course","providers","provider","rankings","scholarships","scholarship","sync"];')
  expect(edge).toContain('fn="website_v2_sync"; args={p_cursor:cleanText(body.cursor)||null,p_full:body.full_load===true,')
  expect(edge).toContain('await svc.rpc("svc_website_settings_v1")')
  expect(edge).toContain('const LOGO_TTL_SECONDS=Math.round(days*86400); // fixed: seconds in a day')
  expect(edge).not.toContain('const LOGO_TTL_SECONDS = 86400;')
})

test.describe('mocked browser', () => {
  test('Pipeline settings: Website API shows Yes/No settings; a change needs a reason and saves true or false', async ({ page }) => {
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_settings_register_read', route => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({
      can_manage: true, check: [], jobs: 90,
      sections: [{ section: 'Website API', settings: [
        { key: 'website.rankings_display_approved', label: 'Website: rankings approved for display', help: 'Yes: approved.', kind: 'boolean', value: true, min: null, max: null, unit: 'yes or no', used_by: 'website API v2: rankings', reason: 'Platform Admin 14 Oct 2026', updated_at: '2026-10-14T09:50:00Z' },
        { key: 'website.logo_link_days', label: 'Website: logo link valid for', help: '', kind: 'number', value: 365, min: 1, max: 730, unit: 'days', used_by: 'wix-course-api (logo links)', reason: '', updated_at: null }] }] }) }))
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_toolsets_write', async route => { calls.push(route.request().postDataJSON()); return route.fulfill({ status: 200, contentType: 'application/json', body: '{"ok":true}' }) })
    await page.goto('/#environment')
    const sec = page.locator('[data-register-section="Website API"]')
    await sec.locator('.cf-card-toggle').click()
    const row = sec.locator('[data-register-setting="website.rankings_display_approved"]')
    const sel = row.getByLabel('Website: rankings approved for display')
    await expect(sel).toHaveValue('true')
    await sel.selectOption('false')
    const save = row.getByRole('button', { name: 'Save' })
    await expect(save).toBeDisabled()
    await row.getByLabel('Reason').fill('Management asked to hold rankings')
    await save.click()
    await expect.poll(() => calls[0]).toEqual({ p_action: 'setting', p_args: { toolset: 'pipeline', key: 'website.rankings_display_approved', value: false, reason: 'Management asked to hold rankings' } })
    await expect(sec.locator('[data-register-setting="website.logo_link_days"]').getByLabel('Website: logo link valid for')).toHaveValue('365')
  })
})

// 15 Oct 2026: reference passed the API's 8 s statement limit under load; it now returns a copy built every 15 minutes
test('reference: answered from a copy built every 15 minutes (catalogued job); live build only when no copy exists', () => {
  const m = fs.readFileSync('supabase/migrations/20261015000200_cf247_website_reference_cache.sql', 'utf8')
  expect(m).toContain("select coalesce((select c.payload - 'generated_at' || jsonb_build_object('generated_at', c.built_at) from pipeline.website_reference_cache c where c.id = 1),")
  expect(m).toContain("select cron.schedule('website-reference-cache', '2-59/15 * * * *', 'select security.website_reference_cache_refresh_v1()');")
  expect(m).toContain("values ('website-reference-cache', 'Search and API', 41,")
  expect(m).not.toMatch(/^(drop|delete|truncate)\b/im)
})
