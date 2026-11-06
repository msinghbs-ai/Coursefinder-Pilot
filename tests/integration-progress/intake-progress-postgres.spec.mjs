// Guards: Platform Admin decision 5 Nov 2026 16:36 §3-§8, 19:14 §10 and 20:03 (generic progress observer reused): Process results › Automation progress against isolated PostgreSQL (fixture tests/fixtures/intake-progress): status, the observer's intake readings, funnel and university rows reconcile with the database, Not processed versus zero eligible, the four history windows, the failure list, Pause/Resume through the existing job toggle and its audit, a running job, a read-only role without controls, persistence after refresh, and the phone layout.
import { test, expect } from '@playwright/test'
const FX = 'http://127.0.0.1:55443'
const sql = async (page, q) => (await (await page.request.post(`${FX}/fixture/sql`, { data: { sql: q } })).json()).rows
const actor = (page, rank) => page.request.post(`${FX}/fixture/actor`, { data: { rank } })
async function mount(page, rank = 6) {
  await actor(page, rank)
  await page.goto('/')
  await page.route('https://example.supabase.co/rest/v1/rpc/**', async route => {
    // forwarded to the authenticated PostgreSQL fixture; no response is fabricated
    const response = await page.request.post(FX + new URL(route.request().url()).pathname, { data: route.request().postDataJSON() })
    await route.fulfill({ response })
  })
  await page.evaluate(async rank => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const ReactDOM = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { default: ProcessResults } = await import('/src/ProcessResults.jsx')
    document.body.innerHTML = '<div id="progress-db-root"></div>'
    ReactDOM.createRoot(document.getElementById('progress-db-root')).render(React.createElement(ProcessResults, { rank }))
  }, rank)
  await expect(page.getByRole('heading', { name: 'Automation progress: intake dates' })).toBeVisible()
  await expect(page.getByTestId('ap-funnel')).toBeVisible()
}
const row = (page, name) => page.getByTestId('ap-universities').locator(`tr[data-university="${name}"]`)
const step = (page, n) => page.getByTestId('ap-funnel').locator(`li[data-step="${n}"] strong`)

test('status, the latest run funnel and the university rows match the database; Not processed is not zero eligible', async ({ page }) => {
  await mount(page)
  await expect(page.locator('.ap-state')).toContainText('Waiting for the next run (healthy, idle)')
  const latest = await sql(page, "select count(*) || '|' || count(*) filter (where outcome = 'filled') || '|' || count(*) filter (where publication_state = 'published') from pipeline.course_intake_date_events where run_at = (select max(run_at) from pipeline.course_intake_date_events where outcome <> 'withdrawn')")
  const [selected, admitted, published] = latest.split('|')
  await expect(step(page, 2)).toHaveText(selected)
  await expect(step(page, 7)).toHaveText(admitted)
  await expect(step(page, 8)).toHaveText(published)
  await expect(row(page, 'The University of Newcastle')).toHaveAttribute('data-state', 'not_processed')
  await expect(row(page, 'The University of Newcastle')).toContainText('Not processed')
  await expect(row(page, 'UNSW Sydney')).toHaveAttribute('data-state', 'zero_eligible')
  await expect(row(page, 'UNSW Sydney')).toContainText('Zero eligible')
  await expect(row(page, 'Torrens University Australia')).toContainText('Other provider')
  await expect(page.locator('[data-alert="publication_mismatch"]')).toHaveAttribute('data-tripped', 'yes')
  await expect(page.locator('[data-alert="publication_mismatch"]')).toContainText('raised by the intake checks as intake-progress:publication-mismatch')
  // Platform Admin 22:46: the repeat classification is shown, unverified repeats as a diagnostic
  const rep = JSON.parse(await sql(page, "select security.intake_progress_repeats_v1()::text"))
  await expect(page.getByTestId('ap-repeats')).toContainText(`confirmed ${rep.confirmed}`)
  await expect(page.getByTestId('ap-repeats')).toContainText(`unverified repeats ${rep.unverified_repeat} (diagnostic, not raised)`)
  // decision 20:03: the generic progress observer's readings of the intake chain, as stored by it
  const observer = page.getByTestId('ap-observer')
  await expect(observer.locator('tbody tr')).toHaveCount(3)
  const created = await sql(page, "select output_created from pipeline.progress_transitions where key = 'intake_selection'")
  await expect(observer.locator('tr[data-transition="intake_selection"] td').nth(3)).toHaveText(created)
  await page.getByRole('button', { name: 'Observer readings' }).click()
  await expect(page.getByTestId('ap-observations').locator('li')).toHaveCount(Number(await sql(page, "select count(*) from pipeline.progress_observations where transition_key like 'intake%'")))
})

test('history windows show gross activity and net gain with withdrawals, and the chosen window survives a refresh', async ({ page }) => {
  await mount(page)
  await page.getByRole('button', { name: 'Last 24 hours' }).click()
  await expect(page.getByTestId('ap-window-summary')).toContainText('net data gain 3 (admitted 4, withdrawn 1)')
  await expect(row(page, 'The University of Newcastle')).toHaveAttribute('data-state', 'admitted')
  await page.getByRole('button', { name: 'Last 30 days' }).click()
  const db = await sql(page, "select count(*) filter (where outcome <> 'withdrawn') from pipeline.course_intake_date_events where run_at >= now() - interval '30 days'")
  await expect(page.getByTestId('ap-window-summary')).toContainText(`gross activity ${db} rows`)
  await expect(page.getByTestId('ap-window-summary')).toContainText('net data gain 5 (admitted 6, withdrawn 1)')
  await page.reload(); await mount(page)
  await expect(page.getByRole('button', { name: 'Last 30 days' })).toHaveAttribute('aria-pressed', 'true')
  await expect(page.getByTestId('ap-window-summary')).toContainText('net data gain 5')
  await page.getByRole('button', { name: 'Latest run' }).click()
  await expect(page.getByTestId('ap-window-summary')).toContainText('net data gain 2')
})

test('the failure list: every held row with its reason, next action and issue; drill-down by university', async ({ page }) => {
  await mount(page)
  const total = await sql(page, "select count(*) from pipeline.course_intake_dates where outcome <> 'filled' or failure_class is not null or publication_state = 'consumer_publication_failed'")
  await expect(page.getByTestId('ap-failures').getByRole('heading')).toContainText(`Failures and holds (${total} intake rows`)
  const pub = page.locator('.ap-failure[data-class="consumer_publication_failed"]')
  await expect(pub).toContainText(await sql(page, "select issue_ref from pipeline.integration_issues where fingerprint = 'intake-dates:fixture-publication'"))
  await expect(pub).toContainText('not in the Website API v2 source')
  await expect(page.locator('.ap-failure[data-class="admission_held"]')).toContainText('A person must actYes')
  await row(page, 'UNSW Sydney').getByRole('button', { name: 'Courses' }).click()
  await expect(page.getByTestId('ap-failures').getByRole('heading')).toContainText('UNSW Sydney')
  const unsw = await sql(page, "select count(*) from pipeline.course_intake_dates where provider_id = md5('intake-progress:p:unsw')::uuid and (outcome <> 'filled' or failure_class is not null)")
  await expect(page.locator('.ap-failure')).toHaveCount(Number(unsw))
})

test('Pause and Resume use the existing job toggle and its audit', async ({ page }) => {
  await mount(page)
  const calls = []
  page.on('request', r => { if (r.url().includes('/rpc/admin_automation_control')) calls.push(r.postDataJSON()) })
  page.on('dialog', d => d.accept())
  await page.getByRole('button', { name: 'Pause intake job' }).click()
  await expect(page.locator('.ap-state')).toContainText('Paused')
  expect(await sql(page, "select active from cron.job where jobname = 'intake-dates-apply'")).toBe('f')
  expect(await sql(page, "select count(*) from pipeline.admin_control_events where action = 'pause' and target = 'intake-dates-apply' and actor = md5('intake-progress:user:6')::uuid and detail->>'reason' = 'Process results › Automation progress: pause'")).toBe('1')
  await page.getByRole('button', { name: 'Resume intake job' }).click()
  await expect(page.locator('.ap-state')).toContainText('Waiting for the next run')
  expect(await sql(page, "select active from cron.job where jobname = 'intake-dates-apply'")).toBe('t')
  expect(await sql(page, "select count(*) from pipeline.admin_control_events where action = 'resume' and detail->>'reason' = 'Process results › Automation progress: resume'")).toBe('1')
  expect(calls.map(c => [c.p_job, c.p_action])).toEqual([['intake-dates-apply', 'pause'], ['intake-dates-apply', 'resume']])
})

test('a running job shows its open run; a read-only role sees no controls and is refused by the server', async ({ page }) => {
  await sql(page, "insert into cron.job_run_details(jobid, status, start_time) values ((select jobid from cron.job where jobname = 'intake-dates-apply'), 'running', now())")
  try {
    await mount(page)
    const runid = await sql(page, "select max(runid) from cron.job_run_details")
    await expect(page.locator('.ap-state')).toContainText('Running')
    await expect(page.getByText(`run ${runid}`).first()).toBeVisible()
  } finally { await sql(page, "delete from cron.job_run_details where status = 'running'") }
  await mount(page, 3)
  await expect(page.getByTestId('ap-funnel')).toBeVisible()
  await expect(page.getByRole('button', { name: /Pause intake job|Resume intake job/ })).toHaveCount(0)
  await expect(page.getByText('Read only: Pause and Resume are for the PIM Admin and above')).toBeVisible()
  await expect(page.getByRole('link', { name: 'Integration queue' })).toHaveCount(0)
  const refused = await page.request.post(`${FX}/rest/v1/rpc/admin_automation_control`, { data: { p_job: 'intake-dates-apply', p_action: 'pause', p_args: {} } })
  expect(refused.status()).toBe(400)
  expect(await sql(page, "select active from cron.job where jobname = 'intake-dates-apply'")).toBe('t')
})

test('phone: Automation progress is usable without page overflow @responsive', async ({ page }) => {
  expect(page.viewportSize().width).toBeLessThanOrEqual(480)
  await mount(page)
  await expect(row(page, 'The University of Newcastle')).toContainText('Not processed')
  await row(page, 'UNSW Sydney').getByRole('button', { name: 'Courses' }).click()
  await expect(page.getByTestId('ap-failures').getByRole('heading')).toContainText('UNSW Sydney')
  await page.getByRole('button', { name: 'Last 7 days' }).click()
  await expect(page.getByTestId('ap-window-summary')).toContainText('net data gain 4')
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
})
