// Guards: StudySearch F-OPS.04 (Feature Acceptance Contract, phone acceptance of operated screens; IQ-00046/47/56 source and read reliability, the one-click Build adapter step) and S121/G4 (phone tests are @responsive and first assert phone width). Layer 2 › Builder, step 0 "one-click Build" (BuildAdapter: Universities, University, Waves) with mocked REST responses; nothing reaches a real backend. Measuring and Admit are not clicked; no consumer API (G3) change.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

const PHONE_MAX = 480
const TAP_MIN = 24 // WCAG 2.2 AA target size (2.5.8) floor, as S121

const field = (state, o = {}) => ({ state, read: 10, agree: 8, differ: 0, new: 2, read_share: 0.9, agree_share: 1, why: state === 'ready' ? 'adds 2 values the catalogue does not hold' : state === 'review' ? '3 of 10 readings differ from the catalogue, so a person should look first' : 'not read by the adapter', admitted: false, ...o })
const LIST = {
  summary: { universities: 3, courses: 1900, by_stage: { tested: 1, building: 1, no_adapter: 1 }, ready: 4, review: 2, not_ready: 2, adds: 120 },
  total: 3, limit: 50, offset: 0, can_build: true, can_admit: true,
  items: [
    { provider_id: 'u-rb', name: 'Riverbend University of Applied Technology and Professional Studies', country: 'AU', courses: 600, pages_read: 400, ready: 4, review: 2, not_ready: 2, adds: 120, stage: 'tested', checked_at: '2026-11-09T03:00:00Z', wave: 'Wave 18' },
    { provider_id: 'u-kc', name: 'Kestrel College', country: 'AU', courses: 300, pages_read: null, ready: null, review: null, not_ready: null, adds: null, stage: 'no_adapter' },
    { provider_id: 'u-st', name: 'Stonehaven Institute', country: 'AU', courses: 1000, pages_read: 12, ready: 0, review: 0, not_ready: 8, adds: 0, stage: 'needs_pages', stop_reason: 'too_few_pages_found_on_the_website', checked_at: '2026-11-09T03:00:00Z' },
  ],
}
const READ = {
  provider_id: 'u-rb', pages_read: 400, has_adapter: true, adds: 120, min_read: 0.5, min_agree: 0.9, measured_at: '2026-11-09T03:00:00Z',
  fields: {
    intakes: field('ready', { admitted: true }), fee: field('ready'), english: field('review'), delivery: field('ready'), duration: field('ready'), campus: field('review'),
    study_level: field('not_ready', { read: 0, new: 0 }), majors: field('not_ready', { read: 0, new: 0, why: 'the adapter does not read majors yet' }),
  },
  ready: ['intakes', 'fee', 'delivery', 'duration'], review: ['english', 'campus'], not_ready: ['study_level', 'majors'],
  university: { name: 'Riverbend University of Applied Technology and Professional Studies', country: 'AU', website: 'https://riverbend.example/a-long-address-that-should-wrap' },
  courses: 600, pages: { bound: 420, read: 400, other_course: 12, unreadable: 8 }, links_fixed: 5,
  build: { status: 'done', stop_reason: null, note: 'Done' }, ai_cost_usd: 0.04, wave: 'Wave 18', admitted: {}, can_build: true, can_admit: true,
}
const WAVES = { waves: [{ wave: 'Wave 18', universities: 8, courses: 2941, by_stage: { tested: 6, building: 1, needs_pages: 1 }, ready: 41, review: 14, not_ready: 9, adds: 6830 }] }

async function atPhoneWidth(page) {
  const w = page.viewportSize()?.width || 9999
  expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
  return w
}
const pageOverflow = (page) => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)

async function mount(page, rank = 6) {
  await mockAdmin(page, { rank })
  const calls = []
  page.buildCalls = calls
  await page.route('**/rest/v1/rpc/admin_adapter_build', async (route) => {
    const b = route.request().postDataJSON()
    calls.push(b)
    const out = b.p_action === 'list' ? LIST : b.p_action === 'read' ? READ : b.p_action === 'waves' ? WAVES : {}
    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(out) })
  })
  await page.goto('/#layer-2-discovery?tab=builder')
  await expect(page.locator('[data-build-list] [data-build-row="u-rb"]')).toBeVisible()
}

async function boxes(page, selector) {
  return page.locator(selector).evaluateAll((els) => els.filter((el) => el.offsetParent !== null).map((el) => {
    const b = el.getBoundingClientRect()
    return { label: (el.getAttribute('aria-label') || el.textContent || el.tagName).trim().slice(0, 40), x: b.x, right: b.x + b.width, w: b.width, h: b.height }
  }))
}

async function tableFrames(page, scope) {
  return page.locator(`${scope} .dense-table-wrap`).evaluateAll((els) => els.map((p) => {
    const t = p.querySelector('table')
    return { frameClient: p.clientWidth, overflowX: getComputedStyle(p).overflowX, tableWidth: t.getBoundingClientRect().width, cls: t.className }
  }))
}

test.describe('Layer 2 › Builder, one-click Build, on a phone @responsive', () => {
  test('universities view: summary, filters and the table fit the phone; the table scrolls in its own frame; the page never scrolls sideways', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    const outside = []
    for (const sel of ['[data-build-summary]', '[data-build-list]', '.ba-tiles > span', '.ba-filters']) {
      const bs = await boxes(page, sel)
      expect(bs.length, `${sel} is on the screen, so this check measures something`).toBeGreaterThanOrEqual(1)
      for (const b of bs) if (b.x < -1 || b.right > w + 1) outside.push(`${sel} "${b.label}" ${Math.round(b.x)}..${Math.round(b.right)}`)
    }
    expect(outside, 'blocks that leave the screen').toEqual([])
    const frames = await tableFrames(page, '[data-build-list]')
    expect(frames.length).toBeGreaterThanOrEqual(1)
    for (const f of frames) {
      expect(f.frameClient, 'table frame fits the phone').toBeLessThanOrEqual(w)
      if (f.tableWidth > f.frameClient) expect(['auto', 'scroll'], `table ${f.cls}: wider than the phone (frame ${f.frameClient}, table ${Math.round(f.tableWidth)}) so it scrolls inside its own frame`).toContain(f.overflowX)
    }
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
  })

  test('every control a Platform Admin taps on the universities view is at least 24 by 24 pixels', async ({ page }) => {
    await atPhoneWidth(page)
    await mount(page)
    await page.locator('[data-build-row="u-rb"] input[type="checkbox"]').check() // reveals "Build 1 selected"
    await expect(page.locator('[data-build-picked]')).toBeVisible()
    const small = []
    let measured = 0
    for (const sel of ['.ba-views button', '.ba-filters select', '.ba-filters button', '[data-build-list] .m-searchbox input', '[data-build-row] button', '[data-build-row] input[type="checkbox"]', '[data-build-picked]']) {
      const bs = await boxes(page, sel)
      measured += bs.length
      for (const b of bs) if (b.w < TAP_MIN || b.h < TAP_MIN) small.push(`${sel} "${b.label}" ${Math.round(b.w)}x${Math.round(b.h)}`)
    }
    expect(measured, 'controls were measured').toBeGreaterThanOrEqual(8)
    expect(small, 'controls under 24 px').toEqual([])
  })

  test('a university page: actions, field tiles and the eight-field table fit the phone; Admit stays reachable and is not clicked', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    await page.locator('[data-build-list]').getByRole('button', { name: /Riverbend University/ }).click()
    await expect(page.locator('[data-build-fields] [data-build-field="fee"]')).toContainText('Ready')
    const admit = page.locator('[data-build-admit]')
    await expect(admit).toHaveText('Admit 3 Ready fields')
    const outside = []
    for (const sel of ['[data-build-university]', '.ba-actions > *', '.ba-tiles > span', '[data-build-fields]']) {
      const bs = await boxes(page, sel)
      expect(bs.length, `${sel} is on the screen`).toBeGreaterThanOrEqual(1)
      for (const b of bs) {
        if (b.x < -1 || b.right > w + 1) outside.push(`${sel} "${b.label}" ${Math.round(b.x)}..${Math.round(b.right)}`)
        if (sel === '.ba-actions > *' && (b.w < TAP_MIN || b.h < TAP_MIN)) outside.push(`${sel} "${b.label}" is ${Math.round(b.w)}x${Math.round(b.h)}`)
      }
    }
    expect(outside, 'blocks or controls out of bounds').toEqual([])
    const frames = await tableFrames(page, '[data-build-fields]')
    expect(frames.length).toBe(1)
    for (const f of frames) {
      expect(f.frameClient).toBeLessThanOrEqual(w)
      if (f.tableWidth > f.frameClient) expect(['auto', 'scroll'], `field table (frame ${f.frameClient}, table ${Math.round(f.tableWidth)}) scrolls in its own frame`).toContain(f.overflowX)
    }
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    expect(page.buildCalls.filter((c) => c.p_action === 'admit' || c.p_action === 'build'), 'nothing was admitted or built').toEqual([])
  })

  test('waves view fits the phone and a wave opens the filtered universities list', async ({ page }) => {
    const w = await atPhoneWidth(page)
    await mount(page)
    await page.getByRole('tab', { name: /Waves/ }).click()
    await expect(page.locator('[data-build-wave="Wave 18"]')).toBeVisible()
    const frames = await tableFrames(page, '[data-build-waves]')
    expect(frames.length).toBe(1)
    for (const f of frames) {
      expect(f.frameClient).toBeLessThanOrEqual(w)
      if (f.tableWidth > f.frameClient) expect(['auto', 'scroll'], `waves table (frame ${f.frameClient}, table ${Math.round(f.tableWidth)}) scrolls in its own frame`).toContain(f.overflowX)
    }
    expect(await pageOverflow(page)).toBeLessThanOrEqual(1)
    await page.locator('[data-build-wave="Wave 18"]').getByRole('button', { name: 'Wave 18' }).click()
    await expect(page.locator('[data-build-list]')).toBeVisible()
    await expect(page.getByText('Wave: Wave 18')).toBeVisible()
  })
})
