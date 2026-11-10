// Guards: Platform Admin decision 10 Nov 2026 19:47 (one primary outcome action, "Read / refresh entry requirements now", for academic entry requirements; F-AER.01-.06) and F-AER.04 (a packet awaiting a person is never called published or active): the action and its stage timeline show in the AER workspace and the Course detail blade, every outcome is in its own words, a second click starts nothing, a role below Platform Admin sees what would happen but cannot start it, and the Data Delivery aer stream shows reviewer-ready packets apart from approved rows.
// Desktop project (chromium-desktop) except the phone test. Mocked admin; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'
import * as F from './support/admin-fixtures.mjs'

const RPC = 'https://example.supabase.co/rest/v1/rpc/'
const PROVIDER = { id: 'p-rmit', name: 'RMIT University (RMIT)', country: 'AU' }
const stages = (over = {}) => [
  { key: 'source_found', label: 'Source found', state: 'done', n: 2, unit: 'entry source', detail: '2 entry source(s), 2 with a stored copy; 40 bound course page(s) stored; last read 09 Nov 2026 14:00' },
  { key: 'parsed', label: 'AI parsed candidates', state: 'done', n: 36, unit: 'candidate row', detail: '36 candidate row(s) waiting (30 university table, 6 course); 8 read(s) done. Candidates are not admissions.' },
  { key: 'packet', label: 'Complete reviewer packet', state: 'done', n: 2, unit: 'packet', detail: '2 complete (30 of 36 rows state every fact; 6 have a fact not stated, flagged for the reviewer); 1 held by the completeness gate, 0 need input, 0 not checked yet.' },
  { key: 'human', label: 'Awaiting a person in Layer 4', state: 'waiting', n: 2, unit: 'decision', detail: '2 packet(s) ready for a person to decide; 0 approved and 0 rejected to date. Nothing is active until a person approves.' },
  { key: 'active', label: 'Approved and active', state: 'done', n: 663, unit: 'active row', detail: '663 university table row(s) and 0 course row(s) are active canonical rows.' },
  { key: 'consumer', label: 'Visible to the website', state: 'unknown', n: null, unit: null, detail: 'Not measured for one provider here. Active rows reach the website when the provider is published.' },
  ...[]].map(s => ({ ...s, ...(over[s.key] || {}) }))
const status = (outcome, extra = {}) => ({ known: true, scope: 'provider', can_run: true, provider: PROVIDER, course: null, stages: stages(), will_do: [], blocks: [], last_request: null,
  facts: { rows_in_reviewer_ready_packets: 36, rows_every_fact_stated: 30, rows_with_a_fact_not_stated: 6, not_stated: { year: 5, scale: 1 } }, next_scheduled_read: '2026-11-10T04:13:00Z',
  outcome: { outcome, reason: 'x', text: `text for ${outcome}`, next_action: 'next for ' + outcome }, ...extra })

async function mock(page, { rank = 6, st, onRun } = {}) {
  await mockAdmin(page, { rank })
  const calls = []; page.arnCalls = calls
  let current = st || status('queued')
  await page.route(`${RPC}admin_aer`, async route => {
    const b = route.request().postDataJSON() || {}, a = b.p_args || {}
    const j = json => route.fulfill({ json })
    if (b.p_action === 'summary') return j({ matrix: { active: 663, proposed: 30, unverified: 0, inactive: 0, superseded: 0 }, course: { proposed: 6 }, sources: { total: 2, held: 0, fetch_failed: 0, reading: 0, read: 2 }, courses_with_active: 0, courses_waiting: 40, can_edit: true, can_reread: rank >= 6 })
    if (b.p_action === 'options') return j({ providers: [{ id: 'p-rmit', name: PROVIDER.name }], countries: [], all_countries: [], levels: [], level_labels: [], bands: [], editions: [], intake_years: [], matrix_kinds: [], requirement_kinds: [], scales: [], audiences: [], statuses: [] })
    if (['matrix_list', 'course_list', 'sources_list'].includes(b.p_action)) return j({ total: 0, offset: 0, page_size: 50, rows: [], can_reread: rank >= 6, ai_allowed: true })
    return j({})
  })
  await page.route(`${RPC}admin_aer_read_now`, async route => {
    const a = (route.request().postDataJSON() || {}).p_args || {}
    calls.push(a)
    if (a.action === 'run') {
      const r = onRun ? onRun(a) : { outcome: 'queued', reason: 'work_started', text: 'Starting 4 read(s)', started: [1, 2, 3, 4], skipped: [], can_run: true, event: 7 }
      if (r.outcome === 'queued') current = status('in_progress', { last_request: { at: '2026-11-10T08:30:00Z', outcome: 'queued', by: 'u1' } })
      return route.fulfill({ json: r })
    }
    return route.fulfill({ json: { ...current, can_run: rank >= 6 } })
  })
  await page.route(`${RPC}admin_entry_requirements`, async route => {
    const b = route.request().postDataJSON() || {}
    if (b.p_action === 'course') return route.fulfill({ json: { rows: [], reads: [], can_read: true, countries: [] } })
    return route.fulfill({ json: {} })
  })
  return calls
}

test.describe('mocked browser', () => {
  test('AER workspace: one primary action, the stage timeline, a second click starts nothing, the run is asked once with its reason', async ({ page }) => {
    const calls = await mock(page)
    await page.goto('/#entry-requirements?provider=p-rmit')
    const box = page.locator('[data-aer-read-now="provider"]')
    await expect(box).toBeVisible({ timeout: 20_000 })
    await expect(box.locator('[data-arn-outcome="queued"]')).toContainText('Ready to start')
    // the six stages, each with its own words
    await expect(box.locator('[data-arn-stage]')).toHaveCount(6)
    await expect(box.locator('[data-arn-stage="source_found"]')).toContainText('Source found')
    await expect(box.locator('[data-arn-stage="parsed"]')).toContainText('AI parsed candidates')
    await expect(box.locator('[data-arn-stage="packet"]')).toContainText('Complete reviewer packet')
    await expect(box.locator('[data-arn-stage="human"]')).toContainText('Awaiting a person in Layer 4')
    await expect(box.locator('[data-arn-stage="human"]')).toContainText('Waiting for a person')
    await expect(box.locator('[data-arn-stage="active"]')).toContainText('Approved and active')
    // a packet awaiting a person is never called published or active; consumer visibility is not measured and not 0
    for (const k of ['parsed', 'packet', 'human']) await expect(box.locator(`[data-arn-stage="${k}"]`)).not.toContainText(/published/i)
    await expect(box.locator('[data-arn-n="consumer"]')).toHaveText('Not measured')
    await expect(box.locator('[data-arn-facts]')).toContainText('30 of 36 rows')
    await expect(box.locator('[data-arn-facts]')).toContainText('5 year')
    await expect(box.locator('[data-arn-facts]')).toContainText('never filled in or inferred')
    // the action: reason first, then one run
    await box.locator('[data-po-action="aer-read-now"]').click()
    await box.getByLabel('Reason: Read / refresh entry requirements now').fill('Refresh before the August intake')
    await box.locator('[data-po-confirm="aer-read-now"]').click()
    await expect(box.locator('[data-arn-result="queued"]')).toContainText('Started 4 read(s). You can close this page')
    expect(calls.filter(c => c.action === 'run')).toEqual([{ action: 'run', provider_id: 'p-rmit', note: 'Refresh before the August intake' }])
    // the server now says in progress: the button is off, so a second click is not possible; the panel says why
    await expect(box.locator('[data-arn-outcome="in_progress"]')).toContainText('In progress')
    await expect(box.locator('[data-po-action="aer-read-now"]')).toBeDisabled()
    await expect(box.locator('[data-arn-nothing]')).toBeVisible()
    await expect(box.locator('[data-arn-foot]')).toContainText('Last request')
    await expect(box.locator('[data-arn-layer4]')).toHaveAttribute('href', /layer-4|layer4|#/)
  })

  const OUTCOMES = { in_progress: 'In progress', human_review_required: 'Waiting for a person', already_up_to_date: 'Already up to date', no_eligible_work: 'No eligible work', source_unavailable: 'Source unavailable', switch_off: 'Switched off', budget_reached: 'Budget reached' }
  for (const [code, label] of Object.entries(OUTCOMES)) {
    test(`outcome ${code} is shown in its own words and starts nothing`, async ({ page }) => {
      await mock(page, { st: status(code, { blocks: code === 'switch_off' ? [{ outcome: 'budget_reached', reason: 'daily_cap', text: 'The daily allowance is used.' }] : [] }) })
      await page.goto('/#entry-requirements?provider=p-rmit')
      const box = page.locator('[data-aer-read-now="provider"]')
      await expect(box.locator(`[data-arn-outcome="${code}"]`)).toContainText(label, { timeout: 20_000 })
      await expect(box.locator(`[data-arn-outcome="${code}"]`)).toContainText(`text for ${code}`)
      await expect(box.locator('[data-po-action="aer-read-now"]')).toBeDisabled()
      if (code === 'switch_off') await expect(box.locator('[data-arn-block="budget_reached"]')).toContainText('daily allowance')
    })
  }

  // Operating Model v1.7 (evidence-backed absence): each kind of "nothing" is named, the source examined is shown as recorded, and no kind says "published"
  const KINDS = [
    ['source_unavailable', 'no_source_found', 'No official source found'], ['source_unavailable', 'source_found_not_read', 'Source found, not read'],
    ['already_up_to_date', 'tried_not_found', 'Read, no requirement kept'], ['source_unavailable', 'technical_failure', 'Technical failure, can be retried'],
    ['budget_reached', 'budget_hold', 'Budget hold'], ['human_review_required', 'human_review', 'Waiting for a person'],
  ]
  for (const [code, kind, label] of KINDS) {
    test(`evidence kind ${kind}: named beside the outcome, with the source examined and the next action`, async ({ page }) => {
      const source = { kind: 'matrix_sources', recorded: true, count: 2, sources: [
        { url: 'https://rmit.example/entry', status: 'read', http_status: 200, read_at: '2026-11-09T04:00:00Z', stored: true, content_hash: 'abc123def456', error: null, last_run: { state: 'done', rows_kept: 0, error: null, at: '2026-11-09T04:05:00Z' } },
        { url: 'https://rmit.example/entry.pdf', status: 'failed', http_status: null, read_at: null, stored: false, content_hash: null, error: 'blocked_pdf', last_run: null }] }
      await mock(page, { st: status(code, { source, outcome: { outcome: code, reason: 'x', class: kind, text: `text for ${kind}`, next_action: `next for ${kind}` } }) })
      await page.goto('/#entry-requirements?provider=p-rmit')
      const box = page.locator('[data-aer-read-now="provider"]')
      await expect(box.locator(`[data-arn-class="${kind}"]`)).toContainText(label, { timeout: 20_000 })
      await expect(box.locator('[data-arn-outcome]')).toContainText(`text for ${kind}`)
      await expect(box.locator('[data-arn-next]')).toContainText(`next for ${kind}`)
      await expect(box.locator('[data-arn-source="matrix_sources"]')).toContainText('https://rmit.example/entry.pdf')
      await expect(box.locator('[data-arn-source-row="failed"]')).toContainText('blocked_pdf')
      await expect(box.locator('[data-arn-source-row="read"]')).toContainText('0 row(s) kept')
      await expect(box.locator('[data-arn-source-row="read"]')).toContainText('hash abc123def456')
      await expect(box.locator('[data-arn-outcome]')).not.toContainText(/published/i)
    })
  }

  test('a missing source record is said to be missing, and a course page shows its stored copy and last recorded result', async ({ page }) => {
    await mock(page, { st: status('source_unavailable', { source: { kind: 'matrix_sources', recorded: false, count: 0, sources: [] }, outcome: { outcome: 'source_unavailable', reason: 'nothing_stored', class: 'no_source_found', text: 't', next_action: 'n' } }) })
    await page.goto('/#entry-requirements?provider=p-rmit')
    await expect(page.locator('[data-arn-source="none"]')).toContainText('no entry source is recorded for this provider', { timeout: 20_000 })
    const p2 = await page.context().newPage()
    await mock(p2, { st: status('already_up_to_date', { scope: 'course', course: { id: F.courseDetail.id, title: 'Associate Degree in Business' },
      source: { kind: 'course_page', recorded: true, url: 'https://rmit.example/course', binding: 'bound', matched_by: 'cricos_code', stored: true, captured_at: '2026-11-01T00:00:00Z', content_hash: 'h1h1h1h1h1h1', last_read: { state: 'skipped', recorded_reason: 'the page does not state it', at: '2026-11-02T00:00:00Z' } },
      outcome: { outcome: 'already_up_to_date', reason: 'tried_not_found', class: 'tried_not_found', text: 't', next_action: 'n' } }) })
    await p2.goto(`/#courses?id=${F.courseDetail.id}`)
    const src = p2.locator('[data-arn-source="course_page"]')
    await expect(src).toContainText('https://rmit.example/course', { timeout: 20_000 })
    await expect(src).toContainText('matched by cricos code')
    await expect(src).toContainText('hash h1h1h1h1h1h1')
    await expect(src).toContainText('the page does not state it')
  })

  test('a role below Platform Admin sees what would happen and cannot start it', async ({ page }) => {
    const calls = await mock(page, { rank: 3 })
    await page.goto('/#entry-requirements?provider=p-rmit')
    const box = page.locator('[data-aer-read-now="provider"]')
    await expect(box.locator('[data-arn-outcome="queued"]')).toBeVisible({ timeout: 20_000 })
    await expect(box.locator('[data-po-action="aer-read-now"]')).toBeDisabled()
    await expect(box.locator('[data-arn-permission]')).toContainText('Platform Admin')
    expect(calls.filter(c => c.action === 'run')).toEqual([])
  })

  test('the server refusing the run (permission denied) is shown, not hidden', async ({ page }) => {
    await mock(page, { onRun: () => ({ outcome: 'permission_denied', reason: 'rank', text: 'Reading entry requirements on demand needs the Platform Admin role. Nothing was asked.', can_run: false, known: true }) })
    await page.goto('/#entry-requirements?provider=p-rmit')
    const box = page.locator('[data-aer-read-now="provider"]')
    await box.locator('[data-po-action="aer-read-now"]').click({ timeout: 20_000 })
    await box.getByLabel('Reason: Read / refresh entry requirements now').fill('Try it')
    await box.locator('[data-po-confirm="aer-read-now"]').click()
    await expect(box.locator('[data-arn-result="permission_denied"]')).toContainText('Platform Admin role')
  })

  test('Course detail: the same action for one course; the earlier direct read is an advanced control', async ({ page }) => {
    const calls = await mock(page, { st: status('queued', { scope: 'course', course: { id: F.courseDetail.id, title: 'Associate Degree in Business' } }) })
    await page.goto(`/#courses?id=${F.courseDetail.id}`)
    const box = page.locator('[data-aer-read-now="course"]')
    await expect(box).toBeVisible({ timeout: 20_000 })
    await expect(box).toContainText('Associate Degree in Business')
    expect(calls[0]).toEqual({ action: 'status', course_id: F.courseDetail.id })
    await expect(page.locator('[data-course-entry-read-advanced]')).toBeVisible()
    await expect(page.locator('[data-course-entry-read-advanced]')).not.toHaveAttribute('open', '')
    await page.locator('[data-course-entry-read-advanced] summary').click()
    await expect(page.locator('[data-po-action="course-entry-read"]')).toBeVisible()
  })

  test('phone width: the panel fits and nothing scrolls sideways @responsive', async ({ page }) => {
    expect(page.viewportSize().width).toBeLessThan(500)
    await mock(page)
    await page.goto('/#entry-requirements?provider=p-rmit')
    await expect(page.locator('[data-aer-read-now="provider"] [data-arn-stage]').first()).toBeVisible({ timeout: 20_000 })
    const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
    expect(over).toBeLessThanOrEqual(1)
    const btn = await page.locator('[data-aer-read-now="provider"] [data-po-action="aer-read-now"]').boundingBox()
    expect(btn.height).toBeGreaterThanOrEqual(24)
  })
})
