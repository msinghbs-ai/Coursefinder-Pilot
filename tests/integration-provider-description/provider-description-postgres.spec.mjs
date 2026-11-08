// Guards: Provider description autonomy mandate (4 November 2026): real PostgreSQL evidence, governed run recovery, Layer 4 admission and mobile publication inspection.
import { test, expect } from '@playwright/test'
import { sql, quote } from '../fixtures/provider-description-autonomy/db.mjs'

const service = 'http://127.0.0.1:55435'
const rpcPath = '/rest/v1/rpc/admin_provider_description_run_v1'

async function rpc(request, action, args = {}, rank = 6) {
  return request.post(service + rpcPath, {
    headers: { 'x-fixture-rank': String(rank) },
    data: { p_action: action, p_args: args },
  })
}

async function read(request, action, args = {}, rank = 6) {
  const response = await rpc(request, action, args, rank)
  expect(response.ok(), await response.text()).toBe(true)
  return response.json()
}

// A retry must start where the first attempt started. The first attempt saves the one eligible cohort, so without this the retry meets a
// disabled Save button and reports that, not the failure that made it a retry (PR #916, 8 Nov 2026). Failures are still reported.
test.beforeEach(async ({ request }, testInfo) => {
  if (testInfo.retry === 0) return
  const response = await request.post(service + '/fixture/reset', { data: {} })
  expect(response.ok(), await response.text()).toBe(true)
})

async function mount(page, { rank = 6, interrupt } = {}) {
  // Avoid loading unrelated application workspaces. The actual production card,
  // shared styles and its unmodified RPC adapter are imported below.
  await page.goto('/tests/fixtures/provider-description-autonomy/browser.html')
  await page.route('https://example.supabase.co/rest/v1/rpc/**', async route => {
    const body = route.request().postDataJSON()
    // Only the HTTP transport is adapted. The actual new RPC executes as an
    // authenticated controlled identity in isolated PostgreSQL with live limits.
    const response = await page.request.post(service + new URL(route.request().url()).pathname, {
      headers: { 'x-fixture-rank': String(rank) }, data: body,
    })
    if (body.p_action === 'run' && interrupt && !interrupt.committed) {
      expect(response.ok(), await response.text()).toBe(true)
      interrupt.result = await response.json()
      interrupt.committed = true
      await route.abort('failed') // The database committed; only the response is lost.
    } else {
      await route.fulfill({ response })
    }
  })
  await page.evaluate(async rank => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const ReactDOM = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { ProviderDescriptions: Component } = await import('/src/FieldCoverage.jsx')
    document.body.innerHTML = '<main id="provider-description-db-root" style="max-width:1200px;margin:0 auto;padding:16px"></main>'
    ReactDOM.createRoot(document.getElementById('provider-description-db-root')).render(React.createElement(Component, { rank }))
  }, rank)
  await expect(page.getByRole('heading', { name: 'Provider Descriptions — Run & Validate', exact: true })).toBeVisible()
  await expect(page.locator('[data-pdesc-switch]')).toHaveText('Reader on')
  const toggle = page.locator('[data-card="coverage.provider-descriptions"] .cf-card-toggle')
  if ((await toggle.getAttribute('aria-expanded')) !== 'true') await toggle.click()
  await expect(page.locator('[data-provider-description-run-validate]')).toBeVisible()
  await expect(page.getByRole('group', { name: 'Provider scope' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Refresh saved results', exact: true })).toBeEnabled()
}

async function screenshot(page, testInfo, name) {
  const file = testInfo.outputPath(name)
  await page.screenshot({ path: file, fullPage: true })
  await testInfo.attach('Actual PostgreSQL provider-description workflow', { path: file, contentType: 'image/png' })
}

test('operator runs a fixed cohort, recovers its committed request, then inspects the authorised admission and publication', async ({ page }, testInfo) => {
  const capabilities = await read(page.request, 'capabilities')
  const provider = capabilities.providers.find(p => /browser/i.test(`${p.stable_key || ''} ${p.name || ''} ${p.provider || ''}`))
  expect(provider, 'SQL seed must retain a distinct eligible browser provider').toBeTruthy()
  const interrupt = {}
  await mount(page, { interrupt })
  const fresh = page.getByRole('button', { name: 'New cohort', exact: true })
  if (await fresh.count()) await fresh.click()
  await page.getByLabel('Description country').selectOption(provider.country)
  await page.getByLabel('Description provider type').selectOption(provider.type || provider.provider_type)
  await page.getByLabel('Description provider selection').selectOption('provider')
  await page.getByLabel('Individual description provider').selectOption(provider.provider_id)
  await page.getByLabel('Description cohort size').fill(String(capabilities.max_size + 1))
  await expect(page.getByRole('button', { name: 'Preview providers', exact: true })).toBeDisabled()
  await page.getByLabel('Description cohort size').fill('1')
  await page.getByRole('button', { name: 'Preview providers', exact: true }).click()
  await expect(page.locator('[data-pdesc-provider]')).toHaveCount(1)
  await expect(page.locator(`[data-pdesc-provider="${provider.provider_id}"]`)).toBeVisible()
  await mount(page, { interrupt })
  await expect(page.locator('[data-pdesc-provider]')).toHaveCount(1)
  await expect(page.getByLabel('Individual description provider')).toHaveValue(provider.provider_id)
  await expect(page.getByRole('button', { name: 'Save previewed cohort', exact: true })).toBeDisabled()
  await page.getByLabel('Provider description audit reason').fill('Isolated browser acceptance of stored official provider evidence')
  await page.getByRole('button', { name: 'Save previewed cohort', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Run Now', exact: true })).toBeEnabled()
  const cohortId = await page.getByLabel('Existing provider description cohort ID').inputValue()
  expect(cohortId).toMatch(/^[0-9a-f-]{36}$/)
  await page.getByRole('button', { name: 'Run Now', exact: true }).click()
  await expect(page.getByText(/Outcome unknown\. Recover this saved cohort/)).toBeVisible()
  expect(interrupt.committed).toBe(true)
  await page.getByRole('button', { name: 'Recover saved cohort', exact: true }).click()
  await expect(page.getByText('Recovered the saved cohort and its existing run references.', { exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Run Now', exact: true })).toBeDisabled()
  let saved = await read(page.request, 'saved', { cohort_id: cohortId })
  expect(saved.cohort_id).toBe(cohortId)
  expect(saved.runs).toHaveLength(1)
  const runId = saved.runs[0].run_id || saved.runs[0].id
  expect(runId).toBeTruthy()
  // An identical request returns that saved task rather than dispatching twice.
  await read(page.request, 'run', { cohort_id: cohortId })
  saved = await read(page.request, 'saved', { cohort_id: cohortId })
  expect(saved.runs).toHaveLength(1)
  expect(saved.runs[0].run_id || saved.runs[0].id).toBe(runId)
  expect(Number(sql(`select count(*) from pipeline.admin_jobs where args->>'cohort_id'=${quote(cohortId)};`, { role: 'postgres' }))).toBe(1)
  expect(Number(sql(`select count(*) from pipeline.provider_description_cohort_members where cohort_id=${quote(cohortId)}::uuid;`, { role: 'postgres' }))).toBe(1)
  expect(Number(sql(`select count(*) from pipeline.provider_description_reads where provider_id=${quote(provider.provider_id)}::uuid;`, { role: 'postgres' }))).toBe(1)

  const processed = await page.request.post(service + '/fixture/process', { data: { cohort_id: cohortId } })
  expect(processed.ok(), await processed.text()).toBe(true)
  await page.getByRole('button', { name: 'Refresh saved results', exact: true }).click()
  const decision = page.getByRole('link', { name: /^Open Layer 4 decision / })
  await expect(decision).toHaveCount(1)
  const decisionUrl = await decision.getAttribute('href')
  const decisionParams = new URLSearchParams(decisionUrl.split('?')[1])
  expect(decisionUrl).toMatch(/^#layer-4-review/)
  expect(decisionParams.get('kind')).toBe('provider_description')
  expect(decisionParams.get('ref')).toMatch(/^[0-9a-f-]{36}$/)
  saved = await read(page.request, 'saved', { cohort_id: cohortId })
  expect(decisionParams.get('review_at')).toBe(saved.providers[0].review_created_at)
  expect(decisionParams.get('review_at')).toMatch(/^\d{4}-\d{2}-\d{2}T/)
  expect(saved.totals.admitted).toBe(0)
  expect(saved.totals.human_decisions_required).toBe(1)
  // This endpoint exists only in the loopback fixture server and calls the real
  // authorised Layer 4 decision function as its controlled reviewer identity.
  const approved = await page.request.post(service + '/fixture/approve', { data: { cohort_id: cohortId } })
  expect(approved.ok(), await approved.text()).toBe(true)
  // Integration Controller decision 5 Nov 2026 (item 3): the existing website-sync-check job (every minute, live function copied into the
  // fixture) is the only writer of the Website/Zoho feed. Run one provider pass of it, as production would within a minute of the approval.
  sql(`update pipeline.website_sync_scan set done=(entity<>'provider'),after_key=null;select security.website_sync_check_v1(security.pipeline_num_v1('batch.website_sync_check', 600)::int);`, { role: 'postgres' })
  await page.getByRole('button', { name: 'Verify catalogue & publication', exact: true }).click()
  saved = await read(page.request, 'saved', { cohort_id: cohortId })
  expect(saved.totals.admitted).toBe(1)
  expect(saved.totals.website_verified).toBe(1)
  expect(saved.totals.zoho_verified ?? saved.zoho_verified).toBe(1)
  expect(saved.totals.cost_usd).toBeGreaterThan(0)
  expect(Number(sql(`select sum(tries) from pipeline.provider_description_reads where provider_id=${quote(provider.provider_id)}::uuid;`, { role: 'postgres' }))).toBe(1)
  const card = page.locator(`[data-pdesc-provider="${provider.provider_id}"]`)
  await card.getByText('Official source and supporting evidence', { exact: true }).click()
  await expect(card.locator('blockquote').first()).toBeVisible()
  await card.getByText('Catalogue / Website / Zoho read-back', { exact: true }).click()
  const publication = card.locator('details').filter({ has: page.getByText('Catalogue / Website / Zoho read-back', { exact: true }) })
  await expect(publication.locator('dd').nth(0)).toHaveText('verified')
  await expect(publication.locator('dd').nth(1)).toHaveText('verified')
  await expect(publication.locator('dd').nth(2)).toHaveText('verified')
  await page.getByLabel('Evidence explanation audit reason').fill('Inspect the official evidence and saved claim validation')
  await card.getByRole('button', { name: /^(AI-assisted )?Explain [Ee]vidence$/ }).click()
  await expect(card.getByText('Evidence explanation', { exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Refresh saved results', exact: true })).toBeEnabled()

  await page.reload()
  // Remount uses the same production component and its default saved() request.
  await mount(page)
  await expect(page.getByLabel('Existing provider description cohort ID')).toHaveValue(cohortId)
  await expect(page.getByText(runId, { exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Run Now', exact: true })).toBeDisabled()
  await expect(page.locator(`[data-pdesc-provider="${provider.provider_id}"]`)).toBeVisible()
  await expect(page.getByText('Evidence explanation', { exact: true })).toBeVisible()
  const restored = page.locator(`[data-pdesc-provider="${provider.provider_id}"]`)
  await restored.getByText('Official source and supporting evidence', { exact: true }).click()
  await restored.getByText('Catalogue / Website / Zoho read-back', { exact: true }).click()
  await expect(page.getByRole('button', { name: 'Refresh saved results', exact: true })).toBeEnabled()
  await screenshot(page, testInfo, 'provider-description-database-desktop.png')
})

test('database permissions refuse a read-only operator and the same role cannot save or run through the screen', async ({ page }) => {
  await mount(page, { rank: 3 })
  const fresh = page.getByRole('button', { name: 'New cohort', exact: true })
  if (await fresh.count()) await fresh.click()
  await page.getByRole('button', { name: 'Preview providers', exact: true }).click()
  await page.getByLabel('Provider description audit reason').fill('Read-only user is refused by service authority')
  await expect(page.getByRole('button', { name: 'Save previewed cohort', exact: true })).toBeDisabled()
  await expect(page.getByText(/Your role can inspect evidence and refresh saved results/)).toBeVisible()
  for (const action of ['prepare', 'run']) {
    const refused = await rpc(page.request, action, { preview_token: 'untrusted', reason: 'Refuse unauthorised browser caller', cohort_id: '90000000-0000-0000-0000-000000000000' }, 3)
    expect(refused.ok()).toBe(false)
    expect((await refused.json()).message).toMatch(/authoris|permission|rank|role|operator|denied/i)
  }
})

test('saved evidence, review links and publication remain inspectable on a phone @responsive', async ({ page }, testInfo) => {
  expect(page.viewportSize().width).toBeLessThanOrEqual(480)
  const cohortId = sql("select c.id::text from pipeline.provider_description_cohorts c where c.state<>'preview' and c.run_id is not null and exists(select 1 from pipeline.provider_description_cohort_members m join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and r.state='admitted') order by c.created_at desc,c.id desc limit 1;", { role: 'postgres' })
  expect(cohortId).toMatch(/^[0-9a-f-]{36}$/)
  await mount(page)
  // A newer saved preview may exist; an operator can still recover the actual
  // completed run by its durable reference on a phone.
  const recovery = page.locator('details.pdesc-history').filter({ has: page.getByText('Saved runs and recovery', { exact: true }) })
  if (!(await recovery.evaluate(el => el.open))) await recovery.getByText('Saved runs and recovery', { exact: true }).click()
  await page.getByLabel('Existing provider description cohort ID').fill(cohortId)
  await page.getByRole('button', { name: 'Recover saved cohort', exact: true }).click()
  await expect(page.getByRole('region', { name: 'Saved provider description cohort' })).toBeVisible()
  await expect(page.locator('[data-pdesc-provider]').first()).toBeVisible()
  await expect(page.getByRole('button', { name: 'Run Now', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Verify catalogue & publication', exact: true })).toBeEnabled()
  await page.getByRole('button', { name: 'Refresh saved results', exact: true }).click()
  await expect(page.getByText('Saved results refreshed.', { exact: true })).toBeVisible()
  await expect(page.getByLabel('Existing provider description cohort ID')).toHaveValue(cohortId)
  const first = page.locator('[data-pdesc-provider]').first()
  await first.getByText('Official source and supporting evidence', { exact: true }).click()
  await first.getByText('Catalogue / Website / Zoho read-back', { exact: true }).click()
  await expect(first.getByRole('link', { name: /^Open Layer 4 decision / })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await screenshot(page, testInfo, 'provider-description-database-phone.png')
})
