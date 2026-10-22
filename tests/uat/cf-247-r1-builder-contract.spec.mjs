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
  const base = { provider_id: 'p-bc', name: 'Britts College Pty Ltd', country: 'AU', courses: 27, pages: { stored: 0, read: 0 }, adapter: null, qualify: null, central: [], suggested: [], can_manage: true, course_list: [{ course_id: 'c1', title: 'Advanced Diploma of Business', code: '112357', state: 'no_page' }] }
  async function open(page, basics, builder = {}) {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page)
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder_basics', r => r.fulfill({ json: basics }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder', async r => { const b = r.request().postDataJSON(); calls.push({ fn: 'admin_adapter_builder', ...b }); await r.fulfill({ json: b.p_action === 'read' ? { budget: { used_usd: 0, limit_usd: 1.5 }, can_manage: true, drafts: [], pages: [], courses: [{ id: 'c1', course: 'Advanced Diploma of Business', code: '112357' }], website: basics.website || null, ...builder } : { ok: true } }) })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_course_list', r => r.fulfill({ json: { lists: [], can_manage: true } }))
    for (const fn of ['admin_provider_website_set', 'admin_firecrawl_write', 'admin_uni_adapter_read', 'admin_uni_adapter_review']) await page.route(`https://example.supabase.co/rest/v1/rpc/${fn}`, async r => { const b = r.request().postDataJSON(); calls.push({ fn, ...b }); await r.fulfill({ json: fn === 'admin_firecrawl_write' ? (b.p_action === 'target' ? { ok: true, domain: 'brittscollege.edu.au' } : { ok: true, items: 27, credits_cap: 200 }) : fn === 'admin_uni_adapter_read' ? { adapter: {}, previews: [] } : {} }) })
    await page.goto('/#layer-2-discovery?tab=builder&provider=p-bc')
    return calls
  }

  // v2.15.245: the website is step 1.1 (searched automatically, Fill in from website, or entered by hand)
  test('no website: step 1.1 asks for the provider website instead of a silent Firecrawl target; no reason prompt', async ({ page }) => {
    let prompted = false
    page.on('dialog', d => { prompted = true; d.dismiss() })
    const calls = await open(page, { ...base, website: null })
    const step = page.locator('[data-builder-step="1.1"]')
    await expect(step).toContainText('No website is recorded yet')
    await expect(step.getByRole('button', { name: 'Fill in from website' })).toBeVisible()
    await step.getByLabel("Provider's own website").fill('https://www.brittscollege.edu.au')
    await step.getByRole('button', { name: 'Save website (entered by hand)' }).click()
    await expect(step.getByRole('status')).toContainText('Website saved (entered by hand)')
    expect(calls.find(c => c.fn === 'admin_provider_website_set')).toEqual({ fn: 'admin_provider_website_set', p_provider_id: 'p-bc', p_url: 'https://www.brittscollege.edu.au' })
    expect(prompted).toBe(false)
  })

  // v2.15.245 (Feature 1): step 2.1 lists every course and its page; the missing ones are searched with Firecrawl as a task
  test('with a website: step 2.1 lists the courses and starts a Find course pages task for this provider', async ({ page }) => {
    page.on('dialog', d => d.accept('Find the missing pages'))
    await open(page, { ...base, website: 'https://www.brittscollege.edu.au' })
    const step = page.locator('[data-builder-step="2.1"]')
    await expect(step.locator('[data-course-list]')).toContainText('Advanced Diploma of Business')
    await expect(step.locator('[data-course-list]')).toContainText('No page yet')
    await step.getByRole('button', { name: /Find every course without a read page \(1\)/ }).click()
    await expect.poll(() => (page.l3calls || []).find(c => c.jobs === 'start')?.args).toMatchObject({ kind: 'course_page_find', args: { provider_id: 'p-bc', scope: 'p-bc' } })
  })

  // v2.15.316 (Platform Admin 22 Oct 2026 16:10, UTS): the page address is entered on the course's own row
  test('a course page entered by hand on its row is saved and captured', async ({ page }) => {
    const calls = await open(page, { ...base, website: 'https://www.brittscollege.edu.au' })
    const list = page.locator('[data-course-list]')
    await list.getByRole('button', { name: 'Add page' }).first().click()
    await list.getByLabel('Page for Advanced Diploma of Business').fill('https://www.brittscollege.edu.au/courses/advanced-diploma-of-business')
    await list.getByRole('button', { name: 'Save page' }).click()
    await expect(list.getByRole('status')).toContainText('page saved and captured')
    const add = calls.find(c => c.fn === 'admin_adapter_builder' && c.p_action === 'add_page')
    expect(add.p_args).toEqual({ provider_id: 'p-bc', course_id: 'c1', url: 'https://www.brittscollege.edu.au/courses/advanced-diploma-of-business', reason: 'Adapter builder: course page entered by hand for Advanced Diploma of Business' })
  })

  test('state chips filter the list, any row can be ticked and Search again takes the ticked courses', async ({ page }) => {
    page.on('dialog', d => d.accept('Search again'))
    await open(page, { ...base, website: 'https://www.brittscollege.edu.au', pages: { stored: 2, read: 1 }, course_list: [
      { course_id: 'c1', title: 'Advanced Diploma of Business', code: '112357', state: 'read', url: 'https://www.brittscollege.edu.au/a' },
      { course_id: 'c2', title: 'Diploma of Leadership', code: '112358', state: 'wrong_page', url: 'https://www.brittscollege.edu.au/b' },
      { course_id: 'c3', title: 'Certificate IV in Business', code: '112359', state: 'old_site', url: 'https://old.brittscollege.edu.au/c' }] })
    const list = page.locator('[data-course-list]')
    await expect(list).toContainText('Wrong page (about another course)')
    await expect(list).toContainText('Old site, refused')
    await expect(list.locator('tbody tr')).toHaveCount(2)
    await list.getByRole('button', { name: /^Read: 1/ }).click()
    await expect(list.locator('tbody tr')).toHaveCount(1)
    await list.getByLabel('Tick Advanced Diploma of Business').check()
    await list.getByRole('button', { name: /Search again for 1 ticked/ }).click()
    await expect.poll(() => (page.l3calls || []).find(c => c.jobs === 'start')?.args).toMatchObject({ kind: 'course_page_find', args: { provider_id: 'p-bc', course_ids: ['c1'] } })
    await expect(page.locator('[data-builder-step="2.1"] .ab-num').first()).toHaveText('2.1')
  })

})
