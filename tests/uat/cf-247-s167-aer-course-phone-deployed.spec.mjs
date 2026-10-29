// Guards: CF-247 AER Course detail and phone deployed acceptance (Platform Admin mandate 29 Oct 2026 12:23 section C): on the live site with real data (DP020 checks at desktop and phone width; drawer and notice at phone width), an Entry requirements row tap opens its drawer with the quote and the drawer closes; the low-credit notice (when shown) starts inside the screen; DP020 Course detail offers India, Nepal, Singapore first then A to Z, India resolves through the resolver only (no AI read), the scholarships result shows, the evidence overlay opens with its timeline (the blade embeds no history) and closes with Escape; no console errors and every list read bounded. Read-only: nothing is edited or read again.
// Runs on deploy: deployed-uat.yml targets this spec when Course detail, the evidence overlay, the country order, the shell notice or this spec changes; it is in the acceptance tier and the weekly deployed run.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { loginAsUatUser, observeRuntime, attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, writeRunEnvironment } from './support/runtime-evidence.mjs'

const DP020 = 'b365fde8-d003-4ef6-80c3-4136fbd5587a'  // RMIT Diploma of Commerce (CRICOS 111278B)
const PRIORITY = ['India', 'Nepal', 'Singapore']
async function finish(testInfo, runtime) { await attachRuntimeEvidence(testInfo, runtime); assertNoServerErrors(runtime) }
function watch(page) {
  const calls = []
  page.on('request', (r) => { if (/\/rest\/v1\/rpc\/(admin_aer|admin_entry_requirements)$/.test(new URL(r.url()).pathname)) { try { const b = r.postDataJSON() || {}; calls.push({ rpc: new URL(r.url()).pathname.split('/').pop(), action: b.p_action, args: b.p_args || {} }) } catch { /* not JSON */ } } })
  return calls
}
function consoleWatch(page) { const errors = []; page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|favicon/i.test(m.text())) errors.push(m.text()) }); return errors }
const at = (hash) => new URL(`/#${hash}`, process.env.UAT_BASE_URL).toString()

// DP020 Course detail (read-only): India, Nepal, Singapore first (those available) then A to Z; India through the resolver only; the scholarships
// result; the evidence overlay with its timeline (the blade embeds none), fitting the screen and closed with Escape
async function dp020(page, calls, act) {
    // 3. DP020 Course detail: India, Nepal, Singapore first (those available), then A to Z
    await page.goto(at(`courses?id=${DP020}`))
    const blade = page.locator('aside.m-drawer-course')
    const select = blade.getByLabel('Country of prior education')
    await expect(select).toBeVisible({ timeout: DETERMINISTIC_UI_TIMEOUT })
    const names = (await select.locator('option').allTextContents()).map((t) => t.trim()).filter((t) => t && t !== 'Choose…')
    expect(names.length).toBeGreaterThan(3)
    const head = names.filter((n) => PRIORITY.some((p) => n.startsWith(p)))
    expect(names.slice(0, head.length)).toEqual(head)
    expect(head.map((n) => PRIORITY.findIndex((p) => n.startsWith(p)))).toEqual([...head.map((n) => PRIORITY.findIndex((p) => n.startsWith(p)))].sort((a, b) => a - b))
    const rest = names.slice(head.length)
    expect(rest).toEqual([...rest].sort((a, b) => a.localeCompare(b)))
    // 4. India resolves through the resolver only: no read, no AI
    const before = calls.length
    await select.selectOption({ label: names.find((n) => n.startsWith('India')) })
    const outcome = blade.locator('[data-entry-resolution]')
    await expect(outcome).toBeVisible({ timeout: DETERMINISTIC_UI_TIMEOUT })
    await expect(outcome).not.toBeEmpty()
    const after = calls.slice(before)
    expect(after.some((c) => c.action === 'resolve')).toBe(true)
    expect(after.filter((c) => ['read', 'reread', 'update', 'add', 'lifecycle'].includes(c.action))).toEqual([])
    // 5. the scholarships result shows (cards, or the explained empty state)
    await expect(blade.locator('[data-course-scholarships]')).toBeVisible()
    // 6. the evidence overlay: the blade embeds no history; the overlay shows the timeline, fits the screen and closes with Escape
    await expect(page.locator('[data-course-audit]')).toHaveCount(0)  // the timeline section exists only inside the overlay
    await blade.locator('[data-course-evidence-open]')[act]()
    const dialog = page.getByRole('dialog')
    await expect(dialog).toBeVisible({ timeout: DETERMINISTIC_UI_TIMEOUT })
    await expect(page.locator('[data-ca-kind]').first()).toBeVisible({ timeout: DETERMINISTIC_UI_TIMEOUT })
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)
    await page.keyboard.press('Escape')
    await expect(dialog).toHaveCount(0)
}

test('the deployed acceptance runs on deploy: targeted (desktop and phone) for Course detail, overlay, country order and notice changes, and in the acceptance tier', () => {
  const wf = fs.readFileSync('.github/workflows/deployed-uat.yml', 'utf8')
  expect(wf).toContain("grep -Eq '(^src/(CourseAudit\\.jsx|Overlay\\.jsx|overlay\\.css|EntryRequirements\\.jsx|aer-countries\\.js|CreditBanner\\.jsx)$|^tests/uat/cf-247-s167-aer-course-phone-deployed\\.spec\\.mjs$)'; then\n            targeted=(tests/uat/cf-247-s167-aer-course-phone-deployed.spec.mjs)")
  expect(wf).toContain('            tests/uat/cf-247-s167-aer-course-phone-deployed.spec.mjs\n            tests/uat/cf-247-s154-aer-workspace-deployed.spec.mjs\n          )\n          case')
  // a targeted run whose spec holds phone checks also runs the phone project (otherwise the phone gate runs only in the wider tiers)
  expect(wf).toContain(`if [ "$UAT_TIER" = "targeted" ] && grep -l '@responsive' "\${specs[@]}" >/dev/null 2>&1; then echo "mobile=true" >> "$GITHUB_OUTPUT"`)
  expect(wf).toContain("if: steps.tier.outputs.tier != 'targeted' || steps.suites.outputs.mobile == 'true'")
})

test.describe('CF-247 AER Course detail and phone acceptance @deployed', () => {
  test.beforeAll(async () => { await writeRunEnvironment({ suite: 'cf-247-s167-aer-course-phone', change_control: 'CF-CHG-20260915-247' }) })

  test('at desktop width on live data: DP020 country order, India through the resolver only, scholarships and the evidence overlay', async ({ page }, testInfo) => {
    const runtime = observeRuntime(page); const calls = watch(page); const consoleErrors = consoleWatch(page)
    try {
      await loginAsUatUser(page)
      await dp020(page, calls, 'click')
      for (const c of calls.filter((x) => /_list$/.test(x.action || ''))) expect(Number(c.args.page_size || 0)).toBeLessThanOrEqual(100)
      expect(consoleErrors).toEqual([])
    } finally { await finish(testInfo, runtime) }
  })

  test('at phone width on live data: row drawer opens and closes, notice inside the screen, DP020 country order, India resolution, scholarships and evidence overlay @responsive', async ({ page }, testInfo) => {
    expect(page.viewportSize().width).toBeLessThan(500)
    const runtime = observeRuntime(page)
    const calls = []
    page.on('request', (r) => { if (/\/rest\/v1\/rpc\/(admin_aer|admin_entry_requirements)$/.test(new URL(r.url()).pathname)) { try { const b = r.postDataJSON() || {}; calls.push({ rpc: new URL(r.url()).pathname.split('/').pop(), action: b.p_action, args: b.p_args || {} }) } catch { /* not JSON */ } } })
    const consoleErrors = []; page.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|favicon/i.test(m.text())) consoleErrors.push(m.text()) })
    try {
      await loginAsUatUser(page)
      // 1. the AER row drawer opens on a tap of a loaded record row and closes again
      await page.goto(at('entry-requirements'))
      const row = page.locator('table[data-table="aer-matrix"] tbody tr[data-row]').first()
      await row.waitFor({ timeout: DETERMINISTIC_UI_TIMEOUT })
      await row.scrollIntoViewIfNeeded(); await row.locator('td').nth(2).tap()
      const drawer = page.locator('[data-aer-drawer="matrix"]')
      await expect(drawer.locator('[data-aer-quote]')).not.toBeEmpty({ timeout: DETERMINISTIC_UI_TIMEOUT })
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)
      // 2. the shell's low-credit notice, when shown, starts inside the screen (its first letter is not cut)
      const banner = await page.evaluate(() => {
        const b = document.querySelector('[data-credit-banner]'); if (!b) return null
        const r = b.getBoundingClientRect(); const range = document.createRange(); range.selectNodeContents(b); const t = range.getBoundingClientRect()
        return { left: r.left, textLeft: t.left, scrolls: b.scrollWidth > b.clientWidth + 1 }
      })
      if (banner) { expect(banner.left).toBeGreaterThanOrEqual(0); expect(banner.textLeft).toBeGreaterThanOrEqual(0); expect(banner.scrolls).toBe(false) }
      await drawer.getByRole('button', { name: 'Close detail' }).tap()
      await expect(drawer).toHaveCount(0, { timeout: DETERMINISTIC_UI_TIMEOUT })
      await dp020(page, calls, 'tap')
      // 7. bounded reads and a quiet console
      for (const c of calls.filter((x) => /_list$/.test(x.action || ''))) expect(Number(c.args.page_size || 0)).toBeLessThanOrEqual(100)
      expect(consoleErrors).toEqual([])
    } finally { await finish(testInfo, runtime) }
  })
})
