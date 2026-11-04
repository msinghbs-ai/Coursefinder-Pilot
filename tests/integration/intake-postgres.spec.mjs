// Guards: PR #872 complete UI workflow against isolated PostgreSQL, including saved recovery and consumer verification.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const previewTimings = []
async function mount(page) {
  await page.goto('/')
  await page.route('https://example.supabase.co/rest/v1/rpc/**', async route => {
    // Forward to real authenticated PostgreSQL fixture RPC transport; no response is fabricated.
    // Fixed test transport allowance covers local Docker startup/JSON delivery; SQL and locks remain capped at 8s.
    const started = performance.now()
    const response = await page.request.post('http://127.0.0.1:55433' + new URL(route.request().url()).pathname, { data: route.request().postDataJSON(), timeout: 60_000 })
    if (route.request().url().includes('/admin_intake_preview_v1')) previewTimings.push({ action: route.request().postDataJSON().p_action, milliseconds: performance.now() - started, ok: response.ok(), error: response.ok() ? null : (await response.json()).message })
    await route.fulfill({ response })
  })
  await page.evaluate(async () => {
    const React = (await import('/node_modules/.vite/deps/react.js')).default
    const ReactDOM = (await import('/node_modules/.vite/deps/react-dom_client.js')).default
    const { default: Component } = await import('/src/IntakeRunValidate.jsx')
    document.body.innerHTML = '<div id="intake-db-root"></div>'
    ReactDOM.createRoot(document.getElementById('intake-db-root')).render(React.createElement(Component, { rank: 6 }))
  })
  await expect(page.getByRole('heading', { name: 'Course intake Run & Validate' })).toBeVisible()
}
test('operator previews, fixes, runs, verifies and restores saved database outcome', async ({ page }, testInfo) => {
  await mount(page)
  testInfo.setTimeout(600_000)
  // The SQL suite already left an earlier saved run. Start a new preview for the browser-only course.
  const fresh = page.getByRole('button', { name: 'New cohort', exact: true })
  await expect(fresh).toBeVisible(); await fresh.click()
  let droppedPreviewPage = false
  const interruptPreview = async route => {
    const args = route.request().postDataJSON()
    if (args.p_action !== 'step' || droppedPreviewPage) { await route.fallback(); return }
    const result = await page.request.post('http://127.0.0.1:55433/rest/v1/rpc/admin_intake_preview_v1', { data: args, timeout: 60_000 })
    expect(result.ok()).toBe(true)
    droppedPreviewPage = true
    await route.abort('failed')
  }
  await page.route('**/rpc/admin_intake_preview_v1', interruptPreview)
  await page.getByRole('button', { name: 'Preview eligible courses' }).click()
  await expect(page.getByRole('button', { name: 'Resume preview' })).toBeVisible({ timeout: 30_000 })
  await page.unroute('**/rpc/admin_intake_preview_v1', interruptPreview)
  await page.getByRole('button', { name: 'Resume preview' }).click()
  let queryTimeoutResumes = 0
  await expect(async () => {
    // Exercise the visible operator recovery path if local CPU contention cancels a page.
    // Never retry other errors or raise the 8s SQL limit; completed/verified results remain mandatory.
    if (await page.getByRole('button', { name: 'Resume preview' }).isVisible()) {
      await expect(page.getByRole('alert')).toContainText('Preview timed out')
      expect(++queryTimeoutResumes).toBeLessThanOrEqual(3)
      await page.getByRole('button', { name: 'Resume preview' }).click()
    }
    expect(await page.locator('.intake-course').count()).toBe(20)
  }).toPass({ timeout: 540_000, intervals: [1000] })
  await expect(page.getByText(/Inland University:.*0 eligible courses/)).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Master of Dense Identity 000000000021' })).toBeVisible()
  fs.writeFileSync('uat-artifacts/intake-complete-scan.json', JSON.stringify({ environment: 'Isolated PostgreSQL17.6; dense evidence; 8s statement/lock timeout per request', query_timeout_resumes: queryTimeoutResumes, timings: previewTimings, max_request_ms: Math.max(...previewTimings.map(x => x.milliseconds)) }, null, 2))
  expect(previewTimings.every(x => x.ok || /statement timeout/.test(x.error || ''))).toBe(true)
  await page.getByLabel('Audited reason').fill('Browser to PostgreSQL operational acceptance')
  await expect(page.getByRole('button', { name: 'Run Now', exact: true })).toBeEnabled()
  let committedRunId
  const interrupt = async route => {
    if (!committedRunId) {
      const result = await page.request.post('http://127.0.0.1:55433/rest/v1/rpc/admin_intake_run_now_v1', { data: route.request().postDataJSON(), timeout: 60_000 })
      expect(result.ok()).toBe(true)
      committedRunId = (await result.json()).run_id
    }
    await route.abort('failed') // Commit real SQL, then lose only its HTTP response.
  }
  await page.route('**/rpc/admin_intake_run_now_v1', interrupt)
  await page.getByRole('button', { name: 'Run Now', exact: true }).click()
  await expect(page.getByText(/Outcome unknown. Verify this cohort first/)).toBeVisible()
  await page.unroute('**/rpc/admin_intake_run_now_v1', interrupt)
  await page.getByRole('button', { name: 'Recover same request' }).click()
  await expect(page.getByText(new RegExp(`Run: ${committedRunId}`))).toBeVisible()
  await expect(page.getByText(/Processed 20 · Admitted 20 · Skipped 0 · Failed 0/)).toBeVisible()
  await page.getByRole('button', { name: 'Verify catalogue & publication' }).click()
  await expect(page.getByText('Catalogue: verified · Website: verified · Zoho: unsupported', { exact: true })).toHaveCount(20)
  await page.getByText('Website / Zoho read-back', { exact: true }).first().click()
  await expect(page.getByText('Catalogue: verified · Website: verified · Zoho: unsupported').first()).toBeVisible()
  await page.locator('.intake-course').evaluateAll(nodes => nodes.slice(1).forEach(n => n.querySelectorAll('details').forEach(d => d.open = false)))
  await page.screenshot({ path: testInfo.outputPath('intake-database-desktop.png'), fullPage: true })
  await testInfo.attach('real database desktop', { path: testInfo.outputPath('intake-database-desktop.png'), contentType: 'image/png' })
  await mount(page)
  await expect(page.getByText(/Processed 20 · Admitted 20 · Skipped 0 · Failed 0/)).toBeVisible()
  await expect(page.getByText('Current catalogue', { exact: true }).first()).toBeVisible()
  await expect(page.getByRole('button', { name: 'Run Now', exact: true })).toBeDisabled()
  const id = await page.getByLabel('Existing cohort ID').inputValue()
  const savedRead = page.waitForResponse(r => r.url().includes('/rpc/admin_intake_run_read_v1') && r.request().postDataJSON()?.p_view === 'verify')
  await page.getByLabel('Saved cohorts').selectOption(id)
  await savedRead
  await expect(page.getByText('Reading verification…', { exact: true })).toBeHidden()
  await expect(page.getByText(/Processed 20 · Admitted 20 · Skipped 0 · Failed 0/)).toBeVisible()
})
test('saved database admission and publication can be inspected on phone @responsive', async ({ page }, testInfo) => {
  expect(page.viewportSize().width).toBeLessThanOrEqual(480)
  await mount(page)
  await expect(page.getByText(/Processed 20 · Admitted 20 · Skipped 0 · Failed 0/)).toBeVisible()
  await page.getByText('Website / Zoho read-back', { exact: true }).first().click()
  await expect(page.getByText('Catalogue: verified · Website: verified · Zoho: unsupported').first()).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await page.locator('.intake-course').evaluateAll(nodes => nodes.slice(1).forEach(n => n.querySelectorAll('details').forEach(d => d.open = false)))
  await page.screenshot({ path: testInfo.outputPath('intake-database-phone.png'), fullPage: true })
  await testInfo.attach('real database phone', { path: testInfo.outputPath('intake-database-phone.png'), contentType: 'image/png' })
})
