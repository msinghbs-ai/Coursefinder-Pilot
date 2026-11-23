// Guards: Course detail declutter (Platform Admin 18 Nov 2026 23:51, after live mobile inspection with Preview as Viewer): the Description pipeline and Tasks that held this course are hidden for Counsellor and Viewer and folded by default for Editors and Platform Admins; Check scholarships for this course and other task triggers are hidden for Counsellor and Viewer; Related insights & funding (QILT and PRISMS) is folded by default for every role; scholarships appear in one place on the Course detail (no second Scholarships & funding card in the insights).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import * as F from './support/admin-fixtures.mjs'
import { routeCorrelated } from './support/correlated-fixtures.mjs'
import { FIELD_VISIBILITY, canSee } from '../../src/lib/field-visibility.js'

const COURSE = '/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5'
const sch = (i) => ({ mapping_id: `m${i}`, scholarship_id: `s${i}`, name: `Scholarship ${i}`, audience: 'international', nationalities: [], value_label: `A$${i},000`, publication_status: 'published', lifecycle_status: 'active', source_url: 'https://www.example.edu.au/s' })
const insights = { student_outcomes: { source_label: 'QILT', granularity: 'provider_context', total: 0, items: [] }, student_flow: { source_label: 'PRISMS', relationship_state: 'regional_context', items: [] },
  scholarships: { total: 4, items: [1, 2, 3, 4].map((i) => ({ id: `s${i}`, name: `Scholarship ${i}`, relationship: 'provider_wide', award_value_text: `A$${i},000` })) }, authority_note: 'Context only.' }

async function open(page, rank) {
  await mockAdmin(page, { rank })
  await routeCorrelated(page)
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', (r) => {
    const op = (r.request().postDataJSON() || {}).p_operation
    if (op === 'course_detail') return r.fulfill({ json: { ...F.courseDetail, course_scholarships: { items: [1, 2, 3, 4].map(sch) } } })
    if (op === 'course_insights') return r.fulfill({ json: { contextual_insights: insights } })
    return r.fallback()
  })
  await page.goto(COURSE)
  const drawer = page.locator('aside.m-drawer')
  await expect(drawer.locator('[data-correlated="course"]')).toBeVisible()
  return drawer
}

test('the rules: Description pipeline and task triggers are internal; insights fold and one scholarship list in the source', () => {
  for (const f of ['description_pipeline', 'task_triggers']) {
    expect(FIELD_VISIBILITY.find((x) => x.field === f)?.audience, f).toBe('internal')
    expect([canSee(f, 'viewer'), canSee(f, 'counsellor'), canSee(f, 'editor'), canSee(f, 'platform_admin')], f).toEqual([false, false, true, true])
  }
  expect(FIELD_VISIBILITY.find((x) => x.field === 'description_pipeline').selector).toContain('[data-cdod-block]')
  expect(FIELD_VISIBILITY.find((x) => x.field === 'task_triggers').selector).toContain('[data-scholarship-actions]')
  const ci = fs.readFileSync('src/ContextualInsights.jsx', 'utf8')
  expect(ci).toContain('<details className="ci-workbench ci-fold" data-ci-fold={entityType}>')
  expect(ci).toContain('{!course&&<ScholarshipPanel group={sch} navigate={navigate}/>}')
  expect(fs.readFileSync('src/CourseDescriptionOnDemand.jsx', 'utf8')).toContain('<details className="cdod-fold" data-cdod-fold>')
})

test.describe('mocked browser', () => {
  test('Platform Admin: the Description pipeline is folded until opened; Preview as Counsellor and Viewer hide it, Tasks that held this course and Check scholarships', async ({ page }) => {
    const drawer = await open(page, 6)
    const block = drawer.locator('[data-cdod-block]')
    const fold = block.locator('[data-cdod-fold]')
    await expect(block).toBeVisible()
    await expect(fold).not.toHaveAttribute('open', '')
    await expect(block.locator('.cdod-tasks-fold')).toBeHidden()
    await fold.locator('> summary').click()
    await expect(fold).toHaveAttribute('open', '')
    await expect(block.locator('.cdod-tasks-fold')).toBeVisible()
    const check = drawer.getByRole('button', { name: /Check scholarships for this course/ })
    await expect(check).toBeVisible()
    for (const role of ['counsellor', 'viewer']) {
      await drawer.locator(`[data-preview-role="${role}"]`).click()
      await expect(block).toBeHidden()
      for (const t of ['Description pipeline', 'Tasks that held this course']) for (const el of await drawer.getByText(t).all()) await expect(el).toBeHidden()
      await expect(check).toBeHidden()
      for (const el of await drawer.locator('[data-job-button], [data-scholarship-actions]').all()) await expect(el).toBeHidden()
    }
    await drawer.locator('[data-preview-role="admin"]').click()
    await expect(block).toBeVisible()
    await expect(check).toBeVisible()
  })

  test('a Viewer: no Description pipeline and no task trigger', async ({ page }) => {
    const drawer = await open(page, 1)
    await expect(drawer).toHaveAttribute('data-view-audience', 'student')
    await expect(drawer.locator('[data-cdod-block]')).toHaveCount(0)
    for (const el of await drawer.locator('[data-job-button], [data-scholarship-actions]').all()) await expect(el).toBeHidden()
  })

  for (const rank of [6, 1]) { // s990: a Counsellor (rank 2) is given the v1.1 build only; a Viewer keeps this drawer
    test(`Related insights & funding is folded by default and scholarships are listed once (rank ${rank})`, async ({ page }) => {
      const drawer = await open(page, rank)
      await drawer.locator('[data-course-more] > summary').click()
      const fold = drawer.locator('[data-ci-fold="course"]')
      await expect(fold).toBeVisible()
      await expect(fold).not.toHaveAttribute('open', '')
      await expect(fold.locator('> summary')).toContainText('Related insights & funding')
      await expect(fold.locator('> summary')).toContainText('QILT & PRISMS context')
      await expect(fold.locator('.ci-outcome-card, .ci-prisms').first()).toBeHidden()
      await fold.locator('> summary').click()
      await expect(fold).toHaveAttribute('open', '')
      await expect(fold.locator('.ci-prisms')).toBeVisible()
      // one canonical scholarship section: no Scholarships & funding card in the insights of a course
      await expect(drawer.locator('.ci-scholarships')).toHaveCount(0)
      await expect(drawer.locator('[data-course-scholarships]')).toHaveCount(1)
      await expect(drawer.locator('[data-course-scholarships] [data-cs-card]')).toHaveCount(3)
      await expect(drawer.locator('[data-show-all="course-scholarships"]')).toHaveText('Show all (4) scholarships')
    })
  }
})
