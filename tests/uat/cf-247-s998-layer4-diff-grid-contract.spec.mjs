// Guards: Layer 4 Review description diff (Platform Admin 23 Nov 2026 19:49): Proposed value and Live value now share the row in equal columns, none collapses to one word per line; one column on a narrow pane.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const css = fs.readFileSync('src/layer4-inbox.css', 'utf8') + fs.readFileSync('src/tokens.css', 'utf8')
const jsx = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
const LONG = 'A broad, practice-led university with campuses across the state and a long standing record in teaching and applied research for its students. '.repeat(3)
const page_html = `<style>${css}</style><div style="width:900px"><div class="l4z-desc" data-l4-description><dl class="l4i-dl l4z-pair"><dt>Proposed value</dt><dd data-l4-description-text><strong>${LONG}</strong></dd><dt>Live value now</dt><dd data-l4-live>${LONG}</dd></dl></div></div>`

test('the description wrapper is not the 110px label grid', () => {
  expect(jsx).toContain('className="l4z-desc" data-l4-description')
  expect(jsx).not.toContain('className="l4i-dl" data-l4-description')
})

test('1440x900: Proposed value and Live value now are equal-width columns side by side', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.setContent(page_html)
  const p = await page.locator('[data-l4-description-text]').boundingBox()
  const l = await page.locator('[data-l4-live]').boundingBox()
  expect(p.width).toBeGreaterThan(300)
  expect(Math.abs(p.width - l.width)).toBeLessThan(2)
  expect(l.x).toBeGreaterThan(p.x + p.width - 1)
  expect(Math.abs(p.y - l.y)).toBeLessThan(2)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
})

test('a narrow pane stacks them in one column', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 })
  await page.setContent(page_html.replace('width:900px', 'width:340px'))
  const p = await page.locator('[data-l4-description-text]').boundingBox()
  const l = await page.locator('[data-l4-live]').boundingBox()
  expect(l.y).toBeGreaterThan(p.y + p.height - 1)
  expect(p.width).toBeGreaterThan(250)
})
