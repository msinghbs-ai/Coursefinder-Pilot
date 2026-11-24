// Guards: Platform Admin brief 24 Nov 2026 15:11 (UI-UX plan v1.2 Slice A; backend s1025): standard Layer 4 queues decide several rows at once (Approve Selected with one 8+ character reason, each card decided through the Inbox's own decision); Counsellor feedback (in app) is triaged with Fixed or Not changed and a closing note; the Counsellor reports an issue from the course drawer and follows it under My reports; Acknowledge and Re-Verify carry an optional audit reason.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { decisionsFor, settleChoices, L4_QUEUES } from '../../src/lib/l4-rules.js'

const FB = [{ key: 'fixed', label: 'Fixed', rank: 3, reason: true }, { key: 'not_changed', label: 'Not changed', rank: 3, reason: true }, { key: 'course', label: 'Open the course', link: 'course', rank: 3 }]
const kinds = { counsellor_feedback: { label: 'Counsellor feedback (in app)', order: 11, choices: FB } }
const ROWS = [1, 2, 3].map(n => ({ kind: 'counsellor_feedback', ref: `f${n}`, provider_id: 'p1', provider: 'Monash University', subject: `Course ${n} · Fee`, why: `Fee looks wrong ${n}. More text.`, country: 'AU', created_at: '2026-11-20T00:00:00Z', age_days: 4 }))

test('rules: the feedback kind has Fixed as Yes and Not changed as No; one batch may settle both; the 19 built-in queues are unchanged', () => {
  const d = decisionsFor('counsellor_feedback', FB)
  expect(d.yes?.key).toBe('fixed'); expect(d.no?.key).toBe('not_changed'); expect(d.more.map(c => c.key)).toEqual(['course'])
  expect(settleChoices('counsellor_feedback', FB).map(c => c.key)).toEqual(['fixed', 'not_changed'])
  expect(L4_QUEUES.length).toBe(19)
})

test('source: the standard bulk bar decides through the Inbox decision only; the counsellor screens use only the two s1025 RPCs', () => {
  const bulk = fs.readFileSync('src/Layer4StandardBulk.jsx', 'utf8'), fb = fs.readFileSync('src/ui-v1/FeedbackReport.jsx', 'utf8')
  expect(bulk).toContain("supabase.rpc('admin_layer4_inbox',{p_action:'decide'")
  expect(fb).toContain("counsellor_feedback_submit_v1"); expect(fb).toContain("counsellor_feedback_list_v1")
  expect(fb.split('\n').filter(l => !l.trim().startsWith('//')).join('\n')).not.toMatch(/admin_|data_flags|zoho/i)
})

test.describe('mocked browser', () => {
  test('Layer 4 Grid: tick rows, one reason, Approve Selected decides each with the reason; Reject Selected is the second decision', async ({ page }) => {
    const decided = []
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async route => {
      const b = route.request().postDataJSON()
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 3, universities: 1, late: 0, by_kind: { counsellor_feedback: { n: 3 } } } })
      if (b.p_action === 'decide') { decided.push(b.p_args); return route.fulfill({ json: { ok: true } }) }
      return route.fulfill({ json: { total: 0, items: [] } })
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_saved_views_read_v1', r => r.fulfill({ json: { views: [], grid_kinds: ['counsellor_feedback'], can_edit_shared: true } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_grid_read_v1', r => r.fulfill({ json: { total: 3, offset: 0, limit: 50, kind: 'counsellor_feedback', sort: 'oldest', export: false, kind_label: kinds.counsellor_feedback.label, rank: 6, rows: ROWS } }))
    await page.goto('/#layer-4-review?view=grid')
    await page.locator('[data-l4g-kind]').selectOption('counsellor_feedback')
    const bulk = page.locator('[data-l4-bulk]')
    await expect(bulk).toBeVisible()
    await bulk.locator('summary').click()
    await expect(bulk.locator('[data-l4-bulk-row]')).toHaveCount(3)
    const approve = bulk.locator('[data-l4-bulk-approve]')
    await expect(approve).toBeDisabled()
    await bulk.locator('thead input[type=checkbox]').check()
    await bulk.locator('[data-l4-bulk-reason]').fill('short')
    await expect(approve).toBeDisabled()                       // a reason of 8 or more characters is needed
    await bulk.locator('[data-l4-bulk-reason]').fill('Corrected on the course page')
    await expect(approve).toContainText('Approve Selected (3)')
    await approve.click()
    await expect(page.locator('[data-l4-bulk-note]')).toContainText('3 of 3 decided')
    expect(decided).toEqual(['f1', 'f2', 'f3'].map(ref => ({ kind: 'counsellor_feedback', ref, choice: 'fixed', reason: 'Corrected on the course page', value: '' })))
    await expect(bulk.locator('[data-l4-bulk-reject]')).toBeVisible()
  })

  test('Human Edits: Acknowledge and Re-Verify carry an optional audit reason only when one is written', async ({ page }) => {
    const calls = []
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async route => {
      const b = route.request().postDataJSON()
      if (b.p_action === 'human_edits') return route.fulfill({ json: { items: [{ id: 'h1', entity_type: 'course', subject: 'Course A', status: 'pending_ack', edited: 'Text', current: 'Text' }], counts: { open: 1, unacknowledged: 1, due: 0 }, total: 1 } })
      if (b.p_action === 'human_edits_ack') { calls.push(b.p_args); return route.fulfill({ json: { rows: 1 } }) }
      return route.fulfill({ json: { total: 0, items: [] } })
    })
    await page.goto('/#human-edits-audit')
    await page.locator('[data-he-audit-reason]').waitFor()
    await page.locator('tbody input[type=checkbox]').first().check()
    await page.locator('[data-he-act="ack"]').click()
    await expect.poll(() => calls.length).toBe(1)
    expect(calls[0]).toEqual({ ids: ['h1'] })
    await page.locator('tbody input[type=checkbox]').first().check()
    await page.locator('[data-he-audit-reason]').fill('Checked against the course page')
    await page.locator('[data-he-act="ack"]').click()
    await expect.poll(() => calls.length).toBe(2)
    expect(calls[1]).toEqual({ ids: ['h1'], reason: 'Checked against the course page' })
  })
})

const CATS = [{ key: 'wrong_fee', label: 'Fee is wrong' }, { key: 'wrong_intake', label: 'Intake is wrong' }]
async function counsellor(page, sent, listed) {
  await mockAdmin(page, { rank: 2, role: 'counsellor' })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    const b = route.request().postDataJSON() || {}
    const op = b.p_operation || b.operation
    if (op === 'courses_page') return route.fulfill({ json: { total: 1, limit: 50, offset: 0, items: [{ id: 'c1', display_title: 'Bachelor of Commerce', provider_name: 'Test University', level_name: 'Bachelor', fee_amount: 30000, fee_currency: 'AUD', field_states: {} }] } })
    if (op === 'course_detail') return route.fulfill({ json: { course_url: 'https://test.edu.au/commerce', campuses: [], fees: [{ amount: 30000, currency: 'AUD', basis: 'annual', year: 2027 }], intakes: [] } })
    return route.fallback()
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/counsellor_feedback_list_v1', async route => { const a = route.request().postDataJSON().p_args; listed.push(a); return route.fulfill({ json: { scope: 'mine', can_triage: false, total: 1, categories: CATS, items: a.limit === 1 ? [] : [{ id: 'r1', created_at: '2026-11-24T01:00:00Z', mine: true, course: 'Bachelor of Commerce', provider: 'Test University', issue_categories: ['wrong_fee'], notes: 'Fee is 31000 on the page', status: 'fixed', triage_note: 'Corrected, thanks', triaged_at: '2026-11-24T05:00:00Z' }] } }) })
  await page.route('https://example.supabase.co/rest/v1/rpc/counsellor_feedback_submit_v1', async route => { sent.push(route.request().postDataJSON().p_args); return route.fulfill({ json: { ok: true, id: 'r2', status: 'open' } }) })
}

test('Counsellor: Report a data issue from the course drawer sends the choice, note, https page and what the screen showed; My reports lists it with the closing note', async ({ page }) => {
  const sent = [], listed = []
  await counsellor(page, sent, listed)
  await page.goto('/#ui-v1/courses')
  await page.getByText('Bachelor of Commerce').first().click()
  await page.locator('[data-report-open]').click()
  const form = page.locator('[data-report-issue]')
  await expect(form.locator('[data-report-categories] input')).toHaveCount(2)
  await expect(form.locator('[data-report-send]')).toBeDisabled()
  await form.getByLabel('Fee is wrong').check()
  await form.getByLabel('Note').fill('The page says 31000')
  await form.locator('[data-report-send]').click()
  await expect(form.locator('[data-report-done]')).toBeVisible()
  expect(sent[0]).toMatchObject({ course_id: 'c1', issue_categories: ['wrong_fee'], notes: 'The page says 31000', source_url: 'https://test.edu.au/commerce' })
  expect(sent[0].displayed_snapshot.title).toBe('Bachelor of Commerce')
  await form.getByRole('link', { name: 'Open My reports' }).click()
  await expect(page.locator('[data-my-reports] [data-report="r1"]')).toContainText('Fee is wrong')
  await expect(page.locator('[data-report-triage]')).toContainText('Corrected, thanks')
  await page.locator('[data-report-filter="open"]').click()
  await expect.poll(() => listed.at(-1)).toMatchObject({ scope: 'mine', status: 'open' })
})

test('phone @responsive: the report form and My reports fit the phone', async ({ page }) => {
  expect(page.viewportSize()?.width || 9999).toBeLessThanOrEqual(480)
  const sent = [], listed = []
  await counsellor(page, sent, listed)
  await page.goto('/#ui-v1/courses')
  await page.getByText('Bachelor of Commerce').first().click()
  await page.locator('[data-report-open]').click()
  const w = page.viewportSize().width
  await expect.poll(async () => { const b = await page.locator('[data-report-issue]').boundingBox(); return b.x >= 0 && b.x + b.width <= w }).toBe(true)
  await page.goto('/#ui-v1/reports')
  await expect(page.locator('[data-my-reports]')).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
})
