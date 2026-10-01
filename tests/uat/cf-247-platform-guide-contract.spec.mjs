// Decision 209: the Platform guide lives in the app (Help › Platform guide) and is reviewed every release.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { PAGES, SECTIONS } from '../../src/nav-map.js'
import { UI_VERSION } from '../../src/release-manifest.js'
import { GUIDE_REVIEWED_FOR, SCREENS } from '../../src/guide/platformGuide.js'

test('guide reviewed for this release (update src/guide/platformGuide.js, then set GUIDE_REVIEWED_FOR)', () => {
  expect(GUIDE_REVIEWED_FOR).toBe(UI_VERSION)
})

test('every menu page has a guide entry, and the guide is in the menu', () => {
  const missing = Object.keys(PAGES).filter(k => k !== 'guide' && !SCREENS[k])
  expect(missing).toEqual([])
  const stale = Object.keys(SCREENS).filter(k => !PAGES[k])
  expect(stale).toEqual([])
  expect(SECTIONS.find(s => s.label === 'Help')?.pages).toEqual(['guide'])
  expect(PAGES.guide).toMatchObject({ label: 'Platform guide', slug: 'platform-guide', min: 1 })
  for (const s of Object.values(SCREENS)) { expect(s.answers).toBeTruthy(); expect(s.read.length).toBeGreaterThan(0); expect(s.act.length).toBeGreaterThan(0) }
})

test('guide words: no money figures that go stale', () => {
  const g = fs.readFileSync('src/guide/platformGuide.js', 'utf8')
  expect(g).not.toMatch(/US\$\s?\d/)
})

test.describe('browser: Platform guide', () => {
  test('opens from the menu, lists screens and opens one', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#platform-guide')
    const g = page.locator('[data-platform-guide]')
    await expect(g.locator('[data-guide-version]')).toContainText(`Reviewed for v${UI_VERSION}`)
    await g.locator('[data-guide-screen="coverage"] .pg-screen-head').click()
    await g.getByRole('button', { name: 'Open Coverage & completeness' }).click()
    await expect(page).toHaveURL(/#coverage/)
  })

  test('a Viewer sees the guide; screens they cannot open say so', async ({ page }) => {
    await mockAdmin(page, { rank: 1 })
    await page.goto('/#platform-guide')
    const g = page.locator('[data-platform-guide]')
    await expect(g.locator('[data-guide-screen="users"]')).toContainText('needs a higher role')
  })
})
