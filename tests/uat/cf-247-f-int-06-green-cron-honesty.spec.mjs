// Guards: F-INT.06 under IQ-00313 (first-run and scheduled controls: no "green cron / failed work" false positives on the existing Automation progress screen); read only, no migration, setting, edge function or consumer API change
import { test, expect } from '@playwright/test'
import { runHealth, stateConflict } from '../../src/intake-job-health.js'

test('a finished scheduled run is flagged when it selected nothing or admitted and published nothing; unknown figures are not flagged', () => {
  expect(runHealth({ cron_run: { status: 'succeeded' }, selected: 0, admitted: 0 }).text).toMatch(/selected no rows/)
  expect(runHealth({ cron_run: { status: 'succeeded' }, selected: 40, admitted: 0, published: 0 }).text).toMatch(/selected 40 rows, but admitted and published none/)
  expect(runHealth({ cron_run: { status: 'succeeded' }, selected: 40, admitted: 0, published: null }).tone).toBe('warning')
  expect(runHealth({ cron_run: { status: 'failed' }, selected: 40, admitted: 3 }).tone).toBe('danger')
  expect(runHealth({ cron_run: { status: 'succeeded' }, selected: 40, admitted: 3, published: 3 })).toBeNull()
  expect(runHealth({ cron_run: { status: 'succeeded' }, selected: 40, admitted: 0, published: 2 })).toBeNull()
  expect(runHealth({ cron_run: { status: 'succeeded' }, selected: null, admitted: null })).toBeNull()
  expect(runHealth({ selected: 40, admitted: 0 })).toBeNull()
  expect(runHealth(null)).toBeNull()
})

test('a waiting job is flagged when a stage is stalled or an alert is raised; any other state or a clear job is left alone', () => {
  const base = { state: 'waiting', observer: { transitions: [{ key: 'intake_publication', title: 'Publication check', stalled: false }] }, alerts: [{ code: 'a', tripped: false }] }
  expect(stateConflict(base)).toBeNull()
  expect(stateConflict({ ...base, state: 'failed', alerts: [{ tripped: true }] })).toBeNull()
  expect(stateConflict({ ...base, observer: { transitions: [{ key: 'k', title: 'Admission', stalled: true }] } }).text).toMatch(/stage Admission is stalled/)
  expect(stateConflict({ ...base, alerts: [{ tripped: true }, { tripped: true }] }).text).toMatch(/2 alerts are raised/)
  expect(stateConflict(null)).toBeNull()
})

test('the Automation progress screen shows both flags from the bridge data', async ({ page }) => {
  const status = { state: 'waiting', job: 'intake-dates-apply', schedule: '26 * * * *', last_success: '2026-11-06T01:26:00Z', controls: { job: 'intake-dates-apply', can_pause_resume: false, control_rank: 5 },
    pending: { never_examined: 100, revisit_due: 5 }, held: {}, usage: {}, scope: ['UNSW Sydney'], alerts: [],
    observer: { job: 'first-run-verify', window_hours: 24, transitions: [{ key: 'intake_admission', title: 'Admission', eligible: 50, processed: 0, created: 0, stalled: true, stalled_since: '2026-11-05T20:00:00Z' }] } }
  const win = { since: '2026-11-05T00:32:00Z', until: '2026-11-06T00:32:00Z', universities: [],
    runs: [{ run_at: '2026-11-06T01:26:00Z', kind: 'scheduled', cron_run: { runid: 9, status: 'succeeded' }, selected: 40, validated: 0, admitted: 0, published: 0, held: 40, by_provider: [] }],
    funnel: { runs: 1, scheduled_runs: 1, run_now_runs: 0, selected: 40, selected_courses: 40, admitted: 0, published: 0, withdrawn: 0, net_gain: 0 } }
  await page.goto('/')
  await page.evaluate(async ({ status, win }) => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: AutomationProgress } = await import('/src/AutomationProgress.jsx')
    const client = { async progress(view) { return view === 'status' ? status : view === 'window' ? win : { total: 0, rows: [], classes: [] } }, async control() { return {} } }
    document.body.innerHTML = '<div id="ap-root"></div>'
    ReactDOM.createRoot(document.getElementById('ap-root')).render(React.default.createElement(AutomationProgress, { rank: 5, client }))
  }, { status, win })
  await expect(page.getByText(/stage Admission is stalled/)).toBeVisible()
  await page.getByText(/Runs in this window/).click()
  await expect(page.getByText(/selected 40 rows, but admitted and published none/)).toBeVisible()
})
