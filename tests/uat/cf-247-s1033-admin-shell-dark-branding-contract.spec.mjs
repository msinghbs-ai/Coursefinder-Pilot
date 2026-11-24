// Guards: Platform Admin hotfix 24 Nov 2026 (header and sidebar branding after Pilot #1519, uniform for every role): the Admin and Counsellor top bar and left menu use the original dark slate surface (#0f172a), nav links carry no underline, the active item is the slate pill with the indigo accent, and the brand lockup stacks StudySearch above PIM Admin and the version, at 1440x900 and 375x812; only the menu items differ by rank.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

const SLATE = 'rgb(15, 23, 42)', ACTIVE = 'rgb(39, 52, 73)'
async function shell(page, w, h) { await page.setViewportSize({ width: w, height: h }); await mockAdmin(page, { rank: 6 }); await page.goto('/#dashboard'); await expect(page.locator('[data-ui-admin-shell]')).toBeVisible() }
const css = (page, sel, prop) => page.locator(sel).first().evaluate((e, p) => getComputedStyle(e)[p], prop)

async function checks(page, nav = '[data-ui-admin-nav]', page1 = '[data-nav-page]') {
  expect(await css(page, '.ui-topbar', 'backgroundColor')).toBe(SLATE)
  expect(await css(page, nav, 'backgroundColor')).toBe(SLATE)
  expect(await css(page, page1, 'textDecorationLine')).toBe('none')
  expect(await css(page, '.ui-brand', 'textDecorationLine')).toBe('none')
  expect(await css(page, `${page1}[aria-current="page"], .ui-nav a[aria-current="page"]`, 'backgroundColor')).toBe(ACTIVE)
  const b = await page.locator('.ui-brand').boundingBox(), v = await page.locator('.ui-brand-version').boundingBox()
  expect(v.y).toBeGreaterThan(b.y + b.height - 2)        // the version sits under the name
  expect(Math.abs(v.x - b.x)).toBeLessThan(2)             // and starts at the same left edge
  expect(await css(page, '.ui-brand-block', 'flexDirection')).toBe('column')
  expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
}

test('1440x900: dark top bar and menu, no underlines, active pill, stacked brand', async ({ page }) => { await shell(page, 1440, 900); await checks(page) })

test('375x812 @responsive: the same palette and stacked brand with the menu open', async ({ page }) => {
  expect(page.viewportSize()?.width || 9999).toBeLessThanOrEqual(480)
  await shell(page, 375, 812)
  await page.getByRole('button', { name: 'Open menu' }).click()
  await expect(page.locator('[data-ui-admin-nav]')).toBeVisible()
  await checks(page)
})

async function counsellor(page, w, h) { await page.setViewportSize({ width: w, height: h }); await mockAdmin(page, { rank: 2, role: 'counsellor' }); await page.goto('/#ui-v1/courses'); await expect(page.locator('.ui-nav')).toBeAttached() }

test('1440x900: the Counsellor (rank 2) shell has the same dark chrome and stacked brand', async ({ page }) => {
  await counsellor(page, 1440, 900); await checks(page, '.ui-nav', '.ui-nav a')
  await expect(page.locator('.ui-brand-version')).toContainText('Counsellor v')
})

test('375x812 @responsive: the Counsellor shell keeps the dark chrome and stacked brand', async ({ page }) => {
  expect(page.viewportSize()?.width || 9999).toBeLessThanOrEqual(480)
  await counsellor(page, 375, 812); await checks(page, '.ui-nav', '.ui-nav a')
})
