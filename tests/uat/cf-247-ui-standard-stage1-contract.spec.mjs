// CF-247 v2.15.227 (Platform Admin, 9 Oct 2026: "every page, in stages"), stage 1: every table resizes the same way as
// the catalogue lists; plain dropdowns and inputs share one look; Evidence and Jobs lose their repeated headers.
import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
const read = p => readFileSync(new URL(`../../${p}`, import.meta.url), 'utf8')

test('any table (here Scheduled jobs › Priority queue) gets resize handles; a drag widens the column and survives a reload', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 })
  await mockAdmin(page)
  await page.goto('/#scheduled-jobs?tab=priority')
  const table = page.locator('table').filter({ has: page.locator('th', { hasText: 'Why here' }) }).first()
  await expect(table.locator('[data-col-resize]').first()).toBeAttached()
  const th = table.locator('thead th').nth(1)
  const before = await th.evaluate(e => e.getBoundingClientRect().width)
  const box = await table.locator('[data-col-resize]').nth(1).boundingBox()
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2)
  await page.mouse.down(); await page.mouse.move(box.x + 100, box.y + box.height / 2, { steps: 5 }); await page.mouse.up()
  await expect.poll(() => th.evaluate(e => e.getBoundingClientRect().width)).toBeGreaterThan(before + 60)
  await page.reload()
  await expect.poll(() => table.locator('thead th').nth(1).evaluate(e => e.getBoundingClientRect().width)).toBeGreaterThan(before + 60)
  await table.locator('[data-col-resize]').nth(1).dblclick()
  await expect.poll(() => table.getAttribute('data-resized')).toBe(null)
})

test('plain dropdowns share the standard look; Evidence and Jobs have no repeated header', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 })
  await mockAdmin(page)
  await page.goto('/#layer-4-review?tab=flags')
  const sel = page.locator('.m-main select').first()
  await expect(sel).toBeVisible()
  expect(await sel.evaluate(e => getComputedStyle(e).borderTopLeftRadius)).not.toBe('0px')
  expect(await sel.evaluate(e => parseFloat(getComputedStyle(e).minHeight))).toBeGreaterThanOrEqual(34)
  await page.goto('/#evidence')
  await expect(page.getByText('Evidence, provenance & change history')).toHaveCount(0)
  await expect(page.locator('.evidence-hero.slim .evidence-count')).toBeVisible()
  expect(read('src/pipeline-ops-entry.jsx')).not.toContain('Server-paged execution history')
})

test('source: one resize helper started once by the shell; tokens only in the standard styles', () => {
  const main = read('src/mature-main.jsx')
  expect(main).toContain("useEffect(()=>startTableResize(document.body),[])")
  expect(main).toContain("import'./ui-standard.css'")
  const t = read('src/table-resize.js')
  expect(t).toContain("table.classList.contains('m-fit-table') || table.hasAttribute('data-no-resize')")
  expect(t).toMatch(/try \{ localStorage\.setItem/)
  expect(read('src/ui-standard.css')).not.toMatch(/#[0-9a-f]{3,8}\b/i)
})
