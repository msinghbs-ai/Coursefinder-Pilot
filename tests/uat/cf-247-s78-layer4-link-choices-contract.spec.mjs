// CF-247 (S78) v2.15.297. Platform Admin, 20 Oct 2026 07:02 (Layer 4 capture): "there is no Approve button"; "Reset filter button is
// misplaced". Course-link items say what each choice does and show the page held beside the new page; Reset filters sits in the chips.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const mig = fs.readFileSync('supabase/migrations/20261020020000_cf247_layer4_link_approve.sql', 'utf8')

test('the desk recognises a proposed page stored as course_url', () => {
  expect(mig).toContain("(b.proposed_value ? ''url'' or b.proposed_value ? ''course_url'')")
})

test.describe('mocked browser', () => {
  // v2.15.300: the Review queue retired; a course link is decided in the Inbox with the same three choices
  test('a course link in the Inbox: Keep the page we hold, Use the new page, Enter another address', async ({ page }) => {
    await mockAdmin(page)
    const kinds = { course_link: { label: 'Course link', order: 1, choices: [{ key: 'keep', label: 'Keep the page we hold', returns: 'Closed' }, { key: 'use', label: 'Use the new page', returns: 'Link written' }, { key: 'enter', label: 'Enter another address', input: 'url', returns: 'Link written' }] } }
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async route => {
      const b = route.request().postDataJSON()
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 1, universities: 1, late: 0, by_kind: { course_link: { n: 1 } } } })
      if (b.p_action === 'items') return route.fulfill({ json: { total: 1, items: [{ kind: 'course_link', ref: 'i1', provider_id: 'pa', provider: 'Adelaide University', subject: 'Bachelor of Computer Science (Honours)', why: "The course page that shows this course's CRICOS code is a different address from the official page we hold.", created_at: '2026-10-20T00:00:00Z',
        detail: { course_code: '115686J', before: ['https://adelaide.edu.au/study/degrees/2027/bachelor-of-computer-science-honours/int/'], proposed: { course_url: 'https://adelaideuni.edu.au/study/degrees/bachelor-of-computer-science-honours/' } } }] } })
      return route.fulfill({ json: { total: 1, items: [{ provider_id: 'pa', name: 'Adelaide University', n: 1, by_kind: { course_link: 1 } }] } })
    })
    await page.goto('/#layer-4-review?tab=review')
    await expect(page).toHaveURL(/kind=course_link/)
    const it = page.locator('[data-l4-item="course_link"]')
    await expect(it.getByRole('button', { name: 'Keep the page we hold' })).toBeVisible()
    await expect(it.getByRole('button', { name: 'Use the new page' })).toBeVisible()
    await expect(it.getByRole('button', { name: /Enter another address/ })).toBeVisible()
    await expect(it.locator('[data-l4-held]')).toContainText('adelaide.edu.au/study/degrees/2027/')
    await expect(it.locator('[data-l4-new]')).toContainText('adelaideuni.edu.au')
  })
})
