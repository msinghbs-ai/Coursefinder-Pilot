// Guards: Platform Admin mandate 5 Nov 2026 17:31, Course Catalogue columns (decision 19:14 §3): customisable columns, per-user layouts, data freshness
// Source contract and the screen in a mocked browser. The acceptance against real SQL is tests/integration/course-columns-postgres.spec.mjs on the
// production-representative fixture (tests/fixtures/course-catalogue-columns, workflow course-catalogue-columns-test.yml).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import path from 'node:path'
import { collisions, selectorClasses } from '../../scripts/verify-css-class-collisions.mjs'
import { COURSE_COLUMNS, GROUPS, defaultLayout, normaliseLayout, moveColumn, toggleColumn, citySummary, sortSentence, intakeSummary, intakeName } from '../../src/catalogue-columns.js'

const MIG = fs.readFileSync('supabase/migrations/20261106300000_cf247_course_catalogue_columns.sql', 'utf8')
const UI = fs.readFileSync('src/mature-main.jsx', 'utf8')

test('the screen registry equals the database registry the server checks a layout against', () => {
  const rows = [...MIG.matchAll(/\('courses', '([a-z0-9_]+)', '([^']+)', '([^']+)', (\d+), (?:'([a-z_]+)'|null), (true|false), (\d+), (\d+), (true|false)\)/g)]
    .map(m => ({ key: m[1], group: m[2], label: m[3], sortKey: m[5] || null, defaultVisible: m[6] === 'true', width: +m[7], minWidth: +m[8], alwaysVisible: m[9] === 'true' }))
  expect(rows).toHaveLength(40)
  expect(COURSE_COLUMNS.map(({ header, ...c }) => ({ ...c, sortKey: c.sortKey || null }))).toEqual(rows)
  expect(new Set(COURSE_COLUMNS.map(c => c.group))).toEqual(new Set(GROUPS))
})

test('the default layout is today\'s 11 columns in today\'s order and headings, then Adapter status, Last modified and Last data admitted', () => {
  expect(defaultLayout().columns).toEqual(['canonical_title', 'course_code', 'provider_name', 'subdivision_name', 'city_names', 'level_name', 'field_of_study', 'intl_fee_amount', 'fee_amount', 'completeness_score_v2', 'adapter_state', 'last_verified_at', 'last_modified_at', 'last_admitted_at'])
  // today's columns() list is unchanged (the readiness workspace and the CRICOS rule read it)
  expect(UI).toContain("{key:'fee_amount',label:'Tuition Only',width:150,sortKey:'fee'}")
  expect(COURSE_COLUMNS.find(c => c.key === 'fee_amount').header).toBe('Tuition Only')
})

test('a saved layout is made safe before use; show, hide and move keep the course title', () => {
  const n = normaliseLayout({ columns: ['provider_name', 'salary', 'provider_name', 'last_admitted_at'], widths: { provider_name: 5, last_admitted_at: 9999, x: 3 }, sort: 'drop', direction: 'sideways' })
  expect(n.columns).toEqual(['canonical_title', 'provider_name', 'last_admitted_at'])
  expect(n.widths).toEqual({ provider_name: 120, last_admitted_at: 1200 })
  expect([n.sort, n.direction]).toEqual(['course', 'asc'])
  expect(toggleColumn(['canonical_title'], 'canonical_title', false)).toEqual(['canonical_title'])
  expect(toggleColumn(['canonical_title', 'last_admitted_at'], 'city_names', true)).toEqual(['canonical_title', 'city_names', 'last_admitted_at'])
  expect(moveColumn(['a', 'b', 'c'], 'c', -1)).toEqual(['a', 'c', 'b'])
  expect(citySummary([{ city: 'Richmond', subdivision_code: 'AU-VIC' }, { city: 'Richmond', subdivision_code: 'AU-NSW' }]).short).toBe('Richmond (VIC) +1')
  expect(sortSentence('admitted', 'desc')).toBe('Last data admitted, newest first (Unknown last)')
  expect(intakeSummary([{ month: 2, year: 2027 }, { label: 'July', month: 7, year: 2027 }, { label: 'Rolling' }]).short).toBe('Feb 2027 +2')
  expect(intakeName({ label: 'Summer school' })).toBe('Summer school')
})

// v2.15.486 acceptance defect: the production build loads every screen's stylesheet; data-quality.css's .cc-bar (18 px, overflow hidden) clipped
// the Columns panel. The screen's classes now carry their own prefix, the build refuses a collision, and the browser tests below load every
// stylesheet in src, as the production bundle does, before they use the panel.
const ALL_CSS = (() => { const walk = d => fs.readdirSync(d, { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(path.join(d, e.name)) : e.name.endsWith('.css') ? [path.join(d, e.name)] : []); return walk('src').map(f => fs.readFileSync(f, 'utf8')).join('\n') })()
test('no class of the Columns screen is defined by another stylesheet (the v2.15.486 collision cannot come back)', () => {
  expect(collisions()).toEqual([])
  expect(selectorClasses(fs.readFileSync('src/data-quality.css', 'utf8')).has('cc-bar')).toBe(true) // the class that clipped the panel is still data quality's
  expect([...selectorClasses(fs.readFileSync('src/catalogue-columns.css', 'utf8'))].filter(c => c.startsWith('cc-'))).toEqual([])
  expect(JSON.parse(fs.readFileSync('package.json', 'utf8')).scripts.prebuild).toContain('node scripts/verify-css-class-collisions.mjs')
})
// every checkbox in the open panel can be clicked: the element at its centre is the checkbox or its label
async function panelUsable(page) {
  await page.addStyleTag({ content: ALL_CSS })
  await page.locator('[data-columns-toggle]').click()
  const boxes = page.locator('[data-columns-panel] [data-col-toggle]')
  expect(await boxes.count()).toBe(40)
  // the whole panel is on screen and not clipped: its close button can be clicked, and each checkbox, centred in the panel's own scroll area
  // (never by scrolling an outer box, which once showed a clipped panel through an 18 px slit), is what is under the pointer
  const panel = page.locator('[data-columns-panel]')
  const pb = await panel.boundingBox(), vw = page.viewportSize()
  expect(pb.x).toBeGreaterThanOrEqual(-1); expect(pb.x + pb.width).toBeLessThanOrEqual(vw.width + 1); expect(pb.height).toBeGreaterThanOrEqual(200)
  const close = page.getByRole('button', { name: 'Close columns' })
  expect(await close.evaluate(el => { const r = el.getBoundingClientRect(); const at = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return Boolean(at && el.contains(at)) })).toBe(true)
  for (const box of await boxes.all()) {
    const hit = await box.evaluate(el => {
      const p = el.closest('[data-columns-panel]'), pr = p.getBoundingClientRect()
      p.scrollTop += el.getBoundingClientRect().top - (pr.top + pr.height / 2)
      const r = el.getBoundingClientRect(); const at = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)
      return Boolean(at && (at === el || (at.closest('label') && at.closest('label').contains(el))))
    })
    expect(hit, await box.getAttribute('data-col-toggle')).toBe(true)
  }
  await page.locator('[data-col-toggle="country_name"]').click()
  await expect(page.locator('[data-col-toggle="country_name"]')).toBeChecked()
  // the acknowledgement is seen where the person is looking: inside the open panel (on a phone the panel covers the bar) and in the bar once closed
  const seen = async loc => { await expect(loc).toContainText('Layout saved to your account'); await loc.scrollIntoViewIfNeeded(); const b = await loc.boundingBox(); expect(b && b.height).toBeGreaterThanOrEqual(12)
    expect(await loc.evaluate(el => { const r = el.getBoundingClientRect(); const at = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return Boolean(at && el.contains(at)) })).toBe(true) }
  await seen(page.locator('[data-layout-ack-panel="success"]'))
  await page.keyboard.press('Escape')
  await seen(page.locator('[data-layout-ack="success"]'))
}
async function layoutRoute(page) {
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_table_layout', route => { const b = route.request().postDataJSON()
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(b.p_action === 'read' ? { screen: 'courses', layout: null, server_layouts: true, new_sorts: true, limits: { max_columns: 60, width_min_px: 64, width_max_px: 1200 } } : { saved: true, layout: b.p_args.layout, saved_at: '2026-11-06T00:30:00Z', has_previous: true }) }) })
}
test('with every stylesheet loaded as in production, all 40 Columns checkboxes can be clicked and the saved acknowledgement shows', async ({ page }) => {
  await mockAdmin(page); await layoutRoute(page)
  await page.goto('/#courses')
  await expect(page.getByRole('heading', { name: 'Course catalogue' })).toBeVisible()
  await panelUsable(page)
})

test.describe('mocked browser', () => {
  async function mount(page, saved = null) {
    await mockAdmin(page)
    const calls = []; let layout = saved
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_table_layout', async route => {
      const b = route.request().postDataJSON(); calls.push(b)
      const json = d => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(d) })
      if (b.p_action === 'read') return json({ screen: 'courses', layout, has_previous: false, limits: { max_columns: 60, width_min_px: 64, width_max_px: 1200, max_bytes: 16000 } })
      if (b.p_action === 'save') { layout = b.p_args.layout; return json({ saved: true, layout, saved_at: '2026-11-05T09:30:00Z', has_previous: true }) }
      if (b.p_action === 'reset') { layout = null; return json({ reset: true, layout: null, has_previous: true }) }
      return json({})
    })
    await page.goto('/#courses')
    await expect(page.getByRole('heading', { name: 'Course catalogue' })).toBeVisible()
    return calls
  }
  const keys = page => page.locator('table[data-table="course"] thead th[data-col]').evaluateAll(t => t.map(th => th.dataset.col))
  test('Columns: grouped, searchable, counted; hiding a column saves the layout and says so; the active sort is shown; Unknown, not a made-up date', async ({ page }) => {
    const calls = await mount(page)
    await expect(page.locator('[data-active-sort]')).toContainText('Sorted by Course, A to Z')
    await expect(page.getByRole('columnheader', { name: 'Last data admitted' })).toBeVisible()
    await expect(page.locator('[data-admitted="unknown"]').first()).toHaveText('Unknown')
    await page.locator('[data-columns-toggle]').click()
    for (const g of GROUPS) await expect(page.locator(`[data-columns-group="${g}"]`)).toBeVisible()
    await expect(page.locator('[data-columns-count]')).toHaveText('14 of 40')
    await expect(page.locator('[data-col-toggle="canonical_title"]')).toBeDisabled()
    await page.getByLabel('Search columns').fill('adapter')
    await expect(page.locator('[data-col-toggle]')).toHaveCount(3)
    await page.locator('[data-col-toggle="adapter_state"]').uncheck()
    await expect(page.locator('[data-layout-ack="success"]')).toContainText('Layout saved to your account')
    expect(await keys(page)).not.toContain('adapter_state')
    const save = calls.find(c => c.p_action === 'save')
    expect(save.p_args.screen).toBe('courses')
    expect(save.p_args.layout.columns).not.toContain('adapter_state')
    expect(Object.keys(save.p_args.layout).sort()).toEqual(['columns', 'direction', 'sort', 'version', 'widths'])
  })
  test('a saved layout is applied when the screen opens; Reset to default restores the default columns', async ({ page }) => {
    await mount(page, { version: 1, columns: ['canonical_title', 'last_admitted_at', 'provider_name'], widths: { provider_name: 300 }, sort: 'admitted', direction: 'desc' })
    await expect.poll(() => keys(page)).toEqual(['canonical_title', 'last_admitted_at', 'provider_name'])
    await expect(page.locator('[data-active-sort]')).toHaveAttribute('data-active-sort', 'admitted:desc')
    await page.locator('[data-columns-toggle]').click()
    await page.locator('[data-columns-reset]').click()
    await expect(page.locator('[data-layout-ack="success"]')).toContainText('Default layout restored')
    expect(await keys(page)).toEqual(defaultLayout().columns)
  })
  test('forward recovery: with server layouts switched off nothing is saved to the server; with the new sorts off they are not offered', async ({ page }) => {
    await mockAdmin(page)
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_table_layout', route => { const b = route.request().postDataJSON(); calls.push(b)
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(b.p_action === 'read' ? { screen: 'courses', layout: null, server_layouts: false, new_sorts: false, limits: { max_columns: 60, width_min_px: 64, width_max_px: 1200 } } : { saved: false, server_layouts: false }) }) })
    await page.goto('/#courses')
    await expect(page.locator('th[data-col="last_admitted_at"] button')).toBeDisabled()
    await expect(page.locator('th[data-col="adapter_state"] button')).toBeDisabled()
    await expect(page.locator('th[data-col="provider_name"] button')).toBeEnabled()
    await page.locator('[data-columns-toggle]').click()
    await page.locator('[data-col-toggle="country_name"]').check()
    await expect(page.locator('[data-layout-ack="warning"]')).toContainText('server layouts are switched off')
    expect(calls.filter(c => c.p_action !== 'read')).toEqual([])
    await expect(page.locator('[data-columns-restore]')).toBeDisabled()
  })
  test('without the server the layout still works from this browser and says it is saved here only', async ({ page }) => {
    await mockAdmin(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_table_layout', route => route.fulfill({ status: 503, contentType: 'application/json', body: '{"message":"unavailable"}' }))
    await page.goto('/#courses')
    await page.locator('[data-columns-toggle]').click()
    await page.locator('[data-col-toggle="country_name"]').check()
    await expect(page.locator('[data-layout-ack="warning"]')).toContainText('Saved in this browser only')
    await page.reload()
    await expect.poll(() => keys(page)).toContain('country_name')
  })
})

test.describe('phone @responsive', () => {
  test('Columns panel at phone width with every stylesheet loaded: all 40 checkboxes can be tapped and the saved acknowledgement shows', async ({ page }) => {
    await mockAdmin(page); await layoutRoute(page)
    expect(page.viewportSize()?.width || 9999, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(480)
    await page.goto('/#courses')
    await expect(page.getByRole('heading', { name: 'Course catalogue' })).toBeVisible()
    await panelUsable(page)
  })
  test('Course catalogue columns at phone width: the Columns panel fits the screen, the table scrolls in its own frame, no sideways page scroll', async ({ page }) => {
    await mockAdmin(page)
    const w = page.viewportSize()?.width || 9999
    expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(480)
    await page.goto('/#courses')
    await page.locator('[data-columns-toggle]').click()
    const b = await page.locator('[data-columns-panel]').boundingBox()
    expect(b.x).toBeGreaterThanOrEqual(-1); expect(b.x + b.width).toBeLessThanOrEqual(w + 1)
    const reset = await page.locator('[data-columns-reset]').boundingBox()
    expect(reset.height).toBeGreaterThanOrEqual(24)
    await page.keyboard.press('Escape')
    const frame = await page.locator('.m-table-wrap.ccol-frame').evaluate(el => ({ client: el.clientWidth, scroll: el.scrollWidth, x: getComputedStyle(el).overflowX }))
    expect(frame.client).toBeLessThanOrEqual(w)
    if (frame.scroll > frame.client) expect(['auto', 'scroll']).toContain(frame.x)
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
  })
})
