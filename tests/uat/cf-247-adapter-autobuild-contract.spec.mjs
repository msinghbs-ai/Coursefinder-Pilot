import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// v2.15.215 (Platform Admin, 7 Oct 2026 20:28 and 22:12): guided adapter build with buttoned steps, and the Providers-list Adapter column.
test('guided build: no schedule, existing functions per step, admit only ready fields', () => {
  const fn = fs.readFileSync('supabase/migrations-archive/20261007001901_cf247_adapter_autobuild_functions.sql', 'utf8')
  expect(fn).toContain("coalesce(v_rank, 0) < 5")
  for (const f of ['20261007001902', '20261007001903', '20261007001904', '20261007001905']) expect(fs.readdirSync('supabase/migrations-archive').some(x => x.startsWith(f))).toBe(false)
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toContain("const adapterCol=type==='provider'&&!completenessMode&&Number(rank)>=6")
  expect(main).toContain("navigate?.('layer2',{tab:'builder',provider:r.id})")
  const ui = fs.readFileSync('src/AdapterBuilderTab.jsx', 'utf8')
  for (const call of ["rpc('admin_firecrawl_write',{p_action:'target'", "rpc('admin_adapter_builder',{p_action:'start'", "rpc('admin_adapter_builder',{p_action:'propose'", "rpc('admin_uni_adapter_write',{p_action:'save'", "rpc('admin_uni_adapter_write',{p_action:'apply'", "rpc('admin_uni_adapter_control',{p_action:'admit'"]) expect(ui).toContain(call)
  expect(ui).not.toContain("admin_adapter_autobuild',{p_action:'start'")
  expect(ui).toContain("Number(x.read||0)<5?'read on fewer than 5 pages'")
  expect(ui).toContain("(Number(x.agree||0)<3||x.agree_share==null)?'not enough held values to check against (needs 3 agreeing courses)'")
  expect(ui).toContain("Number(x.agree_share)<0.9?'agrees on under 90% of checked courses'")
})

test.describe('mocked browser', () => {
  const providers = { total: 2, items: [
    { id: 'p-uwa', canonical_name: 'The University of Western Australia', country_code: 'AU', course_count: 330, lifecycle_status: 'active', publication_status: 'draft' },
    { id: 'p-new', canonical_name: 'New Test Institute', country_code: 'AU', course_count: 12, lifecycle_status: 'active', publication_status: 'draft' }] }
  const states = { 'p-uwa': { adapter: 'admitting', admit_fields: ['intakes'], build: null }, 'p-new': { adapter: null, admit_fields: null, build: null } }
  const basics = { provider_id: 'p-new', name: 'New Test Institute', country: 'AU', courses: 12, pages: { stored: 20, read: 14 }, central: [], suggested: [], can_manage: true,
    adapter: { enabled: true, admit: false, admit_fields: [], updated_at: '2026-10-07T11:10:00Z' },
    qualify: { fields: { intakes: { pass: true, read: 12, agree: 9, agree_share: 1, why: 'passes' }, english: { pass: true, read: 12, agree: 0, agree_share: null, why: 'passes' } } } }
  async function setup(page, rank) {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
      const b = route.request().postDataJSON() || {}
      if (b.p_operation === 'providers_page') return route.fulfill({ json: providers })
      return route.fallback()
    })
    const calls = []
    const log = name => async route => { const b = route.request().postDataJSON() || {}; calls.push({ name, ...b }); return route.fulfill({ json: name === 'admin_adapter_autobuild' ? states : name === 'admin_adapter_builder_basics' ? basics
      : name === 'admin_adapter_builder' ? { budget: { model: 'qwen/qwen3-30b-a3b-instruct-2507', used_usd: 0.01, limit_usd: 1.5 }, can_manage: true, drafts: [{ id: 'd1', status: 'proposed', captures: [{ course: 'A' }], marks: [], proposals: [{ at: '2026-10-07T11:00:00Z', model: 'qwen/qwen3-30b-a3b-instruct-2507', cost: 0.002, reason: 'reads intakes', adapter: { patterns: { intakes: 'x' } } }] }] }
      : name === 'admin_uni_adapter_read' ? { provider: { name: 'New Test Institute' }, adapter: { enabled: true }, pages: { read: 14 }, previews: [], can_manage: true } : { ok: true } }) }
    for (const n of ['admin_adapter_autobuild', 'admin_adapter_builder_basics', 'admin_adapter_builder', 'admin_uni_adapter_control', 'admin_uni_adapter_read', 'admin_uni_adapter_review']) await page.route(`https://example.supabase.co/rest/v1/rpc/${n}`, log(n))
    return calls
  }

  test('Platform Admin: Create adapter opens the guided build; Admit these admits only the ready field', async ({ page }) => {
    const calls = await setup(page, 6)
    await page.goto('/#providers')
    await expect(page.locator('[data-adapter-cell="admitting"]')).toContainText('Open adapter')
    await expect(page.locator('[data-adapter-cell="none"]')).toContainText('Create adapter')
    await page.locator('[data-adapter-cell="none"] button').click()
    await expect(page).toHaveURL(/layer-2-discovery\?tab=builder&provider=p-new/)
    const g = page.locator('[data-guided-build]')
    await expect(g).toContainText('qwen/qwen3-30b-a3b-instruct-2507')
    await expect(g.locator('[data-guided-step="1"]')).toHaveClass(/is-done/)
    await expect(g.locator('[data-guided-step="4"]')).toHaveClass(/is-done/)
    await expect(g.locator('[data-guided-qualify]')).toContainText('held: not enough held values')
    page.once('dialog', d => d.accept('Checked the measures'))
    await g.getByRole('button', { name: 'Admit these' }).click()
    await expect.poll(() => calls.filter(c => c.name === 'admin_uni_adapter_control').length).toBe(1)
    const admit = calls.find(c => c.name === 'admin_uni_adapter_control')
    expect(admit.p_action).toBe('admit')
    expect(admit.p_args).toEqual({ provider_id: 'p-new', admit: true, fields: ['intakes'], reason: 'Checked the measures' })
    if (process.env.AUTOBUILD_SHOT) await page.screenshot({ path: process.env.AUTOBUILD_SHOT, fullPage: true })
  })

  test('PIM Operator: no Adapter column on the Providers list', async ({ page }) => {
    await setup(page, 5)
    await page.goto('/#providers')
    await expect(page.getByText('The University of Western Australia')).toBeVisible()
    await expect(page.locator('[data-adapter-cell]')).toHaveCount(0)
  })
})
