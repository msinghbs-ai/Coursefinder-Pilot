// Captures full-page screenshots of the screens listed in SCREENS for the P3 screen review.
// SCREENS: comma-separated routes; "route>Button" also clicks a tab/button and captures again.
// Privacy: e-mail addresses are always masked; the signed-in user's details are masked.
import { test } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'
import { loginAsUatUser } from '../../tests/uat/support/runtime-evidence.mjs'

const OUT = process.env.OUT_DIR || 'ui-review-out'
const SCREENS = (process.env.SCREENS || '').split(',').map(s => s.trim()).filter(Boolean)
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/

async function settle(page) {
  const t0 = Date.now()
  await page.waitForLoadState('networkidle', { timeout: 30_000 }).catch(() => {})
  await page.locator('.m-pulse, [aria-busy="true"], .m-loading').first().waitFor({ state: 'detached', timeout: 20_000 }).catch(() => {})
  await page.waitForTimeout(1200)
  return Date.now() - t0
}
function masks(page) {
  return [page.getByText(EMAIL), page.locator('.m-user, .m-user-menu, .m-account, [data-private]')]
}

test('capture screens for UI review', async ({ page }) => {
  fs.mkdirSync(OUT, { recursive: true })
  await loginAsUatUser(page)
  const manifest = []
  let n = 0
  for (const spec of SCREENS) {
    const [route, ...clicks] = spec.split('>')
    const shots = [{ label: 'main', click: null }, ...clicks.map(c => ({ label: c, click: c }))]
    await page.goto('/#' + route)
    for (const s of shots) {
      let clicked = true
      if (s.click) {
        const target = page.getByRole('button', { name: s.click }).or(page.getByRole('tab', { name: s.click })).first()
        clicked = await target.click({ timeout: 10_000 }).then(() => true).catch(() => false)
      }
      const settleMs = await settle(page)
      n += 1
      const file = `${String(n).padStart(2, '0')}-${route}${s.click ? '-' + s.click.toLowerCase().replace(/[^a-z0-9]+/g, '-') : ''}.png`
      await page.screenshot({ path: path.join(OUT, file), fullPage: true, mask: masks(page), maskColor: '#9ca3af' })
      const title = await page.locator('h1').first().textContent({ timeout: 2000 }).catch(() => '')
      manifest.push({ file, route, action: s.click, clicked, heading: (title || '').trim(), settle_ms: settleMs, url: page.url() })
    }
  }
  fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify({ captured_at: new Date().toISOString(), base_url: process.env.UAT_BASE_URL, screens: manifest }, null, 2))
})
