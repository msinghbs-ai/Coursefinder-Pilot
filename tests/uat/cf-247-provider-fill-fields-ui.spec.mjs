// Guards: Platform Admin decision 10 Nov 2026 19:47 (F-PDESC.01-.05): ONE primary outcome action, "Extract / refresh description now", in the Provider Catalogue and Provider Detail, over the existing governed reader (preview, prepare, run, saved, verify); plus directive 9-10 Nov 2026 (P0) for the panel, at desktop and phone width (S121/G4: phone tests are @responsive and first assert phone width).
// Mocked client and mocked Supabase: the panel and the screens are real, every server answer is a fixture. Nothing here claims to have exercised the live database or the live reader.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121
const P1 = '11111111-1111-4111-8111-111111111111' // description missing
const P2 = '22222222-2222-4222-8222-222222222222' // basic registry profile
const P3 = '33333333-3333-4333-8333-333333333333' // verified published, locked
const P4 = '44444444-4444-4444-8444-444444444444' // machine-declined for a word: the platform recovers it
const P5 = '55555555-5555-4555-8555-555555555555' // machine-declined for identity: a person decides
const P6 = '66666666-6666-4666-8666-666666666666' // admitted after leaving two sentences out
const CAPS = { contract: 'provider-description-fill-v1', enabled: true, job_active: true, run_now_allowed: true, can_run: true, control_rank: 5, reason_min_chars: 5, min_size: 1, max_size: 3, poll_seconds: 150, status_max: 3, quality_classes: [] }
const LONG_URL = 'https://www.example-university.edu.au/about/who-we-are/the-longest-address-in-the-world-for-checking-the-wrapping-of-long-source-addresses-on-a-phone'
const REASON = 'Extract the description now'
const PROVIDERS = {
  [P1]: { provider_id: P1, name: 'Alpha University', description_present: false, quality_class: 'missing', source_tier: null, reader: { state: null }, missing_fields: ['description', 'phone', 'established_year'], latest_task: null },
  [P2]: { provider_id: P2, name: 'Beta College of a Very Long Name for Checking the Layout of the Panel on a Phone', description_present: true, quality_class: 'basic_registry', source_tier: 'registry_factual', admission_state: 'admitted', admitted_by: 'machine', admitted_at: '2026-11-01T01:00:00Z', reader: { state: 'admitted', rule: 'registry_profile' }, website_publication: 'pending', zoho_publication: 'not_applicable', missing_fields: ['phone'], latest_task: null },
  [P3]: { provider_id: P3, name: 'Gamma Institute', description_present: true, quality_class: 'verified_published', source_tier: 'direct', admission_state: 'admitted', admitted_by: 'layer4', admitted_at: '2026-10-20T01:00:00Z', reader: { state: 'admitted', rule: 'official_site_read' }, website_publication: 'verified', zoho_publication: 'not_applicable', missing_fields: [], locked: true, latest_task: null },
  [P4]: { provider_id: P4, name: 'Delta University', description_present: false, quality_class: 'waiting_decision', source_url: LONG_URL, reader: { state: 'proposed', rule: 'official_site_read', read_via: 'stored', ai_calls: 0, model: 'approved-model', source_captured_at: '2026-11-05T01:00:00Z' }, l4_status: 'pending', machine: { outcome: 'declined', reason: 'machine declined (refused_word:campus)', current_reading: true, subset_result: null }, missing_fields: ['description'], latest_task: null },
  [P5]: { provider_id: P5, name: 'Epsilon College', description_present: false, quality_class: 'waiting_decision', source_url: 'https://epsilon.example/about', reader: { state: 'proposed', rule: 'official_site_read', read_via: 'direct', ai_calls: 1, model: 'approved-model' }, l4_status: 'pending', machine: { outcome: 'declined', reason: 'machine declined (identity_host_mismatch)', current_reading: true, subset_result: null }, missing_fields: ['description'], latest_task: null },
  [P6]: { provider_id: P6, name: 'Zeta Institute', description_present: true, quality_class: 'enriched_admitted', source_url: 'https://zeta.example/about', admitted_at: '2026-11-10T02:00:00Z', admitted_by: 'machine', reader: { state: 'admitted', rule: 'official_site_read', read_via: 'stored', ai_calls: 0 }, website_publication: 'pending', zoho_publication: 'not_applicable', machine: { outcome: 'admitted', reason: 'subset_of_reading', current_reading: true, subset: { given_sentences: 5, kept_sentences: [], dropped: [{ code: 'refused_word:campus', sentence: 'Our campus is lovely.' }, { code: 'figure:percentage', sentence: 'Ninety percent are employed.' }] } }, missing_fields: [], latest_task: null },
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
    const dispatch = ${JSON.stringify(extra.dispatch ?? { parked: false })}
    const denyPrepare = ${JSON.stringify(extra.denyPrepare ?? false)}
    const slowRun = ${JSON.stringify(extra.slowRun ?? false)}
    const override = ${JSON.stringify(extra.override ?? null)}
    let queued = false
    window.fillClient = { async call(name, args) {
      window.fillCalls.push({ name, args })
      if (name === 'fill_caps') return caps
      if (name === 'provider_status') return { as_at: '2026-11-10T01:00:00Z', providers: args.provider_ids.map(id => { const p = { ...providers[id], ...(override && id === '${P1}' ? override : {}) }; if (task && id === task.provider) p.latest_task = task.row; if (queued && !dispatch.parked && id === '${P1}') { p.quality_class = 'queued'; p.reader = { state: 'queued' }; p.latest_task = { cohort_id: 'cohort-1', state: 'started', run_id: 'run-1', requested_by_me: true, created_at: '2026-11-10T01:05:00Z', run_state: 'queued' } } return p }) }
      if (name === 'saved') return task && args.cohort_id === task.row.cohort_id ? task.saved : { cohort_id: args.cohort_id, state: queued ? 'started' : 'prepared', created_at: '2026-11-10T01:05:00Z', reason: 'Because', runs: queued ? [{ run_id: 'run-1', state: 'queued' }] : [], totals: { selected: 1 } }
      if (name === 'preview') return { token: 'tok-' + args.fill_mode, selected: eligible ? args.provider_ids.length : 0, as_at: '2026-11-10T01:00:00Z', expires_at: '2026-11-10T01:10:00Z', providers: args.provider_ids.map(id => ({ provider_id: id, provider: providers[id].name, eligible, eligibility_reason: eligible ? 'official_site_read' : reasonCode, source_url: eligible ? '${LONG_URL}' : null })) }
      if (name === 'prepare') { if (denyPrepare) { const e = new Error('curator role required'); e.code = '42501'; throw e } return { cohort_id: 'cohort-1', state: 'prepared', created_at: '2026-11-10T01:05:00Z', reason: args.reason, runs: [], totals: { selected: 1 } } }
      if (name === 'run') { if (slowRun) await new Promise(r => setTimeout(r, 600)); queued = true; return { run_id: 'run-1', state: dispatch.parked ? 'parked' : 'queued', dispatch } }
      if (name === 'provider_publication') return { as_at: '2026-11-10T01:06:00Z', providers: args.provider_ids.map(id => ({ provider_id: id, name: providers[id].name, catalogue: { status: providers[id].description_present ? 'present' : 'no_description' }, website: id === '${P2}' ? { status: 'not_served', feed: 'not_applicable' } : { status: providers[id].description_present ? 'verified' : 'awaiting_description', feed: 'verified' }, zoho: id === '${P2}' ? { status: 'verified', feed: 'not_applicable' } : { status: 'not_served', feed: 'not_applicable' } })) }
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
const extractButton = page => page.getByRole('button', { name: 'Extract / refresh description now' })
const reasonBox = page => page.getByLabel('Extract audit reason')

test.describe('the Extract / refresh description now panel', () => {
  test('one primary action: it is the only primary button, the older routes sit under a collapsed Details, and one click does preview, fixed cohort and Run Now in that order', async ({ page }) => {
    await mountPanel(page)
    await expect(page.locator('[data-fill-fields] button.cf-btn.primary')).toHaveCount(1) // the only primary button in the panel
    await expect(page.locator('[data-fill-details] button.cf-btn.primary')).toHaveCount(0)
    await expect(page.locator('[data-fill-details]')).not.toHaveAttribute('open', '')
    await expect(page.getByRole('radio', { name: /Preview only/ })).toBeHidden()
    const row = page.locator(`[data-fill-provider="${P1}"]`)
    await expect(row).toContainText('Description missing')
    await expect(row.locator('[data-missing-fields]')).toContainText('Phone, Year established')
    await expect(page.locator('[data-other-fields-note]')).toContainText('The reader produces the description only')
    await expect(page.locator('[data-fill-caps]')).toContainText('Up to 3 providers in one task')
    // the one required audit reason: not made up, not bypassed
    await expect(extractButton(page)).toBeDisabled()
    await reasonBox(page).fill('abc')
    await expect(extractButton(page)).toBeDisabled()
    await reasonBox(page).fill(REASON)
    await expect(extractButton(page)).toBeEnabled()
    await extractButton(page).click()
    const out = page.locator('[data-extract-outcome]')
    await expect(out).toHaveAttribute('data-extract-outcome', 'started')
    await expect(out).toContainText('1 provider sent to the governed reader')
    await expect(out).toContainText('run-1')
    const seq = await names(page)
    expect(seq.filter(n => ['preview', 'prepare', 'run'].includes(n))).toEqual(['preview', 'prepare', 'run'])
    const c = await calls(page)
    expect(c.find(x => x.name === 'preview').args).toEqual({ provider_ids: [P1], fill_mode: 'missing', size: 1 }) // fill-missing chosen from the provider's status
    expect(c.find(x => x.name === 'prepare').args).toEqual({ preview_token: 'tok-missing', reason: REASON })
    expect(c.find(x => x.name === 'run').args).toEqual({ cohort_id: 'cohort-1' })
    await expect(row).toHaveAttribute('data-class', 'in_progress')
    await expect(row.locator('[data-stage="ai"]')).toContainText('Queued for the reader')
    await expect(row.locator('[data-run-line]')).toContainText('run-1')
  })

  test('a duplicate click is idempotent: the button is off while the request is in flight and the cohort is saved and run once', async ({ page }) => {
    await mountPanel(page, { extra: { slowRun: true } })
    await reasonBox(page).fill(REASON)
    const b = extractButton(page)
    await b.click()
    await expect(b).toBeDisabled()
    await b.click({ force: true, noWaitAfter: true }).catch(() => {})
    await expect(page.locator('[data-extract-outcome]')).toHaveAttribute('data-extract-outcome', 'started')
    const seq = await names(page)
    expect(seq.filter(n => n === 'prepare')).toHaveLength(1)
    expect(seq.filter(n => n === 'run')).toHaveLength(1)
    // once the provider is queued, a further click starts nothing: the reader already has it
    await expect(page.locator(`[data-fill-provider="${P1}"]`)).toHaveAttribute('data-class', 'in_progress')
    await expect(page.locator('[data-nothing-to-extract]')).toBeVisible()
    await extractButton(page).click()
    await expect(page.locator('[data-extract-outcome]')).toHaveAttribute('data-extract-outcome', 'in_progress')
    expect((await names(page)).filter(n => n === 'prepare')).toHaveLength(1)
  })

  test('a basic registry description is refreshed with upgrade-basic chosen from its status, and the backend\'s exact refusal is shown while the switch is off', async ({ page }) => {
    await mountPanel(page, { ids: [P2], extra: { eligible: false, reason: 'upgrade_switched_off', caps: { upgrade_basic_on: false } } })
    await reasonBox(page).fill(REASON)
    await extractButton(page).click()
    const out = page.locator('[data-extract-outcome]')
    await expect(out).toHaveAttribute('data-extract-outcome', 'policy')
    await expect(out).toContainText('Upgrade is switched off: a Platform Admin policy decision')
    await expect(out).toContainText('Beta College')
    const c = await calls(page)
    expect(c.find(x => x.name === 'preview').args.fill_mode).toBe('upgrade_basic')
    expect(c.map(x => x.name)).not.toContain('prepare')
    expect(c.map(x => x.name)).not.toContain('run')
  })

  test('a basic registry description that may be refreshed is prepared and run with the upgrade mode', async ({ page }) => {
    await mountPanel(page, { ids: [P2] })
    await reasonBox(page).fill(REASON)
    await extractButton(page).click()
    await expect(page.locator('[data-extract-outcome]')).toHaveAttribute('data-extract-outcome', 'started')
    const c = await calls(page)
    expect(c.find(x => x.name === 'preview').args).toEqual({ provider_ids: [P2], fill_mode: 'upgrade_basic', size: 1 })
    expect(c.find(x => x.name === 'prepare').args.preview_token).toBe('tok-upgrade_basic')
  })

  test('a role below the run right is told "permission denied" and nothing is queued; a refusal from the server is told the same way', async ({ page }) => {
    await mountPanel(page, { rank: 3, extra: { caps: { can_run: false } } })
    await expect(extractButton(page)).toBeDisabled()
    await expect(page.locator('[data-permission-note]')).toContainText('Permission denied')
    expect(await names(page)).toEqual(['fill_caps', 'provider_status'])
    await mountPanel(page, { extra: { denyPrepare: true } })
    await reasonBox(page).fill(REASON)
    await extractButton(page).click()
    await expect(page.locator('[data-extract-outcome]')).toHaveAttribute('data-extract-outcome', 'permission')
    await expect(page.locator('[data-extract-outcome]')).toContainText('Nothing was queued')
    expect(await names(page)).not.toContain('run')
  })

  test('the reasons a saved task is not started are told apart: Run Now allowlist off, reader paused, AI spending limit reached, review queue full', async ({ page }) => {
    const cases = [['job_not_allowlisted', 'allowlist', 'Run Now is not switched on for this reader'], ['job_paused', 'paused', 'The reader is paused'], ['ai_ceiling', 'cap', 'approved AI spending limit'], ['review_full', 'policy', 'review queue for provider descriptions is full']]
    for (const [reason, cat, words] of cases) {
      await mountPanel(page, { extra: { dispatch: { parked: true, reason } } })
      await reasonBox(page).fill(REASON)
      await extractButton(page).click()
      const out = page.locator('[data-extract-outcome]')
      await expect(out, reason).toHaveAttribute('data-extract-outcome', cat)
      await expect(out, reason).toContainText(words)
      await expect(page.locator('[data-fill-task]'), reason).toContainText('cohort-1') // the saved task is kept
    }
  })

  test('each provider shows the durable stages, with the exact machine code in plain words, and says what happens next', async ({ page }) => {
    await mountPanel(page, { ids: [P4, P5, P6] })
    const d = page.locator(`[data-fill-provider="${P4}"]`)
    await expect(d.locator('[data-stage="source"]')).toContainText('Stored official evidence reused')
    await expect(d.locator('[data-stage="source"] a')).toHaveAttribute('href', LONG_URL)
    await expect(d.locator('[data-stage="validation"]')).toContainText('a word the automatic text rule does not admit ("campus")')
    await expect(d.locator('[data-stage="validation"] code')).toHaveText('refused_word:campus')
    await expect(d.locator('[data-stage="decision"]')).toContainText('Technical recovery')
    await expect(d).toHaveAttribute('data-class', 'recovering')
    await expect(d.locator('[data-next-action]')).toContainText('re-checks this reading every hour')
    const e = page.locator(`[data-fill-provider="${P5}"]`)
    await expect(e.locator('[data-stage="source"]')).toContainText('Read fresh from the official page')
    await expect(e.locator('[data-stage="validation"] code')).toHaveText('identity_host_mismatch')
    await expect(e.locator('[data-stage="decision"]')).toContainText('A person decides in Layer 4')
    await expect(e.locator('[data-next-action]')).toContainText('Open Layer 4')
    const z = page.locator(`[data-fill-provider="${P6}"]`)
    await expect(z.locator('[data-stage="validation"]')).toContainText('Passed after leaving out 2 of 5 sentences')
    await expect(z.locator('[data-stage="validation"]')).toContainText('Nothing was reworded or added')
    await expect(z.locator('[data-stage="decision"]')).toContainText('Admitted by the machine rule')
    await expect(z.locator('[data-stage="publication"]')).toContainText('Website: Pending')
    await expect(z.locator('[data-stage="publication"]')).toContainText('Zoho: Not applicable')
    // nothing here can be extracted: a recovering reading, a person's decision and an up-to-date description each say why
    await expect(page.locator('[data-nothing-to-extract]')).toBeVisible()
    await extractButton(page).click()
    await expect(page.locator('[data-extract-outcome]')).toHaveAttribute('data-extract-outcome', /in_progress|person/)
    expect(await names(page)).not.toContain('prepare')
  })

  test('the result by field: tried-not-found, a technical failure that will retry and a budget refusal that is not an attempt are told apart, with the source examined and the next try', async ({ page }) => {
    const cases = [
      [{ reader: { state: 'held', rule: 'not_stated', reason: 'the page does not describe the institution', tries: 1, read_via: 'direct', content_hash: 'abc123' }, source_url: 'https://a.example/about' }, 'not_found', 'Tried, not found', 'Source examined: https://a.example/about'],
      [{ reader: { state: 'queued', rule: 'retry', reason: 'fetch_failed: timeout', tries: 1 }, next_retry_at: '2026-11-10T09:00:00Z' }, 'technical', 'Technical failure: it will be tried again', 'Next try: 2026-11-10T09:00:00Z'],
      [{ reader: { state: 'queued', rule: 'ai_budget_refused', tries: 0 } }, 'not_attempt', 'Not an attempt', 'no try was used'],
    ]
    for (const [over, kind, title, text] of cases) {
      await mountPanel(page, { ids: [P1], extra: { override: over } })
      const f = page.locator(`[data-fill-provider="${P1}"] [data-field-outcome="${kind}"]`)
      await expect(f, kind).toContainText(title)
      await expect(f, kind).toContainText(text)
      await expect(page.locator(`[data-fill-provider="${P1}"] [data-field-outcome="not_read"]`)).toContainText('not read')
    }
  })

  test('a held read is labelled by what it means: only a real read of a page that does not describe the institution is "Tried, not found"; never-read, identity or host, unavailable source, weak evidence and machine-declined holds each have their own words, and no "No source examined yet" sits under a tried-not-found heading', async ({ page }) => {
    const real = { read_via: 'direct', content_hash: 'abc123' }
    const url = { source_url: 'https://a.example/about' }
    const cases = [ // [rule, read facts, source, kind, heading, must not say]
      ['insufficient_verified_facts', {}, {}, 'not_attempted', 'Not attempted', /Tried, not found/],
      ['home_not_read', {}, {}, 'not_attempted', 'Not attempted', /Tried, not found/],
      ['about_not_read', {}, {}, 'not_attempted', 'Not attempted', /Tried, not found/],
      ['no_about_page', {}, {}, 'source_unavailable', 'Source unavailable', /Tried, not found/],
      ['no_about_page', real, url, 'not_found', 'Tried, not found', /No source examined yet/],
      ['not_stated', real, url, 'not_found', 'Tried, not found', /No source examined yet/],
      ['not_stated', {}, {}, 'source_unavailable', 'Source unavailable', /Tried, not found/],
      ['provider_name_not_proved', real, url, 'identity', 'identity or host not proved', /Tried, not found/],
      ['provider_name_conflict', real, url, 'identity', 'identity or host not proved', /Tried, not found/],
      ['provider_host_conflict', {}, {}, 'identity', 'identity or host not proved', /Tried, not found/],
      ['wrong_host', {}, {}, 'source_unavailable', 'Source unavailable', /Tried, not found/],
      ['robots_disallowed', {}, {}, 'source_unavailable', 'Source unavailable', /Tried, not found/],
      ['verbatim_passage', real, url, 'insufficient', 'Insufficient or ambiguous evidence', /Tried, not found/],
      ['quote_not_on_page', real, url, 'insufficient', 'Insufficient or ambiguous evidence', /Tried, not found/],
      ['unsupported_claim', real, url, 'insufficient', 'Insufficient or ambiguous evidence', /Tried, not found/],
      ['machine_declined_machine_text_refused_word', {}, {}, 'person', 'Held for a person or policy', /Tried, not found/],
    ]
    for (const [rule, facts, src, kind, heading, never] of cases) {
      await mountPanel(page, { ids: [P1], extra: { override: { reader: { state: 'held', rule, tries: 1, ...facts }, ...src } } })
      const f = page.locator(`[data-fill-provider="${P1}"] [data-field-outcome]`).first()
      await expect(f, rule).toHaveAttribute('data-field-outcome', kind)
      await expect(f, rule).toContainText(heading)
      await expect(f, rule).not.toContainText(never)
    }
  })

  test('an up-to-date or locked description starts nothing and is told so', async ({ page }) => {
    await mountPanel(page, { ids: [P3, P6] })
    await expect(page.locator(`[data-fill-provider="${P3}"]`)).toContainText('Locked')
    await expect(page.locator(`[data-fill-provider="${P3}"] [data-next-action]`)).toContainText('a person has locked the description')
    await expect(page.locator(`[data-fill-provider="${P6}"] [data-next-action]`)).toContainText('Nothing')
    await extractButton(page).click()
    await expect(page.locator('[data-extract-outcome]')).toBeVisible()
    expect(await names(page)).not.toContain('preview')
    expect(await names(page)).not.toContain('prepare')
  })

  test('no eligible work: when the platform offers nothing the exact reason is shown and nothing is queued', async ({ page }) => {
    await mountPanel(page, { extra: { eligible: false, reason: 'no_verified_stored_source' } })
    await reasonBox(page).fill(REASON)
    await extractButton(page).click()
    const out = page.locator('[data-extract-outcome]')
    await expect(out).toHaveAttribute('data-extract-outcome', 'source')
    await expect(out).toContainText('There is no stored official About page for this provider yet')
    expect(await names(page)).not.toContain('prepare')
  })

  test('a cohort saved and not yet run (the browser was closed in between) is run, not saved again', async ({ page }) => {
    const row = { cohort_id: 'cohort-7', state: 'prepared', requested_by_me: true, created_at: '2026-11-10T00:30:00Z' }
    const saved = { cohort_id: 'cohort-7', state: 'prepared', created_at: '2026-11-10T00:30:00Z', reason: 'Earlier today', runs: [], totals: { selected: 1 } }
    await mountPanel(page, { extra: { task: { provider: P1, row, saved } } })
    await expect(page.locator('[data-fill-task]')).toContainText('cohort-7')
    await expect(reasonBox(page)).toHaveCount(0)
    await extractButton(page).click()
    await expect(page.locator('[data-extract-outcome]')).toHaveAttribute('data-extract-outcome', 'started')
    const c = await calls(page)
    expect(c.map(x => x.name)).not.toContain('prepare')
    expect(c.find(x => x.name === 'run').args).toEqual({ cohort_id: 'cohort-7' })
  })

  test('a task this person already started is read again when the panel is opened, so closing the browser loses nothing', async ({ page }) => {
    const row = { cohort_id: 'cohort-9', state: 'started', requested_by_me: true, created_at: '2026-11-10T00:30:00Z', run_id: 'run-9', run_state: 'running' }
    const saved = { cohort_id: 'cohort-9', state: 'started', created_at: '2026-11-10T00:30:00Z', reason: 'Earlier today', runs: [{ run_id: 'run-9', state: 'running' }], totals: { selected: 1, evidence_read: 1 } }
    await mountPanel(page, { extra: { task: { provider: P1, row, saved } } })
    await expect(page.locator('[data-fill-task]')).toContainText('cohort-9')
    await expect(page.locator('[data-fill-task]')).toContainText('Earlier today')
    await expect(page.locator(`[data-fill-provider="${P1}"]`)).toContainText('yours')
    await expect(page.locator(`[data-fill-provider="${P1}"] [data-run-line]`)).toContainText('run-9')
    expect(await names(page)).toEqual(['fill_caps', 'provider_status', 'saved'])
  })

  test('more providers than the cap are explained and not read; the primary action stays off', async ({ page }) => {
    await mountPanel(page, { ids: [P1, P2, P3], extra: { caps: { max_size: 2 } }, rows: false })
    await expect(page.getByRole('alert')).toContainText('3 providers are selected; one task can take 2')
    expect(await names(page)).toEqual(['fill_caps'])
    await expect(extractButton(page)).toBeDisabled()
  })

  test('Details keeps the older routes: preview only changes nothing, and Verify publication shows Not applicable as such, never as a failure', async ({ page }) => {
    await mountPanel(page, { ids: [P2] })
    await page.locator('[data-fill-details] summary').click()
    await page.getByRole('radio', { name: /Preview only/ }).check()
    await expect(page.getByText('changes no description and queues no read').first()).toBeVisible()
    await page.getByRole('button', { name: 'Preview what the reader would use' }).click()
    await expect(page.locator('[data-fill-preview]')).toContainText('Nothing has been queued and no description has changed')
    expect((await calls(page)).find(c => c.name === 'preview').args.fill_mode).toBe('upgrade_basic')
    await page.getByRole('radio', { name: /Verify publication/ }).check()
    await page.getByRole('button', { name: 'Verify publication now' }).click()
    const rb = page.locator('[data-publication-readback]')
    await expect(rb).toContainText('Website: Not served (not applicable)')
    await expect(rb).toContainText('Zoho: Matched')
    await expect(rb).toContainText('Catalogue: not applicable')
    await expect(rb).not.toContainText('Could not be read')
    await expect(rb).toContainText('it is not a failure')
    // a role without the run right can read status only
    await mountPanel(page, { ids: [P3], rank: 3, extra: { caps: { can_run: false } } })
    await page.locator('[data-fill-details] summary').click()
    await page.getByRole('radio', { name: /Verify publication/ }).check()
    await expect(page.getByRole('button', { name: 'Verify publication now' })).toBeDisabled()
    await expect(page.getByText('An authorised operator must run the publication read-back.')).toBeVisible()
  })

  test('Details preview then save uses the same one reason box', async ({ page }) => {
    await mountPanel(page)
    await page.locator('[data-fill-details] summary').click()
    await page.getByRole('button', { name: 'Preview what the reader would use' }).click()
    const save = page.getByRole('button', { name: 'Save and queue with the reader' })
    await expect(save).toBeDisabled()
    await expect(page.getByLabel('Extract audit reason')).toHaveCount(1)
    await reasonBox(page).fill(REASON)
    await expect(save).toBeEnabled()
    await save.click()
    await expect(page.locator('[data-fill-task]')).toContainText('cohort-1')
    const seq = await names(page)
    expect(seq.indexOf('prepare')).toBeLessThan(seq.indexOf('run'))
  })
})

// ---- the screens ---------------------------------------------------------------------------------------------------------------------------------------
const base = (id, name) => ({ id, canonical_name: name, display_name: name, country_code: 'AU', course_count: 10, lifecycle_status: 'active', publication_status: 'published', last_verified_at: '2026-10-01T00:00:00Z', updated_at: '2026-11-01T02:00:00Z', adapter_status: 'none', university_groups: [], evidence_count: 2, provider_type_code: null, provider_type_name: null,
  pdesc: { description_filled: false, admission_state: 'none', quality: 'missing', missing_fields: ['description', 'phone'], website_publication: null, zoho_publication: null } })
const ROWS = [base(P1, 'Alpha University'), base(P2, 'Beta College'), base(P3, 'Gamma Institute')]

async function mountCatalogue(page, { rank = 6, cap = 2, capFails = false } = {}) {
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
    if (b.p_action === 'fill_caps') return capFails ? route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"unavailable"}' }) : route.fulfill({ json: { ...CAPS, max_size: cap } })
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
  test('each row has a tick box and an Extract / refresh description now button; ticking stops at the cap the server reports; the button opens the panel and does not open the row\'s detail', async ({ page }) => {
    await mountCatalogue(page, { cap: 2 })
    await expect(page.locator('input[aria-label^="Select "][aria-label$="for description extraction"]')).toHaveCount(3)
    await page.getByLabel('Select Alpha University for description extraction').check()
    await page.getByLabel('Select Beta College for description extraction').check()
    await expect(page.locator('[data-fill-selection]')).toContainText('2 selected (up to 2 in one task)')
    await expect(page.getByLabel('Select Gamma Institute for description extraction')).toBeDisabled()
    await page.getByRole('button', { name: 'Extract / refresh description now for selected' }).click()
    await expect(page.locator('[data-fill-fields]')).toContainText('Extract / refresh description now: 2 providers')
    await expect(page.locator(`[data-fill-provider="${P1}"]`)).toBeVisible()
    await expect(page.locator(`[data-fill-provider="${P2}"]`)).toBeVisible()
    await page.getByRole('button', { name: 'Close description panel' }).click()
    await expect(page.locator('[data-fill-fields]')).toHaveCount(0)
    // one row: its own button
    await page.getByRole('button', { name: 'Extract / refresh description now for Gamma Institute' }).click()
    await expect(page.locator('[data-fill-fields]')).toContainText('Gamma Institute')
    await expect(page.locator('aside.m-drawer-provider')).toHaveCount(0)
  })

  test('Provider Detail has a Description card with the same Extract panel, for the provider that is open', async ({ page }) => {
    await mountCatalogue(page)
    await page.locator(`tr[data-row="${P1}"] td`).nth(2).click()
    const card = page.locator('[data-fill-fields-card]')
    await expect(card).toBeVisible()
    await card.getByRole('button', { name: 'Extract / refresh description now' }).click()
    await expect(page.locator('[data-fill-fields]')).toContainText('Alpha University')
    await expect(page.locator(`[data-fill-provider="${P1}"]`)).toBeVisible()
  })

  test('if the limit cannot be read, nothing can be ticked (never unlimited), and the row button still opens the panel', async ({ page }) => {
    await mountCatalogue(page, { capFails: true })
    await expect(page.locator('[data-fill-caps-failed]')).toBeVisible()
    for (const name of ['Alpha University', 'Beta College', 'Gamma Institute']) await expect(page.getByLabel(`Select ${name} for description extraction`)).toBeDisabled()
    await expect(page.locator('[data-fill-selection]')).toHaveCount(0)
    await page.getByRole('button', { name: 'Extract / refresh description now for Alpha University' }).click()
    await expect(page.locator('[data-fill-fields]')).toBeVisible()
  })

  test('below Curator the row has no tick box and no Extract button', async ({ page }) => {
    await mountCatalogue(page, { rank: 2 })
    await expect(page.locator('input[aria-label$="for description extraction"]')).toHaveCount(0)
    await expect(page.getByRole('button', { name: /^Extract \/ refresh description now for / })).toHaveCount(0)
  })

  test('the Description quality level filter is offered with the four groups first and is sent to the server', async ({ page }) => {
    const { filterReads } = await mountCatalogue(page)
    const f = page.locator('.m-filter-select').filter({ has: page.locator('small', { hasText: /^Description quality$/ }) })
    await expect(f).toHaveCount(1)
    await f.locator('button.m-filter-button').click()
    const opts = await f.locator('.m-filter-popover button').allInnerTexts()
    expect(opts.map(o => o.trim()).slice(0, 5)).toEqual(['All', 'Basic registry profile', 'Enriched (admitted, any publication)', 'Missing', 'Held (evidence, identity or policy)'])
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
  test('the Extract / refresh panel at phone width: every control is at least 24 px, long names, addresses and codes wrap, there is no sideways page scroll', async ({ page }) => {
    const w = page.viewportSize()?.width || 9999
    expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
    const row = { cohort_id: 'cohort-with-a-long-identifier-to-test-the-wrapping-of-the-task-line', state: 'started', requested_by_me: true, created_at: '2026-11-10T00:30:00Z', run_state: 'running' }
    const saved = { ...row, reason: 'An audit reason long enough to wrap onto several lines on a narrow phone screen without a sideways scroll', runs: [{ run_id: 'run-with-a-long-identifier-to-test-wrapping', state: 'running' }], totals: { selected: 2, evidence_read: 1 } }
    await mountPanel(page, { ids: [P2, P1, P4], extra: { task: { provider: P2, row, saved } } })
    await reasonBox(page).fill('Phone acceptance reason')
    await expect(extractButton(page)).toBeEnabled()
    const panel = await page.locator('[data-fill-fields-panel]').boundingBox()
    expect(panel.x).toBeGreaterThanOrEqual(-1); expect(panel.x + panel.width).toBeLessThanOrEqual(w + 1)
    expect(await tapTargets(page, '[data-fill-fields] button, [data-fill-fields] input[type="text"], [data-fill-fields] summary, [data-fill-fields] a')).toEqual([])
    expect(await overflow(page)).toBeLessThanOrEqual(1)
    expect(await page.locator('[data-fill-fields-panel]').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
    // the primary action runs on a phone
    await extractButton(page).click()
    await expect(page.locator('[data-extract-outcome]')).toBeVisible()
    expect(await overflow(page)).toBeLessThanOrEqual(1)
    // Details, opened on a phone
    await page.locator('[data-fill-details] summary').click()
    await page.getByRole('radio', { name: /Verify publication/ }).check()
    await page.getByRole('button', { name: 'Verify publication now' }).click()
    await expect(page.locator('[data-publication-readback]')).toBeVisible()
    expect(await tapTargets(page, '[data-fill-fields] label.pff-mode')).toEqual([])
    expect(await tapTargets(page, '[data-fill-fields] input[type="radio"]')).toEqual([])
    expect(await overflow(page)).toBeLessThanOrEqual(1)
  })

  test('the Provider Catalogue row action at phone width: the tick box and the Extract / refresh description now button are at least 24 px and the page does not scroll sideways', async ({ page }) => {
    const w = page.viewportSize()?.width || 9999
    expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
    await mountCatalogue(page, { cap: 2 })
    expect(await tapTargets(page, '.pff-pick')).toEqual([])
    expect(await tapTargets(page, '.pff-open')).toEqual([])
    await page.getByLabel('Select Alpha University for description extraction').check()
    await expect(page.locator('[data-fill-selection]')).toBeVisible()
    expect(await tapTargets(page, '[data-fill-selection] button')).toEqual([])
    expect(await overflow(page)).toBeLessThanOrEqual(1)
    await page.getByRole('button', { name: 'Extract / refresh description now for selected' }).click()
    await expect(page.locator('[data-fill-fields-panel]')).toBeVisible()
    expect(await overflow(page)).toBeLessThanOrEqual(1)
  })
})
