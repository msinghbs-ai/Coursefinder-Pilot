// Guards: Platform Admin directive 9-10 Nov 2026 (P0), Provider "Fill fields": the panel over the existing Provider description Run & Validate (preview, prepare, run, saved, verify), the Provider Catalogue row action and the Provider Detail card, at desktop and phone width (S121/G4: phone tests are @responsive and first assert phone width).
// Mocked client and mocked Supabase: the panel and the screens are real, every server answer is a fixture. Nothing here claims to have exercised the live database or the live reader.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121
const P1 = '11111111-1111-4111-8111-111111111111' // description missing
const P2 = '22222222-2222-4222-8222-222222222222' // basic registry profile
const P3 = '33333333-3333-4333-8333-333333333333' // verified published
const CAPS = { contract: 'provider-description-fill-v1', enabled: true, job_active: true, run_now_allowed: true, can_run: true, control_rank: 5, reason_min_chars: 5, min_size: 1, max_size: 3, poll_seconds: 150, status_max: 3, quality_classes: [] }
const LONG_URL = 'https://www.example-university.edu.au/about/who-we-are/the-longest-address-in-the-world-for-checking-the-wrapping-of-long-source-addresses-on-a-phone'
const PROVIDERS = {
  [P1]: { provider_id: P1, name: 'Alpha University', description_present: false, quality_class: 'missing', source_tier: null, reader: { state: null }, missing_fields: ['description', 'phone', 'established_year'], latest_task: null },
  [P2]: { provider_id: P2, name: 'Beta College of a Very Long Name for Checking the Layout of the Panel on a Phone', description_present: true, quality_class: 'basic_registry', source_tier: 'registry_factual', admission_state: 'admitted', admitted_by: 'machine', admitted_at: '2026-11-01T01:00:00Z', reader: { state: 'admitted', rule: 'registry_profile' }, website_publication: 'pending', zoho_publication: 'not_applicable', missing_fields: ['phone'], latest_task: null },
  [P3]: { provider_id: P3, name: 'Gamma Institute', description_present: true, quality_class: 'verified_published', source_tier: 'direct', admission_state: 'admitted', admitted_by: 'layer4', admitted_at: '2026-10-20T01:00:00Z', reader: { state: 'admitted', rule: 'official_site_read' }, website_publication: 'verified', zoho_publication: 'not_applicable', missing_fields: [], latest_task: null },
}

// A client that answers like the server, and records every call in order.
function clientScript(extra = {}) {
  return `
    window.fillCalls = []
    const providers = ${JSON.stringify(PROVIDERS)}
    const caps = ${JSON.stringify({ ...CAPS, ...(extra.caps || {}) })}
    const eligible = ${JSON.stringify(extra.eligible ?? true)}
    const reasonCode = ${JSON.stringify(extra.reason ?? 'not_selected_by_governed_policy')}
    const task = ${JSON.stringify(extra.task ?? null)}
    let queued = false
    window.fillClient = { async call(name, args) {
      window.fillCalls.push({ name, args })
      if (name === 'fill_caps') return caps
      if (name === 'provider_status') return { as_at: '2026-11-10T01:00:00Z', providers: args.provider_ids.map(id => { const p = { ...providers[id] }; if (task && id === task.provider) p.latest_task = task.row; if (queued && id === '${P1}') { p.quality_class = 'queued'; p.reader = { state: 'queued' }; p.latest_task = { cohort_id: 'cohort-1', state: 'started', requested_by_me: true, created_at: '2026-11-10T01:05:00Z', run_state: 'queued' } } return p }) }
      if (name === 'saved') return task && args.cohort_id === task.row.cohort_id ? task.saved : { cohort_id: args.cohort_id, state: 'started', created_at: '2026-11-10T01:05:00Z', reason: 'Because', runs: [{ run_id: 'run-1', state: 'queued' }], totals: { selected: 1 } }
      if (name === 'preview') return { token: 'tok-1', selected: eligible ? args.provider_ids.length : 0, as_at: '2026-11-10T01:00:00Z', expires_at: '2026-11-10T01:10:00Z', providers: args.provider_ids.map(id => ({ provider_id: id, provider: providers[id].name, eligible, eligibility_reason: eligible ? 'official_site_read' : reasonCode, source_url: eligible ? '${LONG_URL}' : null })) }
      if (name === 'prepare') return { cohort_id: 'cohort-1', state: 'prepared', created_at: '2026-11-10T01:05:00Z', reason: args.reason, runs: [], totals: { selected: 1 } }
      if (name === 'run') { queued = true; return { state: 'queued', reason: 'Queued with the governed reader' } }
      if (name === 'provider_publication') return { as_at: '2026-11-10T01:06:00Z', providers: args.provider_ids.map(id => ({ provider_id: id, name: providers[id].name, catalogue: { status: providers[id].description_present ? 'present' : 'no_description' }, website: { status: providers[id].description_present ? 'verified' : 'awaiting_description' }, zoho: { status: 'not_applicable' } })) }
      if (name === 'verify') return { cohort_id: args.cohort_id }
      return {}
    } }
  `
}

async function mountPanel(page, { ids = [P1], rank = 6, extra = {}, rows = true } = {}) {
  await page.goto('/')
  await page.evaluate(clientScript(extra))
  await page.evaluate(async ({ ids, rank }) => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const ReactDOM = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { default: ProviderFillFields } = await import('/src/ProviderFillFields.jsx')
    document.body.innerHTML = '<div id="pff-root"></div>'
    ReactDOM.createRoot(document.getElementById('pff-root')).render(React.createElement(ProviderFillFields, { providerIds: ids, rank, client: window.fillClient, onClose: () => { window.fillClosed = true } }))
  }, { ids, rank })
  await expect(page.locator('[data-fill-fields-panel]')).toBeVisible()
  if (rows) await expect(page.locator('[data-fill-provider]').first()).toBeVisible()
}
const calls = page => page.evaluate(() => window.fillCalls)
const names = async page => (await calls(page)).map(c => c.name)

test.describe('the Fill fields panel', () => {
  test('shows description present or missing, the level and the other missing fields as information; fill missing: preview, then a reason, then the same governed prepare and run', async ({ page }) => {
    await mountPanel(page)
    const row = page.locator(`[data-fill-provider="${P1}"]`)
    await expect(row).toContainText('Description missing')
    await expect(row).toHaveAttribute('data-quality', 'missing')
    await expect(row.locator('[data-missing-fields]')).toContainText('Phone, Year established')
    await expect(page.locator('[data-other-fields-note]')).toContainText('The reader produces the description only')
    await expect(page.locator('[data-fill-caps]')).toContainText('Up to 3 providers in one task')
    // preview first: nothing is saved or run
    await page.getByRole('button', { name: 'Preview what the reader would use' }).click()
    await expect(page.locator('[data-fill-preview]')).toContainText('Nothing has been saved or run')
    await expect(page.locator(`[data-preview-provider="${P1}"]`)).toHaveAttribute('data-eligible', 'yes')
    expect(await names(page)).toEqual(['fill_caps', 'provider_status', 'preview'])
    expect((await calls(page)).find(c => c.name === 'preview').args).toEqual({ provider_ids: [P1], fill_mode: 'missing', size: 1 })
    // the audit reason is required before the task is saved
    const save = page.getByRole('button', { name: 'Save and queue with the reader' })
    await expect(save).toBeDisabled()
    await page.getByLabel('Fill fields audit reason').fill('Fill the missing description now')
    await expect(save).toBeEnabled()
    await save.click()
    await expect(page.locator('[data-fill-task]')).toContainText('cohort-1')
    const seq = await names(page)
    expect(seq.slice(0, 3)).toEqual(['fill_caps', 'provider_status', 'preview'])
    expect(seq.indexOf('prepare')).toBeLessThan(seq.indexOf('run'))
    expect(seq.indexOf('run')).toBeLessThan(seq.lastIndexOf('saved'))
    const c = await calls(page)
    expect(c.find(x => x.name === 'prepare').args).toEqual({ preview_token: 'tok-1', reason: 'Fill the missing description now' })
    expect(c.find(x => x.name === 'run').args).toEqual({ cohort_id: 'cohort-1' })
    // the status is read again and now says the provider is queued
    await expect(row).toHaveAttribute('data-quality', 'queued')
  })

  test('refresh a basic registry description: the backend\'s exact refusal is shown, and nothing can be queued from a refusal', async ({ page }) => {
    await mountPanel(page, { ids: [P2], extra: { eligible: false, reason: 'not_selected_by_governed_policy' } })
    await expect(page.getByRole('radio', { name: /Refresh a basic registry description/ })).toBeChecked() // a basic registry profile defaults to the refresh mode
    await page.getByRole('button', { name: 'Preview what the reader would use' }).click()
    const prev = page.locator(`[data-preview-provider="${P2}"]`)
    await expect(prev).toHaveAttribute('data-eligible', 'no')
    await expect(prev).toContainText('Reason from the platform: not_selected_by_governed_policy')
    expect((await calls(page)).find(c => c.name === 'preview').args.fill_mode).toBe('upgrade_basic')
    await expect(page.getByRole('button', { name: 'Save and queue with the reader' })).toHaveCount(0)
    expect(await names(page)).not.toContain('prepare')
  })

  test('a task this person saved is read again when the panel is opened, so closing the browser loses nothing', async ({ page }) => {
    const row = { cohort_id: 'cohort-9', state: 'started', requested_by_me: true, created_at: '2026-11-10T00:30:00Z', run_state: 'running' }
    const saved = { cohort_id: 'cohort-9', state: 'started', created_at: '2026-11-10T00:30:00Z', reason: 'Earlier today', runs: [{ run_id: 'run-9', state: 'running' }], totals: { selected: 1, evidence_read: 1 } }
    await mountPanel(page, { extra: { task: { provider: P1, row, saved } } })
    await expect(page.locator('[data-fill-task]')).toContainText('cohort-9')
    await expect(page.locator('[data-fill-task]')).toContainText('Earlier today')
    await expect(page.locator(`[data-fill-provider="${P1}"]`)).toContainText('yours')
    expect(await names(page)).toEqual(['fill_caps', 'provider_status', 'saved'])
  })

  test('more providers than the cap are explained and not read; preview stays off', async ({ page }) => {
    await mountPanel(page, { ids: [P1, P2, P3], extra: { caps: { max_size: 2 } }, rows: false })
    await expect(page.getByRole('alert')).toContainText('3 providers are selected; one task can take 2')
    expect(await names(page)).toEqual(['fill_caps'])
    await expect(page.getByRole('button', { name: 'Preview what the reader would use' })).toBeDisabled()
  })

  test('verify publication reads the catalogue, the Website and Zoho; Not applicable is shown as such, never as a failure; a role without the run right can read status only', async ({ page }) => {
    await mountPanel(page, { ids: [P3] })
    await page.getByRole('radio', { name: /Verify publication/ }).check()
    await page.getByRole('button', { name: 'Verify publication now' }).click()
    const rb = page.locator('[data-publication-readback]')
    await expect(rb).toContainText('Gamma Institute')
    await expect(rb).toContainText('Website: Matched')
    await expect(rb).toContainText('Zoho: Not applicable')
    await expect(rb).toContainText('it is not a failure')
    expect(await names(page)).toContain('provider_publication')
    // rank 3 (Curator): may preview, may not verify or run
    await mountPanel(page, { ids: [P3], rank: 3, extra: { caps: { can_run: false } } })
    await page.getByRole('radio', { name: /Verify publication/ }).check()
    await expect(page.getByRole('button', { name: 'Verify publication now' })).toBeDisabled()
    await expect(page.getByText('An authorised operator must run the publication read-back.')).toBeVisible()
  })
})

// ---- the screens ---------------------------------------------------------------------------------------------------------------------------------------
const base = (id, name) => ({ id, canonical_name: name, display_name: name, country_code: 'AU', course_count: 10, lifecycle_status: 'active', publication_status: 'published', last_verified_at: '2026-10-01T00:00:00Z', updated_at: '2026-11-01T02:00:00Z', adapter_status: 'none', university_groups: [], evidence_count: 2, provider_type_code: null, provider_type_name: null,
  pdesc: { description_filled: false, admission_state: 'none', quality: 'missing', missing_fields: ['description', 'phone'], website_publication: null, zoho_publication: null } })
const ROWS = [base(P1, 'Alpha University'), base(P2, 'Beta College'), base(P3, 'Gamma Institute')]

async function mountCatalogue(page, { rank = 6, cap = 2 } = {}) {
  await mockAdmin(page, { rank })
  const filterReads = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    const b = route.request().postDataJSON() || {}
    if (b.p_operation === 'providers_page') { filterReads.push(b.p_args); return route.fulfill({ json: { items: ROWS, total: ROWS.length, limit: 50, offset: 0, sort: 'provider', direction: 'asc', columns_profile: 'provider_columns_v1' } }) }
    if (b.p_operation === 'provider_detail') return route.fulfill({ json: { id: b.p_args.id, canonical_name: 'Alpha University', display_name: 'Alpha University', country_code: 'AU', lifecycle_status: 'active', publication_status: 'published', website: 'https://www.alpha.edu.au' } })
    return route.fallback()
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_description_run_v1', async route => {
    const b = route.request().postDataJSON() || {}
    if (b.p_action === 'fill_caps') return route.fulfill({ json: { ...CAPS, max_size: cap } })
    if (b.p_action === 'provider_status') return route.fulfill({ json: { as_at: '2026-11-10T01:00:00Z', providers: (b.p_args.provider_ids || []).map(id => PROVIDERS[id] || { provider_id: id, name: 'Unknown', description_present: false, quality_class: 'missing', reader: {}, missing_fields: [] }) } })
    return route.fulfill({ json: {} })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_table_layout', route => route.fulfill({ json: { layout: null, has_previous: false, limits: { max_columns: 60, width_min_px: 64, width_max_px: 1200, max_bytes: 16000 } } }))
  await page.goto('/#providers')
  await expect(page.getByRole('heading', { name: 'Provider catalogue' })).toBeVisible()
  await expect(page.locator('table[data-table="provider"] tbody tr[data-row]').first()).toBeVisible()
  return { filterReads }
}

test.describe('the Provider Catalogue', () => {
  test('each row has a tick box and a Fill fields button; ticking stops at the cap the server reports; the button opens the panel and does not open the row\'s detail', async ({ page }) => {
    await mountCatalogue(page, { cap: 2 })
    await expect(page.locator('input[aria-label^="Select "][aria-label$="for Fill fields"]')).toHaveCount(3)
    await page.getByLabel('Select Alpha University for Fill fields').check()
    await page.getByLabel('Select Beta College for Fill fields').check()
    await expect(page.locator('[data-fill-selection]')).toContainText('2 selected (up to 2 in one task)')
    await expect(page.getByLabel('Select Gamma Institute for Fill fields')).toBeDisabled()
    await page.getByRole('button', { name: 'Fill fields for selected' }).click()
    await expect(page.locator('[data-fill-fields]')).toContainText('Fill fields for 2 providers')
    await expect(page.locator(`[data-fill-provider="${P1}"]`)).toBeVisible()
    await expect(page.locator(`[data-fill-provider="${P2}"]`)).toBeVisible()
    await page.getByRole('button', { name: 'Close Fill fields' }).click()
    await expect(page.locator('[data-fill-fields]')).toHaveCount(0)
    // one row: its own button
    await page.getByRole('button', { name: 'Fill fields for Gamma Institute' }).click()
    await expect(page.locator('[data-fill-fields]')).toContainText('Gamma Institute')
    await expect(page.locator('aside.m-drawer-provider')).toHaveCount(0)
  })

  test('Provider Detail has a Description card with the same Fill fields panel, for the provider that is open', async ({ page }) => {
    await mountCatalogue(page)
    await page.locator(`tr[data-row="${P1}"] td`).nth(2).click()
    const card = page.locator('[data-fill-fields-card]')
    await expect(card).toBeVisible()
    await card.getByRole('button', { name: 'Fill fields' }).click()
    await expect(page.locator('[data-fill-fields]')).toContainText('Alpha University')
    await expect(page.locator(`[data-fill-provider="${P1}"]`)).toBeVisible()
  })

  test('below Curator the row has no tick box and no Fill fields button', async ({ page }) => {
    await mountCatalogue(page, { rank: 2 })
    await expect(page.locator('input[aria-label$="for Fill fields"]')).toHaveCount(0)
    await expect(page.getByRole('button', { name: /^Fill fields for / })).toHaveCount(0)
  })

  test('the Description quality level filter is offered with the four groups first and is sent to the server', async ({ page }) => {
    const { filterReads } = await mountCatalogue(page)
    const f = page.locator('.m-filter-select').filter({ has: page.locator('small', { hasText: /^Description quality$/ }) })
    await expect(f).toHaveCount(1)
    await f.locator('button.m-filter-button').click()
    const opts = await f.locator('.m-filter-popover button').allInnerTexts()
    expect(opts.map(o => o.trim()).slice(0, 5)).toEqual(['All', 'Basic registry profile', 'Enriched (admitted, any publication)', 'Missing', 'Held: evidence or identity'])
    await f.locator('.m-filter-popover button', { hasText: /^Missing/ }).first().click()
    await expect.poll(() => filterReads.some(a => a?.quality === 'missing')).toBe(true)
  })
})

// ---- phone ---------------------------------------------------------------------------------------------------------------------------------------------
const overflow = page => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)
async function tapTargets(page, selector) {
  const small = []
  for (const el of await page.locator(selector).all()) {
    if (!(await el.isVisible())) continue
    const b = await el.boundingBox()
    if (b && (b.width < TAP_MIN || b.height < TAP_MIN)) small.push(`${(await el.getAttribute('aria-label')) || (await el.innerText()).slice(0, 40)} ${Math.round(b.width)}x${Math.round(b.height)}`)
  }
  return small
}

test.describe('phone @responsive', () => {
  test('the Fill fields panel at phone width: every control is at least 24 px, long names and addresses wrap, there is no sideways page scroll', async ({ page }) => {
    const w = page.viewportSize()?.width || 9999
    expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
    const row = { cohort_id: 'cohort-with-a-long-identifier-to-test-the-wrapping-of-the-task-line', state: 'started', requested_by_me: true, created_at: '2026-11-10T00:30:00Z', run_state: 'running' }
    const saved = { ...row, reason: 'An audit reason long enough to wrap onto several lines on a narrow phone screen without a sideways scroll', runs: [{ run_id: 'run-with-a-long-identifier-to-test-wrapping', state: 'running' }], totals: { selected: 2, evidence_read: 1 } }
    await mountPanel(page, { ids: [P2, P1], extra: { task: { provider: P2, row, saved } } })
    await page.getByRole('button', { name: 'Preview what the reader would use' }).click()
    await expect(page.locator('[data-fill-preview]')).toBeVisible()
    await page.getByLabel('Fill fields audit reason').fill('Phone acceptance reason')
    const panel = await page.locator('[data-fill-fields-panel]').boundingBox()
    expect(panel.x).toBeGreaterThanOrEqual(-1); expect(panel.x + panel.width).toBeLessThanOrEqual(w + 1)
    expect(await tapTargets(page, '[data-fill-fields] button, [data-fill-fields] input[type="radio"], [data-fill-fields] textarea, [data-fill-fields] a')).toEqual([])
    expect(await tapTargets(page, '[data-fill-fields] label.pff-mode')).toEqual([])
    expect(await overflow(page)).toBeLessThanOrEqual(1)
    // the panel's own content never forces itself wider than the screen
    expect(await page.locator('[data-fill-fields-panel]').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
    // verify publication on a phone
    await page.getByRole('radio', { name: /Verify publication/ }).check()
    await page.getByRole('button', { name: 'Verify publication now' }).click()
    await expect(page.locator('[data-publication-readback]')).toBeVisible()
    expect(await overflow(page)).toBeLessThanOrEqual(1)
  })

  test('the Provider Catalogue row action at phone width: the tick box and the Fill fields button are at least 24 px and the page does not scroll sideways', async ({ page }) => {
    const w = page.viewportSize()?.width || 9999
    expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
    await mountCatalogue(page, { cap: 2 })
    expect(await tapTargets(page, '.pff-pick')).toEqual([])
    expect(await tapTargets(page, '.pff-open')).toEqual([])
    await page.getByLabel('Select Alpha University for Fill fields').check()
    await expect(page.locator('[data-fill-selection]')).toBeVisible()
    expect(await tapTargets(page, '[data-fill-selection] button')).toEqual([])
    expect(await overflow(page)).toBeLessThanOrEqual(1)
    await page.getByRole('button', { name: 'Fill fields for selected' }).click()
    await expect(page.locator('[data-fill-fields-panel]')).toBeVisible()
    expect(await overflow(page)).toBeLessThanOrEqual(1)
  })
})
