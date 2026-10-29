// Guards: CF-247 decisions W35 cached snapshots and the gap-cause run time (Platform Admin 30 Oct 2026 06:53): the slow notices, publishability and field-coverage reads answer from derived snapshots with their time, age and stale marker, single-flight bounded refresh, exact drill-downs; Why values are missing shows its actual run time
// Approved: "Cached snapshots for the four slow admin reads: APPROVED FOR DESIGN AND IMPLEMENTATION. ... Keep them read-only and derived;
// no consumer/API or admission behaviour change. Show snapshot generation time and staleness. Define bounded refresh/invalidation and
// prevent expensive concurrent rebuild stampedes. Preserve permission checks and exact live-detail drilldowns." and "'Why values are
// missing' run time: APPROVED. Display the actual source run/snapshot time consistently with the hourly reporting correction."
// G1, G2, G3 and housekeeping are guarded centrally (s42, s32, s57); this spec asserts only what W35 decides.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { snapshotMeta } from './support/admin-fixtures.mjs'
import { fmtAge } from '../../src/lib/format.js'

const MIG_DIR = 'supabase/migrations'
const file = fs.readdirSync(MIG_DIR).find((f) => f.endsWith('_cf247_notices_publishability_snapshots.sql'))
const m = fs.readFileSync(`${MIG_DIR}/${file}`, 'utf8')
const RPC = 'https://example.supabase.co/rest/v1/rpc/'
const fulfil = (route, data) => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(data) })

test('migration: every edited read is md5-guarded, answers from the snapshot and adds only fields', () => {
  for (const [sig, md5] of [['public.admin_platform_notices_read(integer)', 'afe21315ffa1abb4ca7339cf5d4e356c'], ['public.admin_progress_read(text,jsonb)', 'e526fbbad139a8dff69e2b60206462ae'],
    ['security.admin_live_activity_v1()', 'bb02b729324db20302d0b2d70543c091'], ['public.admin_waiting_read()', '7e1ed8ba5e92d1a85b3993fd38201617'],
    ['public.admin_field_coverage(text,jsonb)', '1ffdf56fabb9c40da896a87a87e412a1'], ['public.admin_gap_causes(text)', 'd2bb3adffc373a8bc0208f6f65281882']])
    expect(m).toContain(`select pg_temp.edit_n('${sig}', '${md5}', array[`)
  expect(m).toContain("if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)'")
  expect(m).toContain('v := security.platform_notices_cached_v1(true);')
  expect(m).toContain("'generated_at', now(), 'snapshot', security.admin_read_snapshot_meta_v1('platform_notices'),")
  expect(m).toContain("from jsonb_array_elements(security.platform_notices_cached_v1(false)) n where n->>'toolset' in ('firecrawl', 'openrouter')),")
  expect(m).toContain("'notices_snapshot', security.admin_read_snapshot_meta_v1('platform_notices'),")
  expect(m).toContain("from security.scholarship_publishability_cached_v1() p join scholarship.scholarships s on s.id = p.scholarship_id)")
  expect(m).toContain("'publishability_snapshot', security.admin_read_snapshot_meta_v1('scholarship_publishability'),")
  expect(m).toContain("select count(*) into v_n from security.scholarship_publishability_cached_v1() x join scholarship.scholarships s on s.id = x.scholarship_id")
  expect(m).toContain("'snapshot',security.admin_read_snapshot_meta_v1('scholarship_publishability'));")
  // field coverage: every country from the snapshot, one university live (exact drill-down)
  expect(m).toContain("v_snap := case when v_pid is null then (select s.payload from pipeline.admin_read_snapshots s where s.key = 'field_coverage') end;")
  expect(m).toContain("'snapshot', case when v_snap is not null then security.admin_read_snapshot_meta_v1('field_coverage') end);")
  // the admission path is not touched: the source function is only read, never redefined; admin_read (lane M) is not edited
  expect(m).not.toMatch(/create or replace function security\.scholarship_publishability_v1\(/i)
  expect(m).not.toMatch(/create or replace function public\.admin_read\(/i)
  expect(m).not.toMatch(/function (api\.|public\.(website_|zoho_))/i)
  expect(m).toContain("comment on table pipeline.admin_read_snapshots is 'CF-247 decision W35")
  expect(m).toContain('Never read by the consumer API.')
})

test('migration: bounded refresh, single flight, invalidation after a person acts, a failed build keeps the last snapshot', () => {
  expect(m).toContain("select cron.schedule('admin-read-snapshots', '* * * * *', $$select security.admin_read_snapshots_refresh_v1()$$);")
  for (const k of ['snapshots.platform_notices_every_minutes', 'snapshots.scholarship_publishability_every_minutes', 'snapshots.field_coverage_every_minutes', 'snapshots.stale_after_minutes', 'gaps.causes_stale_after_minutes'])
    expect(m).toContain(`('pipeline', '${k}',`)
  expect(m).toContain("-- fixed: fire guard (the job runs each minute; a rebuild due this minute is not put off by a few seconds of start jitter)")
  expect(m).toContain("if not pg_try_advisory_xact_lock(hashtextextended('cf247.w35.admin_read_snapshot.' || k, 0)) then v_out := v_out || jsonb_build_object(k, 'busy'); continue; end if;")
  expect(m).toContain("exists (select 1 from pipeline.firecrawl_search_resumes r where r.resumed_at > v_s.stamp)")
  expect(m).toContain("exists (select 1 from pipeline.coverage_provider_discovery d where d.site_source = 'manual' and d.site_searched_at > v_s.stamp)")
  expect(m).toContain("exists (select 1 from pipeline.scholarship_publication_batches b where b.created_at > v_s.stamp)")
  expect(m).toContain("update pipeline.admin_read_snapshots set last_error = left(sqlerrm, 500), last_error_at = clock_timestamp() where key = k;")
  // the screens never build: only before the first build do they read live
  expect(m).toContain("-- before the first build only: read live, exactly as before W35")
  expect(m).not.toMatch(/grant [^;]* on function security\.admin_read_snapshots_refresh_v1/i)
  expect(m).toContain('revoke all on function security.admin_read_snapshots_refresh_v1(boolean) from public, anon, authenticated;')
  // exact drill-down and the acknowledgement rule
  expect(m).toContain("case when (e.n->>'last_at')::timestamptz = v_s.stamp then jsonb_build_object('last_at', now()) else '{}'::jsonb end")
  expect(m).toContain("and exists (select 1 from catalogue.providers p where p.id = (i.v->>'provider_id')::uuid and nullif(btrim(p.website), '') is not null))")
  expect(m).toContain("select security.admin_read_snapshots_refresh_v1(true);")
  expect(m).toContain("raise exception 'W35 post-check: % of 3 snapshots built', v_n;")
})

test('migration: gap-causes records its actual run; the screen read adds it beside the snapshot hour', () => {
  expect(m).toContain("select cron.alter_job((select jobid from cron.job where jobname = 'gap-causes'), command := $$select security.gap_causes_run_v1()$$);")
  expect(m).toContain('v_rows := security.gap_causes_snapshot_v1();')
  expect(m).toContain("insert into pipeline.gap_cause_runs(started_at, at, finished_at, item_count, source) values (v_start, date_trunc('hour', now()), v_end, coalesce(v_rows, 0), 'job')")
  expect(m).toContain("return jsonb_build_object('at', v_at, 'previous', v_prev, 'run', security.gap_causes_run_meta_v1(v_at),")
  expect(m).toContain("'stale', now() - r.finished_at > make_interval(mins => security.pipeline_num_v1('gaps.causes_stale_after_minutes', 75)::int)")
  expect(m).toMatch(/'gaps\.causes_stale_after_minutes'[^\n]*\n[^\n]*\n\s*to_jsonb\(75\), 30, 1440, 'minutes'/)
})

test('the age reads the same everywhere (server seconds, plain words)', () => {
  expect(fmtAge(20)).toBe('just now')
  expect(fmtAge(720)).toBe('12 min ago')
  expect(fmtAge(3600)).toBe('1 h ago')
  expect(fmtAge(4500)).toBe('1 h 15 min ago')
  expect(fmtAge(2 * 86400)).toBe('2 days ago')
  expect(fmtAge(null)).toBe('')
})

test.describe('mocked browser', () => {
  test('notices: Layer page strip, Toolsets and limits and Progress show when they were checked; an old snapshot is marked stale', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-2-discovery')
    const strip = page.locator('[data-layer-notices="2"] [data-snapshot-stamp="layer-notices"]')
    await expect(strip).toContainText('Notices checked')
    await expect(strip).toContainText('(3 min ago)')
    await expect(strip).toHaveAttribute('data-stale', 'no')
    await expect(strip.locator('[data-stale-marker]')).toHaveCount(0)

    await page.goto('/#coverage?tab=progress')
    await expect(page.locator('[data-progress-needs] [data-snapshot-stamp="progress-notices"]')).toContainText('(3 min ago)')

    await page.route(`${RPC}admin_platform_notices_read`, (route) => fulfil(route, { can_manage: true, notices: [], snapshot: snapshotMeta({ age_seconds: 2700, stale: true, generated_at: '2026-10-30T06:08:00Z' }) }))
    await page.goto('/#models-services?tab=limits')
    await page.locator('[data-card="services.toolsets"] .cf-card-toggle').click()
    const card = page.locator('[data-card="services.toolsets"] [data-snapshot-stamp="toolset-notices"]')
    await expect(card).toHaveAttribute('data-stale', 'yes')
    await expect(card).toContainText('(45 min ago)')
    await expect(card.locator('[data-stale-marker]')).toHaveText('Stale: older than 30 min')
  })

  test('Dashboard: Scholarships ready to publish says when it was counted', async ({ page }) => {
    await mockAdmin(page)
    await page.route(`${RPC}admin_waiting_read`, (route) => fulfil(route, { rank: 6, rows: [
      { key: 'scholarships_ready', label: 'Scholarships ready to publish', count: 12, oldest: null, href: '#scholarships?tab=coverage', min: 5, snapshot: snapshotMeta({ age_seconds: 4500, stale: true, refresh_every_minutes: 10 }) }] }))
    await page.goto('/#dashboard')
    const row = page.locator('[data-waiting-also] [data-queue="scholarships_ready"]')
    await expect(row).toContainText('12')
    await expect(row.locator('[data-snapshot-stamp="scholarships_ready"]')).toContainText('Counted')
    await expect(row.locator('[data-snapshot-stamp="scholarships_ready"]')).toContainText('(1 h 15 min ago)')
    await expect(row.locator('[data-stale-marker]')).toHaveText('Stale: older than 30 min')
  })

  test('Coverage › Attributes: every country from the snapshot, with its time on the figures and on today\'s AI spend', async ({ page }) => {
    await mockAdmin(page)
    const calls = []
    await page.route(`${RPC}admin_field_coverage`, (route) => {
      const b = route.request().postDataJSON() || {}
      calls.push(b)
      if (b.p_action !== 'overview') return fulfil(route, { items: [], days: 7, min_points: 1, gap_points: 30 })
      return fulfil(route, { register: [{ field: 'p_website', level: 'provider', label: 'Website', reader: 'register', target_pct: 80 }], courses_by_country: [],
        providers_by_country: [{ country: 'NZ', field: 'p_website', total: 10, filled: 8 }], computed_at: '2026-10-30T06:47:00Z', crosscheck: [], can_decide: true, can_manage: true,
        queue: { enabled: true, ai_spent_today_usd: 1.25, ai_guard_usd: 5, reads_per_day: 200 },
        snapshot: snapshotMeta({ age_seconds: 300, refresh_every_minutes: 10 }) })
    })
    await page.goto('/#coverage?tab=attributes')
    await page.locator('[data-card="coverage.fields"] .cf-card-toggle').click()
    const fields = page.locator('[data-card="coverage.fields"]')
    await expect(fields).toContainText('provider figures are counted every 10 minutes')
    await expect(fields.locator('[data-snapshot-stamp="field-coverage"]')).toContainText('Provider figures counted')
    await expect(fields.locator('[data-snapshot-stamp="field-coverage"]')).toContainText('(5 min ago)')
    await page.locator('[data-card="coverage.gap-queue"] .cf-card-toggle').click()
    await expect(page.locator('[data-card="coverage.gap-queue"] [data-snapshot-stamp="field-coverage-spend"]')).toContainText('(5 min ago)')
    expect(calls.some((c) => c.p_action === 'overview')).toBe(true)
  })

  test('Why values are missing: the time the last run finished, its age and a stale marker past 75 minutes', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#platform-health?tab=queues')
    const run = page.locator('[data-gap-causes] [data-gap-run="recorded"]')
    await expect(run.locator('[data-snapshot-stamp="gap-causes"]')).toContainText('Last run finished')
    await expect(run.locator('[data-snapshot-stamp="gap-causes"]')).toContainText('(12 min ago)')
    await expect(run.locator('[data-snapshot-stamp="gap-causes"]')).toHaveAttribute('data-stale', 'no')
    await expect(page.locator('[data-gap-causes]')).not.toContainText('Snapshot 23 Oct')

    await page.route(`${RPC}admin_gap_causes`, (route) => fulfil(route, { at: '2026-10-23T00:00:00Z', previous: null, countries: ['NZ'], rows: [],
      run: { recorded: true, started_at: '2026-10-23T00:55:00Z', finished_at: '2026-10-23T00:55:26Z', rows: 412, age_seconds: 5700, stale: true, stale_after_minutes: 75 } }))
    await page.locator('[data-gap-causes]').getByRole('button', { name: 'Refresh' }).click()
    await expect(run.locator('[data-snapshot-stamp="gap-causes"]')).toContainText('(1 h 35 min ago)')
    await expect(run.locator('[data-stale-marker]')).toHaveText('Stale: older than 75 min')
  })
})
