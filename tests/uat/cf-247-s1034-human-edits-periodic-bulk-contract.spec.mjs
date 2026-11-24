// Guards: Platform Admin brief 24 Nov 2026 12:42 and HELD:LOCKS confirmation (24 Nov 05:55): Human Edits & Periodic Audit carries the Periodic Audit - Locked Field Update list with the bulk Yes (Approve & Keep Lock) and No (Reject) bar, up to 100 items and one reason of 8 characters or more, through public.admin_layer4_locked_update_bulk only (the bar itself is guarded by s1030); the existing Acknowledge and Re-Verify bulk actions stay.
import { test, expect } from '@playwright/test'
import { mockAdmin } from './support/admin-mock.mjs'

const ITEMS = [
  { kind: 'locked_field_update', ref: 'u1', provider_id: 'p1', provider: 'Monash University', subject: 'Bachelor of Law · Tuition 2027 AUD 41000', field: 'tuition', seen_count: 1 },
  { kind: 'locked_field_update', ref: 'u2', provider_id: 'p1', provider: 'Monash University', subject: 'Bachelor of Arts · Tuition 2027 AUD 36000', field: 'tuition', seen_count: 1 }]

test('the Periodic Audit list sits on Human Edits; select all ticks every shown item and the bulk call carries the reason', async ({ page }) => {
  const bulk = []
  await mockAdmin(page, { rank: 6 })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
    const b = route.request().postDataJSON()
    if (b.p_action === 'human_edits') return route.fulfill({ json: { items: [], counts: { open: 0, unacknowledged: 0, due: 0 }, total: 0 } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p1', name: 'Monash University', country: 'AU', n: 2, by_kind: { locked_field_update: 2 } }] } })
    if (b.p_action === 'items') return route.fulfill({ json: { total: 2, items: ITEMS } })
    return route.fulfill({ json: { total: 0, items: [] } })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_locked_update_bulk', async (route) => { const a = route.request().postDataJSON(); bulk.push(a); return route.fulfill({ json: { ok: true, decided: a.p_refs.length, asked: a.p_refs.length, items: a.p_refs.map((r) => ({ ref: r, ok: true })) } }) })
  await page.goto('/#human-edits-audit')
  await expect(page.locator('[data-he-periodic] [data-l4-locked-bulk]')).toBeVisible()
  await page.locator('[data-l4-locked-table] thead input[type=checkbox]').check()
  await expect(page.locator('[data-l4-locked-row] input:checked')).toHaveCount(2)
  await page.locator('[data-l4-locked-reason]').fill('Verified against the published 2027 fee schedule')
  await page.locator('[data-l4-locked-bar] [data-l4-choice="approve_keep_lock"]').click()
  await expect(page.locator('[data-l4-locked-note]')).toContainText('2 of 2 decided; the lock is kept')
  expect(bulk).toEqual([{ p_refs: ['u1', 'u2'], p_choice: 'approve_keep_lock', p_reason: 'Verified against the published 2027 fee schedule' }])
  await expect(page.locator('[data-he-act="ack"]')).toBeVisible()
})
