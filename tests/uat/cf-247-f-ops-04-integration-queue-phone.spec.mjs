// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; monitoring closure for the Integration queue, IQ-00046/47/56 queue families) and S121/G4 (phone tests are @responsive and first assert phone width). Platform health › Integration queue (IntegrationQueue) and its Pipeline yield on Work queues (PipelineYield), mounted in the real admin shell with the shared mocked admin REST (support/admin-mock.mjs); nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

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

// The real shell: Platform health › Integration queue (#platform-health?tab=integration) or Work queues, where the Pipeline yield sits (tab=queues)
async function mount(page, tab = 'integration') {
  if (!page.__iq) {
    await mockAdmin(page, { rank: 5 })
    const calls = []
    await page.route('**/rest/v1/rpc/admin_integration_queue', async (route) => {
      const b = route.request().postDataJSON(); calls.push(b)
      return route.fulfill({ contentType: 'application/json', body: JSON.stringify(b.p_action === 'issue' ? detail : summary) })
    })
    await page.route('**/rest/v1/rpc/admin_pipeline_yield', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify(yieldData) }))
    page.__iq = calls
  }
  await page.goto(`/#platform-health?tab=${tab}`)
  if (tab === 'integration') await expect(page.locator('[data-iq-issue="IQ-00001"]')).toBeVisible()
  else await expect(page.locator('[data-pipeline-yield]')).toBeVisible()
  return page.__iq
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
    let panelCount = 0, frameCount = 0
    for (const tab of ['integration', 'queues']) {
      await mount(page, tab)
      const panels = await boxes(page, '.m-panel')
      panelCount += panels.length
      for (const b of panels) {
        expect(b.x, `${tab}: panel "${b.label}" starts inside the screen`).toBeGreaterThanOrEqual(-1)
        expect(b.right, `${tab}: panel "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
      }
      const frames = await page.locator('.cf-table-wrap').evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((p) => {
        const t = p.querySelector('table')
        return { frameClient: p.clientWidth, overflowX: getComputedStyle(p).overflowX, tableWidth: t.getBoundingClientRect().width }
      }))
      frameCount += frames.length
      for (const f of frames) {
        expect(f.frameClient, `${tab}: table frame fits the phone`).toBeLessThanOrEqual(w)
        if (f.tableWidth > f.frameClient) expect(['auto', 'scroll'], `${tab}: a table wider than the phone scrolls inside its own frame`).toContain(f.overflowX)
      }
      expect(await pageOverflow(page), `${tab}: the page does not scroll sideways`).toBeLessThanOrEqual(1)
    }
    expect(panelCount, 'panels are on the screens, so this check measures something').toBeGreaterThanOrEqual(3)
    expect(frameCount, 'issue table, lanes and field backlog frames').toBeGreaterThanOrEqual(3)
    await mount(page, 'integration')
    await expect(page.locator('[data-iq-issue]')).toHaveCount(4)
  })

  test('every control a Platform Admin taps is at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    const small = []
    let measured = 0
    for (const tab of ['integration', 'queues']) {
      await mount(page, tab)
      for (const sel of ['.m-panel button', '.m-panel [role="tab"]', '[data-iq-issue]']) {
        for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${tab} ${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
      }
    }
    expect(measured, 'controls measured').toBeGreaterThanOrEqual(8)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
  })

  test('opening an issue shows its whole history inside its table frame at 360, 390 and 412 px; the scope tabs ask the server for that scope', async ({ page }) => {
    await atPhoneWidth(page)
    const calls = await mount(page)
    for (const width of [360, 390, 412]) {
      await page.setViewportSize({ width, height: 900 })
      await mount(page)
      await page.reload()
      await expect(page.locator('[data-iq-issue="IQ-00001"]')).toBeVisible()
      await page.locator('[data-iq-issue="IQ-00001"]').click()
      const hist = page.locator('[data-iq-history="IQ-00001"]')
      await expect(hist).toBeVisible()
      // the box the history must sit in is the client box of its own table frame (the frame scrolls; the viewport is not the test)
      const read = () => hist.evaluate((el) => {
        const frame = el.closest('.cf-table-wrap'), f = frame.getBoundingClientRect(), b = el.getBoundingClientRect()
        const left = f.left + frame.clientLeft
        return { inLeft: b.left - left, inRight: left + frame.clientWidth - b.right, width: b.width, frameClient: frame.clientWidth, tableWidth: frame.querySelector('table').getBoundingClientRect().width, scrollLeft: frame.scrollLeft }
      })
      const atStart = await read()
      expect(atStart.tableWidth, `${width}px: the table is wider than its frame, so this checks a scrolling frame`).toBeGreaterThan(atStart.frameClient)
      expect(atStart.inLeft, `${width}px: the history starts inside its frame`).toBeGreaterThanOrEqual(-1)
      expect(atStart.inRight, `${width}px: the history ends inside its frame, nothing clipped on the right`).toBeGreaterThanOrEqual(-1)
      // scrolled to the far end, the history stays pinned inside the frame
      await hist.evaluate((el) => { const fr = el.closest('.cf-table-wrap'); fr.scrollLeft = fr.scrollWidth })
      const atEnd = await read()
      expect(atEnd.scrollLeft, `${width}px: the frame did scroll`).toBeGreaterThan(0)
      expect(atEnd.inLeft, `${width}px: scrolled right, the history still starts inside its frame`).toBeGreaterThanOrEqual(-1)
      expect(atEnd.inRight, `${width}px: scrolled right, the history still ends inside its frame`).toBeGreaterThanOrEqual(-1)
      expect(await pageOverflow(page), `${width}px: the page does not scroll sideways`).toBeLessThanOrEqual(1)
    }
    await page.locator('[data-iq-scope="closed"]').click()
    await expect.poll(() => calls.filter((c) => c.p_action === 'summary').map((c) => c.p_args.scope)).toContain('closed')
    expect(calls.filter((c) => c.p_action === 'issue').length, 'each opening asked the server once').toBe(3)
  })
})
