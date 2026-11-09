// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; monitoring closure for the consumer-API console) and S121/G4 (phone tests are @responsive and first assert phone width). Operations › API usage (ApiUsagePanel) with its key dialogs, mocked REST responses; nothing reaches a real backend. Reads the console only; no consumer API (G3) change.
import { test, expect } from '@playwright/test'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121
const BASE = 'https://example.supabase.co/rest/v1/rpc/'

const stats = (calls, ok) => ({
  calls, ok, client_errors: calls - ok, rate_limited: 0, server_errors: 0, success_rate: calls ? Math.round(1000 * ok / calls) / 10 : null,
  bytes: 5242880, avg_bytes: 20480, max_bytes: 614400, items: 900, avg_ms: 410, p95_ms: 900, last_call_at: '2026-11-09T03:00:00Z', last_ok_at: '2026-11-09T03:00:00Z',
  last_error_at: '2026-11-09T02:00:00Z', last_error_code: 'INVALID_INPUT', full_loads_completed: 1, delta_calls: 12, delta_items: 40, delta_bytes: 20480,
  last_delta_at: '2026-11-09T02:30:00Z', exports: 9, export_bytes: 7900000, searches: 20, previous_key_last_at: '2026-11-09T01:00:00Z',
  last_full_load: { started_at: '2026-11-09T01:00:00Z', finished_at: '2026-11-09T01:05:00Z', pages: 260, items: 41700, bytes: 104857600, seconds: 300 },
  last_full_load_started_at: '2026-11-09T01:00:00Z',
})
const usage = {
  days: 14, overlap_hours: 24, can_manage_keys: true,
  refreshed: { at: '2026-11-09T03:10:00Z', trigger: 'on_demand', by: 'admin@example.com' },
  keys: [
    { key_name: 'zoho_crm_sync_v2', platform: 'zoho', api_version: 'v2', consumer: 'Zoho CRM sync', enabled: true, rate_per_minute: 120, key_hint: 'b401f0d6', last_used_at: '2026-11-09T03:00:00Z', rotated_at: '2026-11-01T00:00:00Z', previous_valid_until: '2026-11-10T03:00:00Z', stats: { '24h': stats(40, 38), '7d': stats(100, 96), '30d': stats(100, 96) } },
    { key_name: 'website_developer_v2', platform: 'website', api_version: 'v2', consumer: 'Website (Wix) developer', enabled: true, rate_per_minute: 300, key_hint: '4dc4acd4', last_used_at: null, rotated_at: null, previous_valid_until: null, stats: {} },
  ],
  daily: [{ day: '2026-11-09', platform: 'zoho', api_version: 'v2', key_name: 'zoho_crm_sync_v2', action: 'sync_full', calls: 40, ok: 38, client_errors: 2, rate_limited: 0, server_errors: 0, avg_ms: 420, p95_ms: 900, max_ms: 1200, items: 380, bytes: 900000, last_at: '2026-11-09T03:00:00Z' }],
  recent_errors: [{ at: '2026-11-09T02:00:00Z', key_name: 'zoho_crm_sync_v2', action: 'sync_full', status: 400, error_code: 'INVALID_INPUT', request_id: 'req-0123456789abcdef0123456789abcdef' }],
  events: [{ at: '2026-11-01T00:00:00Z', key_name: 'zoho_crm_sync_v2', event: 'rotated', by: 'admin@example.com', previous_valid_until: '2026-11-10T03:00:00Z', note: 'Scheduled rotation with a long note to check wrapping' }],
}
const NEW_KEY = 'TESTONLY-' + 'a1B2c3D4'.repeat(6)

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

async function mount(page) {
  const { mockAdmin } = await import('./support/admin-mock.mjs')
  await mockAdmin(page, { rank: 6 })
  await page.route(BASE + 'admin_api_usage', (r) => r.fulfill({ json: usage }))
  await page.route(BASE + 'admin_api_key_rotate', (r) => r.fulfill({ json: { key_name: 'zoho_crm_sync_v2', key: NEW_KEY, key_hint: 'abcd1234', previous_valid_until: '2026-11-10T03:00:00Z', platform: 'zoho' } }))
  await page.goto('/#api-usage')
  await expect(page.locator('.cf-api-platform[data-platform="zoho"]')).toBeVisible()
  await expect(page.locator('.cf-api-keys tr[data-key="zoho_crm_sync_v2"]')).toBeVisible()
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Operations › API usage on a phone @responsive', () => {
  test('panels and platform cards fit the phone; each table scrolls in its own frame; the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    const inside = []
    for (const sel of ['.m-panel', '.cf-api-platform']) {
      const bs = await boxes(page, sel)
      expect(bs.length, `${sel} is on the screen, so this check measures something`).toBeGreaterThanOrEqual(2)
      for (const b of bs) if (b.x < -1 || b.right > w + 1) inside.push(`${sel} "${b.label}" ${Math.round(b.x)}..${Math.round(b.right)}`)
    }
    expect(inside, 'blocks that leave the screen').toEqual([])
    const frames = await page.locator('.dense-table-wrap').evaluateAll((els) => els.map((p) => {
      const t = p.querySelector('table')
      return { cls: p.parentElement.querySelector("table").className, frameClient: p.clientWidth, overflowX: getComputedStyle(p).overflowX, tableWidth: t.getBoundingClientRect().width }
    }))
    expect(frames.length, 'keys, full-load, by-day, by-action, error and change tables').toBeGreaterThanOrEqual(5)
    for (const f of frames) {
      expect(f.frameClient, 'table frame fits the phone').toBeLessThanOrEqual(w)
      if (f.tableWidth > f.frameClient) expect(['auto', 'scroll'], `table ${f.cls}: a table wider than the phone scrolls inside its own frame (frame ${f.frameClient}, table ${Math.round(f.tableWidth)})`).toContain(f.overflowX)
    }
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every control a Platform Admin taps is at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page)
    const small = []
    let measured = 0
    for (const sel of ['.m-page-stack button', '.m-page-stack select']) {
      for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    expect(measured, 'controls measured (refresh, period, key actions, key and days filters)').toBeGreaterThanOrEqual(8)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
  })

  test('the rotate dialog and the one-time new key sit inside the screen and can be read and closed', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    await page.locator('.cf-api-keys tr[data-key="zoho_crm_sync_v2"]').getByRole('button', { name: 'Rotate' }).click()
    const dlg = page.getByRole('dialog', { name: 'Rotate zoho_crm_sync_v2' })
    await expect(dlg).toBeVisible()
    for (const name of ['Cancel', 'Rotate key']) {
      const b = await dlg.getByRole('button', { name }).boundingBox()
      expect(b.x, `${name} starts inside the screen`).toBeGreaterThanOrEqual(-1)
      expect(b.x + b.width, `${name} ends inside the screen`).toBeLessThanOrEqual(w + 1)
      expect(Math.min(b.width, b.height), `${name} is at least ${TAP_MIN} px`).toBeGreaterThanOrEqual(TAP_MIN)
    }
    await dlg.getByRole('button', { name: 'Rotate key' }).click()
    const key = page.getByTestId('new-key')
    await expect(key).toHaveText(NEW_KEY)
    const kb = await key.boundingBox()
    expect(kb.x, 'the new key starts inside the screen').toBeGreaterThanOrEqual(-1)
    expect(kb.x + kb.width, 'the new key wraps inside the screen, so all of it can be read before it is gone').toBeLessThanOrEqual(w + 1)
    const done = page.getByRole('button', { name: 'I have stored it' })
    const db = await done.boundingBox()
    expect(db.x + db.width, 'the close button is inside the screen').toBeLessThanOrEqual(w + 1)
    expect(db.y + db.height, 'the close button is inside the screen height').toBeLessThanOrEqual(page.viewportSize().height + 1)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    await done.click()
    await expect(page.getByTestId('new-key')).toHaveCount(0)
  })
})
