// Guards: Platform Admin HELD:LOCKS written confirmation (24 Nov 2026 05:55) and CF-247 s1023: Layer 4 › Grid › Periodic Audit - Locked Field Update decides many locked values at once with Yes (Approve & Keep Lock) or No (Reject), one audit reason of 8 characters or more for every item, at most 100 items, through public.admin_layer4_locked_update_bulk only; the screen writes no value and no lock.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { decisionsFor } from '../../src/lib/l4-rules.js'

test('the bar calls the bulk RPC only, writes nothing itself, and the single card names Yes (Approve & Keep Lock)', () => {
  const t = fs.readFileSync('src/Layer4LockedBulk.jsx', 'utf8')
  expect(t).toContain("rpc('admin_layer4_locked_update_bulk'")
  expect(t).not.toMatch(/\.from\(|manual_locks|\.insert\(|\.update\(/)
  const d = decisionsFor('locked_field_update', [{ key: 'approve_keep_lock' }, { key: 'reject' }])
  expect([d.yes.key, d.no.key, d.more.length]).toEqual(['approve_keep_lock', 'reject', 0])
  expect(fs.readFileSync('src/Layer4DecisionBar.jsx', 'utf8')).toContain('Yes (Approve & Keep Lock)')
})

const kinds = { locked_field_update: { label: 'Periodic Audit - Locked Field Update', order: 20, choices: [{ key: 'approve_keep_lock', label: 'Approve & Keep Lock' }, { key: 'reject', label: 'Reject' }] } }
const ITEMS = [
  { kind: 'locked_field_update', ref: 'u1', provider_id: 'p1', provider: 'Monash University', subject: 'Bachelor of Law · Tuition 2027 AUD 41000', field: 'tuition', seen_count: 2 },
  { kind: 'locked_field_update', ref: 'u2', provider_id: 'p1', provider: 'Monash University', subject: 'Bachelor of Law · Intake 2027-02-27', field: 'intakes', seen_count: 1 },
  { kind: 'locked_field_update', ref: 'u3', provider_id: 'p2', provider: 'RMIT University', subject: 'Master of IT · Tuition 2027 AUD 38000', field: 'tuition', seen_count: 1 }]

async function open(page, rank, bulk) {
  await mockAdmin(page, { rank })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
    const b = route.request().postDataJSON()
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank, total: 3, universities: 2, late: 0, by_kind: { locked_field_update: { n: 3 } } } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: 2, items: [{ provider_id: 'p1', name: 'Monash University', country: 'AU', n: 2, by_kind: { locked_field_update: 2 } }, { provider_id: 'p2', name: 'RMIT University', country: 'AU', n: 1, by_kind: { locked_field_update: 1 } }] } })
    if (b.p_action === 'items') { const pid = b.p_args?.provider_id; const items = ITEMS.filter((i) => !pid || i.provider_id === pid); return route.fulfill({ json: { total: items.length, items } }) }
    return route.fulfill({ json: { total: 0, items: [] } })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_saved_views_read_v1', (route) => route.fulfill({ json: { views: [], grid_kinds: ['locked_field_update'], can_edit_shared: true } }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_grid_read_v1', (route) => route.fulfill({ json: { total: 3, offset: 0, limit: 200, kind: 'locked_field_update', sort: 'oldest', export: false, kind_label: kinds.locked_field_update.label, rank, rows: ITEMS.map((i) => ({ ...i, country: 'AU', why: 'x', created_at: '2026-11-20T00:00:00Z', age_days: 4 })) } }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_locked_update_bulk', async (route) => { bulk.push(route.request().postDataJSON()); const a = route.request().postDataJSON(); return route.fulfill({ json: { ok: true, choice: a.p_choice, decided: a.p_refs.length, asked: a.p_refs.length, items: a.p_refs.map((r) => ({ ref: r, ok: true })) } }) })
  await page.goto('/#layer-4-review?view=grid')
  await expect(page.locator('[data-l4g-grid]')).toBeVisible()
  await page.locator('[data-l4g-kind]').selectOption('locked_field_update')
  await expect(page.locator('[data-l4-locked-bulk]')).toBeVisible()
}

test('filter by Tuition fee and university, tick, give a reason, and Yes (Approve & Keep Lock) sends exactly those refs with the reason', async ({ page }) => {
  const bulk = []; await open(page, 6, bulk)
  await expect(page.locator('[data-l4-locked-row]')).toHaveCount(3)
  await page.locator('[data-l4-locked-field]').selectOption('tuition')
  await page.locator('[data-l4-locked-university]').selectOption('p1')
  await expect(page.locator('[data-l4-locked-row]')).toHaveCount(1)
  const yes = page.locator('[data-l4-locked-bar] [data-l4-choice="approve_keep_lock"]')
  await expect(yes).toBeDisabled()
  await page.locator('[data-l4-locked-row="u1"] input').check()
  await page.locator('[data-l4-locked-reason]').fill('short')
  await expect(yes).toBeDisabled()
  await page.locator('[data-l4-locked-reason]').fill('Checked against the 2027 fee schedule')
  await expect(yes).toHaveText('Yes (Approve & Keep Lock)')
  await yes.click()
  await expect(page.locator('[data-l4-locked-note]')).toContainText('1 of 1 decided; the lock is kept')
  expect(bulk).toEqual([{ p_refs: ['u1'], p_choice: 'approve_keep_lock', p_reason: 'Checked against the 2027 fee schedule' }])
})

test('the buttons are off below Curator rank (the server refuses it as well) and the reason needs 8 characters', () => {
  const t = fs.readFileSync('src/Layer4LockedBulk.jsx', 'utf8')
  expect(t).toContain('Number(rank)>=3')
  expect(t).toContain('MIN_REASON=8')
  expect(t).toContain('Curator rank or higher is needed')
})
