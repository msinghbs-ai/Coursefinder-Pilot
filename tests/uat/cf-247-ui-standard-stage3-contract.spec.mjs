// CF-247 v2.15.230, UI stage 3 (Rankings, Reference data, Settings, Models and services, Go-live, other admin pages):
// settings rows and the Go-live/Capacity headers use the standard text sizes.
import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
const read = p => readFileSync(new URL(`../../${p}`, import.meta.url), 'utf8')

test('Settings rows: labels at the standard small size, not heading size', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 }); await mockAdmin(page)
  await page.goto('/#environment')
  const label = page.locator('.ps-row-text strong').first()
  await expect(label).toBeVisible()
  expect(parseFloat(await label.evaluate(e => getComputedStyle(e).fontSize))).toBeLessThanOrEqual(14)
})

test('Go-live: the tab header is compact (the page header names the page)', async ({ page }) => {
  await page.setViewportSize({ width: 1600, height: 1000 }); await mockAdmin(page)
  await page.goto('/#environment-migration')
  const h = page.locator('.pm-shell[data-view="golive"] .pm-hero-copy h2')
  await expect(h).toBeVisible()
  expect(parseFloat(await h.evaluate(e => getComputedStyle(e).fontSize))).toBeLessThanOrEqual(18)
})

test('source: stage 3 rules live in the shared standard stylesheet', () => {
  const css = read('src/ui-standard.css')
  for (const s of ['.ps-row-text strong', '.pm-shell[data-view]:not([data-view="all"]) .pm-hero', '.env-setting strong']) expect(css).toContain(s)
})
