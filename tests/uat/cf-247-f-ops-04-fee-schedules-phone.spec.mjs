// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; IQ-00046/47/56 source and read reliability) and S121/G4 (phone tests are @responsive and first assert phone width). Layer 2 › Fee schedules (FeeSchedules), mocked REST responses; nothing reaches a real backend and no approval is ever clicked.
import { test, expect } from '@playwright/test'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121

const doc = (n, extra = {}) => ({
  id: `doc-${n}`, provider: `A University With A Deliberately Long Name ${n}`, provider_id: `p-${n}`, country: 'AU',
  url: 'https://example.edu.au/fees/international-fee-schedule-2027.pdf', read_at: '2026-11-09T03:00:00Z',
  rows: 140, new: 90, same: 20, differs: 10, no_course: 12, decision: null, ...extra,
})
const feeDocs = {
  can_decide: true,
  totals: { providers_searched: 40, providers_queued: 3, documents_read: 38, documents_found: 41, with_fee_rows: 30, awaiting_decision: 3 },
  documents: [doc(1), doc(2), doc(3)],
}
const feeRows = { rows: [{ row_id: 1, course_title: 'Bachelor of a Course With a Rather Long Title', course_code: '012345A', amount: 42000, currency_code: 'AUD', basis: 'annual', fee_year: 2027, current_amount: null, outcome: 'new' }] }

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

async function mount(page) {
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
  const calls = []
  await page.route('**/rest/v1/rpc/**', async (route) => {
    const req = route.request()
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors })
    const name = new URL(req.url()).pathname.split('/').pop()
    const d = req.postDataJSON?.() || {}
    calls.push({ name, ...d })
    let body = {}
    if (name === 'admin_provider_fee_schedules_read') body = d.p_source_id ? feeRows : feeDocs
    return route.fulfill({ status: 200, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
  })
  await page.goto('/')
  await page.evaluate(async () => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: FeeSchedules } = await import('/src/FeeSchedules.jsx')
    document.body.innerHTML = '<div id="fs-root"></div>'
    ReactDOM.createRoot(document.getElementById('fs-root')).render(React.default.createElement(FeeSchedules, {}))
  })
  await expect(page.locator('[data-fee-documents]')).toBeVisible()
  return calls
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Layer 2 › Fee schedules on a phone @responsive', () => {
  test('the panel fits the phone and the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    const panel = (await boxes(page, '[data-fee-schedules]'))[0]
    expect(panel.x, 'panel starts inside the screen').toBeGreaterThanOrEqual(-1)
    expect(panel.right, 'panel ends inside the screen').toBeLessThanOrEqual(w + 1)
    expect(await pageOverflow(page), 'the page itself does not scroll sideways').toBeLessThanOrEqual(1)
  })

  test('the schedules table scrolls inside its own frame, not the page', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    const wrap = page.locator('[data-fee-documents]').locator('xpath=ancestor::div[contains(@class,"cf-table-wrap")][1]')
    const m = await wrap.evaluate((el) => { const b = el.getBoundingClientRect(); return { right: b.right, ox: getComputedStyle(el).overflowX } })
    expect(m.right, 'the frame ends inside the screen').toBeLessThanOrEqual(w + 1)
    expect(['auto', 'scroll'], 'a wide table scrolls in its own frame').toContain(m.ox)
  })

  test('every control a Platform Admin taps is at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page)
    const small = []
    let measured = 0
    for (const sel of ['button', 'select', 'input[type=checkbox]']) {
      for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    expect(measured, 'controls measured').toBeGreaterThanOrEqual(8)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
  })

  test('reviewing rows reads only: it asks for the rows and never records a decision', async ({ page }) => {
    const w = await atPhoneWidth(page)
    const calls = await mount(page)
    await page.locator('.fs-review').first().click()
    await expect(page.locator('[data-fee-rows] tbody tr')).toHaveCount(1)
    const rows = (await boxes(page, '[data-fee-rows]'))[0]
    expect(rows.x, 'rows table starts inside the screen').toBeGreaterThanOrEqual(-1)
    expect(calls.filter((c) => c.name === 'admin_provider_fee_schedule_decide'), 'review never decides').toHaveLength(0)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    void w
  })
})
