// Guards: Platform Admin 20 Nov 2026 14:40 (S1-UI-Parity, follow-up s839 after the signed-in check of v2.16.68): a course description card's Main hold
// reason is the rule's plain name in every view (never the machine code, for example "identity margin thin"), and Preview the batch opens in under
// 300 ms because the chosen rule's records are read as soon as the rule is chosen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { cdRailOf } from '../../src/lib/l4-rules.js'

test('s839: the plain rule name of a course description card, from its own hold code', () => {
  expect(cdRailOf({ detail: { machine: { reason_code: 'identity_margin_thin' } } })).toBe('Page match not clear enough')
  expect(cdRailOf({ detail: { machine: { reason_code: 'policy_refused_word' } } })).toBe('Contains a banned word')
  expect(cdRailOf({ detail: { machine: { reason_code: 'check_duplicate_other_course' } } })).toBe('Same wording as another course')
  expect(cdRailOf({ detail: { proposed: { held_rule: 'validation_first_sentence' } } })).toBe(null) // a university description keeps its own wording
  expect(cdRailOf({ detail: {} })).toBe(null)
  const EDIT = fs.readFileSync('src/DescriptionEditAdmit.jsx', 'utf8')
  expect(EDIT).toContain("const title=h.kind==='banned'?h.title:(label||cdRailOf(it)||h.title)")
  expect(fs.readFileSync('src/Layer4Focus.jsx', 'utf8')).toContain('useEffect(()=>{if(sel)batchRead(sel)},[key,g])')
})

const KINDS = { provider_description: { label: 'Course and university descriptions', order: 1, choices: [
  { key: 'approve', label: 'Approve as read', rank: 4, returns: 'x' }, { key: 'reject', label: 'Reject', rank: 4, returns: 'x' },
  { key: 'edit_approve', label: 'Save Edit & Admit', input: 'text', editor: true, rank: 4, returns: 'x' }] } }
const desc = (ref) => ({ kind: 'provider_description', ref, provider_id: 'p1', provider: 'Harbour University', subject: `Course ${ref}`, created_at: '2026-11-15T01:00:00Z',
  why: 'Machine rule cdesc-machine-v1 did not admit this: identity_margin_thin',
  detail: { field_code: 'provider_description', course_id: 'c1', proposed: { description: 'Harbour University teaches nursing in Sydney.', sentences: [] }, machine: { reason_code: 'identity_margin_thin' } } })

test.describe('mocked browser', () => {
  test('the card names the rule in plain English; the batch preview opens in under 300 ms after the rule is chosen', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1000 })
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON()
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 2, universities: 1, late: 0, by_kind: { provider_description: { n: 2 } } } })
      if (b.p_action === 'rule_groups') return route.fulfill({ json: { kind: 'provider_description', built_in: true, total: 2, batch_max: 50, ms: 9, groups: [{ key: 'cd:identity_margin_thin', n: 2, late: 0, refs: ['m1', 'm2'] }] } })
      if (b.p_action === 'rule_group_items') { await new Promise((r) => setTimeout(r, 700)); return route.fulfill({ json: { items: b.p_args.refs.map(desc), ms: 40 } }) }
      if (b.p_action === 'description_rules') return route.fulfill({ json: { provider: { words: [] }, course: { min_chars: 20, max_chars: 360, min_sentences: 1, max_sentences: 2, words: [] } } })
      return route.fulfill({ json: {} })
    })
    await page.goto('/#layer-4-review')
    await expect(page.locator('[data-l4-focus-card] [data-dea-hold]')).toContainText('Main hold reason: Page match not clear enough')
    await expect(page.locator('[data-l4-focus-card] [data-dea-hold] strong')).not.toContainText('identity margin thin')
    await page.locator('[data-l4-focus-group="cd:identity_margin_thin"]').click()
    await page.waitForTimeout(1200)                                                   // the rule's records are read while the reviewer reads
    await page.locator('[data-l4-batch-open]').click()
    const ms = Number((await page.locator('[data-l4-batch-timing]').textContent()).match(/shown in (\d+) ms/i)[1]) // s931: timings under Technical detail
    expect(ms).toBeLessThan(300)
  })
})
