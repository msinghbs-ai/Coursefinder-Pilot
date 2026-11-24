// Guards: Platform Admin 18 Nov 2026 12:50 (Operations aligned with the consolidated dispatchers): Automations leads with the three dispatchers and hides retired legacy jobs unless asked; every Open issues link is named from the menu and opens Queues & yield for the queue watchdog; Storage & retention leads with storage now, staging growth, the staging prune switch and its last run; Evidence says what writes each type and opens the Audit trail and the Layer 4 audit samples.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { platformHealth } from './support/admin-fixtures.mjs'

const job = (name, extra = {}) => ({ job: name, area: 'Pipeline', sort: 1, label: name, description: '', schedule: '* * * * *', active: true, control_rank: 6, catalogued: true, runs_24h: 1440, failed_24h: 0, last: { status: 'succeeded', at: '2026-11-18T01:59:00Z', seconds: 1 }, ...extra })
const retired = (name, by) => job(name, { active: false, runs_24h: 0, last: null, retirement: { status: 'retiring', replaced_by: by, retire_after: '2026-12-02' } })
const JOBS = [
  job('rollup-scheduler'), job('admission-rule-runner'), job('admission-rule-runner-b'), job('admission-rule-runner-c'),
  job('coverage-lane-dispatch'), job('coverage-lane-dispatch-b'), job('coverage-lane-dispatch-c', { failed_24h: 2 }),
  job('housekeeping-daily', { area: 'Housekeeping', schedule: '47 16 * * *', runs_24h: 1 }), job('paused-on-purpose', { area: 'Housekeeping', active: false }),
  retired('report-cache-a', 'rollup-scheduler (pipeline.rollup_targets, mode live)'), retired('report-cache-b', 'rollup-scheduler (pipeline.rollup_targets, mode live)'),
  retired('admission-old', 'admission-rule-runner (pipeline.admission_rules, mode live)'), retired('coverage-old', 'coverage-lane-dispatch (pipeline.field_execution_registry, mode live)'),
]

test('source: dispatchers are named once, retired jobs are filtered before the counts, and links are named from the menu', () => {
  const a = fs.readFileSync('src/ui-v1/AutomationsView.jsx', 'utf8'), p = fs.readFileSync('src/ui-v1/PlatformHealthView.jsx', 'utf8')
  for (const d of ['rollup-scheduler', 'admission-rule-runner', 'coverage-lane-dispatch']) expect(a).toContain(`job:'${d}'`)
  expect(a).toContain("const jobs=useMemo(()=>retired?everyJob:everyJob.filter(j=>!isRetired(j)),[everyJob,retired])")
  expect(p).not.toMatch(/'Platform health › Work queues'/) // the tab was renamed Queues & yield on 3 Nov
  expect(p).toContain('Go to {fixLabel(fixAt(i.check_key))}')
  const s = fs.readFileSync('src/StagingRetention.jsx', 'utf8')
  expect(s).not.toContain('admin_staging_retention_preview') // a preview that finds rows due is logged as a run
})

test.describe('mocked browser', () => {
  test('Automations: three dispatchers first; retired legacy jobs hidden from the list and the counts until shown', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_automations_read', (r) => r.fulfill({ json: { rank: 6, events: [], jobs: JOBS } }))
    await page.goto('/#scheduled-jobs?tab=automations')
    const d = page.locator('[data-au-dispatchers]')
    await expect(d.locator('[data-au-dispatcher]')).toHaveCount(3)
    await expect(d.locator('[data-au-dispatcher="rollup-scheduler"] [data-au-replaced]')).toHaveText('2')
    await expect(d.locator('[data-au-dispatcher="admission-rule-runner"]')).toContainText('Running')
    await expect(d.locator('[data-au-dispatcher="admission-rule-runner"]')).toContainText('4,320')
    await expect(d.locator('[data-au-dispatcher="coverage-lane-dispatch"]')).toContainText('Failures in 24 hours')
    const box = await d.boundingBox(), list = await page.locator('[data-area]').first().boundingBox()
    expect(box.y).toBeLessThan(list.y)
    await expect(page.locator('.ui-metric').filter({ hasText: 'Automations' })).toContainText('8 running')
    await expect(page.locator('.ui-metric').filter({ hasText: 'Automations' })).toContainText('1 paused · 4 retired, hidden')
    await expect(page.locator('[data-job="report-cache-a"]')).toHaveCount(0)
    await page.locator('[data-au-show-retired]').check()
    await expect(page.locator('[data-job="report-cache-a"]')).toContainText('Retiring')
    await expect(page.locator('.ui-metric').filter({ hasText: 'Automations' })).toContainText('5 paused')
  })

  test('Open issues: the queue watchdog link reads Queues & yield and opens it', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', (r) => {
      let b = {}; try { b = r.request().postDataJSON() || {} } catch {}
      if (b.p_operation !== 'platform_health') return r.fallback()
      return r.fulfill({ json: { ...platformHealth, issues: [{ id: 'q1', area: 'Queues', title: 'Find course pages has not moved for 3 hours', detail: {}, severity: 'warning', check_key: 'queue_watch:course_page_search', last_seen: '2026-11-18T01:00:00Z', first_seen: '2026-11-18T01:00:00Z', occurrences: 1, acknowledged_at: null }] } })
    })
    await page.goto('/#platform-health')
    await page.locator('[data-ph-technical] > summary').click()  // s817: the technical sections sit under Technical details
    const link = page.locator('[data-issue-fix]').first()
    await expect(link).toHaveText('Go to Platform health › Queues & yield')
    await expect(page.getByText('Work queues', { exact: false })).toHaveCount(0)
    await link.click()
    await expect(page.locator('[data-queues-yield]')).toBeVisible()
  })

  test('Storage & retention: storage now, staging growth, the prune switch and the last staging run lead the tab', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    const day = '2026-11-18'
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_storage_sizes', (r) => r.fulfill({ json: { day, measured_at: '2026-11-17T13:25:00Z', database_bytes: 4_000_000_000,
      daily: [{ day, database_bytes: 4_000_000_000 }, { day: '2026-11-10', database_bytes: 3_500_000_000 }], buckets: [], schemas: [],
      tables: [{ name: 'pipeline.source_record_staging', bytes: 50_000_000, bytes_7d_ago: 30_000_000, rows: 2661 }, { name: 'pipeline.boost_inbound_staging', bytes: 120_000_000, bytes_7d_ago: 20_000_000, rows: 10348 }, { name: 'pipeline.staging_hash_ledger', bytes: 8192, bytes_7d_ago: 8192, rows: 0 }] } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_retention', (r) => r.fulfill({ json: { database_bytes: 4_000_000_000, categories: [], runs: [],
      storage: { staging: [{ table: 'pipeline.boost_inbound_staging', rows: 10348, bytes: 120_000_000 }], boost_states: { shadow: 10348 },
        prune: { on: false, keep_days: 90, would_go_staging: 12, would_go_boost: 30, ledger_rows: 0, last_runs: [
          { at: '2026-11-18T01:00:00Z', action: 'source_retention_set', detail: {} },
          { at: '2026-11-17T16:47:00Z', action: 'staging_retention_dry_run', detail: { source_record_staging: { due: 12, removed: 0 }, boost_inbound_staging: { due: 30, removed: 0 } } }] } } } }))
    await page.goto('/#platform-health?tab=storage')
    const s = page.locator('[data-staging-retention]')
    await expect(s).toContainText('Dry run only')
    await expect(s).toContainText('Would remove 42 rows') // the latest staging run, not the later keep-period change
    await expect(s).toContainText('+114.4 MB in 7 days') // Layer 1 and Boost staging grew 120,000,000 bytes
    await expect(s.locator('[data-staging-last]')).toContainText('Boost staging 30 due, 0 removed')
    await expect(s.locator('[data-staging-settings]')).toHaveAttribute('href', '#environment?tab=settings')
    const first = await s.boundingBox(), detail = await page.locator('[data-retention-staging]').boundingBox(), sizes = await page.locator('[data-storage-sizes]').boundingBox()
    expect(first.y).toBeLessThan(detail.y)
    expect(detail.y).toBeLessThan(sizes.y)
  })

  test('Evidence: types in plain words grouped by what writes them; a type filters; the Audit trail and the Layer 4 audit samples are one click away', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await page.goto('/#evidence')
    const o = page.locator('[data-evidence-origins]')
    await expect(o.locator('[data-evidence-origin="coverage"]')).toContainText('coverage-lane-dispatch')
    await expect(o.locator('[data-evidence-origin="boost"]')).toContainText('Course page text')
    await o.locator('[data-evidence-origin-type="provider_course_page_text"]').click()
    await expect(o.locator('[data-evidence-origin-type="provider_course_page_text"]')).toHaveAttribute('aria-pressed', 'true')
    expect((page.readCalls || []).some((c) => c.p_operation === 'evidence_page' && c.p_args?.evidence_type === 'provider_course_page_text')).toBeTruthy()
    await expect(o.locator('[data-evidence-layer4-audit]')).toHaveAttribute('href', '#layer-4-review?view=grid')
    await o.locator('[data-evidence-open-audit]').click()
    await expect(page.locator('[data-evidence-audit]')).toBeVisible() // S2-Build's Audit trail (v2.16.39)
  })
})
