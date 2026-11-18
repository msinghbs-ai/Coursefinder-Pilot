// Guards: Course detail shows scholarships in one place only (Platform Admin 19 Nov 2026 06:39, after live inspection of v2.16.47 at 375x812): the correlated Around this course card is headed "Entry requirements" and carries no scholarship line, for Viewer, Counsellor, Editor and Platform Admin alike; the Scholarships section (three, then Show all (N) scholarships) is the only scholarship list; the Provider detail is not changed. No schema change.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import * as F from './support/admin-fixtures.mjs'
import { routeCorrelated } from './support/correlated-fixtures.mjs'
import { CARD_SPEC } from '../../src/lib/correlation-adapters.js'

const COURSE = '/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5'
const sch = (i) => ({ mapping_id: `m${i}`, scholarship_id: `s${i}`, name: `Unique Bursary ${i}`, audience: 'international', nationalities: [], value_label: `A$${i},000`, publication_status: 'published', link: null })
const read = (p) => fs.readFileSync(p, 'utf8')

async function open(page, rank) {
  await mockAdmin(page, { rank })
  await routeCorrelated(page)
  const json = (r, d) => r.fulfill({ json: d })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', (r) => (r.request().postDataJSON() || {}).p_operation === 'course_detail'
    ? json(r, { ...F.courseDetail, course_scholarships: { items: [1, 2, 3, 4, 5].map(sch) } }) : r.fallback())
  await page.goto(COURSE)
  const drawer = page.locator('aside.m-drawer')
  await expect(drawer.locator('[data-correlated="course"]')).toBeVisible()
  await expect(drawer.locator('[data-course-scholarships]')).toBeVisible()
  return drawer
}

test('the entry card is headed Entry requirements and holds no scholarship field', () => {
  const card = CARD_SPEC.course.find((c) => c.id === 'entry')
  expect(card.title).toBe('Entry requirements')
  expect(card.fields.map((f) => f.key)).toEqual(['entry_rows', 'raw_quote', 'layer4_queue_state'])
  expect(JSON.stringify(card)).not.toMatch(/course_scholarships/)
  const src = read('src/CorrelatedBlade.jsx')
  expect(src).toContain('title="Entry requirements"')
  expect(src).not.toContain('Entry requirements & scholarships')
  expect(src).not.toContain('data-cb-scholarships')
  expect(src).not.toContain('data-cb-sch-list')
  expect(src).not.toContain('course_scholarships')
})

test('the Provider card still lists scholarships and accreditations (not part of this change)', () => {
  expect(CARD_SPEC.provider.map((c) => c.id)).toContain('scholarships_accreditations')
})

test('no schema change in this lane', () => {
  const touched = fs.readdirSync('supabase/migrations').filter((f) => /s699/i.test(f))
  expect(touched).toEqual([])
})

test.describe('mocked browser', () => {
  for (const [role, rank] of [['Viewer', 1], ['Counsellor', 2], ['Editor', 3], ['Platform Admin', 6]]) {
    test(`${role}: each scholarship appears once and the entry card has no scholarship line`, async ({ page }) => {
      const drawer = await open(page, rank)
      const entry = drawer.locator('[data-correlated="course"] [data-cb-card="entry"]')
      await expect(entry).toBeVisible()
      await expect(entry.locator('h4')).toHaveText('Entry requirements')
      await expect(entry).not.toContainText(/scholarship/i)
      await expect(entry.locator('[data-cb-scholarships], [data-cb-sch-list]')).toHaveCount(0)
      // the first three are listed once each in the Scholarships section; nowhere else in the drawer
      for (const i of [1, 2, 3]) await expect(drawer.getByText(`Unique Bursary ${i}`, { exact: true })).toHaveCount(1)
      await expect(drawer.locator('[data-course-scholarships] [data-cs-card]')).toHaveCount(3)
      const btn = drawer.locator('[data-show-all="course-scholarships"]')
      await expect(btn).toHaveText('Show all (5) scholarships')
      await btn.click()
      for (const i of [1, 2, 3, 4, 5]) await expect(drawer.getByText(`Unique Bursary ${i}`, { exact: true })).toHaveCount(1)
      await expect(btn).toHaveText('Show less')
      // one scholarship list in the whole blade
      await expect(drawer.locator('[data-course-scholarships]')).toHaveCount(1)
    })
  }

  test('@responsive phone width (375x812): one scholarship list and no scholarship line in the entry card', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 })
    expect(page.viewportSize().width).toBe(375)
    const drawer = await open(page, 1)
    const entry = drawer.locator('[data-correlated="course"] [data-cb-card="entry"]')
    await expect(entry).not.toContainText(/scholarship/i)
    await expect(drawer.getByText('Unique Bursary 1', { exact: true })).toHaveCount(1)
    const over = await drawer.evaluate((el) => el.scrollWidth > el.clientWidth + 1)
    expect(over).toBe(false)
  })
})
