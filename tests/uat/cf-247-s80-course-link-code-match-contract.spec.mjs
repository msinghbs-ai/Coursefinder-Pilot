// CF-247 (S80) v2.15.299. Platform Admin, 20 Oct 2026 09:41: "on right of the Course name display the Cricos code ... the course name is
// align to course url, there should be no confusion. What we hold is correct."
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const mig = fs.readFileSync('supabase/migrations/20261020050000_cf247_course_link_major_rule.sql', 'utf8')

test('page rule: a major or specialisation page of the course held does not replace it', () => {
  expect(mig).toContain("md5(pg_get_functiondef('security.course_page_rule_v1(text,text)'::regprocedure)) <> '53e4bcf49c72e0e29936f3c61f6045c4'")
  expect(mig).toContain("then 'keep:the proposed page is a major or specialisation of the course page held'")
  expect(mig).toContain("like lower(regexp_replace(rtrim(p_held, '/'), '^.*/', '')) || '-%'")
})

test.describe('mocked browser', () => {
  test('the CRICOS code sits beside the course name; each address says whether it is the course name or a major', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    const kinds = { course_link: { label: 'Course link', order: 1, choices: [{ key: 'keep', label: 'Keep the page we hold', returns: 'Closed' }] } }
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async route => {
      const b = route.request().postDataJSON()
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 1, universities: 1, late: 0, by_kind: { course_link: { n: 1 } } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p1', name: 'Adelaide University', country: 'AU', courses: 498, n: 1, by_kind: { course_link: 1 } }] } })
      return route.fulfill({ json: { total: 1, items: [{ kind: 'course_link', ref: 'r1', provider_id: 'p1', subject: 'Bachelor of Journalism', why: 'Different page', created_at: '2026-10-19T00:00:00Z',
        detail: { course_code: '115723J', before: ['https://adelaide.edu.au/study/degrees/bachelor-of-journalism/'], proposed: { course_url: 'https://adelaide.edu.au/study/degrees/bachelor-of-journalism-creative-writing/' } } }] } })
    })
    await page.goto('/#layer-4-review')
    const it = page.locator('[data-l4-item="course_link"]')
    await expect(it.locator('[data-l4-code]')).toHaveText('CRICOS 115723J')
    await expect(it.locator('[data-l4-held] [data-l4-match]')).toHaveText('matches the course name')
    await expect(it.locator('[data-l4-new] [data-l4-match]')).toHaveText('a major or specialisation of the course')
  })
})
