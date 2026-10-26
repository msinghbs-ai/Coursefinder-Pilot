// Guards: CF-247 S122 hotfix (Platform Admin 26 Oct 2026 12:50): no-page and conjoint first runs carry their university in the Layer 4 inbox, show under By university, and offer approve / edit / reject on the card
// Found in the Waikato triage (admin docs/platform/ui-audit/2026-10-26-waikato-triage-followups.md section 3): the 60 waiting first runs had
// no university and the course-link choices.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const m = fs.readFileSync('supabase/migrations/20261026003000_cf247_hotfix_l4_first_runs_inbox.sql', 'utf8')

test('migration: first runs take their university and own kinds; decide routes to layer4_review_decide; md5-guarded', () => {
  expect(m).toMatch(/pg_temp\.edit_n\('security\.layer4_inbox_items_v1\(\)', 'c5f4f34cd2ea79b3a3aff8ef3617b4a6'/)
  expect(m).toMatch(/pg_temp\.edit_n\('security\.layer4_inbox_kinds_v1\(\)', '1703346f9f602cce922aaea2d6f11450'/)
  expect(m).toMatch(/pg_temp\.edit_n\('public\.admin_layer4_inbox\(text,jsonb\)', '2e2225b03af3a206ea3aa126354f023b'/)
  expect(m).toContain("coalesce(c.provider_id, s.provider_id, case when r.entity_type = 'provider' then r.entity_id end)")
  expect(m).toContain("when r.entity_type = 'provider' and r.field_code = 'no_page_first_run' then 'no_page_first_run'")
  expect(m).toContain("when r.entity_type = 'provider' and r.field_code = 'conjoint_rule_first_run' then 'conjoint_first_run'")
  for (const k of ['"no_page_first_run": {"label": "No page published: first run"', '"conjoint_first_run": {"label": "Conjoint or double degrees: first run"']) expect(m).toContain(k)
  for (const c of ['"key": "approve"', '"key": "has_page", "label": "Approve, except courses that have a page", "input": "courses"', '"key": "parent", "label": "Approve with their shared page", "input": "url"', '"key": "reject"']) expect(m).toContain(c)
  expect(m).toContain("case v_choice when 'approve' then 'approve' when 'reject' then 'reject' else 'edit_and_approve' end")
  expect(m).toContain("when 'has_page' then jsonb_build_object('has_page_course_ids', to_jsonb(v_ids))")
  expect(m).toContain("raise exception 'a ticked course is not in this sample'")
})

test.describe('mocked browser', () => {
  test('By university: the first run shows with its sample; "has a page" ticks a sample course and sends its id; reject is offered', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    const kinds = {
      no_page_first_run: { label: 'No page published: first run', order: 15, choices: [
        { key: 'approve', label: 'Approve: none has its own page', returns: 'The sample is recorded as no page published' },
        { key: 'has_page', label: 'Approve, except courses that have a page', input: 'courses', returns: 'The ticked courses keep looking for their page' },
        { key: 'reject', label: 'Reject', returns: 'Nothing is recorded' }] } }
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON(); calls.push(b)
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 1, universities: 1, late: 0, by_kind: { no_page_first_run: { n: 1 } } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p-waikato', name: 'University of Waikato', country: 'NZ', courses: 278, n: 1, oldest: '2026-10-25T14:37:00Z', late: false, by_kind: { no_page_first_run: 1 } }] } })
      if (b.p_action === 'items') return route.fulfill({ json: { total: 1, items: [
        { kind: 'no_page_first_run', ref: 'a534d26b', provider_id: 'p-waikato', subject: 'No page published: first run', why: 'No page published by the provider: check the sample once', created_at: '2026-10-25T14:37:00Z', late: false,
          detail: { field_code: 'no_page_first_run', before: { courses_proposed: 5 }, proposed: { sample: [
            { course_id: 'c-1', title: 'Bachelor of Social Work (Level 7)', code: 'WI0858' }, { course_id: 'c-2', title: 'Graduate Certificate in Education (Level 7)', code: 'WI0100' }] } } }] } })
      if (b.p_action === 'decide') return route.fulfill({ json: { ok: true, returns: 'The ticked courses keep looking for their page' } })
      return route.fulfill({ json: {} })
    })
    await page.goto('/#layer-4-review')
    await expect(page.locator('[data-l4-uni="University of Waikato"]')).toContainText('No page published: first run')
    const item = page.locator('[data-l4-item="no_page_first_run"]')
    await expect(item.locator('[data-l4-sample]')).toContainText('Bachelor of Social Work (Level 7) (WI0858)')
    await expect(item).toContainText('5 course(s) found no page')
    for (const c of ['approve', 'has_page', 'reject']) await expect(item.locator(`[data-l4-choice="${c}"]`)).toBeVisible()
    await item.locator('[data-l4-choice="has_page"]').click()
    await item.getByLabel('Reason').fill('Social Work is a rename (Defect 1); it has a page under its new name')
    await expect(item.locator('[data-l4-confirm]')).toBeDisabled()
    await item.locator('[data-l4-sample-tick="WI0858"]').check()
    await item.locator('[data-l4-confirm]').click()
    await expect(page.getByRole('status')).toContainText('Done.')
    const d = calls.find((c) => c.p_action === 'decide').p_args
    expect(d).toMatchObject({ kind: 'no_page_first_run', ref: 'a534d26b', choice: 'has_page' })
    expect(JSON.parse(d.value)).toEqual(['c-1'])
  })
})
