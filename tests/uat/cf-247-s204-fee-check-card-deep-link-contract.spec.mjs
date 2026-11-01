// Guards: SS-016 usability remediation, Platform Admin direction 1 Nov 2026 13:52 priorities 1 and 2 (admin record §37): a Layer 4 fee-check card shows the exact proposed fee (amount, currency, basis, fee year) and is admitted or not admitted, never sent an address (an address admitted the proposed fee, 46 decisions on 30 Oct); an admitted fee is read back from the course's fees; an address naming another Layer 4 kind on the same screen opens that kind without a reload (UR-09).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const m = fs.readFileSync('supabase/migrations/20261101080000_cf247_ur05_fee_check_card.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('migration: md5-guarded edits; an address on a fee check is refused; a fee decision is read back from course_fees; nothing dropped', () => {
  expect(m).toContain("select pg_temp.edit_once('public.admin_layer4_inbox(text,jsonb)', 'c6b83e211ba5172d16a5b3b7e7399ef5', '417f181d12155f79f68c1e70c27a1892', array[")
  expect(m).toContain("select pg_temp.edit_once('security.layer4_decision_outcome_v1(text,text,jsonb)', 'eae00e61a7785c46f1f570991577ede0', 'c40ee758b2d5888deeb5a101fd036cb6', array[")
  expect(m).toContain("if v_kind = 'course_link' and v_det->>'field_code' = 'provider_current_tuition_validation' and v_choice = 'enter' then")
  expect(m).toContain("where f.notes like 'CF-247 Layer 4 human decision; review item ' || (p_result->>'review_item_id') || ';%' and f.status = 'active'")
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(code(m)).not.toMatch(/^\s*(drop|delete|truncate|update)\b/im)
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|function\s+api\./)
})

const KINDS = {
  course_link: { label: 'Course link', order: 1, choices: [{ key: 'keep', label: 'Keep the page we hold', returns: 'Closed' }, { key: 'use', label: 'Use the new page', returns: 'The new page becomes the course page' }, { key: 'enter', label: 'Enter another address', input: 'url', returns: 'Read again' }] },
  central_page: { label: 'Central page', order: 2, choices: [{ key: 'approve', label: 'Approve', returns: 'Applied' }] },
}
const feeItem = { kind: 'course_link', ref: '9cdf0703-dd18-46ef-9241-e98c3049c5d6', o: 1, provider_id: 'p1', provider: 'College of the North Atlantic', subject: 'Culinary Management',
  why: 'Fee reader: course match not sure enough', created_at: '2026-10-27T00:00:00Z',
  detail: { field_code: 'provider_current_tuition_validation', course_id: 'c-9', course_code: '3A7', before: {}, proposed: { basis: 'indicative_annual', amount: 9370, audience: 'international', fee_year: 2026, currency_code: 'CAD' },
    evidence_id: 'e-9', captured_at: '2026-10-27T03:00:00Z', source_url: 'https://www.cna.nl.ca/program/culinary-management', newer_copy: false } }
const centralItem = { kind: 'central_page', ref: 'c3a1', o: 2, provider_id: 'p2', provider: 'Niagara College', subject: 'Calendar', why: 'Approve the central page', created_at: '2026-10-23T00:00:00Z', detail: {} }

async function route(page, calls, decide) {
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (r) => {
    const b = r.request().postDataJSON(); calls.push(b)
    if (b.p_action === 'summary') return r.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 2, universities: 2, late: 0, by_kind: { course_link: { n: 1 }, central_page: { n: 1 } } } })
    if (b.p_action === 'universities') return r.fulfill({ json: { total: 0, items: [] } })
    if (b.p_action === 'items') return r.fulfill({ json: { total: 1, before: 0, items: [b.p_args.kind === 'central_page' ? centralItem : feeItem] } })
    if (b.p_action === 'decide') return r.fulfill({ json: decide })
    return r.fulfill({ json: {} })
  })
}

test.describe('mocked browser', () => {
  test('a fee-check card shows the proposed fee, offers Admit or Do not admit (no address), and reports the admitted fee', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    const calls = []
    await route(page, calls, { ok: true, ref: feeItem.ref, event_id: 27700, returns: 'x',
      outcome: { class: 'admitted', verified: true, decision_id: 'd1e2f3a4-0000-0000-0000-000000000000', destination: 'course_fees', fee: { amount: 9370, currency: 'CAD', fee_year: 2026, basis: 'indicative_annual' } } })
    await page.goto('/#layer-4-review?view=kind&kind=course_link')
    const card = page.locator(`[data-l4-ref="${feeItem.ref}"]`)
    await expect(card.locator('[data-l4-fee-proposed]')).toHaveText('CAD 9,370 · a year (indicative) · fee year 2026 · international')
    await expect(card.locator('[data-l4-choice="use"]')).toHaveText('Admit this fee')
    await expect(card.locator('[data-l4-choice="keep"]')).toHaveText('Do not admit this fee')
    await expect(card.locator('[data-l4-choice="enter"]')).toHaveCount(0)
    await expect(card.locator('[data-l4-held]')).toHaveCount(0)
    await card.locator('[data-l4-choice="use"]').click()
    await expect(card).toContainText('The proposed fee becomes the course\'s international tuition fee')
    await card.getByLabel('Reason').fill('Stored copy shows CAD 4,685 per 15-week term for 2026-27')
    await card.locator('[data-l4-confirm]').click()
    const status = page.getByRole('status')
    await expect(status).toContainText('Done. Admitted · fee CAD 9,370 · a year (indicative) · fee year 2026')
    await expect(status).toContainText('audit #27700')
    expect(calls.find((c) => c.p_action === 'decide').p_args).toMatchObject({ kind: 'course_link', ref: feeItem.ref, choice: 'use' })
  })

  test('an address naming another kind on the same screen opens that kind without a reload (UR-09)', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    const calls = []
    await route(page, calls, {})
    await page.goto('/#layer-4-review?view=kind&kind=course_link')
    await expect(page.locator('[data-l4-kind="course_link"]')).toHaveClass(/on/)
    await expect(page.locator(`[data-l4-ref="${feeItem.ref}"]`)).toBeVisible()
    await page.evaluate(() => { window.location.hash = '#layer-4-review?view=kind&kind=central_page' })
    await expect(page.locator('[data-l4-kind="central_page"]')).toHaveClass(/on/)
    await expect(page.locator('[data-l4-ref="c3a1"]')).toBeVisible()
    await expect(page.locator(`[data-l4-ref="${feeItem.ref}"]`)).toHaveCount(0)
    expect(calls.filter((c) => c.p_action === 'items').at(-1).p_args.kind).toBe('central_page')
  })
})
