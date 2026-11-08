// Guards: StudySearch F-INT.05 (Feature Acceptance Contract, 8 Nov 2026: intake screens tested on a phone with the approved operator roles; IQ-00313) and S121/G4 (phone tests are @responsive and first assert phone width). Automation progress, mocked bridge; nothing reaches a real backend.
import { test, expect } from '@playwright/test'

const PHONE_MAX = 480
const TAP_MIN = 44 // automation-progress.css sets min-height 44px on a phone
const PROVIDER = '22222222-2222-4222-8222-222222222222'

const status = (controls) => ({
  state: 'waiting', job: 'intake-dates-apply', schedule: '26 * * * *', active: true, last_success: '2026-11-08T08:26:00Z', next_run: '2026-11-08T19:26:00Z',
  last_run: { started_at: '2026-11-08T08:26:00Z', finished_at: '2026-11-08T08:27:10Z', runid: 9001, status: 'succeeded' },
  controls: { job: 'intake-dates-apply', control_rank: 6, ...controls },
  batch: 20, pilot_share_pct: 80, provider_share: 5, rate_per_hour_24h: 12,
  pending: { never_examined: 100, revisit_due: 5, measured_at: '2026-11-08T08:00:00Z' }, held: { held: 7, timed_revisit: 3, waiting_for_change: 2, person_required: 2 },
  usage: { ai_cost_usd: 0.1234, ai_window_days: 7, firecrawl_credits_counted: 10, firecrawl_budget: 100 }, scope: ['Deakin University', 'UNSW Sydney'],
  alerts: [
    { code: 'zero_yield', label: 'A run completed but admitted no value', tripped: true, affected: 4, last_success_stage: 'Evidence found', next_action: 'Review the held rows in Layer 4' },
    { code: 'publication_stalled', label: 'Publication is stalled', tripped: false, zero_reason: 'nothing_to_publish' },
  ],
  observer: { job: 'first-run-verify', window_hours: 24, stall_hours: 6, last_run: '2026-11-08T08:30:00Z', status: 'succeeded',
    transitions: [{ key: 'intake_admission', title: 'Admission', eligible: 40, processed: 40, created: 0, zero_reason: 'every_value_refused', stalled: true, stalled_since: '2026-11-08T02:30:00Z', issue: 'IQ-00313', measured_at: '2026-11-08T08:30:00Z' }] },
})
const windowData = { since: '2026-11-07T08:30:00Z', until: '2026-11-08T08:30:00Z', runs: [], universities: [
  { provider_id: PROVIDER, university: 'Deakin University', pilot: true, state: 'eligible_not_admitted', pending: null, selected: 20, eligible: 12, admitted: 0, published: 0, held: 12, last_run: '2026-11-08T08:26:00Z', next_revisit: null },
], funnel: { runs: 24, scheduled_runs: 24, run_now_runs: 0, selected: 400, selected_courses: 300, examined: 300, evidence_found: 250, dates_extracted: 220, dates_validated: 191, admitted: 0, published: 0, withdrawn: 0, net_gain: 0,
  publication_failed: null, provider_not_published: null, publication_not_checked: null, nothing_new: 10, refused_or_held: 90, awaiting_revisit: 40, waiting_for_change: 20 } }
const failures = { total: 1, classes: [{ class: 'identity_refused', rows: 1, person_required: 1 }], rows: [{ intake_id: 'i-1', class: 'identity_refused', course_title: 'Bachelor of Commerce', intake: 'Semester 1 2027', university: 'Deakin University',
  course_url: 'https://www.deakin.edu.au/course/bachelor-commerce', reason: 'Campus not shown on the official page', person_required: true, auto_recover: false, evidence_version: {}, last_attempt: '2026-11-08T08:26:00Z' }] }

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

async function mount(page, controls) {
  await page.goto('/')
  await page.evaluate(async ({ s, win, fails }) => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: AutomationProgress } = await import('/src/AutomationProgress.jsx')
    window.apCalls = []
    const client = {
      async progress(view, args) { window.apCalls.push({ view, args }); return view === 'status' ? s : view === 'window' ? win : view === 'failures' ? fails : [] },
      async control(job, action, args) { window.apCalls.push({ control: job, action, args }); return {} },
    }
    document.body.innerHTML = '<div id="ap-root"></div>'
    ReactDOM.createRoot(document.getElementById('ap-root')).render(React.default.createElement(AutomationProgress, { rank: 6, client }))
  }, { s: status(controls), win: windowData, fails: failures })
  await expect(page.getByTestId('automation-progress')).toBeVisible()
  await expect(page.getByTestId('ap-controls')).toBeVisible()
}

test.describe('Automation progress on a phone @responsive', () => {
  test('a raised alert, a stalled stage and held rows fit the phone; wide tables scroll in their own frame; the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page, { can_pause_resume: true })
    await expect(page.locator('[data-alert="zero_yield"]')).toHaveAttribute('data-tripped', 'yes')
    await expect(page.locator('[data-transition="intake_admission"]')).toHaveAttribute('data-stalled', 'yes')
    // missing figures read "Not held", never a made-up zero
    await expect(page.locator('[data-step="8"]')).toContainText('Not held')
    await expect(page.getByTestId('ap-failures')).toContainText('Campus not shown on the official page')
    for (const id of ['ap-observer', 'ap-universities']) {
      const frame = page.getByTestId(id).locator('xpath=..')
      await frame.scrollIntoViewIfNeeded()
      const f = await frame.evaluate((el) => ({ client: el.clientWidth, scroll: el.scrollWidth, overflowX: getComputedStyle(el).overflowX }))
      expect(f.client, `${id} frame fits the phone`).toBeLessThanOrEqual(w)
      if (f.scroll > f.client) expect(['auto', 'scroll']).toContain(f.overflowX)
    }
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('Pause is a full-width tap target, asks before it acts, and goes only to the existing job control with the job and a reason', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page, { can_pause_resume: true })
    const pause = page.getByRole('button', { name: 'Pause intake job' })
    await pause.scrollIntoViewIfNeeded()
    const b = await pause.boundingBox()
    expect(b.height, 'tap target').toBeGreaterThanOrEqual(TAP_MIN)
    expect(b.x).toBeGreaterThanOrEqual(-1)
    expect(b.x + b.width).toBeLessThanOrEqual(w + 1)
    page.once('dialog', (d) => d.dismiss())
    await pause.click()
    expect(await page.evaluate(() => window.apCalls.filter((c) => c.control))).toHaveLength(0)
    page.once('dialog', (d) => d.accept())
    await pause.click()
    await expect.poll(() => page.evaluate(() => window.apCalls.filter((c) => c.control))).toEqual([
      { control: 'intake-dates-apply', action: 'pause', args: { reason: 'Process results › Automation progress: pause' } },
    ])
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('a university opens its held courses with one tap; a read-only operator sees no Pause and is told why', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page, { can_pause_resume: false, control_rank: 5 })
    await expect(page.getByRole('button', { name: 'Pause intake job' })).toHaveCount(0)
    await expect(page.getByText(/Read only: Pause and Resume are for the PIM Admin and above/)).toBeVisible()
    const courses = page.getByTestId('ap-universities').getByRole('button', { name: 'Courses' })
    await courses.scrollIntoViewIfNeeded()
    expect((await courses.boundingBox()).height, 'tap target').toBeGreaterThanOrEqual(TAP_MIN)
    await courses.click()
    await expect.poll(() => page.evaluate(() => window.apCalls.filter((c) => c.view === 'failures').pop()?.args)).toEqual({ provider_id: PROVIDER })
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })
})
