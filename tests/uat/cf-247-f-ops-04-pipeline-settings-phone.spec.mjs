// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; IQ-00053 and IQ-00313 families) and S121/G4 (phone tests are @responsive and first assert phone width). Settings › Pipeline settings and the settings register, mocked REST responses; nothing reaches a real backend.
import { test, expect } from '@playwright/test'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121

const pipeline = (canChange) => ({
  can_change: canChange,
  course_pages: { search_monthly_credit_cap: 50000, queued: { matcher_ready: 120, matcher_never_offered: 40, searches_queued: 12 }, priority_countries: ['AU', 'NZ'] },
  reading: { pages_waiting: 85 },
  identity: {
    AU: { currency: 'AUD', active: true, min_annual_international: 8000, identities: { official_url: ['cricos_code', 'exact_title'], english: ['cricos_code'], intakes: ['cricos_code', 'exact_title', 'title_level'], tuition: ['cricos_code'] } },
    NZ: { currency: 'NZD', active: true, min_annual_international: null, identities: { official_url: ['nzqa_code'], english: ['nzqa_code'], intakes: ['nzqa_code', 'exact_title'], tuition: ['nzqa_code'] } },
  },
  budgets: { firecrawl_monthly_limit: 100000, firecrawl_used_this_month: 41000, firecrawl_stop_at_remaining: 2000, firecrawl_by_purpose: { read: 30000, search: 9000, map: 2000 }, openrouter: { remaining_usd: 12.5, observed_at: '2026-11-09T05:00:00Z' } },
  recent_changes: [{ at: '2026-11-09T04:00:00Z', area: 'Settings', action: 'changed', target: 'enrich.ai_calls_at_once with a deliberately long target name to check that it wraps on a phone screen' }],
})
const setting = (i) => ({ key: `batch.job_${i}`, label: `Job ${i} size with a long label that must wrap on a phone`, help: 'How much the job takes in one run.', used_by: 'cron job with a fairly long description of what uses it', kind: 'number', value: 10 * i, min: 1, max: 500, unit: 'items', updated_at: '2026-11-08T22:00:00Z', reason: 'Set by the Platform Admin' })
const register = (canManage) => ({
  can_manage: canManage, jobs: 61, check: [],
  sections: [
    { section: 'Job sizes', settings: [1, 2, 3, 4].map(setting) },
    { section: 'Re-read and retry', settings: [{ ...setting(5), kind: 'boolean', value: true }, { ...setting(6), kind: 'list', value: ['AU', 'NZ'], min: null, max: null }] },
  ],
})

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

async function mount(page, { admin }) {
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' }
  await page.route('**/rest/v1/rpc/**', async (route) => {
    const req = route.request()
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors })
    const name = new URL(req.url()).pathname.split('/').pop()
    const body = name === 'admin_pipeline_settings_read' ? pipeline(admin)
      : name === 'admin_settings_register_read' ? register(admin)
      : name === 'admin_policy_tables_read' ? { can_manage: admin, tables: [], providers: {} }
      : name === 'admin_institution_type_rules_read' ? { rules: [], can_manage: admin }
      : {}
    return route.fulfill({ status: 200, headers: { ...cors, 'content-type': 'application/json' }, body: JSON.stringify(body) })
  })
  // cards start closed and remember being opened per browser session, so open the two that hold settings before the page loads
  await page.addInitScript(() => { try { for (const id of ['job-sizes', 're-read-and-retry']) window.sessionStorage.setItem(`cf.card.settings.register.${id}`, '1') } catch { /* storage unavailable */ } })
  await page.goto('/')
  await page.evaluate(async () => {
    const React = await import('/node_modules/.vite/deps/react.js')
    const { default: ReactDOM } = await import('/node_modules/.vite/deps/react-dom_client.js')
    const { default: PipelineSettings } = await import('/src/PipelineSettings.jsx')
    document.body.innerHTML = '<div id="ps-root"></div>'
    ReactDOM.createRoot(document.getElementById('ps-root')).render(React.default.createElement(PipelineSettings, {}))
  })
  await expect(page.locator('[data-pipeline-settings]').first()).toBeVisible()
  await expect(page.locator('[data-settings-register]')).toBeVisible()
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    // a checkbox is tapped through the label that wraps it, so that is the box measured
    const b = (el.type === 'checkbox' && el.closest('label') ? el.closest('label') : el).getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

test.describe('Settings › Pipeline settings on a phone @responsive', () => {
  test('sections, settings rows and the identity table fit the phone; a wide table scrolls in its own frame; the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page, { admin: true })
    await expect(page.locator('[data-settings-section="budgets"]')).toContainText('Firecrawl this month')
    await expect(page.locator('[data-register-setting="batch.job_1"]')).toBeVisible()
    for (const sel of ['[data-settings-section]', '[data-register-setting]', '.ps-row']) {
      const found = await boxes(page, sel)
      expect(found.length, `${sel} is on the screen, so this check measures something`).toBeGreaterThan(0)
      for (const b of found) {
        expect(b.x, `${sel} "${b.label}" starts inside the screen`).toBeGreaterThanOrEqual(-1)
        expect(b.right, `${sel} "${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
      }
    }
    const table = page.locator('[data-settings-section="identity"] .ps-id-table')
    await table.scrollIntoViewIfNeeded()
    const t = await table.evaluate((el) => {
      const p = el.parentElement
      return { frameClient: p.clientWidth, frameScroll: p.scrollWidth, overflowX: getComputedStyle(p).overflowX, tableWidth: el.getBoundingClientRect().width }
    })
    expect(t.frameClient, 'the identity table frame fits the phone').toBeLessThanOrEqual(w)
    if (t.tableWidth > t.frameClient) expect(['auto', 'scroll'], 'a table wider than the phone scrolls inside its own frame').toContain(t.overflowX)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every control a Platform Admin taps on the phone is a tap target of at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page, { admin: true })
    const small = []
    let measured = 0
    for (const sel of ['[data-pipeline-settings] button', '[data-pipeline-settings] select', '[data-pipeline-settings] input:not([type=hidden])']) {
      for (const b of await boxes(page, sel)) { measured++; if (Math.min(b.w, b.h) < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`) }
    }
    expect(measured, 'controls measured').toBeGreaterThanOrEqual(10)
    expect(small, 'controls below the WCAG 2.2 AA target size').toEqual([])
  })

  test('a read-only role is told why it cannot change a setting and sees no edit control', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page, { admin: false })
    await expect(page.getByText('You can see every setting. Only a Platform Admin can change one.').first()).toBeVisible()
    await expect(page.locator('[data-pipeline-settings] input[type=number]')).toHaveCount(0)
    await expect(page.locator('[data-pipeline-settings] button', { hasText: 'Save' })).toHaveCount(0)
    for (const b of await boxes(page, '[data-register-setting]')) expect(b.right, `"${b.label}" ends inside the screen`).toBeLessThanOrEqual(w + 1)
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })
})
