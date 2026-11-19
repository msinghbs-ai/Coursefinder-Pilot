// Guards: Platform Admin 19 Nov 2026 15:36 AEDT (chat S1-Build, s777): Coverage & completeness › Courses › Pipeline & field ETA shows, for all courses, a country or one university, each API v3 field as Admitted, Trying, Needs a source, Not possible and Wave 2 with the daily velocity, primary bottleneck and expected 100% achievable date; it reads one row of the readiness snapshot through the existing admin_field_coverage (action pipeline_eta, under 500 ms); no table and no consumer API function is added.
// The live rolled-back dry run (label live-dry-run) runs the migration's post-checks against production (ETA read 34 ms, a part 19 s on 19 Nov 2026).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const m = fs.readFileSync(migrationPath('20261119174000_cf247_s777_pipeline_field_eta.sql'), 'utf8')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('only internal functions, one setting pair, one rollup target; nothing dropped, no table, no consumer API', () => {
  expect(m).toMatch(/^-- Replaces: nothing/m); expect(m).toMatch(/^-- Retires: nothing/m)
  expect(c).not.toMatch(/\b(create\s+(temp\w*\s+|unlogged\s+)?table|drop\s+(table|function|index)|truncate|delete\s+from|alter\s+table)\b/i)
  const created = [...c.matchAll(/create or replace function ([a-z_]+\.[a-z0-9_]+)\(/g)].map((x) => x[1])
  expect(created.filter((f) => !f.startsWith('pg_temp.'))).toEqual(['security.course_field_readiness_summary_v1', 'security.course_field_eta_v1', 'security.course_field_readiness_build_v1', 'security.course_field_readiness_tabs_v1'])
  expect(c).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  expect(c).toContain("select pg_temp.cf_edit_def('public.admin_field_coverage(text,jsonb)'::regprocedure, 'bc8b60cb359741753cecabe2449aa30e',")
  expect(c).toContain("return security.course_field_eta_v1(coalesce(p_args->>'scope', 'all'), v_cc, v_pid, p_args->>'q');")
  expect(c).toContain("values ('course-field-readiness', null, 'select security.course_field_readiness_build_v1()', md5('select security.course_field_readiness_build_v1()'), '*/4 * * * *', 'A', 90, true, 'live', 20000,")
  for (const k of ["'readiness.snapshot_parts'", "'readiness.days_kept'"]) expect(c).toContain(k)
})

test('the snapshot lives in the job state table, one part a run; the read is one row; velocity is a 7-day window of daily marks', () => {
  expect(c).not.toContain('pipeline.admin_read_snapshots')
  expect(c).toContain("'course-field-readiness:p' || v_part")
  expect(c).toContain("where s.job_key = 'course-field-readiness:summary');")
  expect(c).toContain("filter (where d::date <= v_now::date - 7), min(d) filter (where d < v_now)) into v_base")
  expect(c).toContain("raise exception 'post-check: the ETA read took % ms and % ms'")
})

test('Pipeline & field ETA: consolidated, by country and by university', async ({ page }) => {
  const calls = []
  const field = (f, a) => ({ field: f, admitted: a, trying: 100, needs_source: 50, not_possible: 10, wave2: 0, velocity: f === 'description' ? 70.5 : null, bottleneck: 'trying',
    remaining: 150, eta_days: f === 'description' ? 3 : null, eta_state: f === 'description' ? 'forecast' : 'not_measured' })
  const answer = (args) => ({ ready: true, scope: args.scope || 'all', label: args.scope === 'country' ? args.country : args.scope === 'provider' ? 'Monash University' : 'All courses',
    courses: args.scope === 'provider' ? 640 : 36031, built_at: '2026-11-19T05:00:00Z', oldest_part_at: '2026-11-19T04:10:00Z', parts: 16, parts_built: 16,
    velocity_from: '2026-11-12', velocity_to: '2026-11-19', velocity_days: 7, countries: [{ code: 'AU', courses: 25703 }, { code: 'CA', courses: 3814 }, { code: 'NZ', courses: 6514 }],
    fields: [field('duration', 29493), field('description', 15030)],
    providers: args.q ? [{ id: 'p-monash', name: 'Monash University', country: 'AU', courses: 640 }] : null })
  const { mockAdmin } = await import('./support/admin-mock.mjs')
  await mockAdmin(page, { rank: 3 })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_field_coverage', async (r) => {
    const b = r.request().postDataJSON() || {}
    if (b.p_action !== 'pipeline_eta') return r.fallback()
    calls.push(b.p_args); await r.fulfill({ json: answer(b.p_args || {}) })
  })
  await page.goto('/#coverage?tab=courses')
  const box = page.locator('[data-pipeline-eta]')
  await expect(box.locator('[data-pe-field="duration"]')).toContainText('29,493')
  await expect(box.locator('[data-pe-meta]')).toContainText('36,031 active courses')
  await expect(box.locator('[data-pe-field="description"] [data-pe-eta="forecast"]')).toContainText('~3 days')
  await box.locator('[data-pe-scope="country"]').click()
  await box.locator('[data-pe-country]').selectOption('NZ')
  await expect(box.locator('[data-pe-meta]')).toContainText('New Zealand')
  await box.locator('[data-pe-scope="provider"]').click()
  await box.locator('[data-pe-search]').fill('mona')
  await box.locator('[data-pe-provider="p-monash"]').click()
  await expect(box.locator('[data-pe-meta]')).toContainText('Monash University')
  await expect(box.locator('[data-pe-meta]')).toContainText('640 active courses')
  expect(calls.some((a) => a.scope === 'country' && a.country === 'NZ')).toBe(true)
  expect(calls.some((a) => a.scope === 'provider' && a.provider === 'p-monash')).toBe(true)
})
