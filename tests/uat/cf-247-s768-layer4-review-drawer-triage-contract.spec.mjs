// Guards: Platform Admin 19 Nov 2026 19:26 (chat S1-RM-Design, s768): the Layer 4 Review drawer shows the proposed value, the verbatim source quote with its clickable address and the exact machine hold reason side by side, with the kind's own decisions beneath, and J and K move to the next and previous item without deciding anything (no migration, no new write path)
// CF-247 S1-RM-Design s768: src/Layer4Grid.jsx, src/layer4-inbox.css
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const G = fs.readFileSync('src/Layer4Grid.jsx', 'utf8')

test('the drawer carries the three review columns, the exact reason badge and J and K, and adds no write path', () => {
  for (const a of ['data-l4g-review', 'data-l4g-proposed', 'data-l4g-source', 'data-l4g-source-link', 'data-l4g-hold-reason', 'data-l4g-nav', 'data-l4g-prev', 'data-l4g-next', 'data-l4g-decide']) expect(G).toContain(a)
  expect(G).toContain("e.key==='j'")
  expect(G).toContain("e.key==='k'")
  // keys are ignored while typing, and moving only reads: the only rpc names in the file are reads
  expect(G).toContain("tag==='input'||tag==='textarea'||tag==='select'")
  const rpcs = [...G.matchAll(/call\('([a-z0-9_]+)'/g)].map((m) => m[1])
  expect(new Set(rpcs)).toEqual(new Set(['admin_saved_views_read_v1', 'admin_layer4_grid_read_v1', 'admin_saved_view_save_v1', 'admin_saved_view_archive_v1', 'admin_layer4_item_trace_v1']))
})

const kinds = { provider_description: { label: 'Provider description', order: 1, choices: [] } }
const ROWS = ['r1', 'r2', 'r3'].map((r, i) => ({ kind: 'provider_description', ref: r, provider: `University ${i + 1}`, country: 'AU', subject: `Description ${i + 1}`, why: 'audit_sample', created_at: '2026-11-10T00:00:00Z', age_days: 9 }))
async function openDrawer(page, traces, decides) {
  await mockAdmin(page, { rank: 6 })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
    const b = route.request().postDataJSON()
    if (b.p_action === 'decide') decides.push(b)
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 3, universities: 3, late: 0, by_kind: { provider_description: { n: 3 } } } })
    return route.fulfill({ json: { total: 0, items: [] } })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_saved_views_read_v1', (route) => route.fulfill({ json: { views: [], grid_kinds: ['provider_description'], can_edit_shared: true } }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_grid_read_v1', async (route) => {
    const a = route.request().postDataJSON().p_args
    return route.fulfill({ json: { total: 3, offset: a.offset || 0, limit: 200, kind: a.kind, sort: 'oldest', export: false, kind_label: 'Provider description', rank: 6, rows: a.offset > 1000 ? [] : ROWS } })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_item_trace_v1', async (route) => {
    const b = route.request().postDataJSON(); traces.push(b.p_ref)
    const n = Number(b.p_ref.slice(1))
    return route.fulfill({ json: { waiting: true, item: { kind: b.p_kind, ref: b.p_ref, provider: `University ${n}`, subject: `Description ${n}`, why: 'Machine rule aer-matrix-machine-v1 did not admit this audit_sample', suggestion: 'Read the quote, then decide.',
      created_at: '2026-11-10T00:00:00Z', detail: { proposed: `Proposed text ${n}`, quote: `Verbatim quote ${n}`, source_url: `https://example.edu.au/about-${n}` } }, evidence: { source_url: `https://example.edu.au/about-${n}`, captured_at: '2026-11-09T00:00:00Z' }, history: [] } })
  })
  await page.goto('/#layer-4-review?view=grid')
  await page.locator('[data-l4g-kind]').selectOption('provider_description')
  await expect(page.locator('[data-l4g-total]')).toContainText('3 waiting')
  await page.getByText('Description 1').first().click()
  await expect(page.locator('[data-l4g-drawer]')).toBeVisible()
}

test.describe('mocked browser', () => {
  test('the drawer shows value, quote with its address and the exact hold reason side by side; J and K move without deciding', async ({ page }) => {
    const traces = [], decides = []
    await openDrawer(page, traces, decides)
    const d = page.locator('[data-l4g-drawer]')
    await expect(d.locator('[data-l4g-hold-reason]')).toHaveText('Machine rule aer-matrix-machine-v1 did not admit this audit_sample')
    await expect(d.locator('[data-l4g-source-link]')).toHaveAttribute('href', 'https://example.edu.au/about-1')
    await expect(d.locator('[data-l4g-pos]')).toHaveText('1 of 3')
    await expect(d.locator('[data-l4g-prev]')).toBeDisabled()
    // the three columns sit in one row on a desktop screen
    const cols = await d.locator('.l4g-rv-col').evaluateAll((els) => els.map((e) => Math.round(e.getBoundingClientRect().top)))
    if ((page.viewportSize()?.width || 0) > 900) expect(new Set(cols).size).toBe(1)
    await page.keyboard.press('j')
    await expect(d.locator('[data-l4g-pos]')).toHaveText('2 of 3')
    await expect(d.locator('[data-l4g-source-link]')).toHaveAttribute('href', 'https://example.edu.au/about-2')
    await page.keyboard.press('J')
    await expect(d.locator('[data-l4g-pos]')).toHaveText('3 of 3')
    await expect(d.locator('[data-l4g-next]')).toBeDisabled()
    await page.keyboard.press('j')
    await expect(d.locator('[data-l4g-pos]')).toHaveText('3 of 3')
    await page.keyboard.press('k')
    await expect(d.locator('[data-l4g-pos]')).toHaveText('2 of 3')
    await d.locator('[data-l4g-next]').click()
    await expect(d.locator('[data-l4g-pos]')).toHaveText('3 of 3')
    // the first open may read twice (the development build mounts effects twice); each move reads the new item once
    expect(traces.filter((t, i) => t !== traces[i - 1])).toEqual(['r1', 'r2', 'r3', 'r2', 'r3'])
    expect(decides, 'moving between items decides nothing').toEqual([])
  })

  test('typing in a field never moves the item', async ({ page }) => {
    await openDrawer(page, [], [])
    await page.locator('[data-l4g-q]').focus()
    await page.keyboard.type('jjkk')
    await expect(page.locator('[data-l4g-pos]')).toHaveText('1 of 3')
  })
})

test.describe('phone @responsive', () => {
  test('the review columns stack inside the screen and the buttons are usable tap targets', async ({ page }) => {
    const w = page.viewportSize().width
    expect(w, 'this test runs on the phone project only').toBeLessThanOrEqual(480)
    await openDrawer(page, [], [])
    const cols = await page.locator('.l4g-rv-col').evaluateAll((els) => els.map((e) => Math.round(e.getBoundingClientRect().top)))
    expect(new Set(cols).size, 'stacked').toBe(3)
    for (const sel of ['[data-l4g-prev]', '[data-l4g-next]']) {
      const r = await page.locator(sel).boundingBox()
      expect(r.x + r.width).toBeLessThanOrEqual(w + 1)
      expect(r.height).toBeGreaterThanOrEqual(24)
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(1)
  })
})
