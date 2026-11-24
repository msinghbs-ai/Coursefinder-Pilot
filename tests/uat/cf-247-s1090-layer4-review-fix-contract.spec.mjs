// Guards: Layer 4 Review fixes (Platform Admin 24 Nov 2026 22:35): one University filter that follows the whole screen, no engineering log under the group buttons,
// no endless Loading beside "Nothing waits", the held-reason table follows the filters and names every reason (no "Other"), and the two reasons a person decides on
// list open with a bulk bar. Mocked admin here; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = (f) => fs.readFileSync(f, 'utf8')
const MIG = read('supabase/migrations/20261125210000_cf247_s1090_l4_hold_reasons_filter.sql')

test('migration: the hold reasons take provider_id and country, and no code is folded into "Other"', () => {
  expect(MIG).toContain("v_provider uuid := nullif(btrim(coalesce(p_args->>'provider_id', '')), '')::uuid;")
  expect(MIG).toContain("v_country text := nullif(upper(btrim(coalesce(p_args->>'country', ''))), '');")
  expect(MIG).toContain("else coalesce(nullif(btrim(l.reason_code), ''), 'other') end,")
  expect(MIG).toContain("when 'active_rows_exist' then 'Course already has active entry requirements")
  expect(MIG).toContain('co.iso_alpha2 = v_country')
  expect(MIG).toMatch(/-- Replaces:[^\n]*layer4_aer_hold_base_v1/)
  expect(MIG).not.toMatch(/\bdrop\s+(table|function)|\bdelete\s+from|\btruncate\b/i)
})

test('source: one University box, no engineering log, a bulk bar through the Inbox decide action', () => {
  expect(read('src/Layer4AdvancedFilters.jsx')).not.toContain('University list')
  expect(read('src/Layer4Groups.jsx')).not.toMatch(/data-l4-grouped-at|Settled by existing rules|Grouped \$\{/)
  const h = read('src/Layer4HoldReasons.jsx')
  for (const s of ["p_action:'decide'", 'data-l4-hold-bulk', 'Approve Selected', 'providerId', 'country', 'ACTIONABLE']) expect(h, s).toContain(s)
  expect(h).not.toMatch(/Other \(/)
  const i = read('src/Layer4Inbox.jsx')
  expect(i).toContain('data-l4-items-error')
  expect(i).toContain("providerId={scope?.provider_id||''} country={dest}")
  expect(i).not.toContain('Page: <q>')
})

const KINDS = { aer_review: { label: 'Entry requirements (AER)', order: 17, detail: false, choices: [{ key: 'approve', label: 'Approve all rows', rank: 6, returns: 'Active' }, { key: 'reject', label: 'Reject the read', rank: 6, returns: 'Withdrawn' }] } }
const UNI = { provider_id: 'p1', name: 'UNSW Sydney', country: 'AU', n: 3, oldest: '2026-10-19T00:00:00Z', late: false, by_kind: { aer_review: 3 } }
const REASONS = (f) => f.provider_id
  ? { total: 3, as_at: '2026-11-24T10:00:00Z', reasons: [{ code: 'matrix_change', n: 2, label: 'Provider matrix, change of an admitted table' }, { code: 'active_rows_exist', n: 1, label: 'Course already has active entry requirements (replacing them is a person\'s decision)' }] }
  : { total: 639, as_at: '2026-11-24T10:00:00Z', reasons: [{ code: 'active_rows_exist', n: 386, label: 'Course already has active entry requirements (replacing them is a person\'s decision)' }, { code: 'matrix_first_run', n: 65, label: 'Provider matrix, first run' }, { code: 'matrix_change', n: 13, label: 'Provider matrix, change of an admitted table' }, { code: 'all_rows_held', n: 175, label: 'All rows held (every row fails a row rule)' }] }
const ITEMS = { matrix_change: [{ id: 'm1', course: 'University-wide entry table', provider: 'UNSW Sydney', country: 'AU', checked_at: null, why: 'A long reason text about the admitted table' }, { id: 'm2', course: 'University-wide entry table 2', provider: 'UNSW Sydney', country: 'AU', checked_at: null, why: '' }],
  matrix_first_run: [{ id: 'f1', course: 'First table', provider: 'Monash University', country: 'AU', checked_at: null, why: '' }] }

async function mocks(page, { unis = [UNI], calls = [], decisions = [] } = {}) {
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
    const b = route.request().postDataJSON(); const a = b.p_args || {}
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 639, universities: 20, late: 4, by_kind: { aer_review: { n: 639 } }, paging: { items: 25, universities: 25, detail_parallel: 2 } } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: unis.length, items: unis } })
    if (b.p_action === 'items') return route.fulfill({ json: { total: 0, before: 0, more: false, items: [] } })
    if (b.p_action === 'decide') { decisions.push(a); return route.fulfill({ json: { ok: true, returns: 'Done', event_id: 1 } }) }
    return route.fulfill({ json: {} })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_aer_queue', async (route) => {
    const a = route.request().postDataJSON().p_args || {}; calls.push(a)
    if (a.hold_reasons && a.reason) return route.fulfill({ json: { reason: a.reason, total: (ITEMS[a.reason] || []).length, items: ITEMS[a.reason] || [] } })
    if (a.hold_reasons) return route.fulfill({ json: REASONS(a) })
    return route.fulfill({ json: { pending: 0, review_ready: 0 } })
  })
}

test.describe('mocked browser', () => {
  test('no university waits: the right pane says so (never an endless Loading) and names the queue', async ({ page }) => {
    await mockAdmin(page, { rank: 6 }); await mocks(page, { unis: [] })
    await page.goto('/#layer-4-review?view=university')
    await expect(page.locator('[data-l4-inbox]')).toBeVisible()
    await expect(page.locator('.l4i-unis')).toContainText('Nothing waits for a person.')
    await expect(page.locator('.l4i-items')).toContainText('Nothing waits for a person.')
    await expect(page.locator('.l4i-items')).not.toContainText('Loading')
    await expect(page.locator('[data-l4-grouped-at], [data-l4-group-a]')).toHaveCount(0)
    await page.getByRole('button', { name: /Advanced filters/ }).click()
    await expect(page.locator('[data-l4-advanced-panel]')).not.toContainText('University list')
    await expect(page.locator('[data-l4-uni-search]')).toHaveCount(1)
  })

  test('held reasons follow the University filter, name every reason, list the two decision reasons open with a bulk bar that decides each item on its own', async ({ page }) => {
    const calls = [], decisions = []
    await mockAdmin(page, { rank: 6 }); await mocks(page, { calls, decisions })
    await page.goto('/#layer-4-review?kind=aer_review&view=kind')
    const hold = page.locator('[data-l4-hold-reasons]')
    await expect(hold).toContainText('Why items are held (639 pending)')
    await expect(hold).not.toContainText('Other')
    await expect(hold).toContainText('Course already has active entry requirements')
    // the two reasons a person decides on are open at once, with tick boxes and the bar
    await expect(page.locator('[data-l4-hold-list="matrix_change"] [data-l4-hold-item]')).toHaveCount(2)
    await expect(page.locator('[data-l4-hold-list="matrix_first_run"] [data-l4-hold-item]')).toHaveCount(1)
    await expect(page.locator('[data-l4-hold-bulk]')).toBeVisible()
    await expect(page.locator('[data-l4-hold-list="matrix_change"] details')).not.toHaveAttribute('open', '')
    // the one University box filters the counts and the lists
    await page.locator('[data-l4-uni-search]').fill('uns')
    await page.locator('[data-l4-uni-pick="p1"]').click()
    await expect(hold).toContainText('Why items are held (3 pending, for the filters chosen)')
    expect(calls.some((c) => c.hold_reasons && c.provider_id === 'p1')).toBe(true)
    await expect(page.locator('[data-l4-hold-list="matrix_first_run"]')).toHaveCount(0)
    await expect(page.locator('.l4i-tiles')).toContainText('Waiting at UNSW Sydney')
    // bulk: tick both, a short reason keeps the button off, then each item is decided on its own
    await page.locator('[data-l4-hold-tick-all="matrix_change"]').check()
    await expect(page.locator('[data-l4-bulk-approve]')).toBeDisabled()
    await page.locator('[data-l4-bulk-reason]').fill('Checked against the stored page')
    await expect(page.locator('[data-l4-bulk-approve]')).toContainText('Approve Selected (2)')
    await page.locator('[data-l4-bulk-approve]').click()
    await expect(page.locator('[data-l4-bulk-note]')).toContainText('2 of 2 decided')
    expect(decisions.map((d) => [d.kind, d.ref, d.choice, d.reason])).toEqual([['aer_review', 'm1', 'approve', 'Checked against the stored page'], ['aer_review', 'm2', 'approve', 'Checked against the stored page']])
  })
})
