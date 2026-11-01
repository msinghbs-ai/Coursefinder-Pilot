// Guards: StudySearch usability remediation UR-05 and UR-06 (Platform Admin mandate 1 Nov 2026 11:48, Tranche B; admin record §36): every Layer 4 card shows its stable reference, the stored copy behind it (capture date, newer copy) and its course record, and a decision reports what actually happened at the destination (admitted, applied, reconciled, downstream, deferred or saved but not yet visible) with its decision and audit identifiers, never only that the card left the list.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const m = fs.readFileSync('supabase/migrations/20261101060000_cf247_ur05_06_l4_evidence_outcome.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('migration: md5-guarded edits; stored copy on review items; outcome read back from the destination; nothing dropped', () => {
  expect(m).toContain("select pg_temp.edit_once('security.layer4_inbox_items_v1()', '3f2b49d511ff60b7b00b69c702c7b615', 'c1a133c3260c3c160397151bd0664957', array[")
  expect(m).toContain("select pg_temp.edit_once('public.admin_layer4_inbox(text,jsonb)', '48a52717d398c14de6920f18667068a0', 'c6b83e211ba5172d16a5b3b7e7399ef5', array[")
  expect(m).toContain("'evidence_id', r.evidence_id, 'captured_at', ev.captured_at, 'source_url', ev.source_url,")
  expect(m).toContain('v_aer := public.layer4_aer_review_read((p_result->>\'review_item_id\')::uuid);')
  expect(m).toContain("and lower(rtrim(l.url, '/')) = lower(rtrim(v_url, '/')));")
  expect(m).toContain("'ref', v_ref, 'event_id', v_event,")
  expect(m).toContain("'outcome', security.layer4_decision_outcome_v1(v_kind, v_choice, v_r));")
  expect(m).toContain('revoke all on function security.layer4_decision_outcome_v1(text, text, jsonb) from public, anon, authenticated;')
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(code(m)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|function\s+api\./)
})

test.describe('mocked browser', () => {
  test('a course-link card shows its reference, stored copy and record; the decision reports the verified outcome and audit id', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    const kinds = { course_link: { label: 'Course link', order: 1, choices: [{ key: 'use', label: 'Use the new page', returns: 'The new page becomes the course page' }, { key: 'keep', label: 'Keep the page we hold', returns: 'Nothing changes' }] } }
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON(); calls.push(b)
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 1, universities: 1, late: 0, by_kind: { course_link: { n: 1 } } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 0, items: [] } })
      if (b.p_action === 'items') return route.fulfill({ json: { total: 1, before: 0, items: [{ kind: 'course_link', ref: '841f56b5-5278-4467-8539-50e6e4152a9e', o: 1, provider_id: 'p1', provider: 'University of Waikato',
        subject: 'Certificate of Attainment in English Language', why: 'Two pages', created_at: '2026-10-20T00:00:00Z', late: true,
        detail: { field_code: 'official_course_url', course_id: 'c-1', course_code: 'WI0194', before: ['https://www.waikato.ac.nz/int/study/x/'], proposed: { course_url: 'https://www.waikato.ac.nz/study/x/' },
          evidence_id: 'e-1', captured_at: '2026-10-19T03:00:00Z', source_url: 'https://www.waikato.ac.nz/study/x/', newer_copy: true } }] } })
      if (b.p_action === 'decide') return route.fulfill({ json: { ok: true, ref: '841f56b5-5278-4467-8539-50e6e4152a9e', event_id: 27999, returns: 'The new page becomes the course page',
        outcome: { class: 'pending_check', verified: false, value: 'https://www.waikato.ac.nz/study/x/', decision_id: '202e4319-9162-4678-8ea0-165e0feb1130' } } })
      return route.fulfill({ json: {} })
    })
    await page.goto('/#layer-4-review?view=kind&kind=course_link')
    const card = page.locator('[data-l4-ref="841f56b5-5278-4467-8539-50e6e4152a9e"]')
    await expect(card.locator('[data-l4-refshow]')).toHaveText('Ref 841f56b5')
    await expect(card.locator('[data-l4-evidence-link]')).toHaveAttribute('href', /evidence/)
    await expect(card.locator('[data-l4-evidence]')).toContainText('captured')
    await expect(card.locator('[data-l4-newer]')).toContainText('a newer copy of this page exists')
    await expect(card.locator('[data-l4-open-record]')).toHaveAttribute('href', /c-1/)
    await card.locator('[data-l4-choice="use"]').click()
    await card.getByLabel('Reason').fill('Canonical page carries the CRICOS code')
    await card.locator('[data-l4-confirm]').click()
    const status = page.getByRole('status')
    await expect(status).toContainText('Done. Saved, but the destination does not show it yet')
    await expect(status).toContainText('not yet the course\'s link: https://www.waikato.ac.nz/study/x/')
    await expect(status).toContainText('decision 202e4319')
    await expect(status).toContainText('audit #27999')
  })
})
