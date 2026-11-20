// Guards: Platform Admin 19 Nov 2026 16:37 AEDT (chat S1-RM-Design, s781): Catalogue › Providers rows lead with a 32 px logo or a colour-coded two-letter monogram, the name in bold with its CRICOS code or stable key under it; country codes show a drawn SVG flag (AU, NZ, CA) beside one code pill, never the "AU AU" emoji fallback; Extract / refresh description is a compact icon, not a full-width button in every row; the adapter badge reads in full; the Type control stays inside its column; five filters in the bar and the eight technical ones in a More filters popover with a count; inactive page tabs read clearly. Checked at 1280 px and at phone width (@responsive).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const UI = fs.readFileSync('src/mature-main.jsx', 'utf8')
const PARTS = fs.readFileSync('src/ProviderListParts.jsx', 'utf8')
const TOKENS = fs.readFileSync('src/tokens.css', 'utf8')
const KIT = fs.readFileSync('src/ui-kit.css', 'utf8')

const row = (id, name, extra = {}) => ({ id, canonical_name: name, display_name: name, country_code: 'AU', course_count: 10, lifecycle_status: 'active', publication_status: 'published', last_verified_at: '2026-10-01T00:00:00Z', adapter_status: 'none', university_groups: [], evidence_count: 2, provider_type_code: 'university', provider_type_name: 'University', ...extra })
const ROWS = [
  row('p1', 'University of Alpha', { stable_key: 'provider:cricos:00001A', registration: { scheme: 'CRICOS', code: '00001A', status: 'active' } }),
  row('p2', 'Beta Institute of Technology', { country_code: 'NZ', stable_key: 'provider:nzqa:8001', registration: { scheme: 'nzqa', code: '8001', status: 'active' }, provider_type_code: null, provider_type_name: null }),
  row('p3', 'Collège Gamma', { country_code: 'CA', stable_key: 'provider:ca:dli:o123' }),
]
const STATES = { p1: { adapter: 'off' }, p2: { adapter: 'testing' }, p3: { adapter: null } }
const TYPES = [{ code: 'university', name: 'University' }, { code: 'tafe', name: 'TAFE and vocational institute with a long name' }]

async function mount(page) {
  await mockAdmin(page, { rank: 6 })
  const reads = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    const b = route.request().postDataJSON() || {}
    if (b.p_operation !== 'providers_page') return route.fallback()
    reads.push(b.p_args || {})
    return route.fulfill({ json: { items: ROWS, total: ROWS.length, limit: 50, offset: 0, columns_profile: 'provider_columns_v1' } })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_autobuild', r => r.fulfill({ json: STATES }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_type_rules', r => r.fulfill({ json: { rules: [], types: TYPES, counts: {}, can_edit: true } }))
  // one logo is stored (p1); the others fall back to the monogram
  await page.route('https://example.supabase.co/functions/v1/provider-asset-access', r => r.fulfill({ json: { expires_in: 600, items: [{ stable_key: 'provider:cricos:00001A', provider_id: 'p1', url: 'data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="navy"/></svg>' }] } }))
  await page.goto('/#providers')
  await expect(page.locator('table[data-table="provider"] tbody tr[data-row]').first()).toBeVisible()
  return { reads }
}
const cellOf = (page, i, col) => page.locator('table[data-table="provider"] tbody tr[data-row]').nth(i).locator(`td[data-col="${col}"], td`).nth(0)

test('source: flags are drawn SVG from tokens, never regional-indicator emoji; the tabs read in slate 700', () => {
  expect(UI).not.toContain('127397')
  expect(UI).not.toContain('countryFlag(')
  expect(UI).toContain("if(key==='country_code')return <CountryTag code={v}/>;")
  expect(UI).toContain("if(k==='country_code')return <CountryTag code={v}/>;")
  for (const c of ['AU:', 'NZ:', 'CA:']) expect(PARTS).toContain(c)
  expect(PARTS).not.toContain('fromCodePoint')
  expect(TOKENS).toContain('--cf-flag-navy:#012169;--cf-flag-red:#c8102e;--cf-flag-ca-red:#d52b1e;')
  expect(KIT).toContain('padding:9px 12px 8px;color:var(--cf-slate-700);')
})

test('Providers at 1280 px: logo or monogram, bold name with its code, one flag and one code, compact actions, Type inside its column', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await mount(page)
  const rows = page.locator('table[data-table="provider"] tbody tr[data-row]')
  await expect(rows).toHaveCount(3)
  // logo slot: an image where one is stored, otherwise the two-letter monogram
  await expect(rows.nth(0).locator('[data-pl-logo="image"] img')).toBeVisible()
  await expect(rows.nth(1).locator('[data-pl-logo="monogram"]')).toHaveText('BI')
  await expect(rows.nth(2).locator('[data-pl-logo="monogram"]')).toHaveText('CG')
  for (let i = 0; i < 3; i++) {
    const box = await rows.nth(i).locator('[data-pl-logo]').boundingBox()
    expect(Math.round(box.width)).toBe(32); expect(Math.round(box.height)).toBe(32)
  }
  // name bold, code underneath
  const title = rows.nth(0).locator('.pl-title')
  expect(Number(await title.evaluate(e => getComputedStyle(e).fontWeight))).toBeGreaterThanOrEqual(600)
  await expect(rows.nth(0).locator('[data-provider-meta]')).toHaveText('CRICOS 00001A')
  await expect(rows.nth(1).locator('[data-provider-meta]')).toHaveText('NZQA 8001') // the register name in capitals, as stored lower case
  await expect(rows.nth(2).locator('[data-provider-meta]')).toHaveText('provider:ca:dli:o123') // no registration: the stable key
  // country: one SVG flag and the code once (no "AU AU")
  for (const [i, c] of [[0, 'AU'], [1, 'NZ'], [2, 'CA']]) {
    const tag = rows.nth(i).locator(`[data-country="${c}"]`)
    await expect(tag.locator(`svg[data-flag="${c}"]`)).toBeVisible()
    expect((await tag.textContent()).trim()).toBe(c)
  }
  expect(await page.locator('table[data-table="provider"]').evaluate(t => /[\u{1F1E6}-\u{1F1FF}]/u.test(t.textContent))).toBe(false)
  // Extract / refresh description is a compact icon with its tooltip; rows stay compact
  const act = rows.nth(0).getByRole('button', { name: 'Extract / refresh description now for University of Alpha' })
  await expect(act).toHaveAttribute('title', 'Extract / refresh description')
  const ab = await act.boundingBox(); expect(ab.width).toBeLessThanOrEqual(32); expect(ab.height).toBeGreaterThanOrEqual(24)
  for (let i = 0; i < 3; i++) expect((await rows.nth(i).boundingBox()).height).toBeLessThanOrEqual(72)
  // adapter: the badge reads in full and stays inside its cell; Open adapter keeps its name
  for (const [i, label] of [[0, 'Switched off'], [1, 'Testing']]) {
    const cell = rows.nth(i).locator('[data-adapter-cell]')
    const chip = cell.locator('.cf-chip')
    await expect(chip).toHaveText(label)
    expect(await chip.evaluate(e => e.scrollWidth <= e.clientWidth + 1)).toBe(true)
    const td = await cell.evaluate(e => { const t = e.closest('td').getBoundingClientRect(), b = e.getBoundingClientRect(); return { inside: b.right <= t.right + 1 } })
    expect(td.inside, `${label} badge inside the Adapter column`).toBe(true)
    await expect(cell.getByRole('button', { name: 'Open adapter' })).toBeVisible()
  }
  await expect(rows.nth(2).getByRole('button', { name: 'Create adapter' })).toBeVisible()
  // Type: the select never crosses its column border
  for (let i = 0; i < 3; i++) {
    const sel = rows.nth(i).locator('[data-type-control] select')
    await expect(sel).toBeVisible()
    const r = await sel.evaluate(e => { const t = e.closest('td').getBoundingClientRect(), b = e.getBoundingClientRect(); return { w: b.width, inside: b.right <= t.right + 1 } })
    expect(r.inside).toBe(true); expect(r.w).toBeLessThanOrEqual(140.5)
  }
  // inactive page tabs: slate 700
  const inactive = page.locator('.cf-page-tabs [role="tab"][aria-selected="false"]').first()
  expect(await inactive.evaluate(e => getComputedStyle(e).color)).toBe(await page.evaluate(() => { const s = document.createElement('span'); s.style.color = 'var(--cf-slate-700)'; document.body.appendChild(s); const c = getComputedStyle(s).color; s.remove(); return c }))
})

test('filters: five in the bar, nine in More filters with a count; a choice there goes to the server', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  const { reads } = await mount(page)
  const bar = page.locator('[data-provider-filters]')
  const labels = () => bar.locator(':scope > .m-filter-select small').allTextContents()
  expect((await labels()).map(x => x.trim())).toEqual(['Country', 'Type', 'Status', 'Description', 'University group'])
  await expect(page.locator('[data-more-filters]')).toHaveCount(0)
  await page.locator('[data-more-filters-toggle]').click()
  const more = page.locator('[data-more-filters]')
  expect((await more.locator('.m-filter-select small').allTextContents()).map(x => x.trim())).toEqual(['State / region', 'Publication', 'Adapter', 'Description quality', 'Description admission', 'Description source', 'Website feed', 'Zoho feed', 'Main campus'])  // s818 (20 Nov 2026): Main campus
  const f = more.locator('.m-filter-select').filter({ has: page.locator('small', { hasText: /^Website feed$/ }) })
  await f.locator('button.m-filter-button').click()
  await f.locator('.m-filter-popover button').nth(1).click()
  await expect(page.locator('[data-more-filters-count]')).toHaveText('1')
  await expect.poll(() => reads.some(a => a.website)).toBe(true)
  await page.keyboard.press('Escape')
  await expect(page.locator('[data-more-filters]')).toHaveCount(0)
  await expect(page.locator('[data-more-filters-count]')).toHaveText('1')
})

test('Providers at phone width: More filters fits the screen and nothing scrolls sideways @responsive', async ({ page }) => {
  expect(page.viewportSize()?.width || 9999, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(480)
  await mount(page)
  await page.locator('[data-more-filters-toggle]').click()
  const panel = page.locator('[data-more-filters]')
  await expect(panel).toBeVisible()
  const b = await panel.boundingBox(), w = page.viewportSize().width
  expect(b.x).toBeGreaterThanOrEqual(0); expect(b.x + b.width).toBeLessThanOrEqual(w + 1)
  expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(1)
  await expect(page.locator('table[data-table="provider"] svg[data-flag="AU"]').first()).toBeAttached()
})
