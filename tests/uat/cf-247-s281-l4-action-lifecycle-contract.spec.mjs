// Guards: Platform Admin decision 4 Nov 2026 12:24 (Layer 4 usability, action lifecycle and audit review; IQ-00279 RMIT Diploma of Commerce): every Layer 4 action has a traceable, durable outcome; §3 timestamps in Australian time; no deterministic repeat of a refused read
// Migration 20261104540000; audit matrix admin docs/platform/ui-audit/2026-11-04-layer4-kind-audit-matrix.md. The lifecycle, the
// acknowledgement and the repeat guard are proved on PostgreSQL 16 by tests/fixtures/l4-action-lifecycle (C1-C10: the RMIT E13 case, accepted
// but incomplete, refused, duplicate, successful corrected read, superseded, role-disabled, admission and publication, re-entry, Refresh during
// an asynchronous read). Mocked admin here; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const m = fs.readFileSync('supabase/migrations/20261104540000_cf247_l4_action_lifecycle.sql', 'utf8')
const fx = fs.readFileSync('tests/fixtures/l4-action-lifecycle/fixtures.sql', 'utf8')
const ui = fs.readFileSync('src/Layer4ItemLifecycle.jsx', 'utf8')
const inbox = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
const fn = (name) => { const i = m.indexOf(`create or replace function ${name}(`); return m.slice(i, m.indexOf('$function$;', i)) }

test('guarded edits: the recovery detail and decision (owned by this change) and the two Inbox replies only', () => {
  expect(m).toContain("select pg_temp.guard('security.layer4_aer_recovery_detail_v1(text)', '636c1764788b008fb7456365d600b452',")
  expect(m).toContain("select pg_temp.guard('security.layer4_aer_recovery_decide_v1(text,text,text,text)', '841234cb4826983b3297d39a34cb0978',")
  expect(m).toContain("select pg_temp.guard('public.admin_layer4_inbox(text,jsonb)', '29705b99108e7a0b4d68fea398565d36',")
  expect(m).toContain("raise exception 'public.admin_layer4_inbox: the two decision replies were not found once each'")
  for (const f of ['layer4_inbox_items_v2', 'layer4_aer_recovery_state_v1', 'course_entry_gate_v1', 'layer4_review_decide_impl', 'layer4_intervention_inbox_decide_v1', 'layer4_aer_review_detail_v1'])
    expect(m).not.toMatch(new RegExp(`create or replace function [a-z]+\\.${f}\\(`))
  expect(m).toMatch(/^-- Replaces: security\.layer4_aer_recovery_detail_v1\(text\) and security\.layer4_aer_recovery_decide_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  // no second Layer 4 system: no new table
  expect(m).not.toMatch(/create table/i)
})

test('a refused corrected read of an unchanged stored copy is neither recommended, allowed nor run again', () => {
  const rep = fn('security.layer4_reread_repeat_v1')
  expect(rep).toContain("v_rep := s.state = 'refused' and not v_transient and v_used is not distinct from coalesce(v_now, v_used) and jsonb_array_length(v_changed) = 0;")
  expect(rep).toContain("w.key = 'layer4.reread_change_keys'")
  const det = fn('security.layer4_aer_recovery_detail_v1')
  expect(det).toContain("when v_repeat then 'open_intervention'")
  expect(det).toContain("'allowed', v_busy is null and not (st->>'complete')::boolean and not v_repeat")
  const dec = fn('security.layer4_aer_recovery_decide_v1')
  expect(dec).toContain("v_req := 'Not read again: ' || (v_rep->>'why') || '. Instead: ' || (v_rep->>'alternative') || '.';")
  expect(dec).toContain("v_req := 'Already requested: recovery action ' || a.id")
  expect(fx).toContain('C1 ok: RMIT')
  expect(fx).toContain("raise exception 'C1: a read was started'")
})

test('every Inbox decision replies with a normalised acknowledgement built after the server has acted', () => {
  expect(m).toContain('return security.layer4_action_ack_v1(v_kind, v_ref, jsonb_build_object(\'ok\', true,')
  expect(m).toContain('return security.layer4_action_ack_v1(v_kind, v_ref, jsonb_build_object(\'ok\', coalesce((v_r->>\'ok\')::boolean, false),')
  const norm = fn('security.layer4_ack_normalise_v1')
  for (const o of ['accepted', 'refused', 'queued', 'already_requested', 'completed', 'incomplete', 'human_input']) expect(norm).toContain(`'${o}'`)
  expect(fn('security.layer4_action_ack_v1')).toContain("'ack', v_n || jsonb_build_object('ref'")
})

test('the lifecycle keeps the five distinctions and the §3 times in Australian time; the first entry is never reset', () => {
  const one = fn('security.layer4_lifecycle_one_v1')
  expect(one).toContain("'steps', jsonb_build_object('requested', v_requested, 'executed', v_executed, 'valid', v_valid, 'approved', v_approved, 'admitted', v_adm, 'published', v_pub)")
  for (const t of ['first_entered', 'item_created', 'last_updated', 'last_reviewer_action', 'last_automated_attempt', 'last_entered', 'next_action', 'decided', 'admitted', 'published'])
    expect(one).toContain(`'${t}', security.l4_time_v1(`)
  expect(m).toContain("set timezone to 'Australia/Sydney'  -- fixed: the decision (§3) fixes Australian time")
  expect(m).toContain("to_char(p_at, 'Dy FMDD Mon YYYY, FMHH12:MI am TZ')")
  expect(m).toContain('alter table pipeline.enrichment_flags add column if not exists first_flagged_at timestamptz;')
  expect(fx).toContain("C8 ok: a built-in decision replies with its acknowledgement")
})

test('the card shows the lifecycle from persisted records, in its own component; the Inbox only hooks it in', () => {
  expect(inbox).toContain("import{ItemLifecycle}from'./Layer4ItemLifecycle'")
  expect(inbox).toContain('<ItemLifecycle kind={it.kind} refId={it.ref} ack={ack} seen={seen}/>')
  expect(inbox).toContain('setAck(r?.ack||null)')
  expect(ui).toContain("supabase.rpc('admin_layer4_lifecycle',{p_args:{items:")
  expect(ui).not.toMatch(/setAck\(\{|ok:\s*true/) // success is never assumed on the client
})

const KINDS = { aer_review: { label: 'Entry requirements (AER)', order: 17, choices: [{ key: 'reject', label: 'Reject the read', rank: 6 }, { key: 'reread_stored', label: 'Re-read from stored evidence', hook: 'aer_review:extend' }, { key: 'open_intervention', label: 'Open human input', hook: 'aer_review:extend' }], detail: true, extension: 'aer_review:extend' } }
const UNI = { provider_id: 'p-rmit', name: 'RMIT University', country: 'AU', courses: 400, n: 1, by_kind: { aer_review: 1 } }
const ITEM = { kind: 'aer_review', ref: 'a7849f66-bfa7-412e-b26e-4fecc7fdaa6e', provider_id: 'p-rmit', provider: 'RMIT University', subject: 'Diploma of Commerce', why: 'held', created_at: '2026-10-29T01:44:26Z', detail: { field_code: 'course_entry_first_read' } }
const T = (text) => ({ at: '2026-11-04T01:17:46Z', text })
const LC = (last) => ({ kind: 'aer_review', ref: ITEM.ref, found: true, open: true, stage: 'failed', stage_label: 'Failed: still pending',
  why_pending: 'The last corrected read was refused by the reader: the corrected read was cut at the row limit (E13). The original read stays pending',
  next: { text: 'Open human input with the dropped requirements, or ask the Platform Admin for a row limit for this university' }, owner: 'Layer 4 reviewer',
  times: { first_entered: T('Thu 29 Oct 2026, 12:44 pm AEDT'), item_created: T('Thu 29 Oct 2026, 12:44 pm AEDT'), last_reviewer_action: T('Wed 4 Nov 2026, 12:17 pm AEDT'), last_updated: T('Wed 4 Nov 2026, 12:18 pm AEDT') },
  steps: { requested: 'yes', executed: 'yes, Wed 4 Nov 2026, 12:18 pm AEDT', valid: 'no: the corrected read was cut at the row limit (E13)', approved: 'not yet', admitted: 'not yet', published: 'not yet' },
  repeat_guard: { why: 'the reader refused the corrected read of this stored copy at Wed 4 Nov 2026, 12:18 pm AEDT' }, last_action: last, history: [] })

async function card(page, { lifecycle, decide }) {
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
    const b = route.request().postDataJSON()
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 1, universities: 1, late: 0, by_kind: { aer_review: { n: 1 } }, paging: { items: 25, universities: 25, detail_parallel: 3 } } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [UNI] } })
    if (b.p_action === 'items') return route.fulfill({ json: { total: 1, before: 0, more: false, items: [ITEM] } })
    if (b.p_action === 'detail') return route.fulfill({ json: { items: [{ kind: 'aer_review', ref: ITEM.ref, detail: {}, hook_detail: { sections: [], actions: [{ key: 'reread_stored', allowed: false }, { key: 'open_intervention', allowed: true }] } }] } })
    if (b.p_action === 'decide') return route.fulfill({ json: decide(b.p_args) })
    return route.fulfill({ json: {} })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_lifecycle', (route) => route.fulfill({ json: { items: { [`aer_review:${ITEM.ref}`]: lifecycle() } } }))
  await page.route('https://example.supabase.co/rest/v1/rpc/layer4_aer_review_read', (route) => route.fulfill({ json: { kind: 'course_entry_first_read', status: 'pending', rows: [], completeness_gate: { complete: false } } }))
}

test.describe('desktop', () => {
  test('the RMIT card shows what was done, when, the result, why it is pending and what is next; the repeat is not offered', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await card(page, { lifecycle: () => LC({ at: T('Wed 4 Nov 2026, 12:17 pm AEDT'), by: 'reviewer', action: 'reread_stored', ref: 'audit #28863', result: { outcome: 'queued' } }), decide: () => ({}) })
    await page.goto('/#layer-4-review')
    await page.locator('[data-l4-uni="RMIT University"] [data-l4-pill="aer_review"]').click()
    const c = page.locator('[data-l4-item="aer_review"]')
    await expect(c.locator('[data-l4-stage]')).toHaveText('Failed: still pending')
    await expect(c.locator('[data-l4-why-pending]')).toContainText('cut at the row limit (E13)')
    await expect(c.locator('[data-l4-ack]')).toContainText('audit #28863 · Wed 4 Nov 2026, 12:17 pm AEDT')
    await expect(c.locator('[data-l4-time="first_entered"]')).toHaveText('Thu 29 Oct 2026, 12:44 pm AEDT')
    await expect(c.locator('[data-l4-next]')).toContainText('Open human input')
    await expect(c.locator('[data-l4-repeat-guard]')).toBeVisible()
    await expect(c.locator('[data-l4-choice="reread_stored"]')).toHaveCount(0)
  })

  test("a decision shows only the server's acknowledgement, and it survives Refresh from the persisted record", async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    let decided = false
    const ack = { outcome: 'human_input', ref: 'audit #30001', at: T('Wed 4 Nov 2026, 1:05 pm AEDT'), next: 'Human input needed item 77 waits for a person' }
    await card(page, {
      lifecycle: () => LC(decided ? { at: ack.at, by: 'reviewer', action: 'open_intervention', ref: 'audit #30001', result: { outcome: 'human_input' } } : null),
      decide: () => { decided = true; return { ok: true, kind: 'aer_review', choice: 'open_intervention', event_id: 30001, ack } },
    })
    await page.goto('/#layer-4-review')
    await page.locator('[data-l4-uni="RMIT University"] [data-l4-pill="aer_review"]').click()
    const c = page.locator('[data-l4-item="aer_review"]')
    await expect(c.locator('[data-l4-stage]')).toBeVisible()
    await expect(c.locator('[data-l4-ack]')).toHaveCount(0)
    await c.locator('[data-l4-choice="open_intervention"]').click()
    await c.getByLabel('Reason').fill('Dropped rows need a person')
    await c.locator('[data-l4-confirm]').click()
    await expect(page.locator('[data-l4-ack="human_input"]').first()).toContainText('audit #30001')
    await page.reload()
    await page.locator('[data-l4-uni="RMIT University"] [data-l4-pill="aer_review"]').click()
    await expect(page.locator('[data-l4-item="aer_review"] [data-l4-ack="human_input"]')).toContainText('audit #30001 · Wed 4 Nov 2026, 1:05 pm AEDT')
  })
})

test.describe('phone @responsive', () => {
  test('Layer 4 card progress at phone width: times and acknowledgement wrap, nothing scrolls sideways', async ({ page }) => {
    const w = page.viewportSize()?.width || 9999
    expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(480)
    await mockAdmin(page, { rank: 6 })
    await card(page, { lifecycle: () => LC({ at: T('Wed 4 Nov 2026, 12:17 pm AEDT'), by: 'reviewer', action: 'reread_stored', ref: 'audit #28863', result: { outcome: 'already_requested', reason: 'Already requested: recovery action 1 at Wed 4 Nov 2026, 12:17 pm AEDT. Now: the reader refused it at Wed 4 Nov 2026, 12:18 pm AEDT: the corrected read was cut at the row limit (E13).', alternative: 'Open human input with the dropped requirements, or ask the Platform Admin for a row limit for this university (Settings › Pipeline settings, entry.max_rows_by_provider)' } }), decide: () => ({}) })
    await page.goto('/#layer-4-review')
    await page.locator('[data-l4-uni="RMIT University"] [data-l4-pill="aer_review"]').click()
    const c = page.locator('[data-l4-item="aer_review"]')
    await expect(c.locator('[data-l4-ack="already_requested"]')).toContainText('row limit')
    await expect(c.locator('[data-l4-time="first_entered"]')).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
  })
})
