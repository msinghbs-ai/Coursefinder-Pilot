// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; IQ-00053 worker output families) and S121/G4 (phone tests are @responsive and first assert phone width). Layer 2 › Enrich fields (EnrichFields), mocked REST responses; nothing reaches a real backend.
import { test, expect } from '@playwright/test'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121

const meta = (canStart) => ({
  can_start: canStart, can_manage: false, countries: ['AU', 'NZ', 'CA'],
  fields: [{ field: 'fee', label: 'Tuition fee' }, { field: 'english', label: 'English requirement' }, { field: 'intakes', label: 'Intake months' }],
  rules: [{ country: 'ALL', field: 'fee', sources: ['adapter', 'ai_stored', 'scraper'], reason: '' }],
})
const job = {
  id: '11111111-2222-3333-4444-555555555555', title: 'Enrich fields: Tuition fee for a university with a deliberately long name', state: 'done',
  created_at: '2026-11-09T03:00:00Z', progress: { done: 120, total: 120 },
  result: { cost_usd: 0.42, by_field: { fee: { filled: 90, review: 12, skipped: 10, failed: 8 } } },
}
const stats = {
  snapshot_at: '2026-11-09T07:00:00Z', first_snapshot_at: '2026-11-01T00:00:00Z',
  coverage: [{ country: 'NZ', field: 'fee', filled: 3000, courses: 4000, first: 2500, day_ago: 2990 }],
  last_24h: { last_hour: 10, filled: 90, ai_calls: 52, ai_failed: 0, ai_cost_usd: 0.42, scraper_credits: 0, pages_requested: 0 },
  limits: { model: 'a-model-with-a-long-name', ai_guard_usd: 5, ai_spent_today_usd: 0.4, openrouter_mode: 'observe', calls_at_once: 2, items_per_call: 5, items_a_minute: 30, campus_min_pages: 2, scraper_share: 100, reads_share: 200 },
}
const items = { items: [{ id: 1, course: 'Bachelor of a Course With a Long Title', provider: 'A University', field: 'fee', state: 'filled', value: {}, source: 'ai_stored', quote: 'Tuition is A$42,000 a year for international students' }] }

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

async function mount(page, { canStart }) {
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
  const calls = []
  await page.route('**/rest/v1/rpc/**', async (route) => {
    const req = route.request()
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors })
    const name = new URL(req.url()).pathname.split('/').pop()
    let body = {}
    if (name === 'admin_enrich_fields') {
      const d = req.postDataJSON()
      calls.push(d)
      if (d.p_action === 'fields') body = meta(canStart)
      else if (d.p_action === 'jobs') body = { jobs: [job] }
      else if (d.p_action === 'stats') body = stats
      else if (d.p_action === 'items') body = items
      else if (d.p_action === 'preview') body = { courses: 300, universities: 2, fields: [{ field: 'fee', missing: 120, stored_page: 80, adapter_value: null }], estimate: { items: 120, in_task: 0, unpublished: 0, usd: 0.5, usd_per_item: 0.004, credits_max: 0 } }
    }
    return route.fulfill({ status: 200, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
  })
  await page.goto('/')
  await page.evaluate(async () => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: EnrichFields } = await import('/src/EnrichFields.jsx')
    document.body.innerHTML = '<div id="ef-root"></div>'
    ReactDOM.createRoot(document.getElementById('ef-root')).render(React.default.createElement(EnrichFields, { rank: 3 }))
  })
  // Cards are collapsed until opened (Decision 254), so open the ones this screen operates from; Course descriptions is its own workspace and is not opened here
  for (const id of ['layer2.enrich.telemetry', 'layer2.enrich.start', 'layer2.enrich.tasks', 'layer2.enrich.sources']) {
    await page.locator(`[data-card="${id}"] .cf-card-toggle`).click()
  }
  await expect(page.locator('[data-enrich-job]')).toBeVisible()
  return calls
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Layer 2 › Enrich fields on a phone @responsive', () => {
  test('panels fit the phone and the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page, { canStart: true })
    const panels = await boxes(page, '.m-panel')
    expect(panels.length, 'panels are on the screen, so this check measures something').toBeGreaterThanOrEqual(3)
    for (const b of panels) {
      expect(b.x, `panel "${b.label}" starts inside the screen`).toBeGreaterThanOrEqual(-1)
      expect(b.right, `panel "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
    }
    await expect(page.locator('[data-coverage-table]')).toBeVisible()
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every control a Pipeline Operator taps is at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page, { canStart: true })
    const small = []
    let measured = 0
    // a checkbox is tapped through its label, so the label is what is measured
    for (const sel of ['button', 'select', 'input[type=text], input:not([type])', 'label.rs-check']) {
      for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    expect(measured, 'controls measured').toBeGreaterThanOrEqual(8)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
  })

  test('Preview reads only: it asks the server for a preview and never starts a task', async ({ page }) => {
    const w = await atPhoneWidth(page)
    const calls = await mount(page, { canStart: true })
    await page.locator('[data-enrich-field="fee"] input').check()
    await page.getByRole('checkbox', { name: /Australia/ }).check()
    await page.getByRole('button', { name: /Preview/ }).click()
    await expect(page.locator('[data-enrich-preview]')).toBeVisible()
    await expect(page.locator('[data-enrich-estimate]')).toContainText('Start would queue 120')
    const box = await page.locator('[data-enrich-preview]').evaluate((el) => { const b = el.getBoundingClientRect(); return { right: b.right } })
    expect(box.right, 'the preview ends inside the screen').toBeLessThanOrEqual(w + 1)
    expect(calls.filter((c) => c.p_action === 'preview')).toHaveLength(1)
    expect(calls.filter((c) => c.p_action === 'start'), 'Preview never starts a task').toHaveLength(0)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('opening a task shows its items inside the screen', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page, { canStart: true })
    await page.locator('.ef-job-head').click()
    await expect(page.locator('[data-enrich-items] tbody tr')).toHaveCount(1)
    const frame = await page.locator('[data-enrich-items] .cf-table-wrap').evaluate((el) => ({ client: el.clientWidth, overflowX: getComputedStyle(el).overflowX, table: el.querySelector('table').getBoundingClientRect().width }))
    expect(frame.client, 'the items frame fits the phone').toBeLessThanOrEqual(w)
    if (frame.table > frame.client) expect(['auto', 'scroll'], 'a table wider than the phone scrolls inside its own frame').toContain(frame.overflowX)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('a read-only role sees the screen but no Start task button', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page, { canStart: false })
    await expect(page.getByRole('button', { name: /Start task/ })).toHaveCount(0)
    await expect(page.getByText('Only a Pipeline Operator or above can start a task.')).toBeVisible()
    for (const b of await boxes(page, '.m-panel')) expect(b.right, `panel "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })
})
