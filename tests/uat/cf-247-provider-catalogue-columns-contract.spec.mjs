// Guards: Platform Admin directive 9 Nov 2026, Provider Catalogue customisable columns (same mechanism as the Course Catalogue columns, decision 5 Nov 2026 19:14 §3): searchable show/hide, order, widths, saved per person and per screen, server-side sorting and filtering over every provider, role permissions kept
// Source contract and the screen in a mocked browser. The acceptance against real SQL (v2 and v3 give the same rows, filter counts equal the database,
// paging over every sort, timings) is the rolled-back dry run recorded on the pull request; the admin screen against the live system is the controller's
// check after deploy. Nothing here claims to have exercised the live database.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'
import { mockAdmin } from './support/admin-mock.mjs'
import { collisions } from '../../scripts/verify-css-class-collisions.mjs'
import { COURSE_COLUMNS, PROVIDER_COLUMNS, GROUPS, defaultLayout, normaliseLayout, moveColumn, toggleColumn, registryOf, groupHeading, sortSentence, columnOf } from '../../src/catalogue-columns.js'

const MIGRATION = 'supabase/migrations/20261109200000_cf247_provider_catalogue_columns.sql'
const MIG = fs.readFileSync(MIGRATION, 'utf8')
const UI = fs.readFileSync('src/mature-main.jsx', 'utf8')
const COLS = fs.readFileSync('src/CatalogueColumns.jsx', 'utf8')
const SQL = MIG.split('\n').filter(l => !/^\s*--/.test(l)).join('\n') // the migration without its comment lines
const rows = [...MIG.matchAll(/\('providers', '([a-z0-9_]+)', '([^']+)', '([^']+)', (\d+), (?:'([a-z0-9_]+)'|null), (true|false), (\d+), (\d+), (true|false)\)/g)]
  .map(m => ({ key: m[1], group: m[2], label: m[3], order: +m[4], sortKey: m[5] || null, defaultVisible: m[6] === 'true', width: +m[7], minWidth: +m[8], alwaysVisible: m[9] === 'true' }))

test('the screen registry equals the database registry the server checks a Provider layout against', () => {
  expect(rows).toHaveLength(32)
  expect(PROVIDER_COLUMNS.map(({ header, ...c }) => ({ ...c, sortKey: c.sortKey || null }))).toEqual(rows)
  expect(new Set(PROVIDER_COLUMNS.map(c => c.group))).toEqual(new Set(GROUPS))
  expect(new Set(rows.map(r => r.key)).size).toBe(32)
})

test('the default Provider layout is today\'s 13 columns in today\'s order and headings; the Course screen is unchanged', () => {
  expect(defaultLayout('providers').columns).toEqual(['canonical_name', 'adapter', 'country_code', 'provider_type_name', 'subdivision_name', 'city', 'course_count', 'university_groups', 'evidence_count', 'lifecycle_status', 'publication_status', 'scholarship_search', 'last_verified_at'])
  expect(defaultLayout('providers').sort).toBe('provider')
  expect(registryOf('providers').filter(c => c.defaultVisible).map(c => c.key)).toEqual(defaultLayout('providers').columns)
  expect(columnOf('last_verified_at', 'providers').header).toBe('Verified')
  expect(columnOf('publication_status', 'providers').header).toBe('Published')
  expect(defaultLayout().columns).toHaveLength(14)
  expect(defaultLayout().sort).toBe('course')
  expect(COURSE_COLUMNS).toHaveLength(40)
  expect(groupHeading('providers', 'Identity')).not.toBe('Identity')
  expect(groupHeading('courses', 'Identity')).toBe('Identity')
})

test('a saved Provider layout is made safe before use; show, hide and move keep the provider name; a newly shown column goes where the registry puts it', () => {
  const n = normaliseLayout({ columns: ['website_state', 'canonical_title', 'website_state', 'description_text'], widths: { website_state: 5, description_text: 9999, x: 3 }, sort: 'drop', direction: 'sideways' }, undefined, 'providers')
  expect(n.columns).toEqual(['canonical_name', 'website_state', 'description_text'])
  expect(n.widths).toEqual({ website_state: 100, description_text: 1200 })
  expect([n.sort, n.direction]).toEqual(['provider', 'asc'])
  expect(normaliseLayout({ columns: ['canonical_name'], sort: 'website', direction: 'desc' }, undefined, 'providers')).toMatchObject({ sort: 'website', direction: 'desc' })
  // a Course key means nothing on the Provider screen, and the other way round
  expect(normaliseLayout({ columns: ['canonical_name', 'canonical_title'] }, undefined, 'providers').columns).toEqual(['canonical_name'])
  expect(normaliseLayout({ columns: ['canonical_title', 'canonical_name'] }).columns).toEqual(['canonical_title'])
  expect(toggleColumn(['canonical_name'], 'canonical_name', false, undefined, 'providers')).toEqual(['canonical_name'])
  expect(toggleColumn(['canonical_name', 'country_code', 'city'], 'registration', true, undefined, 'providers')).toEqual(['canonical_name', 'country_code', 'registration', 'city'])
  expect(toggleColumn(['canonical_name', 'city'], 'last_modified_at', true, undefined, 'providers')).toEqual(['canonical_name', 'city', 'last_modified_at'])
  expect(toggleColumn(['canonical_name', 'city'], 'city', false, undefined, 'providers')).toEqual(['canonical_name'])
  expect(moveColumn(['a', 'b', 'c'], 'a', 1)).toEqual(['b', 'a', 'c'])
  expect(sortSentence('website', 'asc', 'providers')).toBe('Website feed sync, A to Z')
  expect(sortSentence('desc_admitted', 'desc', 'providers')).toBe('Last description admitted, newest first (Unknown last)')
  expect(sortSentence('next_retry', 'asc', 'providers')).toBe('Next retry, soonest first (none last)')
  expect(sortSentence('courses', 'desc', 'providers')).toBe('Courses, most first')
})

test('every sort the Provider registry offers is a sort the server function orders by, and the server keeps every sort the old function accepted', () => {
  const handled = new Set([...MIG.matchAll(/case when v_sort='([a-z0-9_]+)' and v_dir='asc'/g)].map(m => m[1]))
  for (const c of PROVIDER_COLUMNS) if (c.sortKey) expect(handled.has(c.sortKey), `${c.key} sorts by ${c.sortKey}`).toBe(true)
  for (const old of ['provider', 'country', 'currency', 'subdivision', 'city', 'type', 'courses', 'adapter', 'verified']) expect(handled.has(old), `old sort ${old}`).toBe(true)
  // the same set is written in the registry's database rows
  for (const r of rows) if (r.sortKey) expect(handled.has(r.sortKey), r.key).toBe(true)
})

test('the migration is additive: providers_page routes to the new page function behind a body md5 guard, the old one is only marked retiring, nothing consumer-facing is named', () => {
  expect(MIG).toContain("'7efb948272dc64abaac2bb141ccb50f6', '109237d709578315e1acd9eefdb645cc'")
  expect(MIG).toContain('return security.admin_providers_page_v3(p_args);')
  expect(MIG).toMatch(/revoke all on function security\.provider_catalogue_facts_v1\(uuid\[\], boolean\), security\.admin_providers_page_v3\(jsonb\) from public, anon, authenticated;/)
  expect(MIG).toMatch(/status = 'retiring', replaced_by = 'security\.admin_providers_page_v3'/)
  // the page reads the feeds' own tables and candidate scans; it never calls the consumer API functions
  expect(SQL).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  // the Website and Zoho states stay separate facts from the catalogue description (the directive's data rule)
  expect(MIG).toMatch(/website_state[\s\S]*zoho_state[\s\S]*mismatch/)
  expect(MIG).toContain('never read as consumer publication')
})

test('the facts function skips the two feed candidate scans unless a column, filter or sort needs them; a proposal awaiting Layer 4 is pending; an unknown provider type is refused', () => {
  expect(SQL).toMatch(/website_sync_candidates_v1\('provider'\) c where p_feeds and c\.ref_id is not null/)
  expect(SQL).toMatch(/zoho_sync_candidates_v1\('provider'\) c where p_feeds and c\.ref_id is not null/)
  // the whole-set read (filters and sorts) scans only for a feed filter or sort; the page read also when the screen sends feeds=true
  expect(SQL).toContain("v_scan_feeds:=coalesce(v_web,v_zoho) is not null or v_sort in ('website','zoho','mismatch');")
  expect(SQL).toContain("v_page_feeds:=v_scan_feeds or lower(coalesce(p_args->>'feeds',''))='true';")
  expect(SQL).toContain('provider_catalogue_facts_v1(null, v_scan_feeds) where v_need_facts')
  expect(SQL).toContain('provider_catalogue_facts_v1(array(select k.id from keys k), v_page_feeds)')
  expect(SQL).toContain("case when p_feeds then s.website_state end, case when p_feeds then s.zoho_state end")
  // pending before declined
  expect(SQL.indexOf("b.l4_status = 'pending' then 'pending'")).toBeGreaterThan(0)
  expect(SQL.indexOf("b.l4_status = 'pending' then 'pending'")).toBeLessThan(SQL.indexOf("when b.lr_state = 'rejected' or b.lr_rule like"))
  expect(SQL).toMatch(/unsupported provider type filter: %',v_type using errcode='22023'/)
})

test('forward recovery and the post-deploy equivalence check are held outside supabase/migrations', () => {
  expect(fs.readdirSync('supabase/migrations').filter(f => /provider_catalogue_columns/.test(f))).toEqual(['20261109200000_cf247_provider_catalogue_columns.sql'])
  const rec = fs.readFileSync('supabase/held/provider_catalogue_columns_forward_recovery.sql', 'utf8')
  // the recovery is the migration's own edit read backwards: the md5s swap and the new and old texts swap
  expect(rec).toContain("'109237d709578315e1acd9eefdb645cc', '7efb948272dc64abaac2bb141ccb50f6'")
  expect(rec).toContain('return security.admin_providers_page_v2(v_limit,v_offset,')
  expect(rec).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  const eq = fs.readFileSync('supabase/held/provider_catalogue_columns_v2_v3_equivalence.sql', 'utf8')
  expect(eq).not.toMatch(/^\s*(insert|update|delete|drop|alter|create)\b/im)
  expect(eq).toContain('security.admin_providers_page_v2(')
  expect(eq).toContain('security.admin_providers_page_v3(v_a)')
  expect(eq).toContain("raise exception 'EQUIVALENCE")
})

test('the screen reuses the Course catalogue\'s layout mechanism and adds no second one', () => {
  expect(UI).toContain("useCourseLayout(layoutOn?catalogueUser:null,layoutScreen)")
  expect(UI).toContain("const layoutScreen=type==='provider'?PROVIDER_SCREEN:COURSE_SCREEN")
  expect(UI).toContain('providerTableColumns(cl.layout,cl.limits')
  expect(COLS).toContain("p_args: { screen } }")
  expect(fs.existsSync('src/ProviderColumns.jsx')).toBe(false)
  expect(collisions()).toEqual([])
})

// ---- the screen in a mocked browser -------------------------------------------------------------------------------------------------------------------
const ALL_CSS = (() => { const walk = d => fs.readdirSync(d, { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(path.join(d, e.name)) : e.name.endsWith('.css') ? [path.join(d, e.name)] : []); return walk('src').map(f => fs.readFileSync(f, 'utf8')).join('\n') })()
const LONG = 'Alpha University is a research-intensive university with campuses across Melbourne and regional Victoria. It offers undergraduate, postgraduate and research degrees to international students.'
const PDESC = (o = {}) => ({ description_filled: false, admission_state: 'none', source_tier: null, evidence_id: null, source_url: null, admitted_at: null, admitted_by: null, reader_state: null, reader_rule: null, reader_via: null, reader_tries: null, reader_updated_at: null, last_read_ok_at: null, hold_reason: null, hold_rule: null, next_retry_at: null, l4_status: null, l4_at: null, l4_actor: null, canonical_status: 'none', website_state: 'not_applicable', zoho_state: 'not_applicable', mismatch: 'none', text: null, ...o })
const base = (id, name, extra) => ({ id, canonical_name: name, display_name: name, country_code: 'AU', course_count: 10, lifecycle_status: 'active', publication_status: 'published', last_verified_at: '2026-10-01T00:00:00Z', updated_at: '2026-11-01T02:00:00Z', adapter_status: 'none', university_groups: [], evidence_count: 2, provider_type_code: null, provider_type_name: null, ...extra })
const PROVIDERS = [
  base('p1', 'Alpha University', { registration: { scheme: 'CRICOS', code: '00001A', status: 'active', checked_at: '2026-10-02T00:00:00Z' }, scholarships: { total: 4, published: 3 }, entry_coverage: { disposition: 'active_verified', discovery: 'source_read', extraction: 'complete', admission: 'active', matrix_active: 54, course_requirements_active: 2, as_at: '2026-11-01T00:00:00Z' },
    pdesc: PDESC({ description_filled: true, admission_state: 'admitted', source_tier: 'direct', evidence_id: '11111111-2222-4333-8444-555555555555', source_url: 'https://www.alpha.edu.au/about', admitted_at: '2026-10-20T01:00:00Z', admitted_by: 'machine', reader_state: 'admitted', last_read_ok_at: '2026-10-20T00:30:00Z', l4_status: 'approved', canonical_status: 'published', website_state: 'matched', zoho_state: 'matched', text: LONG }) }),
  base('p2', 'Beta College', { registration: null, scholarships: { total: 0, published: 0 }, entry_coverage: null,
    pdesc: PDESC({ admission_state: 'held', reader_state: 'held', reader_rule: 'insufficient_page', hold_reason: 'The page names no founding year or location', hold_rule: 'insufficient_page', next_retry_at: '2026-11-20T01:00:00Z' }) }),
  base('p3', 'Gamma Institute', { registration: { scheme: 'CRICOS', code: '00003C', status: 'active', checked_at: null }, scholarships: { total: 1, published: 0 }, entry_coverage: null,
    pdesc: PDESC({ description_filled: true, admission_state: 'unrecorded', source_tier: 'unknown', canonical_status: 'published', website_state: 'pending', zoho_state: 'missing', mismatch: 'both', text: 'Gamma Institute is a small private college.' }) }),
  base('p5', 'Epsilon College', { registration: null, scholarships: { total: 0, published: 0 }, entry_coverage: { disposition: 'awaiting_layer4', discovery: 'source_read', extraction: 'complete', admission: 'awaiting', matrix_active: 0, course_requirements_active: 0, as_at: null },
    pdesc: PDESC({ admission_state: 'pending', reader_state: 'proposed', reader_rule: 'machine_declined_claim', l4_status: 'pending' }) }), // proposed and waiting for a Layer 4 decision: pending, never declined
  base('p4', 'Delta Academy', {}), // a page that did not return the facts: the cells say Unknown
]
const FEED_KEYS = ['website_state', 'zoho_state', 'mismatch']

async function mount(page, { rank = 6, saved = null, savedCourse = null, providers = PROVIDERS, server = true } = {}) {
  await mockAdmin(page, { rank })
  const reads = [], layoutCalls = []; const layouts = { providers: saved, courses: savedCourse }
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    const b = route.request().postDataJSON() || {}
    if (b.p_operation !== 'providers_page') return route.fallback()
    reads.push(b.p_args)
    const a = b.p_args || {}
    const items = providers.filter(p => (!a.description || (a.description === 'filled') === Boolean(p.pdesc?.description_filled)) && (!a.admission || p.pdesc?.admission_state === a.admission) && (!a.website || p.pdesc?.website_state === a.website))
    return route.fulfill({ json: { items, total: items.length, limit: 50, offset: 0, sort: a.sort, direction: a.direction, columns_profile: 'provider_columns_v1' } })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_table_layout', async route => {
    const b = route.request().postDataJSON(); layoutCalls.push(b)
    const screen = b.p_args?.screen, json = d => route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(d) })
    if (!server) return route.fulfill({ status: 503, contentType: 'application/json', body: '{"message":"unavailable"}' })
    if (b.p_action === 'read') return json({ screen, layout: layouts[screen] ?? null, has_previous: false, limits: { max_columns: 60, width_min_px: 64, width_max_px: 1200, max_bytes: 16000 } })
    if (b.p_action === 'save') { layouts[screen] = b.p_args.layout; return json({ saved: true, layout: layouts[screen], saved_at: '2026-11-09T09:30:00Z', has_previous: true }) }
    if (b.p_action === 'reset') { layouts[screen] = null; return json({ reset: true, layout: null, has_previous: true }) }
    return json({})
  })
  await page.goto('/#providers')
  await expect(page.getByRole('heading', { name: 'Provider catalogue' })).toBeVisible()
  await expect(page.locator('table[data-table="provider"] tbody tr[data-row]').first()).toBeVisible()
  return { reads, layoutCalls, layouts }
}
const keys = page => page.locator('table[data-table="provider"] thead th[data-col]').evaluateAll(t => t.map(th => th.dataset.col))
const filter = (page, label) => page.locator('.m-filter-select').filter({ has: page.locator('small', { hasText: new RegExp(`^${label}$`) }) })
const choose = async (page, label, option) => { await filter(page, label).locator('button.m-filter-button').click(); await filter(page, label).locator('.m-filter-popover button', { hasText: new RegExp(`^${option}`) }).first().click() }

test.describe('mocked browser', () => {
  test('the default Provider table is today\'s columns; the Columns control lists all 32 in four groups, searchable and counted; hiding one saves the Provider layout and says so', async ({ page }) => {
    const { layoutCalls } = await mount(page)
    expect(await keys(page)).toEqual(['canonical_name', 'adapter', 'country_code', 'provider_type_name', 'subdivision_name', 'city', 'course_count', 'university_groups', 'evidence_count', 'lifecycle_status', 'publication_status', 'scholarship_search', 'last_verified_at'])
    await expect(page.locator('[data-active-sort]')).toContainText('Sorted by Provider, A to Z')
    await page.locator('[data-columns-toggle]').click()
    for (const g of GROUPS) await expect(page.locator(`[data-columns-group="${g}"]`)).toBeVisible()
    await expect(page.locator('[data-columns-count]')).toHaveText('13 of 32')
    await expect(page.locator('[data-col-toggle]')).toHaveCount(32)
    await expect(page.locator('[data-col-toggle="canonical_name"]')).toBeDisabled()
    await page.getByLabel('Search columns').fill('zoho')
    await expect(page.locator('[data-col-toggle]')).toHaveCount(1)
    await page.getByLabel('Search columns').fill('')
    await page.locator('[data-col-toggle="evidence_count"]').uncheck()
    await expect(page.locator('[data-layout-ack="success"]')).toContainText('Layout saved to your account')
    expect(await keys(page)).not.toContain('evidence_count')
    const save = layoutCalls.find(c => c.p_action === 'save')
    expect(save.p_args.screen).toBe('providers')
    expect(save.p_args.layout.columns).not.toContain('evidence_count')
    expect(Object.keys(save.p_args.layout).sort()).toEqual(['columns', 'direction', 'sort', 'version', 'widths'])
    // the Provider screen reads and writes only its own layout
    expect(layoutCalls.every(c => c.p_args.screen === 'providers')).toBe(true)
  })

  test('the new columns show the description pipeline and, separately, the Website and Zoho states; a provider the page gave no facts for says Unknown', async ({ page }) => {
    await mount(page, { saved: { version: 1, columns: ['canonical_name', 'admission_state', 'description_filled', 'description_source', 'description_evidence', 'description_admitted_at', 'reader_status', 'hold_reason', 'next_retry_at', 'layer4_status', 'canonical_status', ...FEED_KEYS, 'registration', 'scholarship_count', 'entry_coverage', 'last_modified_at'], widths: {}, sort: 'provider', direction: 'asc' } })
    const row = id => page.locator(`tr[data-row="${id}"]`)
    const at = async (id, col) => { const idx = (await keys(page)).indexOf(col); return row(id).locator('td').nth(idx) }
    await expect(await at('p1', 'admission_state')).toContainText('Admitted')
    await expect(await at('p1', 'description_source')).toContainText('Direct page read')
    await expect(await at('p1', 'description_evidence')).toContainText('11111111')
    await expect(await at('p1', 'description_evidence')).toContainText('alpha.edu.au')
    await expect(await at('p1', 'website_state')).toContainText('Matched')
    await expect(await at('p1', 'zoho_state')).toContainText('Matched')
    await expect(await at('p1', 'registration')).toContainText('CRICOS 00001A')
    await expect(await at('p1', 'scholarship_count')).toContainText('4')
    await expect(await at('p1', 'entry_coverage')).toContainText('Active and verified')
    await expect(await at('p1', 'entry_coverage')).toContainText('54 matrix')
    await expect(row('p1').locator('[data-coverage="active_verified"]')).toHaveAttribute('title', /Active matrix entries: 54\nActive course requirements: 2/)
    // a proposal waiting for its Layer 4 decision is pending and awaits Layer 4: it is not declined
    await expect(await at('p5', 'admission_state')).toContainText('Pending')
    await expect(await at('p5', 'reader_status')).toHaveText('Awaiting Layer 4')
    await expect(await at('p5', 'layer4_status')).toContainText('Awaiting Layer 4')
    await expect(await at('p5', 'entry_coverage')).toContainText('Awaiting Layer 4')
    await expect(row('p2').locator('[data-website="not_applicable"] [title]').first()).toHaveAttribute('title', /not served by the Website feed \(for example, no courses\)/)
    await expect(await at('p2', 'admission_state')).toContainText('Held')
    await expect(await at('p2', 'hold_reason')).toContainText('names no founding year')
    await expect(await at('p2', 'next_retry_at')).toContainText('2026')
    await expect(await at('p2', 'website_state')).toContainText('Not applicable')
    await expect(await at('p2', 'description_admitted_at')).toHaveText('—')
    // a description in the catalogue is not consumer publication: Gamma has one, and its two consumers say pending and missing, with the mismatch shown
    await expect(await at('p3', 'canonical_status')).toContainText('Published (active)')
    await expect(await at('p3', 'website_state')).toContainText('Pending')
    await expect(await at('p3', 'zoho_state')).toContainText('Missing')
    await expect(await at('p3', 'mismatch')).toContainText('Website and Zoho differ')
    await expect(await at('p3', 'admission_state')).toContainText('Admitted: no record')
    await expect(await at('p3', 'description_source')).toContainText('Unknown')
    await expect(await at('p3', 'description_admitted_at')).toContainText('Unknown')
    await expect(await at('p3', 'registration')).toContainText('CRICOS 00003C')
    // nothing returned for Delta: Unknown, never a made-up state
    for (const col of ['admission_state', 'description_filled', 'description_source', 'website_state', 'zoho_state', 'mismatch', 'canonical_status', 'layer4_status']) await expect(await at('p4', col)).toHaveText('Unknown')
    await expect(await at('p4', 'registration')).toHaveText('Unknown')
    await expect(await at('p4', 'entry_coverage')).toHaveText('Unknown')
  })

  test('the Website and Zoho states are asked for only when a column that shows them is in the layout', async ({ page }) => {
    const { reads } = await mount(page)
    expect(reads.every(a => a.feeds === undefined)).toBe(true)
    await page.locator('[data-columns-toggle]').click()
    await page.locator('[data-col-toggle="zoho_state"]').check()
    await expect.poll(() => reads.at(-1)?.feeds).toBe(true)
    await page.locator('[data-col-toggle="zoho_state"]').uncheck()
    await expect.poll(() => reads.at(-1)?.feeds).toBeUndefined()
  })

  test('the description column shows a preview and the full text on demand, and the whole text is always in the tooltip', async ({ page }) => {
    await mount(page, { saved: { version: 1, columns: ['canonical_name', 'description_text'], widths: {}, sort: 'provider', direction: 'asc' } })
    const cell = page.locator('tr[data-row="p1"] [data-description="filled"]')
    await expect(cell).toHaveAttribute('title', LONG)
    await expect(cell.locator('[data-description-text]')).toContainText('…')
    await expect(cell.locator('[data-description-text]')).not.toContainText('international students.')
    await cell.getByRole('button', { name: 'Show full text' }).click()
    await expect(cell.locator('[data-description-text]')).toHaveText(LONG)
    await cell.getByRole('button', { name: 'Show less' }).click()
    await expect(cell.locator('[data-description-text]')).toContainText('…')
    await expect(page.locator('tr[data-row="p2"] [data-description="missing"]')).toHaveText('No description')
    await expect(page.locator('tr[data-row="p4"]')).toContainText('Unknown')
  })

  test('a saved Provider layout (columns, widths, sort) is applied when the screen opens and the sort goes to the server; Reset to default restores today\'s columns', async ({ page }) => {
    const { reads } = await mount(page, { saved: { version: 1, columns: ['canonical_name', 'website_state', 'description_text'], widths: { website_state: 210 }, sort: 'website', direction: 'desc' } })
    await expect.poll(() => keys(page)).toEqual(['canonical_name', 'website_state', 'description_text'])
    await expect(page.locator('[data-active-sort]')).toHaveAttribute('data-active-sort', 'website:desc')
    await expect.poll(() => reads.some(a => a.sort === 'website' && a.direction === 'desc')).toBe(true)
    await page.locator('[data-columns-toggle]').click()
    await page.locator('[data-columns-reset]').click()
    await expect(page.locator('[data-layout-ack="success"]')).toContainText('Default layout restored')
    expect(await keys(page)).toEqual(defaultLayout('providers').columns)
  })

  test('sorting a new column is done by the server over every provider: the header click sends the sort and saves it with the layout', async ({ page }) => {
    const { reads, layoutCalls } = await mount(page, { saved: { version: 1, columns: ['canonical_name', 'admission_state', 'description_text'], widths: {}, sort: 'provider', direction: 'asc' } })
    await page.locator('th[data-col="description_text"] button').isDisabled().then(d => expect(d).toBe(true))
    await page.locator('th[data-col="admission_state"] button').click()
    await expect.poll(() => reads.some(a => a.sort === 'admission' && a.direction === 'asc')).toBe(true)
    await page.locator('th[data-col="admission_state"] button').click()
    await expect.poll(() => reads.some(a => a.sort === 'admission' && a.direction === 'desc')).toBe(true)
    await expect(page.locator('[data-active-sort]')).toContainText('Description admission, Z to A')
    await expect.poll(() => layoutCalls.filter(c => c.p_action === 'save').some(c => c.p_args.layout.sort === 'admission' && c.p_args.layout.direction === 'desc')).toBe(true)
  })

  test('the new filters go to the server as filters over the whole set, paging restarts, and each filter shows as a removable chip', async ({ page }) => {
    const { reads } = await mount(page)
    await choose(page, 'Description', 'Filled')
    await expect.poll(() => reads.at(-1)?.description).toBe('filled')
    await expect(page.locator('table[data-table="provider"] tbody tr[data-row]')).toHaveCount(2)
    await choose(page, 'Description admission', 'Admitted')
    await expect.poll(() => reads.at(-1)?.admission).toBe('admitted')
    await expect(page.locator('table[data-table="provider"] tbody tr[data-row]')).toHaveCount(1)
    await choose(page, 'Website feed', 'Matched')
    await expect.poll(() => reads.at(-1)?.website).toBe('matched')
    await choose(page, 'Description source', 'Direct page read')
    await choose(page, 'Zoho feed', 'Matched')
    await choose(page, 'Type', 'Needs type')
    await expect.poll(() => { const a = reads.at(-1) || {}; return [a.source_tier, a.zoho, a.provider_type, a.offset] }).toEqual(['direct', 'matched', 'unclassified', 0])
    await expect(page.locator('.m-chip-row')).toContainText('Description admission: Admitted')
    await expect(page.locator('.m-chip-row')).toContainText('Website feed: Matched')
    // the existing filters are still sent as before
    expect(reads.at(-1).lifecycle_status).toBe('active')
    await page.getByRole('button', { name: 'Clear' }).click()
    await expect.poll(() => { const a = reads.at(-1) || {}; return [a.description, a.admission, a.website, a.zoho, a.source_tier, a.provider_type] }).toEqual([undefined, undefined, undefined, undefined, undefined, undefined])
  })

  test('without the server the Provider layout still works from this browser and says it is saved here only; switching it off in Settings keeps it off the server', async ({ page }) => {
    await mount(page, { server: false })
    await page.locator('[data-columns-toggle]').click()
    await page.locator('[data-col-toggle="website_state"]').check()
    await expect(page.locator('[data-layout-ack="warning"]')).toContainText('Saved in this browser only')
    await page.reload()
    await expect.poll(() => keys(page)).toContain('website_state')
  })

  test('the Course catalogue keeps its own layout: opening Providers does not read or change it', async ({ page }) => {
    const { layoutCalls } = await mount(page, { savedCourse: { version: 1, columns: ['canonical_title', 'provider_name'], widths: {}, sort: 'course', direction: 'asc' } })
    await page.locator('[data-columns-toggle]').click()
    await page.locator('[data-col-toggle="registration"]').check()
    await expect(page.locator('[data-layout-ack="success"]')).toBeVisible()
    expect(layoutCalls.filter(c => c.p_args?.screen === 'courses')).toEqual([])
  })

  test('roles: Platform Admin sees the Adapter column; PIM Admin and below do not, the count and the list say so, and the Published switch keeps its rank rule', async ({ page }) => {
    await mount(page, { rank: 5 })
    expect(await keys(page)).not.toContain('adapter')
    await page.locator('[data-columns-toggle]').click()
    await expect(page.locator('[data-columns-count]')).toHaveText('12 of 31')
    await expect(page.locator('[data-col-toggle="adapter"]')).toHaveCount(0)
    await page.keyboard.press('Escape')
    await expect(page.locator('tr[data-row="p1"] [role="switch"]')).toBeEnabled()
  })
  test('roles: a viewer can choose columns and read, but cannot change the Published switch', async ({ page }) => {
    await mount(page, { rank: 2 })
    expect(await keys(page)).not.toContain('adapter')
    await expect(page.locator('tr[data-row="p1"] [role="switch"]')).toBeDisabled()
    await page.locator('[data-columns-toggle]').click()
    await page.locator('[data-col-toggle="mismatch"]').check()
    await expect(page.locator('[data-layout-ack="success"]')).toContainText('Layout saved to your account')
    await expect(page.locator('tr[data-row="p3"]')).toContainText('Website and Zoho differ')
  })
})

test('with every stylesheet loaded as in production, all 32 Provider checkboxes can be clicked', async ({ page }) => {
  await mount(page)
  await page.addStyleTag({ content: ALL_CSS })
  await page.locator('[data-columns-toggle]').click()
  const boxes = page.locator('[data-columns-panel] [data-col-toggle]')
  expect(await boxes.count()).toBe(32)
  for (const box of await boxes.all()) {
    const hit = await box.evaluate(el => {
      const p = el.closest('[data-columns-panel]'), pr = p.getBoundingClientRect()
      p.scrollTop += el.getBoundingClientRect().top - (pr.top + pr.height / 2)
      const r = el.getBoundingClientRect(); const at = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)
      return Boolean(at && (at === el || (at.closest('label') && at.closest('label').contains(el))))
    })
    expect(hit, await box.getAttribute('data-col-toggle')).toBe(true)
  }
  await page.locator('[data-col-toggle="zoho_state"]').click()
  await expect(page.locator('[data-col-toggle="zoho_state"]')).toBeChecked()
})

test.describe('phone @responsive', () => {
  test('Provider catalogue columns at phone width: every checkbox can be tapped, the panel fits the screen, the table scrolls in its own frame, no sideways page scroll', async ({ page }) => {
    const w = page.viewportSize()?.width || 9999
    expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(480)
    await mount(page)
    await page.addStyleTag({ content: ALL_CSS })
    await page.locator('[data-columns-toggle]').click()
    const panel = page.locator('[data-columns-panel]')
    const b = await panel.boundingBox()
    expect(b.x).toBeGreaterThanOrEqual(-1); expect(b.x + b.width).toBeLessThanOrEqual(w + 1); expect(b.height).toBeGreaterThanOrEqual(200)
    const boxes = page.locator('[data-columns-panel] [data-col-toggle]')
    expect(await boxes.count()).toBe(32)
    for (const box of await boxes.all()) {
      const hit = await box.evaluate(el => {
        const p = el.closest('[data-columns-panel]'), pr = p.getBoundingClientRect()
        p.scrollTop += el.getBoundingClientRect().top - (pr.top + pr.height / 2)
        const r = el.getBoundingClientRect(); const at = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2)
        return Boolean(at && (at === el || (at.closest('label') && at.closest('label').contains(el))))
      })
      expect(hit, await box.getAttribute('data-col-toggle')).toBe(true)
    }
    await page.locator('[data-col-toggle="description_text"]').click()
    await expect(page.locator('[data-layout-ack-panel="success"]')).toContainText('Layout saved to your account')
    const reset = await page.locator('[data-columns-reset]').boundingBox()
    expect(reset.height).toBeGreaterThanOrEqual(24)
    await page.keyboard.press('Escape')
    const frame = await page.locator('.m-table-wrap.ccol-frame').evaluate(el => ({ client: el.clientWidth, scroll: el.scrollWidth, x: getComputedStyle(el).overflowX }))
    expect(frame.client).toBeLessThanOrEqual(w)
    if (frame.scroll > frame.client) expect(['auto', 'scroll']).toContain(frame.x)
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
  })
})
