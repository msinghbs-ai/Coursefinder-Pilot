// Guards: Platform Admin directive 19 Nov 2026 06:49 (chat S2-BOOST-Courses), item 5: read-only live verification, as the governed UAT user in PIM Admin, of the Coverage attribute counts and the Layer 4 Inbox queue; G3 (consumer API untouched: nothing is written) and G4 (a deployed spec that acts on nothing is not @live-acting).
// Runs on deploy only when .github/s2-boost-live-counts-candidate changes (deployed-uat.yml). It signs in with the repository Actions secrets the other deployed specs use, never prints them, clicks no decision and saves nothing.
import { test, expect } from '@playwright/test'
import { loginAsUatUser, observeRuntime, attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, writeRunEnvironment } from './support/runtime-evidence.mjs'

const at = (hash) => new URL(`/#${hash}`, process.env.UAT_BASE_URL).toString()
const WANT = /course description|description|study load|intake|fee|deadline|campus|requirement|pending|held|waiting|total|admitted|complete|\d[\d,]*\s*(of|\/)\s*\d[\d,]*/i
const report = (title, text) => {
  const lines = String(text || '').split(/\n+/).map((x) => x.trim()).filter((x) => x && x.length < 200 && /\d/.test(x) && WANT.test(x)).slice(0, 80)
  console.log(`UI-COUNTS ${title}: ${lines.length} lines`)
  for (const l of lines) console.log(`UI-COUNTS ${title} | ${l}`)
  return lines
}

test.describe('S2-BOOST-Courses live counts in PIM Admin (read-only) @deployed', () => {
  test.beforeAll(async () => { await writeRunEnvironment({ suite: 'cf-247-s728-pim-admin-live-counts', change_control: 'CF-CHG-20260915-247' }) })

  test('Coverage (Courses, Attributes) and the Layer 4 Inbox show live figures', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page)
    try {
      await loginAsUatUser(page)
      console.log(`UI-COUNTS release pill: ${(await page.locator('.m-release-pill').first().innerText().catch(() => '')).trim()}`)
      for (const [name, hash, tab] of [['Coverage Courses', 'coverage', 'Courses'], ['Coverage Attributes', 'coverage', 'Attributes'], ['Layer 4 Inbox', 'layer-4-review', 'Inbox']]) {
        await page.goto(at(hash))
        const t = page.getByRole('tab', { name: tab, exact: true }).first()
        if (await t.isVisible({ timeout: DETERMINISTIC_UI_TIMEOUT }).catch(() => false)) await t.click()
        await expect(page.locator('.m-nav')).toBeVisible({ timeout: DETERMINISTIC_UI_TIMEOUT })
        await page.waitForTimeout(6000)
        const lines = report(name, await page.locator('body').innerText())
        expect(lines.length, `${name} shows figures`).toBeGreaterThan(0)
        await page.screenshot({ path: testInfo.outputPath(`${name.replace(/\W+/g, '-').toLowerCase()}.png`), fullPage: false })
      }
    } finally { await attachRuntimeEvidence(testInfo, runtime) }
    assertNoServerErrors(runtime)
  })
})
