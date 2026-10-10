// CF-247 v2.15.232 (R1): Platform Admin bug list of 10 Oct 2026 — Fix 3 (course finder address entered by hand), Fix 4 (find course
// pages says what happens), Fix 5 (no reason prompts in the adapter builder), Feature 2 (course page entered by hand as a sample).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261010006400_cf247_r1_course_finder_builder.sql'

test('server: course finder lock, site search keeps it, provider-only find run, own-site course page', () => {
  const sql = fs.readFileSync(MIG, 'utf8')
  for (const md5 of ['fae8f49a62ca00a358d2e7370fea501a', 'f1deed17172207ea537784f2d8d4d121', 'd0ee636ef9b5926f9382dda57b096751', 'db29a9baa824f836c79830d258470a10']) expect(sql).toContain(md5)
  expect(sql).toContain("perform security.manual_lock_set('provider', p_provider_id, 'course_finder', 'value');")
  expect(sql).toContain("update pipeline.coverage_provider_discovery set site_source = 'manual', site_searched_at = now() where provider_id = p_provider_id;")
  expect(sql).toContain("l.field='course_finder'")
  expect(sql).toContain("d.site_source='manual'")
  expect(sql).toContain("b0.provider_id = (p_args->>'provider_id')::uuid")
  expect(sql).toContain("return jsonb_build_object('ok', true, 'domain', (select t.domain from security.firecrawl_targets_v1() t where t.provider_id = v_pid));")
  expect(sql).toContain("if p_action = 'add_page' then")
  expect(sql).toContain("raise exception 'this page is not on the provider''s own website (%)', v_dom;")
  expect(sql).toContain("perform public.admin_course_edit(v_cid, 'set_official_url'")
  expect(sql).not.toMatch(/\bdrop\s+function\b/i)
})

test('UI: no reason prompts in the builder; course finder row shows its lock', () => {
  const ui = fs.readFileSync('src/AdapterBuilderTab.jsx', 'utf8')
  expect(ui).not.toContain('window.prompt')
  expect(ui).not.toContain('Reason (kept in the log)')
  expect(ui).toContain("supabase.rpc('admin_provider_website_set'")
  expect(ui).toContain("p_action:'add_page'")
  const ed = fs.readFileSync('src/RecordEditor.jsx', 'utf8')
  expect(ed).toContain("<Row label=\"Course finder address\" lock={locks.course_finder} can={can} onRelease={()=>release('course_finder')}")
})

test.describe('mocked browser', () => {
  const base = { provider_id: 'p-bc', name: 'Britts College Pty Ltd', country: 'AU', courses: 27, pages: { stored: 0, read: 0 }, adapter: null, qualify: null, central: [], suggested: [], can_manage: true }
  async function open(page, basics, builder = {}) {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page)
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder_basics', r => r.fulfill({ json: basics }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder', async r => { const b = r.request().postDataJSON(); calls.push({ fn: 'admin_adapter_builder', ...b }); await r.fulfill({ json: b.p_action === 'read' ? { budget: { used_usd: 0, limit_usd: 1.5 }, can_manage: true, drafts: [], pages: [], courses: [{ id: 'c1', course: 'Advanced Diploma of Business', code: '112357' }], website: basics.website || null, ...builder } : { ok: true } }) })
    for (const fn of ['admin_provider_website_set', 'admin_firecrawl_write', 'admin_uni_adapter_read', 'admin_uni_adapter_review']) await page.route(`https://example.supabase.co/rest/v1/rpc/${fn}`, async r => { const b = r.request().postDataJSON(); calls.push({ fn, ...b }); await r.fulfill({ json: fn === 'admin_firecrawl_write' ? (b.p_action === 'target' ? { ok: true, domain: 'brittscollege.edu.au' } : { ok: true, items: 27, credits_cap: 200 }) : fn === 'admin_uni_adapter_read' ? { adapter: {}, previews: [] } : {} }) })
    await page.goto('/#layer-2-discovery?tab=builder&provider=p-bc')
    return calls
  }

  test('no website: step 1 asks for the provider website instead of a silent Firecrawl target; no reason prompt', async ({ page }) => {
    let prompted = false
    page.on('dialog', d => { prompted = true; d.dismiss() })
    const calls = await open(page, { ...base, website: null })
    const step = page.locator('[data-guided-step="1"]')
    await expect(step).toContainText('No website is recorded for Britts College Pty Ltd')
    await step.getByLabel("Provider's own website").fill('https://www.brittscollege.edu.au')
    await step.getByRole('button', { name: 'Save website and look for course pages' }).click()
    await expect(step.getByRole('status')).toContainText('Website saved (entered by hand)')
    expect(calls.find(c => c.fn === 'admin_provider_website_set')).toEqual({ fn: 'admin_provider_website_set', p_provider_id: 'p-bc', p_url: 'https://www.brittscollege.edu.au' })
    expect(prompted).toBe(false)
  })

  test('with a website: Find course pages now targets and starts a run for this provider only, and says so', async ({ page }) => {
    page.on('dialog', d => d.accept())
    const calls = await open(page, { ...base, website: 'https://www.brittscollege.edu.au' })
    const step = page.locator('[data-guided-step="1"]')
    await step.getByRole('button', { name: 'Find course pages now' }).click()
    await expect(step.getByRole('status')).toContainText('Page finding started on brittscollege.edu.au: 27 courses')
    const fc = calls.filter(c => c.fn === 'admin_firecrawl_write')
    expect(fc[0].p_args).toEqual({ provider_id: 'p-bc', included: true, reason: 'Adapter builder: find course pages for Britts College Pty Ltd' })
    expect(fc[1].p_args).toEqual({ use_case: 'find_page', provider_id: 'p-bc', reason: 'Adapter builder: find course pages for Britts College Pty Ltd' })
  })

  test('a course page entered by hand is captured as a sample', async ({ page }) => {
    const calls = await open(page, { ...base, website: 'https://www.brittscollege.edu.au' })
    const box = page.locator('[data-manual-page]')
    await box.getByLabel('Course for the page').fill('advanced')
    await box.getByRole('button', { name: /Advanced Diploma of Business/ }).click()
    await box.getByLabel('Course page address').fill('https://www.brittscollege.edu.au/courses/advanced-diploma-of-business')
    await box.getByRole('button', { name: 'Capture this page' }).click()
    await expect(box.getByRole('status')).toContainText('page saved as its official page and added as a sample')
    const add = calls.find(c => c.fn === 'admin_adapter_builder' && c.p_action === 'add_page')
    expect(add.p_args).toEqual({ provider_id: 'p-bc', course_id: 'c1', url: 'https://www.brittscollege.edu.au/courses/advanced-diploma-of-business', reason: 'Adapter builder: course page entered by hand for Advanced Diploma of Business' })
  })
})
