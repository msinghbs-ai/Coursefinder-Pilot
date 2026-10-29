// Guards: CF-247 Platform Admin mandate 29 Oct 2026 12:23 section A2: DP020's scholarship relationship — the Course detail read carries the course's linked scholarships, a page's research level never links every level by field alone, and an empty state says why with a working "Check scholarships for this course"
// Trace (live, 29 Oct 2026): RMIT Diploma of Commerce (DP020, CRICOS 111278B) has 9 mapped scholarships, 6 published and active, but the
// Course detail read lost course_scholarships when admin_read was rebuilt on 14 Oct 2026, so every course showed "No published scholarship
// is linked to this course yet". Two of the nine are RMIT PhD scholarships linked by field alone ("postgraduate_research" mapped to no
// study level). Known eligible, ineligible and genuinely empty cases are checked in the mocked browser.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import * as F from './support/admin-fixtures.mjs'

const MIG = 'supabase/migrations/20261029070000_cf247_scholarship_relationship_fix.sql'
const sql = fs.readFileSync(MIG, 'utf8')
const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
const actions = fs.readFileSync('src/ScholarshipActions.jsx', 'utf8')

test('migration: md5-guarded edits re-attach course_scholarships and make postgraduate_research a research level; nothing re-applied or removed', () => {
  expect(sql).toMatch(/^-- Replaces: public\.admin_read, security\.scholarship_level_codes, security\.scholarship_sweep_apply_v1/m)
  expect(sql).toMatch(/^-- Retires: nothing$/m)
  expect(sql).toContain("select pg_temp.edit_n('public.admin_read(text,jsonb)', 'f7f3ebded941a60b391fa8b7c8e91805'")
  expect(sql).toContain("select pg_temp.edit_n('security.scholarship_level_codes(jsonb)', '902fac0f6dd4912db8d1b4465ed7275b'")
  expect(sql).toContain("select pg_temp.edit_n('security.scholarship_sweep_apply_v1(uuid)', '7189ffebb3e5449b1af4a364731a7687'")
  expect(sql).toContain("||jsonb_build_object('course_scholarships',security.admin_course_scholarships(v_id));end if;")
  expect(sql).toContain("when 'postgraduate_research' then array['masters_research','doctorate']")
  expect(sql).toContain("v_changes:=v_changes||'levels_not_recognised'::text;")
  // the existing mechanisms only: no mapping is written, re-applied, published or removed by the migration
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate|insert|update)\b/im)
  expect(sql).not.toMatch(/scholarship_sweep_apply_v1\(\s*'/)
  expect(sql).not.toMatch(/publication_status\s*=\s*'published'/)
})

test('source: the blade reads course_scholarships, explains an empty state and offers the course check task', () => {
  expect(main).toContain('<CourseScholarships data={data.course_scholarships} navigate={navigate}/><CourseScholarshipAction courseId={data.id}')
  expect(main).toContain(':courseScholarshipEmpty(data,items)}/>}')
  expect(main).not.toContain("'No published scholarship is linked to this course yet.'")
  expect(actions).toContain('<JobButton kind="scholarship_course_check" scope={courseId} args={{course_id:courseId}} icon={Sparkles} label="Check scholarships for this course"')
})

const card = (o = {}) => ({ mapping_id: 'm', scholarship_id: 's', audience: 'international', nationalities: [], value_label: 'A$5,000', publication_status: 'published', lifecycle_status: 'active',
  application_close_date: null, source_url: 'https://www.rmit.edu.au/scholarships/x', mapping_basis: 'sweep_level_field_scope', ...o })

async function openDp020(page, course_scholarships) {
  await mockAdmin(page)
  const jobs = []; page.jobStarts = jobs
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    let b = {}; try { b = route.request().postDataJSON() || {} } catch {}
    if (b.p_operation === 'course_detail') return route.fulfill({ json: { ...F.courseDetail, canonical_title: 'Diploma of Commerce', display_title: 'Diploma of Commerce', course_code: '111278B', level_name: 'Diploma', course_scholarships } })
    return route.fallback()
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_jobs', async route => {
    const b = route.request().postDataJSON() || {}
    if (b.p_action === 'start') { jobs.push(b.p_args); return route.fulfill({ json: { ok: true, id: 'job-sch', title: 'Check scholarships for Diploma of Commerce (111278B)' } }) }
    return route.fallback()
  })
  await page.goto(`/#courses?id=${F.courseDetail.id}`)
  return page.locator('[data-course-scholarships]')
}

test.describe('mocked browser', () => {
  test('eligible: the published, active scholarships linked to the course show as cards', async ({ page }) => {
    const p = await openDp020(page, { state: 'mapped', mapped_count: 3, needs_review_count: 0, items: [
      card({ mapping_id: 'm1', name: 'Dylan Alcott Foundation Scholarship', audience: 'international_and_domestic' }),
      card({ mapping_id: 'm2', name: 'Pathway Scholarship for China' }),
      card({ mapping_id: 'm3', name: 'English to Foundation Studies/Fast Track Pathway Bursary', publication_status: 'withdrawn' }),
    ] })
    await expect(p.locator('[data-cs-card]')).toHaveCount(2)
    await expect(p).toContainText('Dylan Alcott Foundation Scholarship')
    await expect(p).toContainText('Pathway Scholarship for China')
    await expect(p).not.toContainText('Fast Track Pathway Bursary')
    await expect(p.locator('.cs-count')).toHaveText('2 scholarships')
  })

  test('ineligible: a nationality the scholarships do not name, and links that are not published, are explained', async ({ page }) => {
    const p = await openDp020(page, { state: 'mapped', mapped_count: 2, needs_review_count: 0, items: [
      card({ mapping_id: 'm1', name: 'China Pathway Award', nationalities: ['CN'] }),
      card({ mapping_id: 'm2', name: 'Vietnam Pathway Award', nationalities: ['VN'] }),
    ] })
    await p.getByLabel('Student nationality').selectOption('VN')
    await expect(p.locator('[data-cs-card]')).toHaveCount(1)
    await expect(p).not.toContainText('China Pathway Award')
    await page.goto('/#dashboard')
    const q = await openDp020(page, { state: 'mapped', mapped_count: 2, needs_review_count: 0, items: [
      card({ mapping_id: 'm1', name: 'Withdrawn award', publication_status: 'withdrawn' }),
      card({ mapping_id: 'm2', name: 'Old award', publication_status: 'unpublished', lifecycle_status: 'inactive' }),
    ] })
    await expect(q.locator('[data-cs-card]')).toHaveCount(0)
    await expect(q).toContainText('2 scholarships are linked to this course, but none is published and active (unpublished, withdrawn or closed), so none is shown.')
  })

  test('genuinely empty: the reason is stated and "Check scholarships for this course" starts the course check task', async ({ page }) => {
    page.on('dialog', d => d.accept())
    const p = await openDp020(page, { state: 'not_mapped', mapped_count: 0, needs_review_count: 0, items: [] })
    await expect(p.locator('[data-cs-card]')).toHaveCount(0)
    await expect(p).toContainText("No scholarship page from this provider names this course, its study level or its field, so none is linked. Use 'Check scholarships for this course'")
    const btn = page.getByRole('button', { name: 'Check scholarships for this course' })
    await expect(btn).toBeVisible()
    await btn.click()
    await expect.poll(() => page.jobStarts.length).toBe(1)
    expect(page.jobStarts[0].kind).toBe('scholarship_course_check')
    expect(page.jobStarts[0].args.course_id).toBe(F.courseDetail.id)
    await expect(page.getByText('Started "Check scholarships for Diploma of Commerce (111278B)"')).toBeVisible()
  })

  test('waiting for review: candidates are counted, not shown as linked', async ({ page }) => {
    const p = await openDp020(page, { state: 'needs_review', mapped_count: 0, needs_review_count: 2, items: [] })
    await expect(p).toContainText('No scholarship is linked yet. 2 possible scholarships wait for review before they can be linked.')
  })
})
