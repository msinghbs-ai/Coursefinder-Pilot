import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// v2.15.215 (Platform Admin, 7 Oct 2026 20:28): automatic adapter build and the Providers-list Adapter column.
test('automatic build: migrations, rank gates and UI wiring', () => {
  const settings = fs.readFileSync('supabase/migrations/20261007001900_cf247_adapter_autobuild.sql', 'utf8')
  expect(settings).toContain('autobuild_per_day')
  expect(settings).toContain('autobuild_credits')
  const fn = fs.readFileSync('supabase/migrations/20261007001901_cf247_adapter_autobuild_functions.sql', 'utf8')
  expect(fn).toContain("coalesce(v_rank, 0) < 5")
  expect(fn).toContain("if v_rank < 6 then raise exception 'Platform Admin required'")
  expect(fn).toContain('this provider already has an admitting adapter')
  expect(fn).toContain('the automatic builds for today are used')
  const qualify = fs.readFileSync('supabase/migrations/20261007001902_cf247_adapter_autobuild_qualify.sql', 'utf8')
  expect(qualify).toContain("when coalesce((v_x->>'read')::int, 0) < 5 then 'read on fewer than 5 pages'")
  expect(qualify).toContain("when (v_x->>'agree_share')::numeric < 0.9 then 'agrees on under 90% of checked courses'")
  expect(qualify).not.toContain('admin_uni_adapter_control')
  const step = fs.readFileSync('supabase/migrations/20261007001903_cf247_adapter_autobuild_step.sql', 'utf8')
  expect(step).toContain('perform security.adapter_autobuild_qualify_v1(b.id);')
  expect(step).not.toContain('admin_uni_adapter_control')
  const admit = fs.readFileSync('supabase/migrations/20261007001904_cf247_adapter_autobuild_admit.sql', 'utf8')
  expect(admit).toContain("coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required'")
  expect(admit).toContain("x = any(v_ready)")
  const cron = fs.readFileSync('supabase/migrations/20261007001905_cf247_adapter_autobuild_schedule.sql', 'utf8')
  expect(cron).toContain("cron.schedule('adapter-autobuild', '*/2 * * * *'")
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toContain("const adapterCol=type==='provider'&&!completenessMode&&Number(rank)>=6")
  expect(main).toContain("navigate?.('layer2',{tab:'builder',provider:r.id})")
  const ui = fs.readFileSync('src/AdapterBuilderTab.jsx', 'utf8')
  expect(ui).toContain("supabase.rpc('admin_adapter_autobuild',{p_action:'read'")
  expect(ui).toContain("const canStart=st.can_manage&&st.adapter!=='admitting'&&!buildActive(status)")
})

test.describe('mocked browser', () => {
  const providers = { total: 2, items: [
    { id: 'p-uwa', canonical_name: 'The University of Western Australia', country_code: 'AU', course_count: 330, lifecycle_status: 'active', publication_status: 'draft' },
    { id: 'p-new', canonical_name: 'New Test Institute', country_code: 'AU', course_count: 12, lifecycle_status: 'active', publication_status: 'draft' }] }
  const states = { 'p-uwa': { adapter: 'admitting', admit_fields: ['intakes'], build: null }, 'p-new': { adapter: null, admit_fields: null, build: null } }
  async function setup(page, rank) {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
      const b = route.request().postDataJSON() || {}
      if (b.p_operation === 'providers_page') return route.fulfill({ json: providers })
      return route.fallback()
    })
    const calls = []
    let build = null
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_autobuild', async route => {
      const b = route.request().postDataJSON() || {}
      calls.push(b)
      if (b.p_action === 'states') return route.fulfill({ json: states })
      if (b.p_action === 'start') { build = { id: 'b1', status: 'finding_pages', note: 'Finding pages: 4 of 40 done, 9 credits used.' }; return route.fulfill({ json: { ok: true, build_id: 'b1' } }) }
      return route.fulfill({ json: { adapter: null, build, can_manage: true, today: build ? 1 : 0, per_day: 25, model: 'qwen/qwen3-30b-a3b-instruct-2507' } })
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder_basics', route => route.fulfill({ json: { provider_id: 'p-new', name: 'New Test Institute', country: 'AU', courses: 12, pages: { stored: 0, read: 0 }, adapter: null, central: [], suggested: [], can_manage: true } }))
    return calls
  }

  test('Platform Admin: Adapter column opens the builder; Build automatically starts a build', async ({ page }) => {
    const calls = await setup(page, 6)
    await page.goto('/#providers')
    await expect(page.locator('[data-adapter-cell="admitting"]')).toContainText('Open adapter')
    await expect(page.locator('[data-adapter-cell="none"]')).toContainText('Create adapter')
    await page.locator('[data-adapter-cell="none"] button').click()
    await expect(page).toHaveURL(/layer-2-discovery\?tab=builder&provider=p-new/)
    await expect(page.locator('[data-autobuild]')).toContainText('qwen/qwen3-30b-a3b-instruct-2507')
    page.once('dialog', d => d.accept('Pilot automatic build'))
    await page.getByRole('button', { name: 'Build automatically' }).click()
    await expect(page.locator('[data-build-status="finding_pages"]')).toContainText('Finding course pages')
    expect(calls.some(c => c.p_action === 'start' && c.p_args.provider_id === 'p-new' && c.p_args.reason === 'Pilot automatic build')).toBe(true)
    if (process.env.AUTOBUILD_SHOT) await page.screenshot({ path: process.env.AUTOBUILD_SHOT, fullPage: true })
  })

  test('Platform Admin: a finished build lists fields ready to admit and Admit these sends them', async ({ page }) => {
    await setup(page, 6)
    const admits = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_autobuild', route => route.fulfill({ json: { adapter: 'testing', can_manage: true, today: 1, per_day: 25, model: 'pinned',
      build: { id: 'b1', status: 'done', note: 'Ready to admit: intakes.', result: { ready: ['intakes'], held: { fee: 'read on fewer than 5 pages' }, central_pages: [] } } } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_autobuild_admit', route => { admits.push(route.request().postDataJSON()); return route.fulfill({ json: { ok: true, admitted: ['intakes'] } }) })
    await page.goto('/#layer-2-discovery?tab=builder&provider=p-new')
    await expect(page.locator('[data-build-result]')).toContainText('Ready to admit')
    await expect(page.locator('[data-build-result]')).toContainText('held: read on fewer than 5 pages')
    page.once('dialog', d => d.accept('Checked the measures'))
    await page.getByRole('button', { name: 'Admit these' }).click()
    await expect.poll(() => admits.length).toBe(1)
    expect(admits[0].p_args).toEqual({ provider_id: 'p-new', fields: ['intakes'], reason: 'Checked the measures' })
  })

  test('PIM Operator: no Adapter column on the Providers list', async ({ page }) => {
    await setup(page, 5)
    await page.goto('/#providers')
    await expect(page.getByText('The University of Western Australia')).toBeVisible()
    await expect(page.locator('[data-adapter-cell]')).toHaveCount(0)
  })
})
