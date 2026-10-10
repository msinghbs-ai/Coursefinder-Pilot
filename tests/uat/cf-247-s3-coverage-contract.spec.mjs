// CF-247 v2.15.240 (S3, S5): Scholarships › Coverage (each provider against its own listing page; watch list; sign-off; review of
// automatic publishing; settings and jobs on screen) and bulk restore on Providers › Archived. Platform Admin, 11 Oct 2026.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261011007300_cf247_s3_scholarship_coverage.sql'

test('server: listing pages, matching, coverage RPCs, listing job, bulk restore; nothing dropped or deleted', () => {
  const sql = fs.readFileSync(MIG, 'utf8')
  for (const t of ['scholarship_listing_pages', 'scholarship_coverage_checks', 'scholarship_watch']) expect(sql).toContain(`create table pipeline.${t} (`)
  for (const f of ['public.svc_scholarship_listing_next(p_limit integer)', 'security.scholarship_listing_match_v1(p_provider_id uuid)', 'public.admin_scholarship_coverage_read(', 'public.admin_scholarship_coverage_provider(p_provider_id uuid)', 'public.admin_scholarship_coverage_write(p_action text', 'public.admin_archive_restore_bulk(p_section text, p_ids uuid[])']) expect(sql).toContain(`create or replace function ${f}`)
  expect(sql).toContain("'00301J','03567C','00586B'")
  expect(sql).toContain("select cron.schedule('scholarship-listing', '7-59/15 * * * *'")
  expect(sql).toContain("if p_action not in ('watch', 'unwatch') and v_rank < 6 then raise exception 'Platform Admin role required'")
  expect(sql).not.toMatch(/\b(drop\s+(table|function|schema|index|view|trigger)|delete\s+from|truncate)\b/i)
})

test('worker: listing pages read for the scholarships they name', () => {
  const s = fs.readFileSync('supabase/functions/coverage-sweep/scholarship.ts', 'utf8')
  expect(s).toContain('export function scholarshipListing(html: string, baseUrl: string, hosts: string[] = [])')
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(ix).toContain('if (mode === "scholarship_listing") {')
  expect(ix).toMatch(/coverage-sweep-worker-v0\.17\.(3[7-9]|[4-9][0-9])/)
})

test.describe('mocked browser', () => {
  const row = { provider_id: 'p-c', name: 'Curtin University', country: 'AU', watch: true, listing_pages: 1, suggested_pages: 0, listed: 6, found: 5, published: 4, missing: 1, records: 17, records_published: 5, extra: 12, study_australia: 2, state: 'to_check' }
  const read = { scope: 'watch', total: 1, rows: [row], can_manage: true, can_watch: true,
    auto_publish: { on: true, recent: [{ id: 's1', name: 'Curtin Global Merit Scholarship', provider: 'Curtin University', at: '2026-10-11T03:29:00Z', status: 'published', value: '20% off tuition', courses: 300 }] },
    totals: { watch: 27, with_listing: 18, suggested: 30, checked: 0, active: 1505, published: 450 } }
  const prov = { row, can_manage: true,
    listing_pages: [{ id: 1, url: 'https://www.curtin.edu.au/study/scholarships/international-scholarships', source: 'auto', status: 'read', read_at: '2026-10-11T03:00:00Z', items: 6 }],
    listed: [
      { name: 'Home Country-Funded Scholarships', url: null, matched_by: null, record: null },
      { name: 'Global Scholars Program Scholarship', url: 'https://scholarships.curtin.edu.au/Scholarship/?id=7566', matched_by: 'page', record: { id: 's2', name: 'Global Scholars Program Scholarship', status: 'unpublished', value_type: 'fixed_amount', amount: 15000, currency: 'AUD', courses: 120, levels: ['Bachelor Degree'], all_courses: false, publishable: false, reasons: ['not for international students'], held: false } },
      { name: 'Curtin Global Merit Scholarship', url: 'https://scholarships.curtin.edu.au/Scholarship/?id=7986', matched_by: 'page', record: { id: 's1', name: 'Curtin Global Merit Scholarship', status: 'published', value_type: 'percentage', percentage: 20, courses: 300, levels: [], all_courses: true, publishable: true, reasons: [], held: false } }],
    extra: [] }
  async function setup(page, rank = 6) {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_scholarship_coverage_read', r => r.fulfill({ json: read }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_scholarship_coverage_provider', r => r.fulfill({ json: prov }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_scholarship_coverage_write', async r => { calls.push(r.request().postDataJSON()); await r.fulfill({ json: prov }) })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_scholarship_layer_read', r => r.fulfill({ json: { can_manage: true, settings: [], jobs: [] } }))
    return calls
  }

  test('Coverage lists the watch list, opens a provider beside our records, and acts without prompts', async ({ page }) => {
    let prompted = false
    page.on('dialog', d => { prompted = true; d.dismiss() })
    const calls = await setup(page)
    await page.goto('/#scholarships?tab=coverage')
    const box = page.locator('[data-scholarship-coverage]')
    await expect(box.locator('[data-cov-row="p-c"]')).toContainText('To check')
    await expect(box.locator('[data-auto-published]')).toContainText('1 published automatically')
    await box.locator('[data-cov-row="p-c"]').click()
    const p = page.locator('[data-cov-provider="p-c"]')
    await expect(p.locator('[data-cov-record="missing"]')).toContainText('Not found')
    await expect(p.locator('[data-cov-record="s1"]')).toContainText('all courses (page names no restriction)')
    await p.locator('[data-cov-record="s2"]').getByRole('button', { name: 'International' }).click()
    await expect.poll(() => calls.find(c => c.p_action === 'confirm_international')).toMatchObject({ p_args: { provider_id: 'p-c', scholarship_id: 's2' } })
    await p.getByRole('button', { name: 'Sign off' }).click()
    await expect.poll(() => calls.find(c => c.p_action === 'sign_off')).toMatchObject({ p_args: { provider_id: 'p-c' } })
    await p.locator('[data-cov-record="s1"]').getByRole('button', { name: 'Withdraw' }).click()
    await p.locator('[data-cov-record="s1"]').getByLabel('Why hold it').selectOption('Not for international students')
    await expect.poll(() => calls.find(c => c.p_action === 'hold')).toMatchObject({ p_args: { scholarship_id: 's1', reason: 'Not for international students' } })
    expect(prompted).toBe(false)
  })

  test('Archived: tick several and restore them together', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 5 })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_archive_read', r => r.fulfill({ json: { section: 'providers', total: 2, can_restore: true, counts: { providers: 2, courses: 0, departures_waiting: 0 },
      rows: [{ id: 'p-1', name: 'Alpha College', country: 'AU', status: 'archived', source: 'manual', reason: 'Closed', courses: 3 }, { id: 'p-2', name: 'Beta Institute', country: 'AU', status: 'archived', source: 'layer1_departure', reason: 'Left', courses: 1 }] } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_archive_restore_bulk', async r => { calls.push(r.request().postDataJSON()); await r.fulfill({ json: { restored: 2, skipped: 0 } }) })
    await page.goto('/#providers?tab=archived')
    await page.getByLabel('Select all on this page').check()
    await page.locator('[data-bulk-restore]').getByRole('button', { name: 'Restore 2' }).click()
    await expect(page.locator('[data-archived-review]').getByRole('status')).toContainText('2 restored')
    expect(calls[0]).toEqual({ p_section: 'providers', p_ids: ['p-1', 'p-2'] })
  })
})
