// Guards: Platform Admin 20 Nov 2026 06:10 AEDT (chat S1-RM-Design, s807): the UnoPim patterns on Catalogue › Courses and Providers: a per-row Completeness bar (Courses: the server's six-signal score; Providers: the share of the nine tracked fields held), a Missing field pill bar whose pills go to the server as filters over the whole set (Courses through the filters courses_page already has; Providers through the new `missing` argument, migration 20261120090000), a bulk bar for ticked providers (fill, export the ticked rows, clear) and a provenance panel in the Provider drawer. Read only: no write, no new public function (G3 75/48).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = fs.readFileSync('supabase/migrations/20261120090000_cf247_s807_provider_missing_field_filter.sql', 'utf8')
const BAR = fs.readFileSync('src/CompletenessBar.jsx', 'utf8')
const CSS = fs.readFileSync('src/completeness-bar.css', 'utf8')
const UI = fs.readFileSync('src/mature-main.jsx', 'utf8')

test('migration: next free version, md5-guarded edit of one existing security function, says what it replaces and retires, adds nothing public', () => {
  expect(MIG).toMatch(/^-- CF-247 S1-RM-Design/)
  expect(MIG).toContain('-- Replaces:')
  expect(MIG).toContain('-- Retires: nothing')
  expect(MIG).toContain("'789b1a5ceb4ee9fbcc770a9d65e31e39'")
  expect(MIG).toMatch(/is not found exactly once/)
  expect(MIG).not.toMatch(/create\s+(or replace\s+)?(function|table|view)\s/i)
  expect(MIG).not.toMatch(/\b(drop|delete\s+from|truncate)\b/i)
  expect(MIG).not.toMatch(/public\./)
  expect(MIG).toContain('post-check')
})

test('migration: the nine fields it accepts are the nine the screen tracks', () => {
  const fromMig = [...MIG.match(/array\[((?:''[a-z_]+'',?)+)\]\) then raise/)[1].matchAll(/''([a-z_]+)''/g)].map(m => m[1])
  const fromUi = [...BAR.match(/PROVIDER_TRACKED_FIELDS=\[([^\]]+)\]/)[1].matchAll(/'([a-z_]+)'/g)].map(m => m[1])
  expect(fromMig).toEqual(fromUi)
  expect(fromUi).toHaveLength(9)
})

test('source: design tokens only, no colour bands or thresholds in the bar, the argument goes to the server, nothing writes', () => {
  expect(CSS).not.toMatch(/#[0-9a-f]{3,8}\b|rgba?\(/i)
  expect(BAR).not.toMatch(/supabase|\.rpc\(|adminRead/)
  expect(BAR).not.toMatch(/pct\s*[<>]=?\s*\d/)
  expect(UI).toContain("['missing','missing']")
  expect(UI).toContain("'quality','missing']")
})

const dayRow = (id, name, missing, extra = {}) => ({ id, canonical_name: name, display_name: name, country_code: 'AU', course_count: 10, lifecycle_status: 'active', publication_status: 'published', last_verified_at: '2026-10-01T00:00:00Z', stable_key: `provider:cricos:${id}`, pdesc: missing === null ? undefined : { missing_fields: missing, description_filled: !missing.includes('description'), source_tier: missing.includes('description') ? null : 'registry_factual', admission_state: 'admitted' }, ...extra })
const ROWS = [dayRow('p1', 'University of Alpha', []), dayRow('p2', 'Beta Institute', ['website', 'phone', 'email']), dayRow('p3', 'Gamma College', ['description', 'website', 'city', 'state_region', 'provider_type', 'phone', 'email', 'address', 'established_year']), dayRow('p4', 'Delta No Facts', null)]

async function mount(page) {
  await mockAdmin(page, { rank: 6 })
  const reads = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    const b = route.request().postDataJSON() || {}
    if (b.p_operation !== 'providers_page') return route.fallback()
    reads.push(b.p_args || {})
    return route.fulfill({ json: { items: ROWS, total: ROWS.length, limit: 50, offset: 0, columns_profile: 'provider_columns_v1' } })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_autobuild', r => r.fulfill({ json: {} }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_type_rules', r => r.fulfill({ json: { rules: [], types: [], counts: {}, can_edit: true } }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_description_run_v1', async route => {
    const b = route.request().postDataJSON() || {}
    return route.fulfill({ json: b.p_action === 'fill_caps' ? { max_size: 5 } : {} })
  })
  await page.goto('/#providers')
  await expect(page.locator('table[data-table="provider"] tbody tr[data-row]').first()).toBeVisible()
  return { reads }
}

test('Providers: a bar per row from the tracked fields (7 of 9 held is 78 percent, 0 of 9 is 0), unknown where the row says nothing', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await mount(page)
  const rows = page.locator('table[data-table="provider"] tbody tr[data-row]')
  await expect(rows.nth(0).locator('[data-completeness]')).toHaveAttribute('data-completeness', '100')
  await expect(rows.nth(1).locator('[data-completeness]')).toHaveAttribute('data-completeness', '67')
  await expect(rows.nth(2).locator('[data-completeness]')).toHaveAttribute('data-completeness', '0')
  await expect(rows.nth(3).locator('[data-completeness]')).toHaveCount(0)
  await expect(rows.nth(1).locator('[role="progressbar"]')).toHaveAttribute('aria-valuenow', '67')
})

test('Providers: Missing field pills go to the server as one list, show as a chip, count and clear', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  const { reads } = await mount(page)
  const bar = page.locator('[data-missing-bar="provider"]')
  await expect(bar.locator('[data-missing-pill]')).toHaveCount(9)
  await bar.locator('[data-missing-pill="website"]').click()
  await bar.locator('[data-missing-pill="phone"]').click()
  await expect.poll(() => reads.some(a => a.missing === 'website,phone')).toBe(true)
  await expect(bar.locator('[data-missing-pill="website"]')).toHaveAttribute('aria-pressed', 'true')
  await expect(page.locator('.m-chip-row')).toContainText('Missing field: Website, Phone')
  await expect(bar.locator('[data-missing-count]')).toContainText('lack all of these')
  await bar.locator('[data-missing-clear]').click()
  await expect.poll(() => reads.at(-1).missing).toBeUndefined()
})

test('Providers: ticking rows shows the bulk bar; export gives only the ticked rows; clear empties it', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await mount(page)
  await expect(page.locator('[data-bulk-bar]')).toHaveCount(0)
  const picks = page.locator('table[data-table="provider"] tbody tr[data-row] .pff-pick input')
  await picks.nth(1).check(); await picks.nth(2).check()
  const bulk = page.locator('[data-bulk-bar]')
  await expect(bulk.locator('[data-bulk-count]')).toContainText('2 selected')
  const [dl] = await Promise.all([page.waitForEvent('download'), bulk.locator('[data-bulk-export]').click()])
  const text = fs.readFileSync(await dl.path(), 'utf8')
  expect(text.split('\r\n').filter(Boolean)).toHaveLength(3)
  expect(text).toContain('Beta Institute')
  expect(text).toContain('Gamma College')
  expect(text).not.toContain('University of Alpha')
  await bulk.locator('[data-bulk-clear]').click()
  await expect(page.locator('[data-bulk-bar]')).toHaveCount(0)
})

test('Provider drawer: completeness and provenance, with the description source in the platform words and the limit stated', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await mount(page)
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    const b = route.request().postDataJSON() || {}
    if (b.p_operation === 'provider_detail') return route.fulfill({ json: { id: 'p1', canonical_name: 'University of Alpha', country_code: 'AU', course_count: 10, scholarship_count: 0, lifecycle_status: 'active', publication_status: 'published' } })
    return route.fallback()
  })
  await page.locator('table[data-table="provider"] tbody tr[data-row]').first().locator('.pl-title').click()
  const panel = page.locator('[data-provenance-panel]')
  await expect(panel).toBeVisible()
  await expect(panel.locator('[data-completeness]')).toHaveAttribute('data-completeness', '100')
  await expect(panel.locator('[data-prov-field="description"] [data-provenance="register"]')).toHaveText('Register')
  await expect(panel).toContainText('their source is not recorded per field yet')
})

test('Courses: the Completeness column is a bar and the Missing field pills ride the filters the list already has @responsive', async ({ page }) => {
  expect(page.viewportSize()?.width || 9999, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(480)
  await mockAdmin(page, { rank: 6 })
  const reads = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    const b = route.request().postDataJSON() || {}
    if (b.p_operation !== 'courses_page') return route.fallback()
    reads.push(b.p_args || {})
    return route.fulfill({ json: { items: [{ id: 'c1', canonical_title: 'Course One', provider_name: 'University of Alpha', country_code: 'AU', completeness_score_v2: 66.67, lifecycle_status: 'active', publication_status: 'published' }], total: 1, limit: 50, offset: 0 } })
  })
  await page.goto('/#courses')
  const bar = page.locator('[data-missing-bar="course"]')
  await expect(bar).toBeVisible()
  await bar.locator('[data-missing-pill="fee"]').click()
  await bar.locator('[data-missing-pill="description"]').click()
  await expect.poll(() => reads.some(a => a.has_fee === false && a.description === 'missing')).toBe(true)
  await expect(page.locator('[data-completeness="67"]').first()).toBeAttached()
  expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(1)
  const pill = await bar.locator('[data-missing-pill="fee"]').boundingBox()
  expect(pill.height).toBeGreaterThanOrEqual(24)
})
