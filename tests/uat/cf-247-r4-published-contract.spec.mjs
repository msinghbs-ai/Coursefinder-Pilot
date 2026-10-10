// CF-247 v2.15.236 (R4): Platform Admin bug list of 10 Oct 2026 — Feature 4. Publication becomes a real gate: unpublished (and archived)
// providers, with their courses, campuses and scholarships, are not served to Wix, Zoho or the website. A Published switch in the
// provider list (PIM Operator and above, no reason asked). Every active provider is published by default.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261010006800_cf247_r4_published_gate.sql'

test('server: hidden providers join the block views; published by default; switch RPC; consumer paths gated', () => {
  const sql = fs.readFileSync(MIG, 'utf8')
  for (const md5 of ['b7139dc51771973044c4d554cc2fe9b7', '48c2240a8b99521cba8c3f86fa5682d4', 'd948c919da1d2f37e36fa36e29600821', '1c4446248ee63ed2aad35a79de9c84ee', '2cfa72d4b45491e936dfdbad7bb08cb0', 'a05b163b1bba1835f04c22ab3a3b6cbe', '780d080dfc113df3e2e38d8db7cdb672']) expect(sql).toContain(md5)
  expect(sql).toContain("where p.publication_status is distinct from 'published' or p.lifecycle_status is distinct from 'active';")
  for (const v of ['providers', 'courses', 'campuses', 'scholarships']) expect(sql).toContain(`create or replace view security.layer4_search_blocked_${v} as`)
  expect(sql).toContain("alter table catalogue.providers alter column publication_status set default 'published';")
  expect(sql).toContain("update catalogue.providers set publication_status = 'published', updated_at = now()")
  expect(sql).toContain("and p.publication_status='published' and p.lifecycle_status='active';")
  expect(sql).toContain('create or replace function public.admin_provider_publish(p_provider_id uuid, p_published boolean)')
  expect(sql).toContain("coalesce(security.current_role_rank(), 0) < 5")
  expect(sql).toContain("raise exception 'an archived provider cannot be published: restore it first'")
  const own = sql.slice(sql.indexOf('-- 1. Hidden providers'), sql.indexOf('-- 4. Consumer paths')) // existing function bodies are kept as they were
  expect(own.length).toBeGreaterThan(2000)
  expect(own).not.toMatch(/\b(drop\s+(table|function|schema|view|trigger)|delete\s+from|truncate)\b/i)
})

test.describe('mocked browser', () => {
  const providers = { total: 2, items: [
    { id: 'p-a', canonical_name: 'Alpha College', country_code: 'AU', course_count: 20, lifecycle_status: 'active', publication_status: 'published' },
    { id: 'p-b', canonical_name: 'Beta Institute', country_code: 'AU', course_count: 5, lifecycle_status: 'active', publication_status: 'unpublished' }] }
  async function setup(page, rank) {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
      const b = route.request().postDataJSON() || {}
      if (b.p_operation === 'providers_page') return route.fulfill({ json: providers })
      return route.fallback()
    })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_publish', async route => { const b = route.request().postDataJSON(); calls.push(b); await route.fulfill({ json: { provider_id: b.p_provider_id, publication_status: b.p_published ? 'published' : 'unpublished' } }) })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_autobuild', r => r.fulfill({ json: {} }))
    return calls
  }

  test('PIM Operator switches a provider off and on from the list, with no reason prompt; unpublished rows are greyed', async ({ page }) => {
    let prompted = false
    page.on('dialog', d => { prompted = true; d.dismiss() })
    const calls = await setup(page, 5)
    await page.goto('/#providers')
    const alpha = page.locator('tr', { hasText: 'Alpha College' }), beta = page.locator('tr', { hasText: 'Beta Institute' })
    await expect(beta).toHaveClass(/m-row-muted/)
    await expect(alpha).not.toHaveClass(/m-row-muted/)
    await alpha.getByRole('switch').click()
    await expect(alpha.getByRole('switch')).toHaveAttribute('aria-checked', 'false')
    await expect(alpha).toHaveClass(/m-row-muted/)
    await beta.getByRole('switch').click()
    await expect(beta.getByRole('switch')).toHaveAttribute('aria-checked', 'true')
    expect(calls).toEqual([{ p_provider_id: 'p-a', p_published: false }, { p_provider_id: 'p-b', p_published: true }])
    expect(prompted).toBe(false)
    await expect(page.locator('[data-drawer], .m-detail-drawer')).toHaveCount(0) // the switch does not open the provider
  })

  test('Curator sees the switch but cannot change it', async ({ page }) => {
    await setup(page, 3)
    await page.goto('/#providers')
    await expect(page.locator('tr', { hasText: 'Alpha College' }).getByRole('switch')).toBeDisabled()
  })
})
