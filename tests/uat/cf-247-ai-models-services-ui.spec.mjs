// Guards: Platform Admin 13 Nov 2026 19:14–19:36 — Models & services redesign (one model list, service cascades, caps, prompts, usage; no blank model)
// Platform Admin written review, 13 Nov 2026 22:10 (the final UI decisions this spec holds the page to):
//   "Default to expanded panes on desktop. Allow collapsing, but keep warnings visible." (this page is the stated, narrow exception to
//       cards-start-closed, Decision 254; on a phone the cards start closed)
//   "Do not silently remove role-3 read-only access."
//   "Scholarship Extraction configuration belongs in Models & Services. Scholarships › Coverage links to the same configuration and retains
//       scholarship-specific operational results."
//   "Reconcile the Adapter Builder model picker. Do not leave competing model controls."
//   "Do not display a model cascade as operational unless the worker actually executes it."
// Mocked browser (chromium-desktop) and the address map. The three calls are answered by tests/uat/support/ai-overview-fixture.mjs in the shape of
// docs/platform/AI-MODELS-SERVICES-CONTRACT.md, with the server's own refusals; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { mockAi, services as seedServices } from './support/ai-overview-fixture.mjs'
import { resolveTarget, PAGES, RETIRED_AI_CARDS } from '../../src/nav-map.js'

// the four cards are open by default at desktop width; a test that needs another card open (Settings) opens it before the page loads
const CARDS = ['services.ai.openrouter', 'services.ai.models', 'services.ai.services', 'services.ai.usage']
const openCards = (page, more = []) => page.addInitScript((ids) => { try { for (const id of ids) window.sessionStorage.setItem(`cf.card.${id}`, '1') } catch { /* storage unavailable */ } }, [...CARDS, ...more])
async function open(page, over = {}, opts = {}) {
  await mockAdmin(page, { rank: opts.rank ?? 6 })
  const ai = await mockAi(page, over, opts)
  await page.goto('/#models-services?tab=ai')
  await expect(page.locator('[data-ai-page="ready"]')).toBeVisible({ timeout: 30_000 })
  return ai
}
const row = (page, code) => page.locator(`[data-ai-service="${code}"]`)
const detail = (page, code) => page.locator(`[data-ai-service-detail="${code}"]`)

test.describe('Models & services › AI, mocked browser', () => {
  test('one page, exactly four panes, in the order asked: OpenRouter key and usage, Models, Services, Recent usage', async ({ page }) => {
    await open(page)
    await expect(page.locator('[data-ai-page] > *')).toHaveCount(4)
    const panes = await page.locator('[data-ai-pane]').evaluateAll(els => els.map(e => e.getAttribute('data-ai-pane')))
    expect(panes).toEqual(['openrouter', 'models', 'services', 'usage'])
    await expect(page.locator('[data-ai-pane] h2')).toHaveText(['1 · OpenRouter key and usage', '2 · Models', '3 · Services', '4 · Recent usage'])
    // the retired screens are not drawn anywhere on the tab
    for (const old of ['[data-ai-config]', '[data-ai-uses]', '[data-ai-profiles]', '[data-ai-central]', '[data-ai-adapter]', '[data-ai-scholarship-models]', '[data-scholarship-extraction]', '[data-card="services.ai-models"]']) await expect(page.locator(old)).toHaveCount(0)
    // pane 1: the key is never shown; the credit and when it was read; the one ceiling with today's spend; a plain state line
    const or = page.locator('[data-ai-pane="openrouter"]')
    await expect(or.locator('[data-ai-account-state="running"]')).toContainText('Running')
    await expect(or.locator('[data-ai-key]')).toContainText('Present')
    await expect(or.locator('[data-ai-key]')).toContainText('never shown')
    await expect(or.locator('[data-ai-balance="figure"]')).toContainText('US$53.00')
    await expect(or.locator('[data-ai-balance]')).toContainText('read ')
    await expect(or.locator('[data-ai-ceiling]')).toContainText('US$9.27 of US$14.00')
    await expect(or.locator('[data-ai-ceiling] [role="meter"]')).toHaveAttribute('aria-valuenow', '9.27')
    await expect(or.locator('input[type="password"]')).toHaveValue('')
    // pane 2: families in the Platform Admin's order, then Not allowed
    const fams = await page.locator('[data-ai-models] tbody[data-ai-family] .aim-group th').evaluateAll(els => els.map(e => e.childNodes[0].textContent.trim()))
    expect(fams).toEqual(['Qwen3', 'MiMo', 'Mistral Small', 'Kimi K2', 'Gemini', 'Llama', 'DeepSeek', 'Not allowed'])
    await expect(page.locator('[data-ai-family="not_allowed"] [data-ai-model]')).toHaveCount(3)
    await expect(page.locator('[data-ai-model="gpt-4.1-mini"]')).toHaveAttribute('data-ai-model-status', 'not_allowed')
    await expect(page.locator('[data-ai-model="mimo-v2.6-flash"] [data-ai-price]')).toHaveText('not checked')
    await expect(page.locator('[data-ai-model="qwen3-30b"] [data-ai-price="known"]')).toContainText('US$0.10 / US$0.30')
    await expect(page.locator('[data-ai-model="deepseek-v3.2"]')).toContainText('Course entry requirements')
    await expect(page.locator('[data-ai-model="deepseek-v3.2"] [data-ai-qualified-for]')).toContainText('Qualified for:')
    // nothing hidden: places outside the services that still name a model that is not allowed, and the retired Layer 3 profiles
    await expect(page.locator('[data-ai-guard="1"]')).toContainText('One place outside the services still names')
    await expect(page.locator('[data-ai-layer3] summary')).toContainText('2 model profiles still switched on')
    // pane 3: areas in order, one row per service
    const areas = await page.locator('[data-ai-services] tbody[data-ai-area]').evaluateAll(els => els.map(e => e.getAttribute('data-ai-area')))
    expect(areas).toEqual(['Courses', 'Entry requirements', 'Providers', 'Scholarships', 'Fees', 'Matching and identity', 'Operations'])
    await expect(page.locator('[data-ai-service]')).toHaveCount(seedServices().length)
    await expect(row(page, 'course_entry_requirements').locator('[data-ai-cascade]')).toHaveText('1 DeepSeek V3.2→2 Qwen3 30B')
    await expect(row(page, 'course_entry_requirements')).toContainText('Field: Course entry requirements')
    await expect(row(page, 'fee_reader').locator('[data-ai-state-pill]')).toHaveText('Held: cap reached')
    await expect(row(page, 'entry_requirements_v2_shadow').locator('[data-ai-state-pill]')).toHaveText('Off')
    await expect(row(page, 'course_description').locator('[data-ai-state-pill]')).toHaveText('Running')
  })

  test('the four panes are open by default on desktop; each can be collapsed, stays collapsed, and a collapsed pane still shows its warnings', async ({ page }) => {
    const base = (await import('./support/ai-overview-fixture.mjs')).aiOverview().openrouter
    await open(page, { openrouter: { ...base, balance_usd: 0.4 } }) // at the credit floor, with caps over the ceiling and a service with no model
    await expect(page.locator('[data-ai-pane] .cf-card-toggle[aria-expanded="true"]')).toHaveCount(4)
    await expect(page.locator('[data-ai-services]')).toBeVisible()
    for (const pane of ['openrouter', 'models', 'services', 'usage']) await page.locator(`[data-ai-pane="${pane}"] .cf-card-toggle`).click()
    await expect(page.locator('[data-ai-pane] .cf-card-toggle[aria-expanded="true"]')).toHaveCount(0)
    await expect(page.locator('[data-ai-services], [data-ai-models]')).toHaveCount(0) // a collapsed card draws no body
    // the warnings stay on the collapsed cards: no credit, caps over the ceiling, places to check, no model, held
    await expect(page.locator('[data-ai-pane="openrouter"] [data-ai-account-chip="no_credit"]')).toHaveText('No credit')
    await expect(page.locator('[data-ai-pane="openrouter"] [data-ai-caps-chip]')).toHaveText('Caps over the ceiling')
    await expect(page.locator('[data-ai-pane="openrouter"] .cf-card-meta')).toContainText('US$9.27 of US$14.00 today')
    await expect(page.locator('[data-ai-pane="models"] .cf-card-meta')).toContainText('12 of 15 allowed')
    await expect(page.locator('[data-ai-pane="models"] .cf-card-meta')).toContainText('1 to check')
    await expect(page.locator('[data-ai-pane="services"] [data-ai-no-model-chip]')).toHaveText('1 with no model')
    await expect(page.locator('[data-ai-pane="services"] .cf-card-meta')).toContainText('held')
    await page.reload()
    await expect(page.locator('[data-ai-page="ready"]')).toBeVisible()
    await expect(page.locator('[data-ai-pane] .cf-card-toggle[aria-expanded="true"]')).toHaveCount(0) // a collapsed choice is remembered for the session
    await page.locator('[data-ai-pane="services"] .cf-card-toggle').click()
    await expect(row(page, 'entry_matrices').locator('[data-ai-no-model]').first()).toBeVisible()
  })

  test('a balance with no reading is "Balance not measured" on the collapsed card too', async ({ page }) => {
    const base = (await import('./support/ai-overview-fixture.mjs')).aiOverview().openrouter
    await open(page, { openrouter: { ...base, balance_usd: null, balance_observed_at: null, balance_known: false, balance_note: 'No balance has been read: the credit floor holds nothing.' } })
    await page.locator('[data-ai-pane="openrouter"] .cf-card-toggle').click()
    await expect(page.locator('[data-ai-pane="openrouter"] [data-ai-account-chip="unread"]')).toHaveText('Held: balance not measured')
  })

  test('a model cell is never blank: no model is a red "No model", and unknown figures say so instead of 0', async ({ page }) => {
    const bare = seedServices().map(s => (s.service_code === 'provider_description' ? { ...s, cascade: [] } : s))
    await open(page, { services: bare })
    // every service row's model cell has words in it
    const cells = await page.locator('[data-ai-service] [data-ai-model-cell]').evaluateAll(els => els.map(e => e.textContent.trim()))
    expect(cells.length).toBe(bare.length)
    for (const c of cells) { expect(c.length).toBeGreaterThan(0); expect(c).not.toMatch(/^[—–-]$/) }
    // the contract returned no model at all
    const none = row(page, 'provider_description')
    await expect(none.locator('[data-ai-model-cell] [data-ai-no-model]').first()).toHaveText('No model')
    await expect(none.locator('[data-ai-state-pill]')).toHaveText('No allowed model')
    // a cascade that names only a model that is not allowed (the 19:36 case: GPT-4.1 mini is named, struck out, and flagged)
    const gpt = row(page, 'entry_matrices')
    await expect(gpt.locator('[data-ai-cascade-model="gpt-4.1-mini"]')).toContainText('GPT-4.1 mini')
    await expect(gpt.locator('[data-ai-cascade-model="gpt-4.1-mini"]')).toContainText('not allowed')
    await expect(gpt.locator('[data-ai-no-model]').first()).toHaveText('No allowed model')
    await expect(page.locator('[data-ai-no-model-warning]')).toContainText('Entry requirement matrices (provider pages)')
    await expect(page.locator('[data-ai-no-model-warning]')).toContainText('Provider description')
    // unknown is never 0
    await expect(row(page, 'course_matching').locator('[data-ai-spent]')).toContainText('Not measured')
    await expect(row(page, 'course_matching').locator('[data-ai-spent]')).toContainText('calls not measured')
    await expect(row(page, 'course_matching').locator('[data-ai-spent]')).not.toContainText('US$0.00')
    // usage: spend with no model recorded is named, not dropped
    await page.locator('[data-ai-usage-pick="day"]').click(); await page.locator('[data-ai-usage-pick="model"]').click()
    await expect(page.locator('[data-ai-usage="day-model"] [data-ai-usage-row="(none)"]')).toContainText('Model not recorded')
    await expect(page.locator('[data-ai-usage-strip="day"] li')).toHaveCount(14)
    await page.locator('[data-ai-usage-pick="hour"]').click(); await page.locator('[data-ai-usage-pick="service"]').click()
    await expect(page.locator('[data-ai-usage-strip="hour"] li')).toHaveCount(24)
    await expect(page.locator('[data-ai-usage="hour-service"] [data-ai-usage-row="fee_reader"]')).toContainText('US$5.02')
  })

  test('no usage figures is "Not measured", never a row of zeros', async ({ page }) => {
    await open(page, { usage: { by_day_14d: null, by_hour_24h: null } })
    await expect(page.locator('[data-ai-usage-none]')).toContainText('Not measured')
    await expect(page.locator('[data-ai-pane="usage"] table')).toHaveCount(0)
  })

  test('a cascade edit refuses a model that is not allowed and an empty cascade, offers allowed models only, and saves with a reason and the change shown', async ({ page }) => {
    const { calls } = await open(page)
    await row(page, 'entry_matrices').locator('.aim-toggle').click()
    const d = detail(page, 'entry_matrices')
    await d.locator('[data-ai-edit="entry_matrices"]').click()
    const save = d.locator('[data-ai-confirm="route-entry_matrices"]')
    // the saved cascade names GPT-4.1 mini: it cannot be saved again as it is
    await expect(d.locator('[data-ai-blocked]')).toContainText('Not an allowed model: GPT-4.1 mini')
    await d.getByLabel('Reason: route-entry_matrices').fill('try to keep GPT')
    await expect(save).toBeDisabled()
    // only allowed models are offered
    const offered = await d.getByLabel('Add a model to Entry requirement matrices (provider pages)').locator('option').allTextContents()
    expect(offered.join('|')).toContain('Qwen3 30B A3B Instruct (2507)')
    expect(offered.join('|')).not.toMatch(/GPT|Claude/)
    // remove it: an empty cascade is refused too
    await d.getByLabel('Remove GPT-4.1 mini').click()
    await expect(d.locator('[data-ai-blocked]')).toContainText('The cascade is empty: name at least one allowed model')
    await expect(d.locator('[data-ai-editor] [data-ai-no-model]')).toBeVisible()
    await expect(save).toBeDisabled()
    expect(calls).toEqual([])
    // add two allowed models, reorder, save with a reason
    const add = d.getByLabel('Add a model to Entry requirement matrices (provider pages)')
    await add.selectOption('qwen3-30b'); await add.selectOption('mistral-small-3.2')
    await d.getByLabel('Move Mistral Small 3.2 24B up').click()
    await expect(d.locator('[data-ai-blocked]')).toHaveCount(0)
    await expect(d.locator('[data-ai-changes]')).toContainText('Cascade: 1 GPT-4.1 mini becomes 1 Mistral Small 3.2 → 2 Qwen3 30B')
    await d.getByLabel('Reason: route-entry_matrices').fill('abc')
    await expect(save).toBeDisabled() // a reason has at least 4 characters
    await d.getByLabel('Reason: route-entry_matrices').fill('GPT-4.1 mini is not allowed any more')
    await save.click()
    await expect(d.locator('[data-ai-saved]')).toContainText('Saved. Cascade: 1 GPT-4.1 mini becomes 1 Mistral Small 3.2 → 2 Qwen3 30B')
    expect(calls).toEqual([{ name: 'admin_ai_route_set_v1', p_service: 'entry_matrices', p_cascade: ['mistral-small-3.2', 'qwen3-30b'], p_daily_usd_cap: 4, p_daily_calls_cap: null, p_enabled: true, p_reason: 'GPT-4.1 mini is not allowed any more' }])
    await expect(row(page, 'entry_matrices').locator('[data-ai-cascade]')).toHaveText('1 Mistral Small 3.2→2 Qwen3 30B')
    await expect(row(page, 'entry_matrices').locator('[data-ai-state-pill]')).toHaveText('Running')
  })

  test('caps, the switch and a model\'s allowed switch each ask for a reason and say what changes; a server refusal is shown in plain words', async ({ page }) => {
    const { calls } = await open(page)
    // cap and switch of one service
    await row(page, 'course_entry_requirements').getByRole('switch').click()
    const d = detail(page, 'course_entry_requirements')
    await expect(d.locator('[data-ai-changes]')).toContainText('Switch: On becomes Off')
    await d.getByLabel('Daily cap in US dollars for Course entry requirements').fill('5')
    await d.getByLabel('Daily cap in calls for Course entry requirements').fill('')
    await expect(d.locator('[data-ai-changes]')).toContainText('Daily cap (US$): US$3.00 becomes US$5.00')
    await expect(d.locator('[data-ai-changes]')).toContainText('Daily cap (calls): 500 calls becomes no cap')
    await expect(d.locator('[data-ai-confirm="route-course_entry_requirements"]')).toBeDisabled()
    await d.getByLabel('Daily cap in US dollars for Course entry requirements').fill('-1')
    await expect(d.locator('[data-ai-blocked]')).toContainText('not negative')
    await d.getByLabel('Daily cap in US dollars for Course entry requirements').fill('')
    await expect(d.locator('[data-ai-blocked]')).toContainText('Give a daily US$ cap: every service has one')
    await d.getByLabel('Daily cap in US dollars for Course entry requirements').fill('5')
    await d.getByLabel('Reason: route-course_entry_requirements').fill('hold it while the credit is low')
    await d.locator('[data-ai-confirm="route-course_entry_requirements"]').click()
    await expect(row(page, 'course_entry_requirements').locator('[data-ai-state-pill]')).toHaveText('Off')
    expect(calls[0]).toEqual({ name: 'admin_ai_route_set_v1', p_service: 'course_entry_requirements', p_cascade: ['deepseek-v3.2', 'qwen3-30b'], p_daily_usd_cap: 5, p_daily_calls_cap: null, p_enabled: false, p_reason: 'hold it while the credit is low' })
    // a model: the change names the services that use it
    const m = page.locator('[data-ai-model="deepseek-v3.2"]')
    await m.getByRole('switch').click()
    const bar = page.locator('[data-ai-save="model-deepseek-v3.2"]')
    await expect(bar.locator('[data-ai-changes]')).toContainText('DeepSeek V3.2: Allowed becomes Not allowed')
    await expect(bar.locator('[data-ai-changes]')).toContainText('1 service names it (Course entry requirements)')
    await expect(bar.locator('[data-ai-confirm]')).toBeDisabled()
    await bar.getByLabel('Reason: model-deepseek-v3.2').fill('costs more than Qwen3')
    await bar.locator('[data-ai-confirm]').click()
    await expect(page.locator('[data-ai-model="deepseek-v3.2"]')).toHaveAttribute('data-ai-model-status', 'not_allowed')
    expect(calls[1]).toEqual({ name: 'admin_ai_model_set_v1', p_code: 'deepseek-v3.2', p_status: 'not_allowed', p_reason: 'costs more than Qwen3' })
    // GPT and Claude cannot be allowed from the screen, and the row says why in the server's words
    await expect(page.locator('[data-ai-model="gpt-4.1-mini"]').getByRole('switch')).toBeDisabled()
    await expect(page.locator('[data-ai-model="gpt-4.1-mini"] [data-ai-family-refused]')).toContainText('Not in a family the Platform Admin allows; adding a family is a release')
    // the server's refusal, in plain words (the page's own check is bypassed by a refusing server)
    await page.route(/\/rest\/v1\/rpc\/admin_ai_route_set_v1$/, r => r.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ code: 'P0001', message: 'a cascade holds 4 models at most' }) }))
    await row(page, 'ops_diagnosis').locator('.aim-toggle').click()
    const o = detail(page, 'ops_diagnosis')
    await o.locator('[data-ai-edit="ops_diagnosis"]').click()
    await o.getByLabel('Daily cap in US dollars for Operations diagnosis').fill('2')
    await o.getByLabel('Reason: route-ops_diagnosis').fill('raise the cap')
    await o.locator('[data-ai-confirm="route-ops_diagnosis"]').click()
    await expect(o.locator('[data-ai-error]')).toHaveText('A cascade holds 4 models at most.')
  })

  test('each service keeps its prompt (never blank) and its AI settings, saved in place with the existing setting write and a reason', async ({ page }) => {
    await open(page)
    // a prompt whose text lives in the worker: version and "kept in the worker"
    await row(page, 'course_entry_requirements').locator('.aim-toggle').click()
    const w = detail(page, 'course_entry_requirements').locator('[data-ai-prompt]')
    await expect(w).toContainText('Source: worker code')
    await expect(w).toContainText('Version: course-entry-v1')
    await expect(w.locator('[data-ai-prompt-kept]')).toContainText('Kept in the worker')
    // its complete text, version and sha256 come from the generated docs/platform/ai-prompts.json, read only
    const file = JSON.parse(fs.readFileSync('docs/platform/ai-prompts.json', 'utf8')).services.course_entry_requirements
    await expect(w.locator('[data-ai-prompt-text="worker"] pre').first()).toHaveText(file.prompts[0].text)
    await expect(w.locator('[data-ai-prompt-text="worker"]')).toContainText(file.prompts[0].sha256)
    await expect(w.locator('[data-ai-prompt-text="worker"]')).toContainText(`version ${file.prompts[0].version}`)
    await expect(w.locator('textarea')).toHaveCount(0)
    await expect(page.locator('[data-ai-page]')).not.toContainText('4,000 characters')
    // a prompt held in the database: its text, read only
    await row(page, 'provider_description').locator('.aim-toggle').click()
    const p = detail(page, 'provider_description').locator('[data-ai-prompt]')
    await expect(p).toContainText('Version: 4')
    await expect(p.locator('pre[data-ai-prompt-text="database"]')).toContainText('You write a provider description')
    await expect(p.locator('[data-ai-prompt-sha]')).toHaveText(/^[0-9a-f]{64}$/)
    await expect(p.locator('textarea')).toHaveCount(0)
    // settings: a number with its range, a text setting as a text box, an old model setting read only
    await row(page, 'ops_diagnosis').locator('.aim-toggle').click()
    const s = detail(page, 'ops_diagnosis').locator('[data-ai-service-settings]')
    const text = s.locator('[data-ai-setting="pipeline.har.ai_escalation_model"]')
    await expect(text).toHaveAttribute('data-ai-setting-kind', 'text')
    await expect(text.locator('input')).toHaveAttribute('type', 'text')
    await expect(text.locator('input')).toHaveValue('qwen/qwen3-235b-a22b-2507')
    await expect(text).not.toContainText('Between')
    await expect(s.locator('[data-ai-setting="pipeline.ops.ai_diagnosis_model"]')).toContainText('Not read any more')
    await expect(s.locator('[data-ai-setting="pipeline.ops.ai_diagnosis_model"] input')).toHaveCount(0)
    await row(page, 'adapter_builder').locator('.aim-toggle').click() // marked not_read by the server: shown with its value, not editable
    await expect(detail(page, 'adapter_builder').locator('[data-ai-setting="firecrawl.builder_model"]')).toContainText('qwen/qwen3-30b-a3b-instruct-2507')
    await expect(detail(page, 'adapter_builder').locator('[data-ai-setting="firecrawl.builder_model"] input')).toHaveCount(0)
    await text.locator('input').fill('qwen/qwen3-30b-a3b-instruct-2507')
    await expect(text.locator('[data-ai-changes]')).toContainText('Health repair: escalation model: qwen/qwen3-235b-a22b-2507 becomes qwen/qwen3-30b-a3b-instruct-2507')
    await expect(text.locator('[data-ai-confirm]')).toBeDisabled()
    await text.getByLabel('Reason: har.ai_escalation_model').fill('the cheaper model is enough')
    await text.locator('[data-ai-confirm]').click()
    await expect.poll(() => (page.l3calls || []).filter(c => c.toolsets === 'setting')).toEqual([{ toolsets: 'setting', args: { toolset: 'pipeline', key: 'har.ai_escalation_model', value: 'qwen/qwen3-30b-a3b-instruct-2507', reason: 'the cheaper model is enough' } }])
    // the ceiling is a setting of pane 1, out of its range it cannot be saved
    const ceil = page.locator('[data-ai-openrouter-settings] [data-ai-setting="pipeline.budgets.ai_daily_ceiling_usd"]')
    await ceil.locator('input').fill('9000')
    await expect(ceil).toContainText('Between 0 to 500')
    await expect(ceil.locator('[data-ai-confirm]')).toHaveCount(0)
  })

  for (const rank of [3, 4]) test(`rank ${rank} (${rank === 3 ? 'Curator' : 'Pipeline Operator'}) reads the whole page and can change nothing; each control says the role it needs`, async ({ page }) => {
    const { calls } = await open(page, {}, { rank })
    // read: health, model in effect, errors, budget and usage; the key only as present or absent; the credit in words
    await expect(page.locator('[data-ai-account-state]')).toBeVisible()
    await expect(page.locator('[data-ai-key]')).toContainText('Present')
    await expect(page.locator('[data-ai-key-readonly]')).toContainText('The key is present')
    await expect(page.locator('[data-ai-key-controls], [data-ai-page] input[type="password"]')).toHaveCount(0)
    await expect(page.locator('[data-ai-balance="words"]')).toContainText('Within budget')
    await expect(page.locator('[data-ai-ceiling]')).toContainText('US$9.27 of US$14.00')
    await expect(row(page, 'course_entry_requirements').locator('[data-ai-cascade]')).toHaveText('1 DeepSeek V3.2→2 Qwen3 30B')
    await expect(row(page, 'fee_reader').locator('[data-ai-state-pill]')).toHaveText('Held: cap reached')
    await expect(page.locator('[data-ai-usage="hour-service"] [data-ai-usage-row="fee_reader"]')).toContainText('US$5.02')
    // change: nothing, with the role named
    await expect(page.locator('[data-ai-pane="openrouter"] [data-ai-needs="6"]')).toContainText('needs Platform Admin')
    await expect(page.locator('[data-ai-pane="models"] [data-ai-needs="6"]')).toContainText('Allow or disallow a model: needs Platform Admin')
    await expect(page.locator('[data-ai-model="qwen3-30b"]').getByRole('switch')).toBeDisabled()
    await expect(row(page, 'course_description').getByRole('switch')).toBeDisabled()
    await row(page, 'fee_reader').locator('.aim-toggle').click()
    const d = detail(page, 'fee_reader')
    await expect(d.locator('[data-ai-edit]')).toHaveCount(0)
    await expect(d.locator('[data-ai-route] [data-ai-needs="5"]')).toContainText('Change the cascade, switch or cap: needs PIM Admin')
    await expect(d.locator('[data-ai-last-error]')).toContainText('Last error')
    await expect(d.locator('[data-ai-unqualified] [data-ai-needs="6"]').first()).toContainText('Record qualification: needs Platform Admin')
    await expect(d.locator('[data-ai-qualify]')).toHaveCount(0)
    await row(page, 'course_description').locator('.aim-toggle').click()
    await expect(detail(page, 'course_description').locator('[data-ai-setting] input')).toHaveCount(0)
    await expect(detail(page, 'course_description').locator('[data-ai-service-settings] [data-ai-needs="6"]')).toBeVisible()
    await expect(page.locator('[data-ai-page] input:not([disabled]), [data-ai-page] select:not([disabled])')).toHaveCount(0)
    expect(calls).toEqual([])
  })

  test('rank 5 (PIM Admin) changes a route, cap and switch; the model list, qualification, the ceiling and the key need the Platform Admin', async ({ page }) => {
    const { calls } = await open(page, {}, { rank: 5 })
    await expect(page.locator('[data-ai-model="qwen3-30b"]').getByRole('switch')).toBeDisabled()
    await expect(page.locator('[data-ai-pane="models"] [data-ai-needs="6"]')).toBeVisible()
    await expect(page.locator('[data-ai-key-controls]')).toHaveCount(0)
    await expect(page.locator('[data-ai-openrouter-settings] input')).toHaveCount(0) // the floor and the daily ceiling
    await row(page, 'course_entry_requirements').locator('.aim-toggle').click()
    const d = detail(page, 'course_entry_requirements')
    await expect(d.locator('[data-ai-setting] input')).toHaveCount(0)
    await expect(d.locator('[data-ai-qualify]')).toHaveCount(0)
    await d.locator('[data-ai-edit="course_entry_requirements"]').click()
    await d.getByLabel('Daily cap in US dollars for Course entry requirements').fill('4')
    await d.getByLabel('Reason: route-course_entry_requirements').fill('a little more room')
    await d.locator('[data-ai-confirm="route-course_entry_requirements"]').click()
    await expect(d.locator('[data-ai-saved]')).toContainText('Daily cap (US$): US$3.00 becomes US$4.00')
    expect(calls.map(c => c.name)).toEqual(['admin_ai_route_set_v1'])
  })

  test('rank 6 (Platform Admin) has every control: key, ceiling, model list, qualification, routes and settings', async ({ page }) => {
    await open(page, {}, { rank: 6 })
    await expect(page.locator('[data-ai-key-controls] input[type="password"]')).toBeEnabled()
    await expect(page.locator('[data-ai-key-controls]').getByRole('button', { name: 'Verify' })).toBeEnabled()
    await expect(page.locator('[data-ai-balance="figure"]')).toContainText('US$53.00')
    await expect(page.locator('[data-ai-balance-age]')).toHaveText(/^(\d+ min ago|\d+ h ago)$/) // the credit balance with its age
    await expect(page.locator('[data-ai-mode="stop"]')).toContainText('Enforcing')
    await expect(page.locator('[data-ai-mode="stop"]')).toContainText('always stop a service, Run now included')
    await expect(page.locator('[data-ai-openrouter-settings] [data-ai-setting="pipeline.budgets.ai_daily_ceiling_usd"] input')).toBeEnabled()
    await expect(page.locator('[data-ai-model="qwen3-30b"]').getByRole('switch')).toBeEnabled()
    await expect(page.locator('[data-ai-page] [data-ai-needs]')).toHaveCount(0)
    await row(page, 'course_entry_requirements').locator('.aim-toggle').click()
    await expect(detail(page, 'course_entry_requirements').locator('[data-ai-edit]')).toBeVisible()
    await expect(detail(page, 'course_entry_requirements').locator('[data-ai-setting] input')).toBeEnabled()
    await expect(detail(page, 'course_entry_requirements').locator('[data-ai-qualify]').first()).toBeVisible()
  })

  test('a cascade is shown as the worker runs it: one model where there is no fallback yet, read-only where the service is not migrated, and only qualified models can be added', async ({ page }) => {
    const { calls } = await open(page)
    // routed_single: exactly one model and the note
    const one = row(page, 'ops_diagnosis')
    await expect(one.locator('[data-ai-model-cell]')).toHaveAttribute('data-ai-migration', 'routed_single')
    await expect(one.locator('[data-ai-cascade-model]')).toHaveCount(1)
    await expect(one.locator('[data-ai-single]')).toHaveText('Fallback not available for this service yet')
    await one.locator('.aim-toggle').click()
    const od = detail(page, 'ops_diagnosis')
    await od.locator('[data-ai-edit="ops_diagnosis"]').click()
    await od.getByLabel('Model of Operations diagnosis').selectOption('mistral-small-3.2') // replaces, never adds a second
    await expect(od.locator('[data-ai-step]')).toHaveCount(1)
    await expect(od.locator('[data-ai-changes]')).toContainText('Cascade: 1 Qwen3 30B becomes 1 Mistral Small 3.2')
    await expect(od.locator('button[aria-label^="Move "]:visible')).toHaveCount(0)
    // not_migrated: a pill, the model in effect, nothing to change
    const nm = row(page, 'page_identity')
    await expect(nm.locator('[data-ai-not-migrated]')).toHaveText('Not migrated')
    await expect(nm.locator('[data-ai-model-cell]')).toContainText('Qwen3 30B')
    await expect(nm.locator('[data-ai-cascade-model]')).toHaveCount(0) // no numbered cascade is drawn for it
    await expect(nm.getByRole('switch')).toBeDisabled()
    await nm.locator('.aim-toggle').click()
    await expect(detail(page, 'page_identity').locator('[data-ai-edit]')).toHaveCount(0)
    await expect(detail(page, 'page_identity').locator('[data-ai-unwired]')).toContainText('Not migrated')
    // a provisional qualification is said, in amber, with its evidence; the model a service ran on before is a muted line
    await row(page, 'fee_reader').locator('.aim-toggle').click()
    await expect(detail(page, 'fee_reader').locator('[data-ai-qualified-model="qwen3-30b"][data-ai-provisional="true"]')).toContainText('Provisional: Platform Admin 13 Nov 19:09: regression qualification pending')
    await expect(detail(page, 'fee_reader').locator('[data-ai-qualified-model="qwen3-30b"]')).toHaveClass(/tone-warning/)
    await expect(row(page, 'fee_reader').locator('[data-ai-was-on]')).toHaveText('Was on: GPT-4.1 mini')
    await expect(row(page, 'course_description').locator('[data-ai-was-on]')).toHaveCount(0) // unchanged: nothing to say
    // routed: a model that is allowed but not qualified for the service cannot be added
    await row(page, 'course_description').locator('.aim-toggle').click()
    const cd = detail(page, 'course_description')
    await expect(cd.locator('[data-ai-unqualified-model="kimi-k2-0905"]')).toContainText('Kimi K2 (0905)')
    await cd.locator('[data-ai-edit="course_description"]').click()
    const add = cd.getByLabel('Add a model to Course description')
    await expect(add.locator('option:disabled', { hasText: 'Kimi K2 (0905) · Not qualified for this service' })).toHaveCount(1)
    await expect(add.locator('option:not(:disabled)', { hasText: 'Kimi K2' })).toHaveCount(0)
    await cd.getByRole('button', { name: 'Cancel' }).click()
    // the Platform Admin records a qualification with evidence and a reason; it adds the model to nothing
    await cd.locator('[data-ai-qualify="kimi-k2-0905"]').click()
    const bar = cd.locator('[data-ai-save="qualify-course_description-kimi-k2-0905"]')
    await expect(bar.locator('[data-ai-blocked]')).toContainText('Say what the qualification rests on (the evidence), in at least 10 characters')
    await cd.getByLabel('Evidence that Kimi K2 (0905) is qualified for Course description').fill('qualification run 41, 38 of 40 right')
    await bar.getByLabel(/^Reason:/).fill('passed the sample')
    await bar.locator('[data-ai-confirm]').click()
    await expect(cd.locator('[data-ai-saved]')).toContainText('Kimi K2 (0905) is recorded as qualified for Course description')
    expect(calls).toEqual([{ name: 'admin_ai_qualification_set_v1', p_service: 'course_description', p_code: 'kimi-k2-0905', p_evidence: 'qualification run 41, 38 of 40 right', p_reason: 'passed the sample', p_status: 'qualified' }])
    await expect(cd.locator('[data-ai-unqualified-model="kimi-k2-0905"]')).toHaveCount(0)
    await expect(row(page, 'course_description').locator('[data-ai-cascade-model]')).toHaveCount(1)
    await expect(page.locator('[data-ai-model="kimi-k2-0905"] [data-ai-qualified-for]')).toContainText('Course description')
  })

  test('each service shows the model it used most recently, its last outcome or error and its recovery; the per-call record shows tokens, failures and fallbacks', async ({ page }) => {
    await open(page)
    await expect(row(page, 'fee_reader').locator('[data-ai-last]')).toContainText('Last used: Mistral Small 3.2')
    await expect(row(page, 'fee_reader').locator('[data-ai-last]')).toContainText('Failed')
    await expect(row(page, 'provider_description').locator('[data-ai-last]')).toHaveText('Last used: not measured')
    await row(page, 'fee_reader').locator('.aim-toggle').click()
    const d = detail(page, 'fee_reader').locator('[data-ai-last-call]')
    await expect(d).toContainText('mistralai/mistral-small-3.2-24b-instruct')
    await expect(d.locator('[data-ai-last-error]')).toHaveText('Last error: the call timed out (attempt 2)')
    await expect(d.locator('[data-ai-recovery="held"]')).toContainText('Recovery: Held: nothing is handed out')
    await row(page, 'provider_description').locator('.aim-toggle').click()
    await expect(detail(page, 'provider_description').locator('[data-ai-recovery="no_calls"]')).toContainText('No call on record yet')
    // the spend ledger has usd and calls only: tokens, failures and fallbacks there are Not measured, never 0
    const u = page.locator('[data-ai-usage="hour-service"] [data-ai-usage-row="fee_reader"]')
    for (const col of ['Tokens', 'Failures', 'Fallbacks']) await expect(u.locator(`td[data-label="${col}"]`)).toHaveText('Not measured')
    // the per-call record carries them
    const c = page.locator('[data-ai-calls] [data-ai-calls-row="fee_reader:mistralai/mistral-small-3.2-24b-instruct"]')
    await expect(c.locator('td[data-label="Attempts"]')).toHaveText('6')
    await expect(c.locator('td[data-label="Failures"]')).toHaveText('1')
    await expect(c.locator('td[data-label="Fallbacks"]')).toHaveText('6')
    await expect(c.locator('td[data-label="Tokens in / out"]')).toHaveText('25,200 / 2,280')
    await expect(page.locator('[data-ai-calls] [data-ai-calls-row="course_description:qwen/qwen3-30b-a3b-instruct-2507"] td[data-label="Tokens in / out"]')).toHaveText('Not measured')
    await expect(page.locator('[data-ai-usage-evidence]')).toHaveCount(0) // the contract gives no evidence link yet
    await expect(page.locator('[data-ai-fallbacks] summary')).toContainText('Failed attempts in the last 24 hours (2)')
    await expect(page.locator('[data-ai-model="qwen3-30b"] [data-ai-model-spend]')).toContainText('US$')
    await expect(page.locator('[data-ai-model="kimi-k2-0905"] [data-ai-model-spend]')).toHaveText('none recorded')
  })

  test('Scholarship extraction is configured under the Scholarship pages service; Scholarships › Coverage keeps its results and links to it', async ({ page }) => {
    await open(page)
    await row(page, 'scholarship_extraction').locator('.aim-toggle').click()
    const cfg = detail(page, 'scholarship_extraction').locator('[data-ai-scholarship-config] [data-scholarship-extraction="config"]')
    await expect(detail(page, 'scholarship_extraction').locator('[data-ai-config-summary]')).toContainText('AI admission: Off. Instruction versions: 7 (current), 6')
    await expect(cfg.locator('[data-sx-admission]')).toContainText('AI admission')
    await expect(cfg.locator('[data-sx-models]')).toBeVisible()
    await expect(cfg.locator('[data-sx-sample-row]').first()).toBeVisible()
    await expect(cfg.locator('[data-sx-recent-row], [data-sx-action="backfill"], [data-sx-chain-editor], [data-sx-action^="activate-"]')).toHaveCount(0)
    await page.goto('/#scholarships?tab=coverage&at=sch-extraction')
    const res = page.locator('[data-fold="scholarship-extraction"] [data-scholarship-extraction="results"]')
    await expect(res.locator('[data-sx-recent-row]').first()).toBeVisible()
    await expect(res.locator('[data-sx-config-link] a')).toHaveAttribute('href', '#models-services?tab=ai&card=services.ai.services&at=services.ai.services&service=scholarship_extraction')
    // no second set of controls: the switch, models, sample and instructions are not drawn here
    await expect(res.locator('[data-sx-admission], [data-sx-models], [data-sx-sample-row], [data-sx-action="admission-on"], [data-sx-action="admission-off"]')).toHaveCount(0)
  })

  test('at the daily ceiling the account says so and the services read Held: ceiling', async ({ page }) => {
    const { state } = await mockAiAt(page)
    expect(state.overview.openrouter.spent_today_usd).toBe(14.2)
    await expect(page.locator('[data-ai-account-state="ceiling"]')).toContainText('Held: today\'s ceiling reached')
    await expect(row(page, 'course_description').locator('[data-ai-state-pill]')).toHaveText('Held: ceiling')
    await expect(row(page, 'entry_requirements_v2_shadow').locator('[data-ai-state-pill]')).toHaveText('Off')
    await expect(row(page, 'course_description')).toContainText('Work asked for under an open request is still let through')
    await expect(row(page, 'course_description').locator('[data-ai-would-hold]')).toHaveCount(0) // it is held: nothing is "would be"
  })

  test('observing: limits are reported, not enforced. A service over its cap or the ceiling runs and says "Would be held"; what always holds still holds', async ({ page }) => {
    const base = (await import('./support/ai-overview-fixture.mjs')).aiOverview().openrouter
    await open(page, { mode: 'observe', openrouter: { ...base, mode: 'observe', spent_today_usd: 14.2 } })
    await expect(page.locator('[data-ai-mode="observe"]')).toContainText('Observing: limits are reported, not enforced')
    await expect(page.locator('[data-ai-account-state="ceiling_observed"]')).toContainText('nothing is held by it')
    const r = row(page, 'course_description')
    await expect(r.locator('[data-ai-state-pill]')).toHaveText('Running')
    await expect(r.locator('[data-ai-would-hold="ceiling"]')).toContainText('Would be held')
    await expect(r.locator('[data-ai-would-hold="ceiling"]')).toContainText('Limits are observed, not enforced, so it runs')
    await expect(page.locator('[data-ai-caps-exceed]')).toContainText('the ceiling would stop work first if limits were enforced')
    // off and no model hold in both modes
    await expect(row(page, 'entry_requirements_v2_shadow').locator('[data-ai-state-pill]')).toHaveText('Off')
    await expect(row(page, 'entry_matrices').locator('[data-ai-state-pill]')).toHaveText('No allowed model')
    await expect(row(page, 'entry_matrices').locator('[data-ai-would-hold]')).toHaveCount(0)
  })

  test('the credit floor stops everything (Held: no credit); a balance that is not measured or too old holds everything too; caps over the ceiling are said plainly', async ({ page }) => {
    const base = (await import('./support/ai-overview-fixture.mjs')).aiOverview().openrouter
    await open(page, { openrouter: { ...base, balance_usd: 0.4 } })
    await expect(page.locator('[data-ai-account-state="no_credit"]')).toContainText('No credit')
    await expect(page.locator('[data-ai-account-state="no_credit"]')).toContainText('including Run now')
    await expect(row(page, 'course_description').locator('[data-ai-state-pill]')).toHaveText('Held: no credit')
    await expect(row(page, 'course_description')).not.toContainText('still let through') // the floor holds on-demand work too
    await expect(row(page, 'entry_matrices').locator('[data-ai-state-pill]')).toHaveText('No allowed model')
    // the fixture's caps (US$35.00 for the services that are on) are over the US$14.00 ceiling
    await expect(page.locator('[data-ai-caps-exceed]')).toContainText('Service caps add up to US$35.00 a day, more than the US$14.00 ceiling: the ceiling will stop work first.')
    // no balance reading: fail closed. Every service is held; the balance is "not measured", never a figure and never "no credit"
    await page.route(/\/rest\/v1\/rpc\/admin_ai_overview_v1$/, async r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify((await import('./support/ai-overview-fixture.mjs')).aiOverview({ openrouter: { ...base, balance_usd: null, balance_observed_at: null, balance_known: false, balance_note: 'No balance has been read.' } })) }))
    await page.reload()
    await expect(page.locator('[data-ai-account-state="unread"]')).toContainText('Held: balance not measured')
    await expect(page.locator('[data-ai-account-state="unread"]')).toContainText('including Run now')
    await expect(page.locator('[data-ai-balance]')).toContainText('Balance not measured')
    await expect(page.locator('[data-ai-balance]')).not.toContainText('US$0')
    await expect(row(page, 'course_description').locator('[data-ai-state-pill]')).toHaveText('Held: balance not measured')
    // a reading older than the allowed age: held too
    await page.route(/\/rest\/v1\/rpc\/admin_ai_overview_v1$/, async r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify((await import('./support/ai-overview-fixture.mjs')).aiOverview({ openrouter: { ...base, balance_observed_at: new Date(Date.now() - 4 * 3600e3).toISOString() } })) }))
    await page.reload()
    await expect(page.locator('[data-ai-account-state="stale"]')).toContainText('Held: balance reading too old')
    await expect(row(page, 'course_description').locator('[data-ai-state-pill]')).toHaveText('Held: balance reading too old')
  })

  test('Settings no longer lists the AI settings, points to Models & services, and draws a text setting as a text box', async ({ page }) => {
    await mockAdmin(page, { rank: 6 }); await mockAi(page)
    const set = (key, label, o = {}) => ({ key, label, help: 'help', used_by: 'a job', kind: 'number', value: 10, min: 1, max: 500, unit: 'items', updated_at: '2026-11-08T22:00:00Z', reason: 'set', ...o })
    const register = { can_manage: true, jobs: 61, check: [], sections: [
      { section: 'Job sizes', settings: [set('batch.job_1', 'Job 1 size'), set('enrich.ai_calls_at_once', 'AI calls at once', { home: 'models_services', home_group: 'course_other_fields' }), set('entry.course_page_chars', 'Entry page characters', { home: 'models_services' }),
        set('reading.fresh_marker', 'Marker read on a fresh page', { kind: 'text', value: 'updated', min: 0, max: 0, unit: null }), set('har.ai_escalation_model', 'Health repair: escalation model', { kind: 'text', value: 'qwen/qwen3-235b-a22b-2507', min: 0, max: 0, unit: null, home: 'models_services', home_group: 'ops_diagnosis' })] },
      { section: 'Admission checks', settings: [set('only.marked_by_home', 'Marked by its home only', { home: 'models_services' })] }] }
    let overviewCalls = 0
    page.on('request', q => { if (/rpc\/admin_ai_overview_v1$/.test(q.url())) overviewCalls++ })
    await page.route(/\/rest\/v1\/rpc\/admin_settings_register_read$/, r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(register) }))
    await openCards(page, ['settings.register.job-sizes'])
    await page.goto('/#environment')
    const reg = page.locator('[data-settings-register]').last()
    await expect(reg.locator('[data-register-setting="batch.job_1"]')).toBeVisible({ timeout: 30_000 })
    // the one line, with its link
    const moved = reg.locator('[data-ai-settings-moved] a')
    await expect(moved).toHaveText('AI models, prompts, caps and the OpenRouter key are in Models & services')
    await expect(moved).toHaveAttribute('href', '#models-services?tab=ai')
    // marked home = models_services by the settings read: not listed here (no second call is made for it); a section left empty is not drawn
    for (const k of ['enrich.ai_calls_at_once', 'entry.course_page_chars', 'har.ai_escalation_model', 'only.marked_by_home']) await expect(reg.locator(`[data-register-setting="${k}"]`)).toHaveCount(0)
    await expect(reg.locator('[data-register-section="Admission checks"]')).toHaveCount(0)
    await expect(reg.locator('[data-register-section="Job sizes"]')).toContainText('2 settings')
    expect(overviewCalls, 'Settings does not read the AI overview').toBe(0)
    // every other setting stays, and a text setting is a text box with no number range
    const text = reg.locator('[data-register-setting="reading.fresh_marker"]')
    await expect(text.locator('input[data-setting-kind="text"]')).toHaveAttribute('type', 'text')
    await expect(text.locator('input[data-setting-kind="text"]')).toHaveValue('updated')
    await text.locator('input[data-setting-kind="text"]').fill('last updated')
    await expect(text).not.toContainText('Between')
    await text.getByPlaceholder('Reason (kept in the log)').fill('the page words changed')
    await text.getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => (page.l3calls || []).filter(c => c.toolsets === 'setting')).toEqual([{ toolsets: 'setting', args: { toolset: 'pipeline', key: 'reading.fresh_marker', value: 'last updated', reason: 'the page words changed' } }])
    // the same settings are on the page they moved to
    await moved.click()
    await expect(page.locator('[data-ai-page="ready"]')).toBeVisible()
    await expect(page.locator('[data-ai-services]')).toBeVisible()
    await row(page, 'course_other_fields').locator('.aim-toggle').click()
    await expect(detail(page, 'course_other_fields').locator('[data-ai-setting="pipeline.enrich.ai_calls_at_once"]')).toBeVisible()
  })

  test('old addresses open the new page, and the pages that use a model link to it', async ({ page }) => {
    await mockAdmin(page, { rank: 6 }); await mockAi(page)
    // the old OpenRouter toolset card (the notices' Go to link) and the old AI uses card
    await page.goto('/#models-services?card=services.toolsets,services.toolset.openrouter&at=services.toolset.openrouter')
    await expect(page.locator('[data-ai-page="ready"]')).toBeVisible({ timeout: 30_000 })
    await expect(page).toHaveURL(/#models-services\?tab=ai&card=services\.ai\.openrouter&at=services\.ai\.openrouter$/)
    await expect(page.locator('[data-card="services.ai.openrouter"]')).toHaveAttribute('data-card-open', 'true') // the card that replaced it is opened
    await expect(page.locator('[data-ai-account-state]')).toBeVisible()
    await page.goto('/#models-services?tab=ai&card=services.ai.uses')
    await expect(page).toHaveURL(/#models-services\?tab=ai&card=services\.ai\.services&at=services\.ai\.services$/)
    await expect(page.locator('[data-ai-services]')).toBeVisible()
    // Services & limits: the OpenRouter card only points to the AI tab
    await page.goto('/#models-services')
    const card = page.locator('[data-service-card="openrouter"]')
    await expect(card.locator('[data-ai-moved="openrouter"] a')).toHaveAttribute('href', '#models-services?tab=ai')
    await expect(card.locator('[data-toolset="openrouter"], [data-openrouter]')).toHaveCount(0)
    // the old Scholarships › Extraction address opens the configuration under the Scholarship pages service; it names its model with a link
    // and no longer sets the order or makes a model active (the cascade of the service does)
    await page.goto('/#scholarships?tab=extraction')
    await expect(page).toHaveURL(/#models-services\?tab=ai&card=services\.ai\.services&at=services\.ai\.services&service=scholarship_extraction$/)
    await expect(page.locator('[data-ai-scholarship-config] [data-scholarship-extraction="config"]')).toBeVisible()
    await expect(page.locator('[data-model-line="scholarship"]')).toContainText('Model:')
    await expect(page.locator('[data-model-line="scholarship"] a')).toHaveAttribute('href', /#models-services\?tab=ai&card=services\.ai\.services/)
    await expect(page.locator('[data-sx-chain-editor], [data-sx-action^="activate-"]')).toHaveCount(0)
    await expect(page.locator('[data-sx-action^="qualify-"]').first()).toBeVisible()
  })
})

async function mockAiAt(page) {
  await mockAdmin(page, { rank: 6 })
  const base = (await import('./support/ai-overview-fixture.mjs')).aiOverview().openrouter
  const ai = await mockAi(page, { openrouter: { ...base, spent_today_usd: 14.2 } })
  await page.goto('/#models-services?tab=ai')
  await expect(page.locator('[data-ai-page="ready"]')).toBeVisible({ timeout: 30_000 })
  return ai
}

test.describe('Models & services › AI, source and address map', () => {
  test('the address map: one AI tab, the retired cards redirect, Scholarship extraction opens under the Scholarship pages service', () => {
    const tabs = PAGES.services.tabs.map(t => [t.key, t.label, t.min])
    expect(tabs).toEqual([['services', 'Services & limits', 4], ['ai', 'AI', 3]]) // Curator and above read the AI tab
    for (const [card, pane] of Object.entries(RETIRED_AI_CARDS)) {
      const r = resolveTarget('models-services', new URLSearchParams({ card }))
      expect([r.page, r.tab, r.params.get('at'), r.params.get('card')], card).toEqual(['services', 'ai', pane, pane])
      const a = resolveTarget('models-services', new URLSearchParams({ tab: 'services', at: card }))
      expect([a.page, a.tab, a.params.get('at')], `${card} as at`).toEqual(['services', 'ai', pane])
    }
    expect(resolveTarget('models-services', new URLSearchParams({ card: 'services.ai.provider-description-prompt' })).params.get('service')).toBe('provider_description')
    // a card that is not retired is left alone
    const fc = resolveTarget('models-services', new URLSearchParams({ card: 'services.toolset.firecrawl', at: 'firecrawl:Daily budget' }))
    expect([fc.page, fc.tab, fc.params.get('card')]).toEqual(['services', '', 'services.toolset.firecrawl'])
    // older addresses that led to the old AI screens
    expect(resolveTarget('layer-3-ai', new URLSearchParams({ tab: 'models' })).page).toBe('services')
    const sx = resolveTarget('scholarships', new URLSearchParams({ tab: 'extraction' }))
    expect([sx.page, sx.tab, sx.params.get('service')]).toEqual(['services', 'ai', 'scholarship_extraction'])
    expect(PAGES.scholarships.tabs.map(t => t.key)).toEqual(['list', 'coverage']) // no tab was added: the menu keeps its count
  })

  test('the old AI screens are gone from the source, and the page writes only through the contract\'s calls', () => {
    expect(fs.existsSync('src/AiConfig.jsx')).toBe(false)
    const shell = fs.readFileSync('src/mature-main.jsx', 'utf8')
    expect(shell).not.toMatch(/import\('\.\/AiConfig'\)|<AiConfig|part="models"|<ProviderDescriptionPrompt|only=\{\['openrouter'\]\}/)
    expect(shell).toContain("tab==='ai'?<AiModelsServices")
    const ms = fs.readFileSync('src/ModelsServices.jsx', 'utf8')
    expect(ms).not.toMatch(/services\.ai-models|admin_services_control',\{p_kind:kind/)
    expect(fs.readFileSync('src/Toolsets.jsx', 'utf8')).not.toMatch(/function OpenRouter\(|data-openrouter/)
    expect(fs.readFileSync('src/ScholarshipExtraction.jsx', 'utf8')).not.toContain('ScholarshipAiModels')
    const pageSrc = fs.readFileSync('src/AiModelsServices.jsx', 'utf8')
    const rpcs = [...new Set([...pageSrc.matchAll(/rpc\('([a-z0-9_]+)'/g)].map(m => m[1]))].sort()
    expect(rpcs).toEqual(['admin_ai_overview_v1', 'admin_toolsets_write']) // the key's profile id comes with the overview
    expect(pageSrc).toMatch(/act\('admin_ai_model_set_v1'/); expect(pageSrc).toMatch(/act\('admin_ai_route_set_v1'/)
    expect(pageSrc).not.toMatch(/window\.(prompt|confirm)\(/) // a reason is typed on the page, beside what changes
    expect(pageSrc).not.toMatch(/\?\?\s*'—'|\|\|\s*'—'/) // no dash stands in for a model or a figure
  })
})
