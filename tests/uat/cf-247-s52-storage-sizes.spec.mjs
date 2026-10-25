// Guards: CF-247 (S52): Platform Admin 16 Oct 2026 23:18: "Prepare and record all db and tables data and sizes also prepare total bucket usage.
// CF-247 (S52): Platform Admin 16 Oct 2026 23:18: "Prepare and record all db and tables data and sizes also prepare total bucket usage.
// Keep the stat's simple and recoed on daily basis".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261016100000_cf247_storage_size_daily.sql', 'utf8')

test('daily record of database, schemas, tables and buckets; job catalogued; old table rows by setting', () => {
  expect(mig).toContain("check (kind in ('database', 'schema', 'table', 'bucket'))")
  expect(mig).toContain("select cron.schedule('storage-size-daily', '25 13 * * *', 'select security.storage_size_snapshot_v1()');")
  expect(mig.indexOf("('storage-size-daily', 'Platform'")).toBeLessThan(mig.indexOf("select cron.schedule('storage-size-daily'"))
  expect(mig).toContain("security.pipeline_num_v1('storage.size_keep_days', 365)")
  expect(mig).toContain("coalesce(sum((o.metadata ->> 'size')::bigint), 0), count(*)")
  expect(mig).toContain("greatest(c.reltuples, 0)::bigint")
})

test.describe('mocked browser', () => {
  test('Storage & retention shows sizes: database, buckets, schemas, tables', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 6 })
    let measured = 0
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_retention', r => r.fulfill({ json: { database_bytes: 4612238483, categories: [], runs: [] } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_storage_sizes', r => r.fulfill({ json: { day: '2026-10-16', measured_at: '2026-10-16T12:30:00Z', database_bytes: 4612238483, can_measure: true,
      buckets: [{ name: 'evidence', bytes: 20976000000, files: 194630, bytes_7d_ago: null }, { name: 'adapter-captures', bytes: 7015000000, files: 4097 }],
      schemas: [{ name: 'pipeline', bytes: 2909000000, index_bytes: 900000000, rows: 4000000 }],
      tables: [{ name: 'pipeline.coverage_provider_urls', bytes: 348000000, table_bytes: 203000000, index_bytes: 145000000, toast_bytes: 0, rows: 279012, bytes_1d_ago: null, bytes_7d_ago: null }],
      daily: [{ day: '2026-10-16', database_bytes: 4612238483, bucket_bytes: 28100000000, bucket_files: 200761 }] } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_storage_sizes_measure', r => { measured++; return r.fulfill({ json: { day: '2026-10-16', tables: 640 } }) })
    await page.goto('/#storage-retention')
    const s = page.locator('[data-storage-sizes]')
    await expect(s).toContainText('4.3 GB')
    await expect(s.locator('[data-storage-buckets]')).toContainText('evidence')
    await expect(s.locator('[data-storage-tables]')).toContainText('pipeline.coverage_provider_urls')
    await s.getByRole('button', { name: 'Measure now' }).click()
    await expect.poll(() => measured).toBe(1)
  })
})

// Platform Admin 16 Oct 2026 23:44: "Run 1,2,6,7": daily housekeeping job replaces the two job-log trims made outside git.
const hk = fs.readFileSync('supabase/migrations/20261016110000_cf247_housekeeping_daily.sql', 'utf8')
test('daily housekeeping: expired request codes and old job run records by setting; old trims switched off, not removed', () => {
  expect(hk).toContain("make_interval(days => security.pipeline_num_v1('retention.nonce_keep_days', 1)::int)")
  expect(hk).toContain("make_interval(days => security.pipeline_num_v1('retention.job_log_keep_days', 3)::int)")
  expect(hk).toContain("security.pipeline_num_v1('batch.housekeeping_rows', 400000)::int")
  expect(hk.indexOf("('housekeeping-daily', 'Platform upkeep'")).toBeLessThan(hk.indexOf("select cron.schedule('housekeeping-daily'"))
  expect(hk).toContain("select cron.alter_job((select jobid from cron.job where jobname = 'cron-history-trim'), active := false);")
  expect(hk).not.toMatch(/cron\.unschedule|^select security\.housekeeping_daily_v1/m)
})
