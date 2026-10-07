import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('Layer 2 Adapter builder tab is wired to its read function and the existing write functions', () => {
  const nav = fs.readFileSync('src/nav-map.js', 'utf8')
  expect(nav).toContain("{ key: 'builder', label: 'Adapter builder', min: 5 }")
  expect(nav).toContain("{ key: 'adapters', label: 'Adapters', min: 4 }")
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toContain("if(tab==='builder')return <AdapterBuilderTab rank={rank} onError={err} initialProvider={routeParams?.get?.('provider')||''}/>")
  const ui = fs.readFileSync('src/AdapterBuilderTab.jsx', 'utf8')
  expect(ui).toContain("supabase.rpc('admin_adapter_builder_basics'")
  expect(ui).toContain("supabase.rpc('admin_provider_central_page'")
  expect(ui).toContain('<AdapterEditor key={key} providerId={b.provider_id} hideReview onError={onError}/>')
  expect(ui).toContain('<AdapterReview providerId={b.provider_id}')
  const sql = fs.readFileSync('supabase/migrations/20261007001600_cf247_adapter_builder_tab.sql', 'utf8')
  expect(sql).toContain('coalesce(v_rank, 0) < 5')
  expect(sql).toContain('da0b0eae7ad2566bc09efa0a90356102')
  expect(sql).toContain("revoke all on function public.admin_adapter_builder_basics(text, jsonb) from public, anon")
})

test.describe('mocked browser', () => {
  test('Adapter builder: pick a provider, see basics, central pages and the admit rule', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page)
    const basics = { provider_id: 'p-uwa', name: 'The University of Western Australia', website: 'https://www.uwa.edu.au', country: 'AU', courses: 330,
      pages: { stored: 324, read: 285, needs_render: 1 }, adapter: { enabled: true, admit: true, admit_fields: ['intakes'], patterns: 8, json_paths: 0 },
      qualify: { fields: { intakes: { read: 200, read_share: 0.71, agree_share: 0.986, pass: true, why: 'passes' }, english: { read: 12, read_share: 0.04, agree_share: null, pass: false, why: 'read on 12 of 285 pages, under the share needed' } } },
      central: [{ kind: 'intake_calendar', url: 'https://www.uwa.edu.au/students/my-course/important-dates', status: 'read', decision: null }],
      suggested: [{ kind: 'fee_schedule', url: 'https://www.uwa.edu.au/study/international-fees', title: 'International fees' }], can_manage: true }
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder_basics', async route => {
      const b = route.request().postDataJSON() || {}
      await route.fulfill({ json: b.p_action === 'search' ? { providers: [{ provider_id: 'p-uwa', name: basics.name, country: 'AU', courses: 330, adapter: 'admitting' }] } : basics })
    })
    for (const fn of ['admin_uni_adapter_read', 'admin_adapter_builder', 'admin_uni_adapter_review']) await page.route(`https://example.supabase.co/rest/v1/rpc/${fn}`, r => r.fulfill({ json: fn === 'admin_uni_adapter_read' ? { provider: { name: basics.name }, adapter: { enabled: true }, pages: { read: 285 }, previews: [], can_manage: true } : fn === 'admin_adapter_builder' ? { budget: { used_usd: 0, limit_usd: 2, proposals: 0, limit_proposals: 10, model: 'pinned' }, can_manage: true, drafts: [] } : { admit: { on: true, fields: ['intakes'] } } }))
    await page.goto('/#layer-2-discovery?tab=builder')
    await expect(page.getByRole('tab', { name: 'Adapter builder' })).toHaveAttribute('aria-selected', 'true')
    await page.getByLabel('Find a provider').fill('western')
    await page.getByRole('button', { name: /The University of Western Australia/ }).click()
    await expect(page.locator('[data-builder-step="2"]')).toContainText('285 read of 324 stored')
    await expect(page.locator('[data-builder-step="3"]')).toContainText('International fee schedule')
    await expect(page.locator('[data-builder-qualify]')).toContainText('Passes')
    if (process.env.BUILDER_SHOT) await page.screenshot({ path: process.env.BUILDER_SHOT, fullPage: true })
  })
})
