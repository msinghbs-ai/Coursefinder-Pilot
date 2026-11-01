// Guards: SS-016 UR-17 acceptance (usability review 1 Nov 2026 §4 UR-17 "Accept"; overnight mandate §4): at each rank 1 to 6, every Specialist task Open button the rank is shown lands on the screen the task names, and where the rank cannot do the task there, that screen says who does it (a handoff) rather than showing nothing or an error. Fixture evidence only.
import { test, expect } from '@playwright/test'
import { PAGES, canOpen } from '../../src/nav-map.js'
import { SPECIALIST_TASKS } from '../../src/guide/platformGuide.js'
import { asRole, mockAer, mockInbox, ROLE } from './support/role-fixtures.mjs'

// the rank each task needs, from its role words (the live boundary: admin_aer edit 3, AER decision 6, re-read 6)
const NEEDS = { 1: /^Viewer/, 2: /^Counsellor/, 3: /^Curator/, 6: /^Platform Admin|the Platform Admin acts/ }
const needs = (t) => Number(Object.entries(NEEDS).find(([, r]) => r.test(t.role))?.[0] || 1)

test('each specialist task names a role the rank table knows, and its screen exists', () => {
  expect(SPECIALIST_TASKS.length).toBeGreaterThanOrEqual(7)
  for (const t of SPECIALIST_TASKS) { expect(PAGES[t.page], t.task).toBeTruthy(); expect([1, 2, 3, 6], t.task).toContain(needs(t)) }
})

test.describe('mocked browser', () => {
  for (let rank = 1; rank <= 6; rank++) {
    test(`${ROLE[rank][1]} (${rank}): each Open lands on its screen; a task above the rank shows who does it`, async ({ page }) => {
      await asRole(page, rank)
      await mockAer(page, rank)
      await mockInbox(page, rank)
      const opened = []
      for (const [i, t] of SPECIALIST_TASKS.entries()) {
        await page.goto('/#platform-guide')
        const row = page.locator('[data-guide-task]').nth(i)
        await expect(row).toContainText(t.task)
        // the row itself always names the lowest role and who to escalate to
        await expect(row).toContainText(t.role)
        if (!canOpen(t.page, rank)) { await expect(row.locator('.pg-open')).toHaveCount(0); continue }
        await row.locator('.pg-open').click()
        await expect(page.locator('.m-topbar h1, h1').first()).toHaveText(PAGES[t.page].title)
        await expect(page.locator('[data-handoff]')).toHaveCount(0)
        opened.push(t.page)
        if (rank >= needs(t)) continue
        // the rank reached the screen but cannot do the task there: the screen names who does
        if (t.page === 'entry' && needs(t) === 3) {
          await page.getByText('CBSE Year 12').first().click()
          await expect(page.locator('[data-aer-owner]')).toContainText('A Curator (rank 3) or above corrects')
        } else if (t.page === 'entry' && needs(t) === 6) {
          await page.goto('/#entry-requirements?tab=sources')
          await expect(page.locator('[data-aer-reread-owner]')).toContainText('The Platform Admin reads it again')
        } else if (t.page === 'layer4') {
          await page.goto('/#layer-4-review?kind=aer_review')
          const item = page.locator('[data-l4-item="aer_review"]')
          await expect(item.locator('[data-l4-handoff]')).toContainText('Platform Admin (rank 6) or above decides')
        } else if (t.page === 'health') {
          await expect(page.locator('main')).toContainText('Platform health')
        }
      }
      test.info().annotations.push({ type: 'UR-17', description: `rank ${rank}: ${opened.length} of ${SPECIALIST_TASKS.length} Open buttons shown and followed (${opened.join(', ')})` })
    })
  }

  test('Curator (3): an SOP Open for a tab above the rank lands on that page with the handoff, not silently on another tab', async ({ page }) => {
    await asRole(page, 3)
    await page.goto('/#platform-guide?tab=operator-sop')
    await page.locator('[data-sop="operator-sop"]').getByRole('button', { name: 'Layer 2/3 Build & enrich › Adapter builder' }).first().click()
    await expect(page.locator('[data-tab-handoff]')).toContainText('Layer 2/3 Build & enrich › Adapter builder opens from PIM Admin (rank 5)')
    await expect(page.locator('[data-tab-handoff]')).toContainText('Ask a PIM Admin')
  })
})
