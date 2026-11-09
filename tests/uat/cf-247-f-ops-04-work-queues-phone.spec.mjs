// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; IQ-00053 and IQ-00046/47/56 queue-watch families) and S121/G4 (phone tests are @responsive and first assert phone width). Platform health › Work queues (QueueWatch), mocked REST responses; nothing reaches a real backend.
import { test, expect } from '@playwright/test'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121

const STATES = ['stuck', 'out_of_toolset', 'failing', 'waiting', 'moving', 'capped', 'nothing_left', 'done', 'paused']
const queue = (state, i) => ({
  key: `queue_${i}`,
  label: `Enrichment queue ${i} with a deliberately long name to check wrapping on a phone`,
  area: 'Layer 2 enrichment', purpose: 'Official course pages and the fees they hold',
  state, reason: 'Nothing finished for 130 minutes while 412 items wait for a worker slot', pending: 1000 * i, per_hour: 12 * i,
  failed_window: state === 'failing' ? 9 : 0, eta_hours: 30 * i, exhausted: state === 'nothing_left' ? 44 : 0,
  nothing_left_is: state === 'nothing_left' ? 'every tool was tried on each item' : '', last_progress: '2026-11-09T04:00:00Z', since: '2026-11-09T02:00:00Z',
  tools_out: state === 'out_of_toolset' ? ['Firecrawl credit'] : [], tools_waiting: state === 'waiting' ? ['AI budget'] : [],
  why_idle: state === 'stuck' ? 'The worker has not been called since 02:10' : '', fix_at: state === 'stuck' ? '/health/integration' : null,
})
const watch = (canRun) => ({
  can_run: canRun, settings: { stuck_minutes: 120 },
  queues: STATES.map((s, i) => queue(s, i + 1)),
  fixes: [{ id: 'f1', key: 'queue_1', items: 14, at: '2026-11-09T03:00:00Z', detail: { what: 'Items that gave up on a time-out were tried once more' } }],
  alerts: [{ id: 'a1', state: 'stuck', channel: 'notify', title: 'Enrichment queue 1 is stuck with a long alert title to check wrapping', body: 'Nothing finished for 130 minutes', raised_at: '2026-11-09T02:05:00Z', sent_at: null }],
  events: [{ id: 'e1', at: '2026-11-09T02:05:00Z', key: 'queue_1', from_state: 'moving', to_state: 'stuck', reason: 'Nothing finished for 130 minutes while work was waiting' }],
})
const stats = {
  latest: {
    at: '2026-11-09T07:15:00Z', gaps: [{ note: 'A gap note long enough to need wrapping on a narrow phone screen' }],
    countries: { AU: { now: { courses: 25000, fee: 20000 }, change_15m: { fee: 12 }, change_24h: { fee: 300 } }, NZ: { now: { courses: 4000, fee: 3000 }, change_15m: { fee: 0 }, change_24h: { fee: -5 } } },
    firecrawl: { used_today: 120, total: 1000, groups: [{ group: 'read', label: 'Page reads', used: 90, share: 700 }] },
    ai: [{ use: 'enrich', label: 'Enrichment', spent_usd: 0.4, guard_usd: 5, calls: 52 }],
    worker_calls_15m: { enrich_ai: { calls: 4, failed: 0, avg_s: 3.2, max_s: 6 } }, tasks: { running: 2, queued: 5, not_moving: 0 },
  },
}
const gaps = {
  at: '2026-11-09T07:00:00Z', countries: ['NZ', 'AU'], run: { recorded: false },
  rows: [{ country: 'NZ', attribute: 'fee', cause: 'The official page does not state a fee', courses: 120, change: -3, automatic: false, action: 'Add a reader for the fee table' }],
}

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

async function mount(page, { canRun }) {
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
  const calls = []
  await page.route('**/rest/v1/rpc/**', async (route) => {
    const req = route.request()
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors })
    const name = new URL(req.url()).pathname.split('/').pop()
    let body = {}
    if (name === 'admin_queue_watch') { calls.push(req.postDataJSON()); body = watch(canRun) }
    else if (name === 'admin_stats_15m') body = stats
    else if (name === 'admin_gap_causes') body = gaps
    return route.fulfill({ status: 200, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
  })
  await page.goto('/')
  await page.evaluate(async () => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: QueueWatch } = await import('/src/QueueWatch.jsx')
    document.body.innerHTML = '<div id="qw-root"></div>'
    ReactDOM.createRoot(document.getElementById('qw-root')).render(React.default.createElement(QueueWatch, {}))
  })
  await expect(page.locator('[data-queue="queue_1"]')).toBeVisible()
  return calls
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Platform health › Work queues on a phone @responsive', () => {
  test('panels fit the phone; the queue and change tables scroll in their own frames; the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page, { canRun: true })
    const panels = await boxes(page, '.m-panel')
    expect(panels.length, 'panels are on the screen, so this check measures something').toBeGreaterThanOrEqual(5)
    for (const b of panels) {
      expect(b.x, `panel "${b.label}" starts inside the screen`).toBeGreaterThanOrEqual(-1)
      expect(b.right, `panel "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
    }
    const frames = await page.locator('.qw-table').first().evaluate((el) => {
      const p = el.closest('.cf-table-wrap')
      return { frameClient: p.clientWidth, overflowX: getComputedStyle(p).overflowX, tableWidth: el.getBoundingClientRect().width }
    })
    expect(frames.frameClient, 'the queue table frame fits the phone').toBeLessThanOrEqual(w)
    if (frames.tableWidth > frames.frameClient) expect(['auto', 'scroll'], 'a table wider than the phone scrolls inside its own frame').toContain(frames.overflowX)
    await expect(page.locator('[data-queue^="queue_"]')).toHaveCount(STATES.length)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every control a Platform Admin taps is at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page, { canRun: true })
    await expect(page.locator('[data-queue-run]')).toBeVisible()
    const small = []
    let measured = 0
    for (const sel of ['button', 'select', 'a[href]']) {
      for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    expect(measured, 'controls measured').toBeGreaterThanOrEqual(4)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
  })

  test('Check now asks the server once with a reason', async ({ page }) => {
    await atPhoneWidth(page)
    const calls = await mount(page, { canRun: true })
    await page.locator('[data-queue-run]').click()
    await expect(page.locator('.qw-msg')).toContainText('Checked 9 queues')
    const runs = calls.filter((c) => c.p_action === 'run')
    expect(runs).toHaveLength(1)
    expect(runs[0].p_args.reason).toContain('Check now')
  })

  test('a read-only role sees the queues but no Check now button', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page, { canRun: false })
    await expect(page.locator('[data-queue-run]')).toHaveCount(0)
    for (const b of await boxes(page, '.m-panel')) expect(b.right, `panel "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })
})
