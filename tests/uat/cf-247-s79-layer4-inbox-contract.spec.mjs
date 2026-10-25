// Guards: CF-247 (S79) v2.15.298. Platform Admin, 20 Oct 2026 07:02: "anything that needs attention or intervention should come to Layer 4, define its return path";
// CF-247 (S79) v2.15.298. Platform Admin, 20 Oct 2026 07:02: "anything that needs attention or intervention should come to Layer 4, define
// its return path"; choices: by university, all stopped onboarding cases, courses not on the site at the bottom, websites down after 30 days.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const mig = fs.readFileSync('supabase/migrations/20261020040000_cf247_layer4_inbox.sql', 'utf8')

test('inbox: every source, every kind names its choices and return path; decide routes to the existing actions', () => {
  for (const k of ['course_link', 'held_scholarship', 'website_needed', 'pages_not_found', 'too_few_pages', 'nothing_ready', 'central_to_approve', 'onboarding_failed', 'site_down', 'not_offered', 'fee_check', 'counsellor_report', 'not_on_site'])
    expect(mig, k).toContain(`"${k}": {"label"`)
  expect(mig).toContain("make_interval(days => security.pipeline_num_v1('layer4.site_down_days', 30)::int)")
  expect(mig).toContain("and ob.provider_id not in (select provider_id from cricos_only)")
  expect(mig).toContain('"not_on_site": {"label": "Course not on the university\'\'s site", "order": 13')
  for (const call of ['public.layer4_review_decide(', "public.admin_scholarship_ai('review_decide'", 'public.admin_provider_website_set(', 'security.flag_release_v1(', "public.admin_adapter_build('build'", "public.admin_provider_onboarding('retry'", 'public.admin_provider_archive(', "public.admin_course_edit((v_det->>'course_id')::uuid, 'archive'"])
    expect(mig, call).toContain(call)
  expect(mig).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test.describe('mocked browser', () => {
  test('universities with their items; a choice shows what happens next and needs a reason', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    const kinds = { pages_not_found: { label: 'Course pages not found', order: 4, choices: [
      { key: 'website', label: 'Change the website', input: 'url', returns: 'The hold is released, the site is mapped again and onboarding starts again' },
      { key: 'pages', label: 'Add page addresses', link: 'builder', returns: 'Opens the Adapter builder (2.1)' },
      { key: 'release', label: 'Release and try again', rank: 4, returns: 'The hold is released; the site is mapped again and onboarding starts again' }] },
      course_link: { label: 'Course link', order: 1, choices: [{ key: 'keep', label: 'Keep the page we hold', returns: 'Closed' }] } }
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async route => {
      const b = route.request().postDataJSON(); calls.push(b)
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 4, total: 2, universities: 1, late: 1, by_kind: { pages_not_found: { n: 1 }, course_link: { n: 1 } } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p1', name: 'Holmes Institute', country: 'AU', courses: 25, n: 2, oldest: '2026-10-01T00:00:00Z', late: true, by_kind: { course_link: 1, pages_not_found: 1 } }] } })
      if (b.p_action === 'items') return route.fulfill({ json: { total: 2, items: [
        { kind: 'pages_not_found', ref: '9', provider_id: 'p1', why: 'Re-find wave 1: the site map returned no course pages.', created_at: '2026-10-19T20:00:00Z', late: false, detail: { flag_id: 9 } },
        { kind: 'course_link', ref: 'r1', provider_id: 'p1', subject: 'Diploma of Business', why: 'Different page', created_at: '2026-10-06T00:00:00Z', late: true, detail: { before: ['https://holmes.edu.au/a'], proposed: { course_url: 'https://holmes.edu.au/b' } } }] } })
      if (b.p_action === 'decide') return route.fulfill({ json: { ok: true, returns: 'The hold is released; the site is mapped again and onboarding starts again' } })
      return route.fulfill({ json: {} })
    })
    await page.goto('/#layer-4-review')
    await expect(page.locator('[data-l4-inbox]')).toBeVisible()
    await expect(page.locator('[data-l4-uni="Holmes Institute"]')).toContainText('Course pages not found')
    const held = page.locator('[data-l4-item="pages_not_found"]')
    await expect(held).toContainText('Re-find wave 1')
    await expect(page.locator('[data-l4-item="course_link"] [data-l4-new]')).toContainText('holmes.edu.au/b')
    await held.locator('[data-l4-choice="release"]').click()
    await expect(held).toContainText('What happens next: The hold is released; the site is mapped again and onboarding starts again')
    await expect(held.locator('[data-l4-confirm]')).toBeDisabled()
    await held.getByLabel('Reason').fill('Website checked: holmesinstitute.edu.au is right')
    await held.locator('[data-l4-confirm]').click()
    await expect(page.getByRole('status')).toContainText('Done.')
    expect(calls.find(c => c.p_action === 'decide').p_args).toMatchObject({ kind: 'pages_not_found', ref: '9', choice: 'release', reason: 'Website checked: holmesinstitute.edu.au is right' })
    await expect(held.locator('[data-l4-choice="pages"]')).toBeVisible()
  })
})
