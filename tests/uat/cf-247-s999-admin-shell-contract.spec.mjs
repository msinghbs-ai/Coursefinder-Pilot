// Guards: UI/UX Unification v1.2 Slice 1 step 1 (Platform Admin 23 Nov 2026 19:59, approved 24 Nov 05:55): the Admin (rank 3+) menu is the v1.1 shell drawn from the route table (SECTIONS and PAGES in src/nav-map.js, the source of docs/UI-MAP.md), opens the existing screens unchanged, and only the two ui-v1 stylesheets are used.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { SECTIONS, PAGES, canOpen } from '../../src/nav-map.js'
import { menuFor } from '../../src/ui-v1/AdminShell.jsx'
import { mockAdmin } from './support/admin-mock.mjs'

const expected = rank => menuFor({ sections: SECTIONS, pages: PAGES, rank, canOpen })

test('the menu is the route table filtered by rank: every page a rank may open, none it may not', () => {
  for (const rank of [3, 4, 5, 6]) {
    const keys = expected(rank).flatMap(s => s.items.map(i => i.key))
    expect(keys.sort()).toEqual(Object.keys(PAGES).filter(k => canOpen(k, rank)).sort())
  }
  expect(expected(6).flatMap(s => s.items.map(i => i.key))).toContain('layer4')
})

test('the shell imports only the two ui-v1 stylesheets and keeps the global element rules under body.ui-v1', () => {
  const t = fs.readFileSync('src/ui-v1/AdminShell.jsx', 'utf8')
  const css = [...t.matchAll(/import\s+['"]([^'"]+\.css)['"]/g)].map(m => m[1]).sort()
  expect(css).toEqual(['./tokens.css', './ui-kit.css'])
  const kit = fs.readFileSync('src/ui-v1/ui-kit.css', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '')
  expect(kit).not.toMatch(/^(html|body|a|button|input|select|\*)(?![\w.-])/m)
})

test('1440x900: rank 6 sees the route-table menu, opens Layer 4 Review from it, and the legacy screen is drawn inside the shell', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await mockAdmin(page, { rank: 6 })
  await page.goto('/#dashboard')
  const nav = page.locator('[data-ui-admin-nav]')
  await expect(nav).toBeVisible()
  const want = expected(6)
  await expect(nav.locator('[data-nav-group] > .ui-nav-label')).toHaveText(want.map(s => s.label).filter(Boolean))
  await expect(nav.locator('a[data-nav-page]')).toHaveCount(want.reduce((n, s) => n + s.items.length, 0))
  await nav.locator('a[data-nav-page="layer4"]').click()
  await expect(page).toHaveURL(/#layer-4-review/)
  await expect(page.locator('.m-topbar h1')).toHaveText('Layer 4 Review')
  await expect(nav.locator('a[aria-current="page"]')).toHaveAttribute('data-nav-page', 'layer4')
  expect(await page.evaluate(() => document.body.classList.contains('ui-v1'))).toBe(false)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
})

test('a Curator (rank 3) is not shown pages above the rank', async ({ page }) => {
  await mockAdmin(page, { rank: 3 })
  await page.goto('/#dashboard')
  const shown = await page.locator('[data-ui-admin-nav] a[data-nav-page]').evaluateAll(a => a.map(x => x.dataset.navPage))
  expect(shown.sort()).toEqual(expected(3).flatMap(s => s.items.map(i => i.key)).sort())
})

test('@responsive 375x812: the menu opens from Menu, closes on choosing a page, and nothing overflows sideways', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 })
  expect(page.viewportSize().width).toBeLessThanOrEqual(480)
  await mockAdmin(page, { rank: 6 })
  await page.goto('/#dashboard')
  await expect(page.locator('.ui-admin')).not.toHaveClass(/is-open/)
  await page.getByRole('button', { name: 'Open menu' }).click()
  await expect(page.locator('.ui-admin')).toHaveClass(/is-open/)
  await page.locator('[data-ui-admin-nav] a[data-nav-page="layer4"]').click()
  await expect(page.locator('.ui-admin')).not.toHaveClass(/is-open/)
  await expect(page).toHaveURL(/#layer-4-review/)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true)
})
