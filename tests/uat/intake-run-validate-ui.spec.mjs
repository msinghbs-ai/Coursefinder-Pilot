// Guards: Course Intake Run & Validate UI mandate (4 Nov 2026): automatic fixed cohort, governed Run Now, evidence, honest publication verification and role permissions.
import { test, expect } from '@playwright/test'

const cohortId = '11111111-1111-4111-8111-111111111111'
async function mount(page, options = {}) {
  await page.goto('/')
  await page.evaluate(async ({ options, cohortId }) => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: Intake } = await import('/src/IntakeRunValidate.jsx')
    const caps = { contract: 'intake-run-validate-v1', can_run: true, control_rank: 6, min_size: 1, max_size: 20, default_size: 20,
      scopes: [{ id: 'au-top', label: 'Top Australian universities (approved scope)' }, { id: 'all', label: 'All eligible universities' }] }
    const course = { course_id: 'course-1', course_title: 'Bachelor of Science', provider_name: 'University of Melbourne', pattern: 'semester', fills: ['year', 'start_date'],
      at_selection: [{ intake_id: 'intake-1', before: { year: null }, planned: { year: 2027 }, page_quote: 'Semester 1 begins in February', calendar_url: 'https://university.example/calendar' }] }
    window.intakeCalls = []; window.runAttempts = 0
    const client = {
      async read(view, args) {
        window.intakeCalls.push({ method: 'read', view, args })
        if (options.missing) throw new Error('Unknown operation intake_run_validate')
        if (view === 'capabilities') return { ...caps, can_run: !options.readOnly }
        if (view === 'preview' && options.timeout) throw Object.assign(new Error('canceling statement due to statement timeout'), { code: '57014' })
        if (view === 'preview') return { token: 'preview-1', courses: [course], eligible_courses: 37, rule: 'Most gaps first; round-robin providers and evidence patterns', as_at: '2026-11-04T10:00:00Z', expires_at: '2026-11-04T10:10:00Z' }
        return { cohort_id: cohortId, as_at: '2026-11-04T10:02:00Z', totals: { selected: 1, admitted: 1, published: 1, not_as_planned: 0, vendor_calls: 0 }, runs: [{ state: 'done', processed: 1 }], courses: [{ ...course, now: [{ year: 2027 }], added: [{ intake_id: 'intake-1', before: { year: null }, after: { year: 2027 } }], published: 1, website_intakes: [{ year: 2027 }], zoho_intakes: { error: 'Unsupported read-back' } }] }
      },
      async prepare(args) { window.intakeCalls.push({ method: 'prepare', args }); return { cohort_id: cohortId, preview_token: 'preview-1', request_key: 'fixture-key' } },
      async run(id, reason, key) {
        window.intakeCalls.push({ method: 'run', id, reason, key }); window.runAttempts++
        if (options.unknown && window.runAttempts === 1) throw new Error('Network interrupted')
        if (options.refused) return { run_id: 'run-1', state: 'refused', refused: 'job is paused' }
        return { run_id: 'run-1', state: 'done', processed: 1, admitted: 1, skipped: 0, failed: 0, started_at: '2026-11-04T10:01:00Z', finished_at: '2026-11-04T10:02:00Z' }
      },
    }
    document.body.innerHTML = '<div id="intake-test-root"></div>'
    ReactDOM.createRoot(document.getElementById('intake-test-root')).render(React.default.createElement(Intake, { client, rank: options.readOnly ? 3 : 6 }))
  }, { options, cohortId })
  await expect(page.getByRole('heading', { name: 'Course intake Run & Validate' })).toBeVisible()
}
async function fix(page) {
  await page.getByRole('button', { name: 'Preview eligible courses' }).click()
  await expect(page.getByText('Bachelor of Science', { exact: true })).toBeVisible()
  await page.getByLabel('Audited reason').fill('Validate stored intake evidence')
  await page.getByRole('button', { name: 'Fix previewed cohort' }).click()
  await expect(page.getByRole('button', { name: 'Run Now', exact: true })).toBeEnabled()
}
test('preview, fix, run and verify retain evidence and distinguish publication from Zoho support', async ({ page }, testInfo) => {
  await mount(page)
  await page.getByLabel('Cohort size').fill('21')
  await expect(page.getByRole('button', { name: 'Preview eligible courses' })).toBeDisabled()
  await page.getByLabel('Cohort size').fill('10')
  await fix(page)
  await expect(page.getByLabel('University scope')).toBeDisabled()
  await page.getByRole('button', { name: 'Run Now', exact: true }).click()
  await expect(page.getByText('Processed 1 · Admitted 1 · Skipped 0 · Failed 0')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Run Now', exact: true })).toBeDisabled()
  await page.getByRole('button', { name: 'Verify catalogue & publication' }).click()
  await expect(page.getByText('Before', { exact: true })).toBeVisible()
  await page.getByText('Website / Zoho read-back', { exact: true }).click()
  await expect(page.getByText(/Zoho response alone does not prove/)).toBeVisible()
  await expect(page.getByText(/Unsupported read-back/)).toBeVisible()
  const calls = await page.evaluate(() => window.intakeCalls)
  expect(calls.find(c => c.method === 'prepare').args).toEqual({ p_scope: 'au-top', p_size: 10, p_reason: 'Validate stored intake evidence', p_preview_token: 'preview-1' })
  expect(calls.filter(c => c.method === 'run')).toHaveLength(1)
  await page.screenshot({ path: testInfo.outputPath('intake-desktop.png'), fullPage: true })
  await testInfo.attach('desktop UI evidence', { path: testInfo.outputPath('intake-desktop.png'), contentType: 'image/png' })
})
test('missing bridge fails closed and read-only roles cannot prepare or run', async ({ page }) => {
  await mount(page, { missing: true })
  await expect(page.getByText(/Blocked: the required browser bridge/)).toBeVisible()
  expect(await page.evaluate(() => window.intakeCalls.some(c => c.method !== 'read'))).toBe(false)
  await mount(page, { readOnly: true })
  await page.getByRole('button', { name: 'Preview eligible courses' }).click()
  await page.getByLabel('Audited reason').fill('Read only operator')
  await expect(page.getByRole('button', { name: 'Fix previewed cohort' })).toBeDisabled()
  await expect(page.getByRole('button', { name: 'Run Now', exact: true })).toBeDisabled()
  await expect(page.getByRole('button', { name: /AI diagnostic/ })).toHaveCount(0)
})
test('uncertain response recovery reuses the same key and refusal gives a permitted next action', async ({ page }) => {
  await mount(page, { unknown: true })
  await fix(page)
  await page.getByRole('button', { name: 'Run Now', exact: true }).click()
  await expect(page.getByText(/Outcome unknown. Verify this cohort first/)).toBeVisible()
  await page.getByRole('button', { name: 'Recover same request' }).click()
  const runs = await page.evaluate(() => window.intakeCalls.filter(c => c.method === 'run'))
  expect(runs).toHaveLength(2)
  expect(runs[0]).toEqual(runs[1])
  await mount(page, { refused: true })
  await fix(page)
  await page.getByRole('button', { name: 'Run Now', exact: true }).click()
  await expect(page.getByText('job is paused', { exact: true })).toBeVisible()
  await expect(page.getByText(/Next action: verify the cohort/)).toBeVisible()
})
test('scope changes invalidate the preview and require another server selection', async ({ page }) => {
  await mount(page)
  await page.getByRole('button', { name: 'Preview eligible courses' }).click()
  await expect(page.getByText('Bachelor of Science', { exact: true })).toBeVisible()
  await page.getByLabel('University scope').selectOption('all')
  await expect(page.getByText('Bachelor of Science', { exact: true })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Fix previewed cohort' })).toBeDisabled()
})
test('phone operators can preview and verify without page overflow @responsive', async ({ page }, testInfo) => {
  expect(page.viewportSize().width).toBeLessThanOrEqual(480)
  await mount(page)
  await fix(page)
  await page.getByRole('button', { name: 'Run Now', exact: true }).click()
  await page.getByRole('button', { name: 'Verify catalogue & publication' }).click()
  await expect(page.getByText('Current catalogue', { exact: true })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await page.screenshot({ path: testInfo.outputPath('intake-phone.png'), fullPage: true })
  await testInfo.attach('phone UI evidence', { path: testInfo.outputPath('intake-phone.png'), contentType: 'image/png' })
})

test('browser adapter sends only a cohort to the server-bound governed Run Now facade', async ({ page }) => {
  await page.goto('/')
  const calls = []
  await page.route('https://example.supabase.co/rest/v1/rpc/**', async route => {
    calls.push({ url: route.request().url(), body: route.request().postDataJSON() })
    await route.fulfill({ json: { state: 'done' } })
  })
  await page.evaluate(async cohortId => {
    const { intakeRunApi } = await import('/src/intake-run-api.js')
    await intakeRunApi.read('preview', { scope: 'au-top', size: 10 })
    await intakeRunApi.run(cohortId, 'Check stored evidence', 'fixed-key')
  }, cohortId)
  expect(calls).toEqual([
    { url: 'https://example.supabase.co/rest/v1/rpc/admin_intake_run_read_v1', body: { p_view: 'preview', p_args: { scope: 'au-top', size: 10 } } },
    { url: 'https://example.supabase.co/rest/v1/rpc/admin_intake_run_now_v1', body: { p_cohort_id: cohortId } },
  ])
})


test('preview timeout identifies the failed stage and never prepares or dispatches a job', async ({ page }) => {
  await mount(page, { timeout: true })
  await page.getByRole('button', { name: 'Preview eligible courses' }).click()
  await expect(page.getByRole('alert')).toContainText('Preview timed out before a cohort was fixed. No intake job was started.')
  await expect(page.getByRole('button', { name: 'Fix previewed cohort' })).toBeDisabled()
  await expect(page.getByRole('button', { name: 'Run Now', exact: true })).toBeDisabled()
  expect(await page.evaluate(() => window.intakeCalls.every(c => c.method === 'read'))).toBe(true)
})
