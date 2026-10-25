// Guards: CF-247 v2.15.257 (S22): Platform Admin 12 Oct 2026: "SOPs for Platform Admin and operators ...
// CF-247 v2.15.257 (S22): Platform Admin 12 Oct 2026: "SOPs for Platform Admin and operators ... under Guides in the UI and as versioned docs,
// kept up to date with the UI and the data admission mechanism". One source (src/guide/sops.js) for the in-app guides and docs/sops/*.md.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { PAGES, SECTIONS } from '../../src/nav-map.js'
import { UI_VERSION } from '../../src/release-manifest.js'
import { SOPS, SOP_REVIEWED_FOR, sopMarkdown, AUTOMATION } from '../../src/guide/sops.js'

const label = (page, tab) => { const p = PAGES[page]; const t = (p?.tabs || []).find((x) => x.key === tab); return [p?.label || page, t?.label].filter(Boolean).join(' › ') }

test('SOPs reviewed for this release (update src/guide/sops.js, raise the SOP version, then set SOP_REVIEWED_FOR)', () => {
  expect(SOP_REVIEWED_FOR).toBe(UI_VERSION)
})

test('Guides menu holds the Platform guide and both SOPs', () => {
  expect(SECTIONS.find((s) => s.label === 'Guides')?.pages).toEqual(['guide'])
  expect(PAGES.guide.tabs.map((t) => t.key)).toEqual(['guide', 'admin-sop', 'operator-sop'])
  expect(SOPS.map((s) => s.id)).toEqual(['admin-sop', 'operator-sop'])
})

test('every SOP step opens a real screen and tab; each SOP has its sections and a version history entry for its version', () => {
  for (const s of SOPS) {
    const steps = [...s.schedule.flatMap((b) => b.steps), ...s.weekly]
    for (const x of steps) {
      expect(PAGES[x.page], `${s.id}: ${x.do}`).toBeTruthy()
      if (x.tab) expect(PAGES[x.page].tabs.some((t) => t.key === x.tab), `${s.id}: ${x.page}?tab=${x.tab}`).toBe(true)
    }
    expect(s.interventions.length).toBeGreaterThan(3)
    expect(s.watch.length).toBeGreaterThan(2)
    expect(s.changes.some((c) => c.version === s.version)).toBe(true)
  }
  expect(AUTOMATION.length).toBe(8) // v2.15.258: the seven journey stages, then delivery
})

test('the versioned documents equal what src/guide/sops.js generates (run node scripts/export-sops.mjs)', () => {
  for (const s of SOPS) expect(fs.readFileSync(`docs/sops/${s.id}.md`, 'utf8')).toBe(sopMarkdown(s, label))
})

test.describe('mocked browser', () => {
  test('a Platform Admin opens the Platform Admin SOP and goes from a step to its screen', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#platform-guide?tab=admin-sop')
    const s = page.locator('[data-sop="admin-sop"]')
    await expect(s.locator('[data-sop-version]')).toContainText(`reviewed for v${UI_VERSION}`)
    await expect(s.locator('[data-sop-automation]')).toContainText('Where a person decides')
    await expect(s.locator('[data-sop-step]').first()).toBeVisible()
    await expect(s.locator('[data-sop-interventions]')).toContainText('Ready to admit')
    await s.getByRole('button', { name: 'Layer 2/3 Build & enrich › Universities' }).first().click() // v2.15.300
    await expect(page).toHaveURL(/#layer-2-discovery\?tab=universities/)
  })

  test('a Curator sees both SOP tabs; the Operator SOP names who does each step', async ({ page }) => {
    await mockAdmin(page, { rank: 3 })
    await page.goto('/#platform-guide?tab=operator-sop')
    const s = page.locator('[data-sop="operator-sop"]')
    await expect(s.locator('[data-sop-daily]')).toContainText('Curator: Layer 4 › Inbox') // v2.15.300
    await expect(page.getByRole('tab', { name: 'Platform Admin SOP' })).toBeVisible()
  })

  test('a Viewer sees the Platform guide only', async ({ page }) => {
    await mockAdmin(page, { rank: 1 })
    await page.goto('/#platform-guide')
    await expect(page.locator('[data-platform-guide]')).toBeVisible()
    await expect(page.getByRole('tab', { name: 'Platform Admin SOP' })).toHaveCount(0)
  })
})
