// Guards: Course and Provider detail UI fixes (Platform Admin 18 Nov 2026 23:02, after live inspection of v2.16.44): the Preview as pills show their full labels at every pane width; Archive course and Read with AI are hidden for Counsellor and Viewer (and Preview as Counsellor or Viewer); the Read / refresh entry requirements now pipeline is hidden for them and only approved entry requirements, or one empty-state line, are shown; scholarship lists show three, then Show all (N) scholarships / Show less, with no nested scrolling.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import * as F from './support/admin-fixtures.mjs'
import { routeCorrelated } from './support/correlated-fixtures.mjs'
import { FIELD_VISIBILITY, canSee, STUDENT_ONLY_EMPTY_ENTRY } from '../../src/lib/field-visibility.js'

const COURSE = '/#courses?id=0b1fb6d4-c02f-47c7-98d0-9f0d57240fd5'
const sch = (i) => ({ mapping_id: `m${i}`, scholarship_id: `s${i}`, name: `Scholarship ${i}`, audience: 'international', nationalities: [], value_label: `A$${i},000`, publication_status: 'published', lifecycle_status: 'active', application_close_date: null, source_url: 'https://www.example.edu.au/s' })

async function open(page, rank, { entryRows } = {}) {
  await mockAdmin(page, { rank })
  await routeCorrelated(page)
  const json = (r, d) => r.fulfill({ json: d })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_course_edit_read', (r) => json(r, { ...F.courseEdit, can_edit: true, can_manage: true, course: { ...F.courseEdit.course, lifecycle_status: 'active' } }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_course_audit', (r) => json(r, { can_read_now: true }))
  if (entryRows) await page.route('https://example.supabase.co/rest/v1/rpc/admin_entry_requirements', (r) => json(r, { rows: entryRows, countries: [], reads: [], can_read: true }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', (r) => (r.request().postDataJSON() || {}).p_operation === 'course_detail'
    ? json(r, { ...F.courseDetail, course_scholarships: { items: [1, 2, 3, 4, 5].map(sch) } }) : r.fallback())
  await page.goto(COURSE)
  const drawer = page.locator('aside.m-drawer')
  await expect(drawer.locator('[data-correlated="course"]')).toBeVisible()
  return drawer
}

test('the visibility rules name the four fixes', () => {
  for (const f of ['archive_actions', 'read_with_ai', 'entry_pipeline', 'unapproved_entry']) {
    expect(FIELD_VISIBILITY.find((x) => x.field === f)?.audience, f).toBe('internal')
    expect([canSee(f, 'viewer'), canSee(f, 'counsellor'), canSee(f, 'editor'), canSee(f, 'platform_admin')], f).toEqual([false, false, true, true])
  }
  expect(FIELD_VISIBILITY.find((x) => x.field === 'archive_actions').selector).toContain('.re-manage')
  expect(FIELD_VISIBILITY.find((x) => x.field === 'read_with_ai').selector).toContain('[data-course-read-ai]')
  expect(FIELD_VISIBILITY.find((x) => x.field === 'entry_pipeline').selector).toContain('[data-course-entry]')
  expect(STUDENT_ONLY_EMPTY_ENTRY).toBe('No approved entry requirements published for this course yet.')
  expect(fs.readFileSync('src/field-visibility.css', 'utf8')).toContain('[data-view-audience="student"] [data-student-only]{display:block}')
  expect(fs.readFileSync('src/correlated-blade.css', 'utf8')).toContain('.m-drawer-head .cb-preview .cb-preview-btn{width:auto;height:auto;')
})

test.describe('mocked browser', () => {
  for (const width of [1500, 720, 390]) {
    test(`Preview as: Admin, Counsellor and Viewer show their full labels at ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 })
      const drawer = await open(page, 6)
      for (const [k, label] of [['admin', 'Admin'], ['counsellor', 'Counsellor'], ['viewer', 'Viewer']]) {
        const b = drawer.locator(`[data-preview-role="${k}"]`)
        await expect(b).toHaveText(label)
        const m = await b.evaluate((e) => ({ sw: e.scrollWidth, cw: e.clientWidth, w: e.getBoundingClientRect().width, right: e.getBoundingClientRect().right, pane: e.closest('aside').getBoundingClientRect().right }))
        expect(m.sw, `${k} clipped`).toBeLessThanOrEqual(m.cw + 1)
        expect(m.w, `${k} too narrow`).toBeGreaterThan(36)
        expect(m.right, `${k} out of the pane`).toBeLessThanOrEqual(m.pane + 1)
      }
    })
  }

  test('Archive course, Read with AI and the entry pipeline: shown to the Platform Admin, hidden in Preview as Counsellor and Viewer', async ({ page }) => {
    const drawer = await open(page, 6, { entryRows: [{ id: 'a1', kind: 'atar', description: 'Minimum ATAR', min_entry_score: 70, min_entry_score_basis: 'ATAR', status: 'active', quote: 'ATAR 70', source_url: 'https://example.edu.au' },
      { id: 'p1', kind: 'prerequisite', description: 'English units 3 and 4', status: 'proposed', quote: 'English' }] })
    const archive = drawer.getByRole('button', { name: 'Archive course' })
    const readAi = drawer.locator('[data-course-read-ai]')
    const pipeline = drawer.locator('[data-course-entry]')
    await expect(archive).toBeVisible()
    await expect(readAi).toBeVisible()
    await expect(pipeline).toBeVisible()
    await expect(drawer.locator('[data-student-entry]')).toBeHidden()
    for (const role of ['counsellor', 'viewer']) {
      await drawer.locator(`[data-preview-role="${role}"]`).click()
      await expect(archive).toBeHidden()
      await expect(readAi).toBeHidden()
      await expect(pipeline).toBeHidden()
      for (const t of ['Read / refresh entry requirements now', 'Open in Entry requirements']) for (const el of await drawer.getByText(t).all()) await expect(el).toBeHidden()
      const student = drawer.locator('[data-student-entry]')
      await expect(student).toBeVisible()
      await expect(student.locator('[data-student-entry-rows] li')).toHaveCount(1)
      await expect(student).toContainText('Minimum ATAR')
      await expect(student).not.toContainText('English units')
      await expect(drawer.locator('[data-correlated="course"] [data-vis="unapproved_entry"]')).toBeHidden()
    }
    await drawer.locator('[data-preview-role="admin"]').click()
    await expect(archive).toBeVisible()
  })

  test('a Viewer with no approved entry requirement sees one empty-state line and no pipeline', async ({ page }) => { // s990: a Counsellor (rank 2) is given the v1.1 build only
    const drawer = await open(page, 1, { entryRows: [{ id: 'p1', kind: 'prerequisite', description: 'English units 3 and 4', status: 'proposed', quote: 'English' }] })
    await expect(drawer).toHaveAttribute('data-view-audience', 'student')
    await expect(drawer.locator('[data-course-entry]')).toBeHidden()
    await expect(drawer.locator('[data-student-entry-empty]')).toHaveText(STUDENT_ONLY_EMPTY_ENTRY)
    await expect(drawer.locator('[data-cb-empty="entry-approved"]')).toBeVisible()
    await expect(drawer.getByRole('button', { name: 'Archive course' })).toBeHidden()
    await expect(drawer.locator('[data-course-read-ai]')).toBeHidden()
  })

  test('scholarships: three shown, then Show all (5) scholarships and Show less, with no inner scroll box', async ({ page }) => {
    const drawer = await open(page, 6)
    const cards = drawer.locator('[data-course-scholarships] [data-cs-card]')
    await expect(cards).toHaveCount(3)
    const btn = drawer.locator('[data-show-all="course-scholarships"]')
    await expect(btn).toHaveText('Show all (5) scholarships')
    await btn.click()
    await expect(cards).toHaveCount(5)
    await expect(btn).toHaveText('Show less')
    await expect(btn).toHaveAttribute('aria-expanded', 'true')
    await btn.click()
    await expect(cards).toHaveCount(3)
    // s699: the correlated card no longer carries a second scholarship list
    await expect(drawer.locator('[data-correlated="course"] [data-cb-sch-list], [data-correlated="course"] [data-cb-scholarships]')).toHaveCount(0)
    // no nested scroll box around the scholarship list
    for (const sel of ['[data-course-scholarships] .cs-cards']) {
      const o = await drawer.locator(sel).evaluate((e) => { const s = getComputedStyle(e); return { y: s.overflowY, mh: s.maxHeight } })
      expect(['visible', 'clip'].includes(o.y) || o.mh === 'none', sel).toBe(true)
    }
  })

  test('Provider detail: the scholarship insight list shows three, then Show all (N) scholarships', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await routeCorrelated(page)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', (r) => {
      const op = (r.request().postDataJSON() || {}).p_operation
      if (op === 'provider_detail') return r.fulfill({ json: { id: 'p1', canonical_name: 'RMIT University', country_code: 'AU', scholarship_count: 6 } })
      if (op === 'provider_insights') return r.fulfill({ json: { contextual_insights: { scholarships: { total: 6, items: [1, 2, 3, 4, 5, 6].map((i) => ({ id: `s${i}`, name: `Scholarship ${i}`, relationship: 'provider_wide', award_value_text: `A$${i},000` })) } } } })
      return r.fallback()
    })
    await page.goto('/#providers?id=p1')
    await page.locator('[data-provider-more] > summary').click()
    await page.locator('[data-ci-fold] > summary').click() // s698: Related insights & funding is folded by default
    const rows = page.locator('.ci-scholarships .ci-sch-row')
    await expect(rows).toHaveCount(3)
    await page.locator('[data-show-all="insight-scholarships"]').click()
    await expect(rows).toHaveCount(6)
    await expect(page.locator('[data-show-all="insight-scholarships"]')).toHaveText('Show less')
  })
})
