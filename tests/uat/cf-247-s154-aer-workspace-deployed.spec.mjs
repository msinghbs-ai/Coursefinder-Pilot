// Guards: CF-247 AER operations workspace deployed acceptance (Platform Admin mandate 29 Oct 2026 08:06, item 10; admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md): the live workspace opens, its summary, combined filters, Columns menu, list, drawer, pills, sources and resolution inspection work against live data with every list read bounded and no console or server errors; a governed edit of a live row and its history is exercised only under the live-acting switch
// Runs on deploy: deployed-uat.yml targets this spec when the workspace, its migration or this spec changes; it is in the acceptance tier and the weekly deployed run.
import { test, expect } from '@playwright/test'
import { loginAsUatUser, observeRuntime, attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo, runtime) { await attachRuntimeEvidence(testInfo, runtime); assertNoServerErrors(runtime) }
const at = (hash) => new URL(`/#${hash}`, process.env.UAT_BASE_URL).toString()
function watchAer(page) {
  const calls = []
  page.on('request', (r) => { if (r.url().includes('/rest/v1/rpc/admin_aer')) { try { const b = r.postDataJSON() || {}; calls.push({ action: b.p_action, args: b.p_args || {} }) } catch { /* not JSON */ } } })
  return calls
}

test.describe('CF-247 AER operations workspace @deployed', () => {
  test.beforeAll(async () => { await writeRunEnvironment({ suite: 'cf-247-s154-aer-workspace', change_control: 'CF-CHG-20260915-247' }) })

  test('the workspace on live data: summary, combined filters, columns, drawer, sources and resolution, bounded', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page); const calls = watchAer(page)
    const consoleErrors = []; page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|favicon/i.test(m.text())) consoleErrors.push(m.text()) })
    try {
      await loginAsUatUser(page)
      await page.goto(at('entry-requirements'))
      await expect(page.getByRole('tab', { name: 'Provider entry matrix' })).toHaveAttribute('aria-selected', 'true', { timeout: DETERMINISTIC_UI_TIMEOUT })
      await expect(page.locator('[data-aer-tile="active"] strong')).toHaveText(/^\d[\d,]*$/, { timeout: DETERMINISTIC_UI_TIMEOUT })
      for (const k of ['proposed', 'quarantined', 'withdrawn', 'held', 'courses']) await expect(page.locator(`[data-aer-tile="${k}"]`)).toBeVisible()
      // combined filters on live data: India, active (the default), RMIT
      const bar = page.locator('[data-aer-filters="matrix"]')
      await bar.getByRole('button', { name: /Country/ }).click(); await page.locator('.m-filter-popover input').fill('India'); await page.locator('.m-filter-popover').getByRole('button', { name: /^India/ }).first().click()
      await bar.getByRole('button', { name: /Provider/ }).click(); await page.locator('.m-filter-popover input').fill('RMIT'); await page.locator('.m-filter-popover').getByRole('button', { name: /RMIT/ }).first().click()
      await expect.poll(() => calls.filter((c) => c.action === 'matrix_list').at(-1)?.args).toMatchObject({ country: 'IN' })
      await expect(page.locator('table[data-table="aer-matrix"] tbody tr').first()).toContainText('India', { timeout: DETERMINISTIC_UI_TIMEOUT })
      await expect(page.locator('[data-aer-pill="active"]').first()).toContainText('Active')
      // flexible columns
      await page.locator('[data-aer-columns] summary').click(); await page.locator('[data-aer-col="quote"]').uncheck()
      await expect(page.locator('table[data-table="aer-matrix"] thead')).not.toContainText('Quote')
      await page.locator('[data-aer-col="quote"]').check(); await page.locator('[data-aer-columns] summary').click()
      // the drawer: quote, stored copy, history section
      await page.locator('table[data-table="aer-matrix"] tbody tr').first().click()
      const d = page.locator('[data-aer-drawer="matrix"]')
      await expect(d.locator('[data-aer-quote]')).not.toBeEmpty({ timeout: DETERMINISTIC_UI_TIMEOUT })
      await expect(d).toContainText('Stored copy'); await expect(d).toContainText('History')
      await d.getByRole('button', { name: 'Close detail' }).click()
      // sources, reads and holds
      await page.goto(at('entry-requirements?tab=sources'))
      await expect(page.locator('[data-aer-view="sources"] table[data-table="aer-sources"] tbody tr').first()).toBeVisible({ timeout: DETERMINISTIC_UI_TIMEOUT })
      await expect(page.locator('[data-aer-hold]').first()).toBeVisible()
      // resolution inspection: RMIT Bachelor of Engineering (Honours), India (the developer guide's worked example)
      await page.goto(at('entry-requirements?tab=resolve'))
      await page.locator('[data-aer-resolve-course]').fill('0100714')
      await page.locator('.aer-suggest button').first().click()
      await page.getByRole('button', { name: /Country of prior education/ }).click(); await page.locator('.m-filter-popover input').fill('India'); await page.locator('.m-filter-popover').getByRole('button', { name: /^India/ }).first().click()
      await expect(page.locator('[data-aer-outcome]')).toBeVisible({ timeout: DETERMINISTIC_UI_TIMEOUT })
      await expect(page.locator('[data-aer-steps] tbody tr')).toHaveCount(5)
      await expect(page.locator('[data-aer-steps]')).toContainText('Used')
      // every list read was bounded
      const lists = calls.filter((c) => /_list$/.test(c.action))
      expect(lists.length).toBeGreaterThan(0)
      for (const c of lists) expect(Number(c.args.page_size || 0)).toBeLessThanOrEqual(100)
      expect(consoleErrors).toEqual([])
    } finally { await finish(testInfo, runtime) }
  })

  test('a governed edit of a live active row, its history and version, then put back @live-acting', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page); const calls = watchAer(page)
    try {
      await loginAsUatUser(page)
      await page.goto(at('entry-requirements'))
      await expect(page.locator('[data-aer-edit-toggle]')).toBeVisible({ timeout: DETERMINISTIC_UI_TIMEOUT })  // the UAT user is Curator or above
      const bar = page.locator('[data-aer-filters="matrix"]')
      await bar.getByRole('button', { name: /Country/ }).click(); await page.locator('.m-filter-popover input').fill('India'); await page.locator('.m-filter-popover').getByRole('button', { name: /^India/ }).first().click()
      await page.locator('[data-aer-edit-toggle]').click()
      const edit = page.locator('[data-aer-edit="matrix"]')
      await edit.locator('[data-aer-reason]').fill('UAT governed edit: as-at put back in the same test')
      const row = edit.locator('tbody tr[data-edit-row]').filter({ has: page.locator('[data-aer-pill="active"]') }).first()
      const id = await row.getAttribute('data-edit-row')
      const before = (await row.locator('[data-aer-cell="as_at"]').innerText()).trim()
      await row.locator('[data-aer-cell="as_at"]').click()
      const input = row.getByLabel(/As at for/)
      const was = await input.inputValue()
      await input.fill('2026-10-01'); await input.press('Enter')
      await expect.poll(() => calls.filter((c) => c.action === 'update').length).toBe(1)
      await expect(row.locator('[data-aer-cell="as_at"]')).not.toHaveText(before)
      // put it back
      await row.locator('[data-aer-cell="as_at"]').click(); await row.getByLabel(/As at for/).fill(was); await row.getByLabel(/As at for/).press('Enter')
      await expect.poll(() => calls.filter((c) => c.action === 'update').length).toBe(2)
      await expect(row.locator('[data-aer-cell="as_at"]')).toHaveText(before)
      // the history in the drawer: both changes, before and after, with the reason
      await row.locator('.aer-row-link').click()
      const d = page.locator('[data-aer-drawer="matrix"]')
      await expect(d.locator('[data-aer-history]')).toContainText('UAT governed edit: as-at put back in the same test', { timeout: DETERMINISTIC_UI_TIMEOUT })
      await expect.poll(() => d.locator('[data-aer-history] tbody tr').filter({ hasText: 'Edited as_at' }).count(), { timeout: DETERMINISTIC_UI_TIMEOUT }).toBeGreaterThanOrEqual(2)
      const r = calls.filter((c) => c.action === 'update').map((c) => c.args)
      expect(r[0]).toMatchObject({ kind: 'matrix', id, reason: 'UAT governed edit: as-at put back in the same test', changes: { as_at: '2026-10-01' } })
      expect(r[1].changes.as_at).toBe(was)
      expect(r[1].expected_updated_at).not.toBe(r[0].expected_updated_at)  // the second save carried the row as returned by the first
    } finally { await finish(testInfo, runtime) }
  })
})
