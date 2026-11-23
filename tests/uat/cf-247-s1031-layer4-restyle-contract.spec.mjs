// Guards: UI/UX Unification v1.2 Slice 1 step 2 (Platform Admin 24 Nov 2026 09:07): Layer 4 Review inside the ui-v1 Admin shell keeps the five primary filters on one row, Advanced filters (N), Technical detail closed and the three-button decision bar, at 1440x900 and 375x812, drawn with ui-v1 tokens only; no data-l4-* hook is removed.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const K = { aer_review: { label: 'Entry requirements (AER)', order: 17, choices: [{ key: 'approve', label: 'Approve', rank: 6 }, { key: 'reject', label: 'Reject the read', rank: 6 }], detail: true } }
async function open(page, w, h) {
  await page.setViewportSize({ width: w, height: h })
  await mockAdmin(page, { rank: 6 })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
    const b = route.request().postDataJSON()
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds: K, target_days: 7, rank: 6, total: 1, universities: 1, late: 0, by_kind: { aer_review: { n: 1 } }, paging: { items: 25, universities: 25, detail_parallel: 3 } } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p', name: 'RMIT University', country: 'AU', courses: 400, n: 1, by_kind: { aer_review: 1 } }] } })
    if (b.p_action === 'items') return route.fulfill({ json: { total: 1, before: 0, more: false, items: [{ kind: 'aer_review', ref: 'r1', provider_id: 'p', provider: 'RMIT University', subject: 'Diploma of Commerce', why: 'held', created_at: '2026-10-29T01:44:26Z', detail: {} }] } })
    return route.fulfill({ json: {} })
  })
  await page.goto('/#layer-4-review?view=university')
  await page.locator('[data-l4-uni="RMIT University"] [data-l4-pill="aer_review"]').click()
  await expect(page.locator('[data-l4-item="aer_review"]')).toBeVisible()
}

test('1440x900: the primary filters share one row, Advanced filters is a closed button, Technical detail is closed, the bar has Yes and No', async ({ page }) => {
  await open(page, 1440, 900)
  const tops = await page.locator('[role=toolbar][aria-label="Filters"] > *').evaluateAll(a => a.map(x => Math.round(x.getBoundingClientRect().top)))
  expect(Math.max(...tops) - Math.min(...tops)).toBeLessThan(40)   // labels differ in height; one row, not stacked
  await expect(page.locator('[data-l4-advanced-toggle]')).toHaveAttribute('aria-expanded', 'false')
  await expect(page.locator('[data-l4-item="aer_review"] details[open]')).toHaveCount(0)
  await expect(page.locator('[data-l4-item="aer_review"] [data-l4-decision="yes"]')).toBeVisible()
  await expect(page.locator('[data-l4-item="aer_review"] [data-l4-decision="no"]')).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
})

test('375x812 @responsive: nothing scrolls sideways and the decision buttons are reachable', async ({ page }) => {
  expect(page.viewportSize()?.width || 9999).toBeLessThanOrEqual(480)
  await open(page, 375, 812)
  await expect(page.locator('[data-l4-item="aer_review"] [data-l4-decision="yes"]')).toBeAttached()
  expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
})

test('the restyle uses ui-v1 tokens only and is scoped to the Admin shell', () => {
  const css = fs.readFileSync('src/layer4-inbox.css', 'utf8'), i = css.indexOf('Slice 1 step 2')
  const block = css.slice(i)
  expect(block).not.toMatch(/#[0-9a-fA-F]{3,8}\b|rgba?\(/)
  for (const sel of block.split('\n').filter(l => /^\.|^@media/.test(l)).map(l => l.split('{')[0])) if (!sel.startsWith('@media')) expect(sel).toMatch(/^\.ui-admin /)
})
