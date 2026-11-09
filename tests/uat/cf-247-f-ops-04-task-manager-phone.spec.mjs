// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; IQ-00053 worker output families) and S121/G4 (phone tests are @responsive and first assert phone width). Task manager (AdminTasks) with its Background jobs board, mocked REST responses; nothing reaches a real backend.
import { test, expect } from '@playwright/test'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121

const job = (id, state, extra = {}) => ({
  id, state, kind: 'reread_pages', title: `Read pages again for a provider with a deliberately long task name to check wrapping on a phone ${id}`,
  requested_by_name: 'Platform Admin with a long display name', reason: 'Check the phone layout', created_at: '2026-11-09T04:00:00Z', started_at: '2026-11-09T04:01:00Z',
  progress: { done: 12, total: 40 }, result: { passing: 3, errors: state === 'failed' ? 2 : 0 }, error: null, status: null, args: {}, events: [{ at: '2026-11-09T04:02:00Z', note: 'Started' }], ...extra,
})
const tasks = (canManage) => ({
  can_admit: false, kinds: { reread_pages: { label: 'Read pages again', can_pause: canManage } },
  jobs: [job('t1', 'running'), job('t2', 'queued'), job('t3', 'paused', { pause_requested: false })],
  job: null,
})
const running = (canManage) => ({
  can_manage: canManage, refused_hour: 0, credits_hour: { read: 12 },
  jobs: ['enrich-ai-fill', 'intake-dates-apply', 'coverage-admit-intakes', 'provider-description-run'].map((job, i) => ({
    job, label: `Scheduled job ${i + 1} with a deliberately long label to check wrapping`, stage: 'Layer 2 enrichment', schedule: '*/10 * * * *',
    active: i !== 3, running: i === 0, runs_24h: 140 - i, failed_24h: i === 1 ? 2 : 0, queue: { left: 10 * i },
  })),
})

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

async function mount(page, { canManage }) {
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
  const calls = []
  await page.route('**/rest/v1/rpc/**', async (route) => {
    const req = route.request()
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors })
    const name = new URL(req.url()).pathname.split('/').pop()
    let body = {}
    if (name === 'admin_jobs') { const a = req.postDataJSON(); calls.push(a); body = a.p_action === 'read' ? tasks(canManage) : { ok: true } }
    else if (name === 'admin_jobs_pulse') body = { per_lane: 1, jobs: {} }
    else if (name === 'admin_progress_read') body = running(canManage)
    else if (name === 'admin_evidence_reuse_today') body = { kept: 10, read: 40, new_copies: 30, new_bytes: 0 }
    else if (name === 'admin_automation_control') { calls.push({ automation: req.postDataJSON() }); body = { ok: true } }
    return route.fulfill({ status: 200, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
  })
  await page.goto('/')
  await page.evaluate(async () => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: AdminTasks } = await import('/src/AdminTasks.jsx')
    document.body.innerHTML = '<div id="tm-root"></div>'
    ReactDOM.createRoot(document.getElementById('tm-root')).render(React.default.createElement(AdminTasks, {}))
  })
  await expect(page.locator('[data-task-row="t1"]')).toBeVisible()
  await expect(page.locator('[data-progress-job="enrich-ai-fill"]')).toBeVisible()
  return calls
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Task manager on a phone @responsive', () => {
  test('panels fit the phone; both tables scroll in their own frames; the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page, { canManage: true })
    const panels = await boxes(page, '.m-panel')
    expect(panels.length, 'panels are on the screen, so this check measures something').toBeGreaterThanOrEqual(2)
    for (const b of panels) {
      expect(b.x, `panel "${b.label}" starts inside the screen`).toBeGreaterThanOrEqual(-1)
      expect(b.right, `panel "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
    }
    const frames = await page.locator('.cf-table-wrap').evaluateAll((els) => els.map((p) => ({ frameClient: p.clientWidth, overflowX: getComputedStyle(p).overflowX, tableWidth: p.querySelector('table').getBoundingClientRect().width })))
    expect(frames.length, 'both the task table and the background jobs table are on the screen').toBeGreaterThanOrEqual(2)
    for (const f of frames) {
      expect(f.frameClient, 'the table frame fits the phone').toBeLessThanOrEqual(w)
      if (f.tableWidth > f.frameClient) expect(['auto', 'scroll'], 'a table wider than the phone scrolls inside its own frame').toContain(f.overflowX)
    }
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every control a Platform Admin taps is at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page, { canManage: true })
    await expect(page.locator('[data-task-row="t1"] button', { hasText: 'Cancel' })).toBeVisible()
    await expect(page.locator('[data-progress-job] button', { hasText: 'Run now' }).first(), 'a manager has Run now on the jobs board (the read-only test proves it absent)').toBeVisible()
    const small = []
    let measured = 0
    for (const sel of ['button', 'select']) {
      for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    // a checkbox is tapped through its label; a link inside a sentence is exempt from the target-size rule (WCAG 2.5.8 inline exception)
    for (const b of await boxes(page, 'label:has(input[type="checkbox"])')) { measured++; if (b.h < TAP_MIN) small.push(`checkbox label "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    const standalone = await page.locator('a[href]').evaluateAll((els) => els.filter((el) => el.offsetParent !== null && !(el.parentElement.textContent.trim().length > el.textContent.trim().length + 2)).map((el) => { const b = el.getBoundingClientRect(); return { label: el.textContent.trim().slice(0, 40), w: b.width, h: b.height } }))
    for (const b of standalone) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`link "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    expect(measured, 'controls measured').toBeGreaterThanOrEqual(8)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
  })

  test('Pause asks for a reason first and sends nothing when the reason is empty', async ({ page }) => {
    await atPhoneWidth(page)
    const calls = await mount(page, { canManage: true })
    page.once('dialog', (d) => d.dismiss())
    await page.locator('[data-task-row="t1"] button', { hasText: 'Pause' }).click()
    expect(calls.filter((c) => c.p_action === 'pause'), 'no pause without a reason').toHaveLength(0)
    page.once('dialog', (d) => d.accept('Phone check of the pause control'))
    await page.locator('[data-task-row="t1"] button', { hasText: 'Pause' }).click()
    await expect.poll(() => calls.filter((c) => c.p_action === 'pause').length).toBe(1)
    expect(calls.find((c) => c.p_action === 'pause').p_args.reason).toContain('Phone check')
  })

  test('opening a task shows its detail inside the screen width', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page, { canManage: true })
    await page.locator('[data-task-row="t2"] .tm-link').click()
    await expect(page.locator('[data-task-row="t2"]')).toHaveClass(/tm-open/)
    for (const b of await boxes(page, '.m-panel')) expect(b.right, `panel "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('a read-only role sees the tasks and jobs, and the Background jobs board offers no Pause, Resume or Run now', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page, { canManage: false })
    // The Background jobs board (Progress) drops its Control column for a role that cannot manage. The task table above it shows Resume and Cancel
    // by task state and leaves the refusal to the server, so this test makes no claim about those task buttons.
    await expect(page.locator('[data-progress-job]').first(), 'the jobs board is on the screen, so this check measures something').toBeVisible()
    await expect(page.locator('.pg-jobs th', { hasText: 'Control' }), 'no Control column').toHaveCount(0)
    await expect(page.locator('[data-progress-job] .tm-actions'), 'no control cell in any job row').toHaveCount(0)
    await expect(page.locator('[data-progress-job] button', { hasText: /^(Pause|Resume|Run now)$/ }), 'no Pause, Resume or Run now in the jobs board').toHaveCount(0)
    for (const b of await boxes(page, '.m-panel')) expect(b.right, `panel "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })
})
