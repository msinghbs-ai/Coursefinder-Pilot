// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; monitoring closure for the Integration queue, IQ-00046/47/56 queue families) and S121/G4 (phone tests are @responsive and first assert phone width). Platform health › Integration queue (IntegrationQueue, PipelineYield), mocked REST responses; nothing reaches a real backend.
import { test, expect } from '@playwright/test'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121

const issue = (n, severity, status) => ({
  id: `id-${n}`, ref: `IQ-${String(n).padStart(5, '0')}`, title: `A deliberately long issue title ${n} to check wrapping on a narrow phone screen`,
  source: 'scheduled_check', validation_layer: 'V4', root_cause: 'queue_not_moving', providers: 3, courses: 12, more_entities: true,
  severity, status, regressions: n === 2 ? 1 : 0, workstream: 'A8', layer: 'L2', retry_count: n, last_observed_at: '2026-11-09T11:00:00Z', cleared_at: null,
})
const summary = {
  mode: { mode: 1, set_by: 'Platform Admin', set_at: '2026-11-08T00:00:00Z', reason: 'Active remediation until the closure conditions hold' },
  by_status: { triaged: 69, deployed: 3, production_verification: 1, reopened: 1, closed: 40 },
  by_severity: { P0: 2, P1: 5, P2: 9 }, by_workstream: { A8: 4, A2: 3, A4: 1 }, reopened: 1, regressions_total: 2,
  job_active: true, last_check: { at: '2026-11-09T11:30:00Z', found: 7 }, last_deploy_check: { release: 'v2.15.300', ok: true, at: '2026-11-09T11:00:00Z' },
  issues: [issue(1, 'P0', 'deployed'), issue(2, 'P1', 'reopened'), issue(3, 'P1', 'triaged'), issue(4, 'P2', 'production_verification')],
}
const detail = {
  issue: {
    issue_ref: 'IQ-00001', failure: 'A long failure description that has to wrap onto several lines on a narrow phone screen without sideways scroll',
    expected: 'The queue moves', impact: 'Courses wait', detected_at: '2026-11-08T00:00:00Z', detection_source: 'scheduled_check',
    depends_on: ['IQ-00002'], blocked_by: [3], fix_commit: 'abcdef1234567890abcdef1234567890abcdef12', fix_migration: '20261109200000', deployed_version: 'v2.15.300',
    verification_outcome: 'passed', verified_by: 'controller', verified_at: '2026-11-09T11:00:00Z', country_codes: ['AU', 'NZ'],
    evidence_refs: ['docs/platform/STUDYSEARCH-EXECUTION-REGISTER.md#a-very-long-anchor-name-that-would-not-wrap-without-break-rules'], aer_root_cause_ref: 'AER-1',
  },
  events: [{ id: 'e1', kind: 'status_changed', from_status: 'triaged', to_status: 'deployed', actor: 'controller', at: '2026-11-09T10:00:00Z', note: 'Deployed with a long note to check wrapping' }],
}
const lanes = ['stored', 'paid', 'ai', 'l4', 'gap'].map((lane) => ({
  lane, label: `Lane ${lane} with a long label`, stages: { invoked: 10, source_accessed: 9, pages_discovered: 8, read_completely: 7, extracted: 6, accepted_or_held: { accepted: 3, held: 3 }, published: 0, consumer_read_back: null },
  eligible: 100, processed: 10, failed: 1, held: { source_gone: 2 }, live_hold: 3, cost: { usd: 0.5 }, last_run: { outcome: 'ok', items: 10, at: '2026-11-09T11:00:00Z' },
}))
const yieldData = {
  window_hours: 24, lanes, lane_status: { lanes },
  field_backlog: { country: 'AU', fields: [{ field: 'fee', label: 'Fee', eligible: 100, waiting_layer4: 1, not_supported: 2, stored_source: 3, requires_acquisition: 4, processed_24h: 5, admitted_24h: 6, processed_7d: 7, admitted_7d: 8, accepted_per_hour: 2, forecast_hours: 50, note: '' }], source_proof: { waiting_for_page_proof: 1, settled_24h: 2, free_per_run: 3, paid_search_per_run: 0 } },
  plan_outcomes: { window_since: '2026-11-08T00:00:00Z', moved: 5, not_needed: 2, no_movement: 1, steps_not_needed: { fee: 2 }, tasks_not_needed: 4 },
}

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
    let body = {}
    if (name === 'admin_integration_queue') {
      const b = req.postDataJSON(); calls.push(b)
      body = b.p_action === 'issue' ? detail : summary
    } else if (name === 'admin_pipeline_yield') body = yieldData
    return route.fulfill({ status: 200, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
  })
  await page.goto('/')
  await page.evaluate(async () => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: IntegrationQueue, PipelineYield } = await import('/src/IntegrationQueue.jsx')
    document.body.innerHTML = '<div id="iq-root"></div>'
    ReactDOM.createRoot(document.getElementById('iq-root')).render(
      React.default.createElement(React.default.Fragment, {}, React.default.createElement(IntegrationQueue, {}), React.default.createElement(PipelineYield, {})))
  })
  await expect(page.locator('[data-iq-issue="IQ-00001"]')).toBeVisible()
  await expect(page.locator('[data-pipeline-yield]')).toBeVisible()
  return calls
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Platform health › Integration queue on a phone @responsive', () => {
  test('panels fit the phone; the issue and yield tables scroll in their own frames; the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    const panels = await boxes(page, '.m-panel')
    expect(panels.length, 'panels are on the screen, so this check measures something').toBeGreaterThanOrEqual(3)
    for (const b of panels) {
      expect(b.x, `panel "${b.label}" starts inside the screen`).toBeGreaterThanOrEqual(-1)
      expect(b.right, `panel "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
    }
    const frames = await page.locator('.cf-table-wrap').evaluateAll((els) => els.map((p) => {
      const t = p.querySelector('table')
      return { frameClient: p.clientWidth, overflowX: getComputedStyle(p).overflowX, tableWidth: t.getBoundingClientRect().width }
    }))
    expect(frames.length, 'issue table, lanes and field backlog frames').toBeGreaterThanOrEqual(3)
    for (const f of frames) {
      expect(f.frameClient, 'table frame fits the phone').toBeLessThanOrEqual(w)
      if (f.tableWidth > f.frameClient) expect(['auto', 'scroll'], 'a table wider than the phone scrolls inside its own frame').toContain(f.overflowX)
    }
    await expect(page.locator('[data-iq-issue]')).toHaveCount(4)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every control a Platform Admin taps is at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page)
    const small = []
    let measured = 0
    for (const sel of ['button', '[role="tab"]', '[data-iq-issue]']) {
      for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    expect(measured, 'controls measured').toBeGreaterThanOrEqual(8)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
  })

  test('opening an issue shows its history inside the screen; the scope tabs ask the server for that scope', async ({ page }) => {
    const w = await atPhoneWidth(page)
    const calls = await mount(page)
    await page.locator('[data-iq-issue="IQ-00001"]').click()
    const hist = page.locator('[data-iq-history="IQ-00001"]')
    await expect(hist).toBeVisible()
    const b = await hist.boundingBox()
    expect(b.x, 'the history starts inside the screen').toBeGreaterThanOrEqual(-1)
    expect(b.x + b.width, 'the history ends inside the screen, so it is read without scrolling sideways').toBeLessThanOrEqual(w + 1)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    await page.locator('[data-iq-scope="closed"]').click()
    await expect.poll(() => calls.filter((c) => c.p_action === 'summary').map((c) => c.p_args.scope)).toContain('closed')
    expect(calls.filter((c) => c.p_action === 'issue')).toHaveLength(1)
  })
})
