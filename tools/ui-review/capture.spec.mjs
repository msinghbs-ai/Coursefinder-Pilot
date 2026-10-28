// Captures full-page screenshots of the screens listed in SCREENS for the P3 screen review.
// SCREENS: comma-separated routes; "route>Button" also clicks a tab/button and captures again.
// Privacy: e-mail addresses are always masked; the signed-in user's details are masked.
import { test } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'
import { loginAsUatUser } from '../../tests/uat/support/runtime-evidence.mjs'
import { aerTour } from './aer-tour.mjs'

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
  // 11 Oct 2026: a tab clicked just before this starts its read a moment later, so wait at least 1.5 s, and keep waiting while
  // the screen still says it is loading (a capture of "Loading…" is not a capture of the screen).
  await page.waitForTimeout(1500)
  while (Date.now() - t0 < 45_000) {
    const loading = await page.evaluate(() => /Loading|Reading what is running/.test(document.querySelector('main')?.innerText || '') || Boolean(document.querySelector('main .cf-skeleton-line, main [aria-busy="true"]'))).catch(() => false)
    if (!loading && inflight === 0 && Date.now() - lastRequestAt > 2000) break
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

test('capture screens for UI review', async ({ page, browser }) => {
  if (SCREENS.includes('aer-tour')) test.setTimeout(40 * 60_000)  // CF-247: the AER tour takes 14 screenshots at two widths
  fs.mkdirSync(OUT, { recursive: true })
  track(page)
  const consoleErrors = []
  page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 400)) })
  page.on('pageerror', e => consoleErrors.push('pageerror: ' + String(e.message).slice(0, 400)))
  await loginAsUatUser(page)
  const captured = new Set()
  const manifest = []
  let n = 0
  for (const spec of SCREENS) {
    // CF-247 (29 Oct 2026): "aer-tour" is the AER workspace's scripted read-only acceptance tour (aer-tour.mjs)
    if (spec === 'aer-tour') {
      try { await aerTour({ page, browser, out: OUT, settle, fitHeight, masks, login: loginAsUatUser, manifest, consoleErrors, baseURL: process.env.UAT_BASE_URL }) }
      catch (e) { manifest.push({ route: 'aer-tour', error: String(e?.message || e).slice(0, 400) }) }
      fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify({ captured_at: new Date().toISOString(), base_url: process.env.UAT_BASE_URL, screens: manifest }, null, 2))
      continue
    }
    const [route, ...clicks] = spec.split('>')
    const shots = [...(captured.has(route) ? [] : [{ label: 'main', click: null }]), ...clicks.map(c => ({ label: c, click: c }))]
    captured.add(route)
    await page.goto('/#' + route)
    // Diagnostics (CF-247): route "layer-2-discovery~AU~any" sets the Adapters filters the Platform Admin used
    if (process.env.ADAPTER_FILTERS && route === 'layer-2-discovery') {
      await page.locator('[data-adapters-tally]').waitFor({ timeout: 60_000 }).catch(() => {})
      await page.getByRole('combobox', { name: 'Adapters country' }).selectOption('AU').catch(() => {})
      await page.getByRole('combobox', { name: 'Provider kind' }).selectOption('any').catch(() => {})
      await page.waitForTimeout(3000)
    }
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
      // Diagnostics (CF-247, 11 Oct 2026): console errors and, on Layer 2 › Adapters, what the list actually drew
      const diag = await page.evaluate(() => { const w = document.querySelector('[data-adapters-workspace]'); if (!w) return null; return { rows: w.querySelectorAll('[data-adapter-row]').length, tally: w.querySelector('[data-adapters-tally]')?.textContent || null, list_html: (w.querySelector('.ad-list')?.outerHTML || 'no .ad-list').slice(0, 600), alerts: [...w.querySelectorAll('.dq-alert')].map(a => a.textContent.slice(0, 300)) } }).catch(e => ({ error: String(e) }))
      manifest.push({ file, route, action: s.click, clicked, heading: (title || '').trim(), settle_ms: settleMs, height: size.height, url: page.url(), diag, console_errors: consoleErrors.splice(0) })
      await page.setViewportSize({ width: 1440, height: 1000 })
    }
  }
  fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify({ captured_at: new Date().toISOString(), base_url: process.env.UAT_BASE_URL, screens: manifest }, null, 2))
})
