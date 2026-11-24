// Guards: Platform Admin 18 Nov 2026 12:19 and 14:23 (Coverage & completeness modernisation, no schema change in this lane): no hardcoded attribute list on the screen; courses by fields admitted from 0 of N to N of N; every field against its target with its change and trend; a country by domain readiness grid; the Link refresh supply rows and Stalled fields counters retired, a link to act only where a field is below target; until the coverage read is live the screen shows every recorded field from the completeness report and says what is waiting.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

test('screens: the hardcoded score bands, the portal rows and the read-only stalled counters are gone', () => {
  expect(fs.readFileSync('src/ui-v1/CourseCoverageView.jsx', 'utf8')).not.toContain('<h2>Courses by attributes admitted</h2>')
  expect(fs.readFileSync('src/ui-v1/LinkRefreshView.jsx', 'utf8')).not.toContain('data-portals')
  expect(fs.readFileSync('src/ui-v1/FieldCoverageView.jsx', 'utf8')).not.toContain('<StalledFields scope={scope} readOnly')
  expect(fs.readFileSync('src/mature-main.jsx', 'utf8')).toContain('<CoverageTelemetry onError={err}/>{/* v2.16.54 (s777, Platform Admin 19 Nov 2026 15:36): Pipeline & field ETA, consolidated, by country or by university */}<PipelineEta onError={err}/><CoverageView view="courses"/>') // v2.16.54 (s777): Pipeline & field ETA sits between them
})

const day = '2026-11-18'
const pts = (a) => a.map((p, i) => ({ day: `2026-11-${String(5 + i).padStart(2, '0')}`, pct: p }))
const T = {
  day, then: '2026-11-11', velocity_days: 7, spark_days: 14, country: null, unlabelled: 1,
  domains: [{ code: 'courses', label: 'Courses' }, { code: 'providers', label: 'Providers & campuses' }, { code: 'aer', label: 'AER & grade scales' }, { code: 'scholarships', label: 'Scholarships' }, { code: 'destinations', label: 'Destination editions' }],
  countries: ['AU', 'NZ', 'CA', 'GB', 'IE', 'US'],
  fields: [
    { field: 'official_url', domain: 'courses', label: 'Official course page', unlabelled: false, target_pct: 80, in_score: true, action_href: '#layer-4-review?kind=course_link', action_label: 'Course links in Layer 4', total: 36031, filled: 24064, pct: 66.8, pct_then: 67.1, pts: pts([66, 66.5, 67.1, 66.8]) },
    { field: 'level', domain: 'courses', label: 'Study level', unlabelled: false, target_pct: 80, in_score: true, action_href: '#platform-health?tab=queues', action_label: 'Queues & yield', total: 36031, filled: 35818, pct: 99.4, pct_then: 99.0, pts: pts([99, 99.2, 99.4]) },
    { field: 'v3_study_load', domain: 'courses', label: 'Study load (API v3)', unlabelled: false, target_pct: 80, in_score: false, action_href: '#platform-health?tab=queues', action_label: 'Boost queue', total: 36031, filled: 5367, pct: 14.9, pct_then: 1.2, pts: pts([1.2, 8, 14.9]) },
    { field: 's_award_value', domain: 'scholarships', label: 'Award value held', unlabelled: false, target_pct: 80, in_score: false, action_href: '#scholarships?tab=coverage', action_label: 'Scholarships › Coverage', total: 1253, filled: 1250, pct: 99.8, pct_then: null, pts: pts([99.8]) },
    { field: 'brand_new_field', domain: null, label: 'brand_new_field', unlabelled: true, target_pct: 80, in_score: false, action_href: null, total: 10, filled: 1, pct: 10, pct_then: null, pts: null },
  ],
  score: { n: 15, courses: 36031, fields: [], bands: Array.from({ length: 16 }, (_, i) => ({ admitted: i, courses: i === 12 ? 5800 : i === 15 ? 0 : 100 + i })) },
  grid: [{ country: 'AU', domain: 'courses', total: 385576, filled: 263918, fields: 16, pct: 68.4 }, { country: 'CA', domain: 'aer', total: 3866, filled: 0, fields: 2, pct: 0 }],
}

test.describe('mocked browser', () => {
  test('Coverage now: readiness grid, 0 of 15 to 15 of 15, every field with its change, and a link only below target', async ({ page }) => {
    await mockAdmin(page)
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_coverage_telemetry_v1', (r) => { calls.push(r.request().postDataJSON()); r.fulfill({ json: T }) })
    await page.goto('/#coverage')
    const c = page.locator('[data-coverage-telemetry]')
    await expect(c.locator('[data-ct-cell="AU:courses"]')).toHaveText('68.4%')
    await expect(c.locator('[data-ct-cell="AU:courses"]')).toHaveClass(/ct-heat-3/)
    await expect(c.locator('[data-ct-cell="GB:courses"]')).toHaveText('Not started')
    await expect(c.locator('[data-ct-row]')).toHaveCount(6)
    await expect(c.locator('[data-ct-band]')).toHaveCount(16)
    await c.locator('[data-ct-table-toggle]').click()
    await expect(c.locator('[data-ct-bands-table]')).toContainText('0 of 15')
    await expect(c.locator('[data-ct-bands-table]')).toContainText('15 of 15')
    await expect(c.locator('[data-ct-field="v3_study_load"] [data-ct-delta]')).toHaveText('+13.7 pts')
    await expect(c.locator('[data-ct-field="official_url"] [data-ct-action]')).toHaveAttribute('href', '#layer-4-review?kind=course_link')
    await expect(c.locator('[data-ct-field="level"] [data-ct-action]')).toHaveCount(0) // at or above target: no link
    await expect(c.locator('[data-ct-field="brand_new_field"] [data-ct-unlabelled]')).toBeVisible() // a new recorded field shows without code
    await c.locator('[data-ct-below]').check()
    await expect(c.locator('[data-ct-field="level"]')).toHaveCount(0)
    await c.locator('[data-ct-country]').selectOption('NZ')
    await expect.poll(() => calls.some((b) => b?.p_args?.country === 'NZ')).toBeTruthy()
    await expect(page.locator('[data-portals]')).toHaveCount(0)
    const top = await c.first().boundingBox(), older = await page.locator('[data-link-refresh]').boundingBox()
    expect(top.y).toBeLessThan(older.y)
  })

  test('until the coverage read is live: every recorded field by country from the completeness report, and the rest says it is waiting', async ({ page }) => {
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_coverage_telemetry_v1', (r) => r.fulfill({ status: 404, json: { code: 'PGRST202', message: 'Could not find the function public.admin_coverage_telemetry_v1' } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_completeness_report', (r) => r.fulfill({ json: { snapshot_date: day, countries: ['AU', 'NZ'], cells: [
      { country_code: 'AU', category_key: 'basics', fields: [{ field: 'duration', label: 'Duration', total: 100, filled: 80 }, { field: 'v3_study_load', label: 'v3_study_load', total: 100, filled: 15 }] },
      { country_code: 'AU', category_key: 'provider', fields: [{ field: 'p_website', label: 'Website', total: 10, filled: 9 }] },
      { country_code: 'NZ', category_key: 'basics', fields: [{ field: 'duration', label: 'Duration', total: 50, filled: 10 }, { field: 's_award_value', label: 's_award_value', total: 20, filled: 19 }] }] } }))
    await page.goto('/#coverage')
    const c = page.locator('[data-coverage-telemetry]')
    await expect(c.locator('[data-ct-fallback]')).toContainText('its database change is with S2-Build')
    await expect(c.locator('[data-ct-cell="AU:courses"]')).toHaveText('47.5%') // (80 + 15) of 200
    await expect(c.locator('[data-ct-cell="AU:providers"]')).toHaveText('90.0%')
    await expect(c.locator('[data-ct-cell="NZ:scholarships"]')).toHaveText('95.0%')
    await expect(c.locator('[data-ct-cell="GB:courses"]')).toHaveText('Not started')
    await expect(c.locator('[data-ct-field="duration"]')).toContainText('90 of 150')
    await expect(c.locator('[data-ct-field="v3_study_load"] [data-ct-unlabelled]')).toBeVisible()
    await expect(c.locator('[data-ct-score]')).toHaveCount(0)
    await expect(c.locator('[data-ct-action]')).toHaveCount(0) // no target is known, so no link to act
  })
})
