// Guards: CF-247 (S62) v2.15.288, bug 18/10-01: check or change a university's website in the Adapter builder (Platform Admin 18 Oct 2026 20:35: "add to bug/fix: Website - should have to…
// CF-247 (S62) v2.15.288, bug 18/10-01: check or change a university's website in the Adapter builder (Platform Admin 18 Oct 2026 20:35:
// "add to bug/fix: Website - should have to feature to validate or change the website in the adapter builder").
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261018130000_cf247_website_check_change.sql'
const sql = fs.readFileSync(MIG, 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const ui = fs.readFileSync('src/AdapterBuilderTab.jsx', 'utf8')

test('server: md5-guarded, checks queued and read by the worker, change saved only when Verified or Likely', () => {
  for (const md5 of ['7de75fd98eb315284f59ed306b9e3822', 'a557f380714b8763065a749fd11ab04b', '5ea5b5f8c20b934645dca7f0211db658']) expect(sql).toContain(md5)
  expect(sql).toContain("if p_action = 'change' and v_rank < 6 then raise exception 'Platform Admin required to change a website'")
  expect(sql).toContain("if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required'")
  expect(sql).toContain("if v_c.action <> 'change' or v_c.applied or v_c.verdict not in ('verified', 'likely') then return null; end if;")
  expect(sql).toContain('perform public.admin_provider_website_set(v_c.provider_id, v_url);')
  expect(sql).toContain('insert into pipeline.firecrawl_search_resumes(provider_id, reason, set_by)')
  expect(sql).toContain("security.pipeline_num_v1('batch.website_check', 5)")
  expect(sql).toMatch(/-- Replaces: nothing\n-- Retires: nothing/)
  expect(sql).toContain('comment on table pipeline.provider_website_checks')
  expect(sql.indexOf("insert into pipeline.automation_catalogue")).toBeLessThan(sql.indexOf("select cron.schedule('provider-website-check'"))
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(sql).not.toMatch(/website_v2_|website_edge_|zoho_edge_|\bapi\./) // Decision 266: the consumer API is not touched
})

test('worker v0.31.0: mode site_check reads the home page and records what it shows', () => {
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(3[1-9]|[4-9]\d)\.\d+";/)
  expect(worker).toContain('if (mode === "site_check") {')
  expect(worker).toContain('await rpc("svc_provider_website_check_next"')
  expect(worker).toContain('await rpc("svc_provider_website_check_record"')
  expect(worker).toContain('useFc("site_verify", it.provider_id, origin + "/", true)')
})

test('source: step 1.1 has Check website and Change website through one RPC', () => {
  expect(ui).toContain("supabase.rpc('admin_provider_website_check'")
  expect(ui).toContain('<WebsiteCheck b={b} onChanged={onChanged} onError={onError}/>')
})

test.describe('mocked browser', () => {
  const base = { provider_id: 'p-sf', name: 'Sydney Film School', country: 'AU', courses: 4, pages: { stored: 0, read: 0 }, adapter: null, qualify: null, central: [], suggested: [], can_manage: true,
    website: 'https://www.sydneyfilmschool.com.au, www.sydneyactorsschool.edu.au', course_list: [] }
  const check = (o = {}) => ({ id: 'k1', url: 'https://www.sydneyfilmschool.com.au', action: 'check', state: 'done', verdict: 'verified', why: "the provider's CRICOS code 01234A is on the home page", requested_at: '2026-10-18T10:00:00Z', checked_at: '2026-10-18T10:00:05Z', applied: false, apply_note: null,
    result: { answers: true, http: 200, via: 'direct', third_party: false, cricos_code: '01234A', cricos_on_site: true, name_basis: 'name_on_home_page', domain_fits: true, title: 'Sydney Film School' }, ...o })
  async function open(page, { rank = 6, checks = [] } = {}) {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank })
    const calls = []; let list = checks
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder_basics', r => r.fulfill({ json: base }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder', r => r.fulfill({ json: { budget: { used_usd: 0, limit_usd: 1.5 }, can_manage: true, drafts: [], pages: [], courses: [], website: base.website } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_website_check', async r => {
      const b = r.request().postDataJSON(); calls.push(b)
      if (b.p_action === 'change') list = [check({ id: 'k2', action: 'change', url: b.p_args.url, applied: true, apply_note: { saved: b.p_args.url, before: base.website, searches_queued: 3, extra_site: 'sydneyactorsschool.edu.au', pages_on_old_address: 0 } }), ...list]
      if (b.p_action === 'check') list = [check(), ...list]
      await r.fulfill({ json: b.p_action === 'list' ? { website: base.website, sites: ['https://www.sydneyfilmschool.com.au', 'https://www.sydneyactorsschool.edu.au'], can_check: true, can_change: rank >= 6, checks: list } : { id: 'k', state: 'queued' } })
    })
    await page.goto('/#layer-2-discovery?tab=builder&provider=p-sf')
    return calls
  }

  test('a record with two addresses is pointed out; Check website shows the verdict and the evidence', async ({ page }) => {
    const calls = await open(page)
    const box = page.locator('[data-website-check]')
    await expect(box.locator('[data-website-multi]')).toContainText('holds 2 addresses')
    await box.getByRole('button', { name: 'Check website' }).click()
    await expect.poll(() => calls.find(c => c.p_action === 'check')?.p_args).toEqual({ provider_id: 'p-sf' })
    await expect(box.locator('[data-website-result="verified"]')).toContainText('Verified')
    await expect(box.locator('[data-website-evidence]')).toContainText('CRICOS code 01234A on the home page: yes')
  })

  test('Change website (Platform Admin): main address, other site and reason; the result says what restarted', async ({ page }) => {
    const calls = await open(page)
    const box = page.locator('[data-website-check]')
    await box.getByRole('button', { name: 'Change website' }).click()
    await expect(box.getByLabel('New website')).toHaveValue('https://www.sydneyfilmschool.com.au')
    await expect(box.getByLabel('Other site of this provider (optional)')).toHaveValue('https://www.sydneyactorsschool.edu.au')
    await box.getByLabel('Reason').fill('Two sites in one field')
    await box.getByRole('button', { name: 'Check and save' }).click()
    await expect.poll(() => calls.find(c => c.p_action === 'change')?.p_args).toEqual({ provider_id: 'p-sf', url: 'https://www.sydneyfilmschool.com.au', extra_site: 'https://www.sydneyactorsschool.edu.au', reason: 'Two sites in one field' })
    await expect(box.locator('[data-website-applied]')).toContainText('Course-page searches queued again: 3')
  })

  test('a PIM Admin can check but not change', async ({ page }) => {
    await open(page, { rank: 5 })
    const box = page.locator('[data-website-check]')
    await expect(box.getByRole('button', { name: 'Check website' })).toBeVisible()
    await expect(box.getByRole('button', { name: 'Change website' })).toHaveCount(0)
  })
})
