// CF-247 (S44): Platform Admin, 15 Oct 2026 12:55: "Bug/fix: i'm unable to upload Uni Logos or request to find it". Decisions: "make it
// background Job to find and attached + Plus admin to upload by clicking on logo from provider details blade or list editing"; upload by the
// Platform Admin. The logo is made clickable by the screen itself (a page watcher missed panels whose details arrived late).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261015050000_cf247_provider_logo_finder.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const logo = fs.readFileSync('supabase/functions/coverage-sweep/logo.ts', 'utf8')
const upload = fs.readFileSync('supabase/functions/provider-asset-upload/index.ts', 'utf8')
const src = fs.readFileSync('src/ProviderLogo.jsx', 'utf8')
const main = fs.readFileSync('src/mature-main.jsx', 'utf8')

test('who may change logos is one setting, read by the screens and by the upload function', () => {
  expect(mig).toContain("('pipeline', 'logo.upload_min_rank', 'Lowest role that can upload or find a logo'")
  expect(mig).toContain("select security.pipeline_num_v1('logo.upload_min_rank', 6)::int")
  expect(upload).toContain('gate.rpc("svc_logo_upload_allowed",{p_user_id:context.user_id})')
  expect(upload).not.toContain('role_rank||0)<5')
  expect(src).toContain("supabase.rpc('admin_provider_logo_capability')")
  expect(src).not.toContain('enableProviderLogoUpload')
})

test('the finder: a job, a request from the editor, attached only when the provider has no logo, not found flagged', () => {
  expect(mig).toContain("select cron.schedule('logo-find', '*/10 * * * *', 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''logo_find'', ''limit'', security.pipeline_num_v1(''batch.logo_find'', 12)::int))');")
  expect(mig).toContain("v_status := 'skipped_has_logo';  -- a person added one meanwhile: theirs stays")
  expect(mig).toContain("'logo', 'logo_not_found'")
  expect(mig).toContain('CREATE OR REPLACE FUNCTION public.admin_provider_logo_find_request(p_provider_id uuid)')
  expect(worker).toContain('if (mode === "logo_find") {')
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(2[5-9]|3\d)\.\d+";/)
  expect(logo).toContain('export function svgSafe(text: string): boolean {')
  expect(src).toContain("supabase.rpc('admin_provider_logo_find_request',{p_provider_id:providerId})")
})

test('the logo is editable in the provider panel and the logo list', () => {
  expect(main).toContain("size={54} editable/>")
  expect(main).toContain("<ProviderBrand providerId={r.provider_id} name={r.provider_name} size={28} editable/>")
  expect(src).toContain('function bindListEdit(slot,providerId,name){')
})

test.describe('mocked browser', () => {
  const id = '11111111-1111-4111-8111-111111111111'
  async function setup(page, can) {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: can ? 6 : 4 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
      const b = route.request().postDataJSON() || {}
      if (b.p_operation === 'providers_page') return route.fulfill({ json: { total: 1, items: [{ id, canonical_name: 'Alpha University', country_code: 'AU', course_count: 20, lifecycle_status: 'active', publication_status: 'published' }] } })
      if (b.p_operation === 'provider_detail') { await new Promise(r => setTimeout(r, 800)); return route.fulfill({ json: { id, canonical_name: 'Alpha University', country_code: 'AU' } }) }
      return route.fallback()
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_logo_capability', r => r.fulfill({ json: { rank: can ? 6 : 4, min_rank: 6, can_upload: can, finder: { found: 3, not_found: 1, waiting: 2 } } }))
    const calls = { upload: 0, find: [] }
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_logo_find_request', async r => { calls.find.push(r.request().postDataJSON()); await r.fulfill({ json: { provider_id: id, queued: true, has_website: true } }) })
    await page.route('https://example.supabase.co/functions/v1/**', async r => { if (r.request().url().includes('provider-asset-upload')) calls.upload++; await r.fulfill({ json: { ok: true, items: [], url: null } }) })
    return calls
  }

  test('a provider opened by link, details arriving late: the Platform Admin clicks the logo, uploads, and asks the finder', async ({ page }) => {
    const calls = await setup(page, true)
    await page.goto('/#providers?id=' + id)
    const logo = page.locator('.m-drawer-provider .cf-provider-logo[data-logo-edit="1"]')
    await expect(logo).toHaveCount(1)
    await logo.click()
    await page.locator('.cf-logo-editor [data-file]').setInputFiles({ name: 'l.png', mimeType: 'image/png', buffer: Buffer.alloc(500, 1) })
    await page.locator('.cf-logo-editor [data-save]').click()
    await expect(page.locator('.cf-logo-upload-note')).toHaveText('Logo updated')
    expect(calls.upload).toBe(1)
    await logo.click()
    await page.locator('.cf-logo-editor [data-find]').click()
    await expect(page.locator('.cf-logo-upload-note')).toContainText('Queued')
    expect(calls.find).toEqual([{ p_provider_id: id }])
  })

  test('a role below the setting sees the logo but cannot change it', async ({ page }) => {
    await setup(page, false)
    await page.goto('/#providers?id=' + id)
    await expect(page.locator('.m-drawer-provider .cf-provider-logo')).toHaveCount(1)
    await page.waitForTimeout(500)
    await expect(page.locator('[data-logo-edit="1"]')).toHaveCount(0)
  })
})
