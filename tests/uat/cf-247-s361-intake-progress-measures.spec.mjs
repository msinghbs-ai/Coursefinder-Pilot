// Guards: Platform Admin direction 6 Nov 2026 (Automation Progress shows newly admitted, net published gain after withdrawals and publication checks passed as three separate measures; 975 checks are 186 new plus 789 older admissions checked again, not 975 new publications). CF-247 agent G, window 5 Nov 11:32 to 6 Nov 11:32.
import { test, expect } from '@playwright/test'

const status = { state: 'waiting', job: 'intake-dates-apply', schedule: '26 * * * *', last_success: '2026-11-06T01:26:00Z', controls: { job: 'intake-dates-apply', can_pause_resume: false, control_rank: 5 },
  pending: { never_examined: 100, revisit_due: 5 }, held: {}, usage: {}, scope: ['UNSW Sydney'], alerts: [],
  observer: { job: 'first-run-verify', window_hours: 24, transitions: [{ key: 'intake_publication', title: 'Publication check', eligible: 186, processed: 975, created: 975, stalled: false }] } }
const win = { since: '2026-11-05T00:32:00Z', until: '2026-11-06T00:32:00Z', runs: [], universities: [],
  funnel: { runs: 24, scheduled_runs: 24, run_now_runs: 0, selected: 400, selected_courses: 300, examined: 300, evidence_found: 250, dates_extracted: 220, dates_validated: 191, admitted: 191, published: 186, withdrawn: 5, net_gain: 186,
    publication_failed: 0, provider_not_published: 0, publication_not_checked: 0, nothing_new: 10, refused_or_held: 90, awaiting_revisit: 40, waiting_for_change: 20 } }

async function mount(page, w) {
  await page.goto('/')
  await page.evaluate(async ({ status, win, w }) => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: AutomationProgress } = await import('/src/AutomationProgress.jsx')
    const client = { async progress(view) { return view === 'status' ? status : view === 'window' ? w : { total: 0, rows: [], classes: [] } }, async control() { return {} } }
    document.body.innerHTML = '<div id="ap-root"></div>'
    ReactDOM.createRoot(document.getElementById('ap-root')).render(React.default.createElement(AutomationProgress, { rank: 5, client }))
  }, { status, win, w })
  await expect(page.getByTestId('ap-measures')).toBeVisible()
}

test('three distinct measures: newly admitted, net published gain after withdrawals, publication checks passed (new plus older re-checked)', async ({ page }) => {
  await page.addInitScript(() => { try { localStorage.setItem('cf.intakeProgress.window', '24h') } catch {} })
  await mount(page, win)
  const m = page.getByTestId('ap-measures')
  await expect(m.locator('[data-measure="newly_admitted"]')).toContainText('191')
  await expect(m.locator('[data-measure="withdrawn"]')).toContainText('5')
  await expect(m.locator('[data-measure="net_published_gain"]')).toContainText('Net published gain after withdrawals')
  await expect(m.locator('[data-measure="net_published_gain"]')).toContainText('186')
  const c = m.locator('[data-measure="publication_checks_passed"]')
  await expect(c).toContainText('Publication checks passed')
  await expect(c).toContainText('975')
  await expect(c).toContainText('186 new plus 789 older admissions checked again')
  await expect(page.getByTestId('ap-window-summary')).not.toContainText('975')
})

test('a window the observer does not read never invents the new-versus-older split @responsive', async ({ page }) => {
  expect(page.viewportSize().width).toBeLessThanOrEqual(480)
  await mount(page, win)
  const c = page.getByTestId('ap-measures').locator('[data-measure="publication_checks_passed"]')
  await expect(c).toContainText('975')
  await expect(c).toContainText('not a count of new publications')
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
})
