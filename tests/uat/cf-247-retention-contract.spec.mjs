import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// v2.15.219 (Platform Admin, 8 Oct 2026): Storage & retention.
test('retention: Platform Admin only, preview changes nothing, purge needs reason and typed name, rules exclude live data', () => {
  const a = fs.readFileSync('supabase/migrations/20261008000500_cf247_retention_screen.sql', 'utf8')
  expect(a).toContain("coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required'")
  expect(a).toContain("coalesce(p_args->>'confirm', '') <> v_cat")
  expect(a).toContain("'evidence_audit', 'label', 'Evidence files (audit)', 'kind', 'files', 'purge', false")
  const w = fs.readFileSync('supabase/migrations/20261008000600_cf247_retention_worker.sql', 'utf8')
  expect(w).not.toContain('layer2_run_items') // Layer 3 work items cascade from run items: never purged
  expect(w).not.toMatch(/delete from storage\.objects/i) // files only through Storage
  expect(w).not.toMatch(/delete from pipeline\.evidence_artifacts/i)
  expect(w).toContain('and not exists (select 1 from pipeline.coverage_course_pages pg where pg.url = u.url)')
  expect(w).toContain("d.start_time < now() - interval '7 days'")
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(ix).toContain('c.storage.from("adapter-captures").remove(next.map((x) => x.name))')
  const nav = fs.readFileSync('src/nav-map.js', 'utf8')
  expect(nav).toContain("retention: { label: 'Storage & retention', slug: 'storage-retention', icon: 'database', min: 6")
})

test.describe('mocked browser', () => {
  const data = { database_bytes: 3.27e9, runs: [], categories: [
    { key: 'job_log', label: 'Scheduled-job run log', kind: 'rows', purge: true, rule: 'older than 7 days', estimate: { size_bytes: 78e6, purgeable_rows: 38644, purgeable_bytes: 21e6, measured_at: '2026-10-08T01:00:00Z', detail: {} } },
    { key: 'evidence_audit', label: 'Evidence files (audit)', kind: 'files', purge: false, rule: 'count only', estimate: null }] }
  test('Platform Admin purges with reason and typed confirmation; audit button for evidence', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 6 })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_retention', async r => { const b = r.request().postDataJSON() || {}; calls.push(b); return r.fulfill({ json: b.p_action === 'read' ? data : { ok: true } }) })
    const answers = ['Reduce database size', 'job_log']
    page.on('dialog', d => d.accept(answers.shift()))
    await page.goto('/#storage-retention')
    await expect(page.locator('[data-retention-row="job_log"]')).toContainText('38,644 rows')
    await page.locator('[data-retention-row="job_log"]').getByRole('button', { name: 'Preview' }).click()
    await expect(page.locator('[data-retention-preview="job_log"]')).toContainText('a preview changes nothing')
    expect(calls.filter(c => c.p_action !== 'read')).toHaveLength(0)
    await page.locator('[data-retention-row="job_log"]').getByRole('button', { name: 'Purge' }).click()
    await expect.poll(() => calls.find(c => c.p_action === 'purge')?.p_args).toEqual({ category: 'job_log', reason: 'Reduce database size', confirm: 'job_log' })
    await expect(page.locator('[data-retention-row="evidence_audit"]').getByRole('button', { name: 'Run audit' })).toBeVisible()
    await expect(page.locator('[data-retention-row="evidence_audit"]').getByRole('button', { name: 'Purge' })).toHaveCount(0)
    if (process.env.RETENTION_SHOT) await page.screenshot({ path: process.env.RETENTION_SHOT, fullPage: true })
  })
  test('PIM Admin cannot open Storage & retention', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 5 })
    await page.goto('/#storage-retention')
    await expect(page.locator('[data-retention]')).toHaveCount(0)
  })
})
