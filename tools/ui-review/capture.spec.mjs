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

// Wait until the app's data requests have finished: no request to the backend for 2 s
// (max 30 s). "Page loaded" is not enough, because screens fetch data after rendering.
let lastRequestAt = Date.now(), inflight = 0
function track(page) {
  const isData = r => /supabase|\/rest\/v1\/|\/functions\/v1\//.test(r.url())
  page.on('request', r => { if (isData(r)) { inflight++; lastRequestAt = Date.now() } })
  const done = r => { if (isData(r)) { inflight = Math.max(0, inflight - 1); lastRequestAt = Date.now() } }
  page.on('requestfinished', done); page.on('requestfailed', done)
}
async function settle(page) {
  const t0 = Date.now()
  await page.waitForLoadState('networkidle', { timeout: 30_000 }).catch(() => {})
  while (Date.now() - t0 < 30_000) {
    if (inflight === 0 && Date.now() - lastRequestAt > 2000) break
    await page.waitForTimeout(250)
  }
  return Date.now() - t0
}
// The app scrolls inside its main panel, so grow the window to the tallest scroll area.
async function fitHeight(page) {
  const h = await page.evaluate(() => {
    let max = document.documentElement.scrollHeight
    for (const el of document.querySelectorAll('*')) {
      const cs = getComputedStyle(el)
      if (/(auto|scroll)/.test(cs.overflowY) && el.scrollHeight > el.clientHeight) max = Math.max(max, el.scrollHeight + el.getBoundingClientRect().top)
    }
    return Math.ceil(max)
  })
  await page.setViewportSize({ width: 1440, height: Math.min(Math.max(1000, h + 40), 14000) })
  await page.waitForTimeout(400)
}
function masks(page) {
  return [page.getByText(EMAIL), page.locator('.m-user, .m-user-menu, .m-account, [data-private]')]
}

test('capture screens for UI review', async ({ page }) => {
  fs.mkdirSync(OUT, { recursive: true })
  track(page)
  await loginAsUatUser(page)
  const captured = new Set()
  const manifest = []
  let n = 0
  for (const spec of SCREENS) {
    const [route, ...clicks] = spec.split('>')
    const shots = [...(captured.has(route) ? [] : [{ label: 'main', click: null }]), ...clicks.map(c => ({ label: c, click: c }))]
    captured.add(route)
    await page.goto('/#' + route)
    for (const s of shots) {
      let clicked = true
      if (s.click) {
        const target = page.getByRole('button', { name: s.click }).or(page.getByRole('tab', { name: s.click })).first()
        clicked = await target.click({ timeout: 10_000 }).then(() => true).catch(() => false)
      }
      const settleMs = await settle(page)
      await fitHeight(page)
      n += 1
      const file = `${String(n).padStart(2, '0')}-${route}${s.click ? '-' + s.click.toLowerCase().replace(/[^a-z0-9]+/g, '-') : ''}.png`
      await page.screenshot({ path: path.join(OUT, file), fullPage: true, mask: masks(page), maskColor: '#9ca3af' })
      const title = await page.locator('h1').first().textContent({ timeout: 2000 }).catch(() => '')
      const size = page.viewportSize()
      manifest.push({ file, route, action: s.click, clicked, heading: (title || '').trim(), settle_ms: settleMs, height: size.height, url: page.url() })
      await page.setViewportSize({ width: 1440, height: 1000 })
    }
  }
  fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify({ captured_at: new Date().toISOString(), base_url: process.env.UAT_BASE_URL, screens: manifest }, null, 2))
})
