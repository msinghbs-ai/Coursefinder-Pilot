// Guards: PR #872 complete UI workflow against isolated PostgreSQL, including saved recovery and consumer verification.
import { test, expect } from '@playwright/test'
async function mount(page) {
  await page.goto('/')
  await page.route('https://example.supabase.co/rest/v1/rpc/**', async route => {
    // Forward to real authenticated PostgreSQL fixture RPC transport; no response is fabricated.
    const response = await page.request.post('http://127.0.0.1:55433' + new URL(route.request().url()).pathname, { data: route.request().postDataJSON() })
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
  // The SQL suite already left an earlier saved run. Start a new preview for the browser-only course.
  const fresh = page.getByRole('button', { name: 'New cohort', exact: true })
  await expect(fresh).toBeVisible(); await fresh.click()
  await page.getByRole('button', { name: 'Preview eligible courses' }).click()
  await expect(page.locator('.intake-course')).toHaveCount(20)
  await expect(page.getByText(/Inland University:.*0 eligible courses/)).toBeVisible()
  await page.getByLabel('Audited reason').fill('Browser to PostgreSQL operational acceptance')
  await page.getByRole('button', { name: 'Fix previewed cohort' }).click()
  await expect(page.getByRole('button', { name: 'Run Now', exact: true })).toBeEnabled()
  let committedRunId
  const interrupt = async route => {
    if (!committedRunId) {
      const result = await page.request.post('http://127.0.0.1:55433/rest/v1/rpc/admin_intake_run_now_v1', { data: route.request().postDataJSON() })
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
