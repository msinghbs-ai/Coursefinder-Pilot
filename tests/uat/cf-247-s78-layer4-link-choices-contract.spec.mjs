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
  test('a course link: keep, use the new page or enter another; both addresses shown; reset filters in the chip row', async ({ page }) => {
    await mockAdmin(page)
    const item = { id: 'i1', status: 'pending', task: 'Official course link', field_code: 'official_course_url', can_approve: true, claimed_by_me: true, claim_active: true,
      entity: { type: 'course', title: 'Bachelor of Computer Science (Honours)', provider: 'Adelaide University', code: '115686J' },
      reason: "The course page that shows this course's CRICOS code is a different address from the official page we hold.", suggestion: { action: 'check', text: 'Check the page, then decide.' },
      links: {}, technical: { before_value: ['https://adelaide.edu.au/study/degrees/2027/bachelor-of-computer-science-honours/int/'], proposed_value: { course_url: 'https://adelaideuni.edu.au/study/degrees/bachelor-of-computer-science-honours-ai/' } } }
    await page.route('https://example.supabase.co/rest/v1/rpc/layer4_review_desk_v1', r => r.fulfill({ json: { items: [item], summary: { waiting: 1, oldest_days: 0, by_task: { 'Official course link': 1 } } } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/layer4_claim_v1', r => r.fulfill({ json: { ok: true } }))
    await page.goto('/#layer-4-review')
    await expect(page.getByRole('button', { name: 'Keep the page we hold' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Use the new page' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Enter another address' })).toBeVisible()
    await expect(page.locator('[data-l4-held]')).toContainText('adelaide.edu.au/study/degrees/2027/')
    await expect(page.locator('[data-l4-new]')).toContainText('adelaideuni.edu.au')
    await page.getByRole('button', { name: 'Official course link (1)' }).click()
    await expect(page.locator('.l4d-chips .l4d-reset')).toHaveText('Reset filters')
  })
})
