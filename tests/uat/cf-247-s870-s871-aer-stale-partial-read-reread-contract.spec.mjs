// Guards: Platform Admin 20 Nov 2026 16:28 (S1-RM-Design s870 and s871): an AER item held as technical recovery is never a dead-end card. With a
// bound stored copy it offers Re-read from stored copy ($0), which supersedes the stale partial read and re-reads the copy with the deterministic
// reader aer-det-v1.3 (no AI, no Firecrawl); with no stored page it offers Queue stored-page fetch. Technical-recovery items sit under System recovery,
// apart from Waiting for a reviewer. The stale partial-table holds are superseded once, never touching entry matrices, audit samples, locks or active rows.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { groupLabel, isRecoveryGroup, rereadAction } from '../../src/lib/l4-rules.js'

const MIG = fs.readFileSync('supabase/migrations/20261120145500_cf247_s870_s871_aer_stale_partial_read_det_reread.sql', 'utf8')

test('s870/s871 migration: no public object, G3 before and after, md5-guarded edits, nothing deleted, protected items excluded', () => {
  expect((MIG.match(/consumer_api_check_v1/g) || []).length).toBeGreaterThanOrEqual(2)
  expect(MIG).toMatch(/^-- Replaces:/m); expect(MIG).toMatch(/^-- Retires:/m)
  expect(MIG).not.toMatch(/create\s+(or replace\s+)?function\s+public\.|create\s+(table|view)\b|^\s*(drop|delete|truncate)\b/im)
  expect(MIG).toContain("pg_temp.cf_edit_def('public.admin_layer4_inbox(text,jsonb)'::regprocedure, '93cb781009da3ef410943e905f9d893b',")
  expect(MIG).toContain("pg_temp.cf_edit_def('security.aer_det_propose_v1()'::regprocedure, '8516a3992010f7f55a7f9bcc8a9c8bb3',")
  expect(MIG).toContain("and r.status <> 'superseded') then v_outcome := 'earlier_read';")
  expect(MIG).toContain("when r.field_code <> 'course_entry_first_read' or r.entity_type <> 'course' then 'not_a_course_read'")  // matrices, S677, matrix changes
  expect(MIG).toContain("when r.code = 'audit_sample' then 'audit_sample'")
  expect(MIG).toContain("when r.locked then 'locked'")
  expect(MIG).toContain("if p_action <> 'aer_det_reread_check' and v_rank < 6 then raise exception 'Platform Admin role required'")
  for (const c of ['entry matrix items changed', 'manual locks changed', 'active entry rows changed']) expect(MIG).toContain(c)
  expect(MIG).toContain("v_ext constant text := 'aer-det-v1.3'")
  expect(MIG).toContain("security.course_page_needed_add_v1(r.entity_id")
})

test('s870: the card action and the recovery groups', () => {
  expect(rereadAction({ reread: { verdict: 'rereadable' } })).toMatchObject({ key: 'aer_det_reread', label: 'Re-read from stored copy ($0)' })
  expect(rereadAction({ reread: { verdict: 'no_stored_page' } })).toMatchObject({ key: 'aer_page_fetch', label: 'Queue stored-page fetch' })
  expect(rereadAction({ reread: { verdict: 'audit_sample' } })).toBe(null)
  expect(isRecoveryGroup({ key: 'aerb:gate_incomplete' })).toBe(true); expect(isRecoveryGroup({ key: 'aer:audit_sample' })).toBe(false)
  expect(groupLabel({ key: 'aerb:gate_incomplete', label: 'Completeness gate (partial table read)' })).toBe('Completeness gate (partial table read)')
  expect(groupLabel({ key: 'aerb:no_bound_page' })).toBe('No stored page bound')
  expect(fs.readFileSync('src/Layer4ItemLifecycle.jsx', 'utf8')).toContain("lc.group==='B'?'System recovery: the platform is working on it':lc.stage_label") // s875: entry matrices in recovery have no re-read
})

const KINDS = { aer_review: { label: 'Entry requirements', order: 1, choices: [{ key: 'approve', label: 'Approve all rows', rank: 6, returns: 'x' }, { key: 'reject', label: 'Reject', rank: 6, returns: 'x' }] } }
const aer = (ref, code, verdict) => ({ kind: 'aer_review', ref, provider_id: 'p1', provider: 'Notre Dame', subject: `Course ${ref}`, created_at: '2026-10-29T01:00:00Z',
  why: `Machine rule aer-machine-v1 did not admit this: ${code}`, detail: {}, reread: verdict ? { verdict, evidence_id: verdict === 'rereadable' ? 'e1' : null } : undefined })

test.describe('mocked browser', () => {
  test('System recovery apart from Waiting for a reviewer; a recovery card re-reads in one click; the batch re-reads after a confirmation', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1000 })
    await mockAdmin(page, { rank: 6 })
    const calls = []
    const items = { a1: aer('a1', 'gate_incomplete', 'rereadable'), a2: aer('a2', 'gate_incomplete', 'rereadable'), a3: aer('a3', 'gate_incomplete', 'no_stored_page'), s1: aer('s1', 'audit_sample') }
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON(); calls.push(b)
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 4, universities: 1, late: 0, by_kind: { aer_review: { n: 4 } } } })
      if (b.p_action === 'rule_groups') return route.fulfill({ json: { kind: 'aer_review', built_in: true, total: 4, batch_max: 50, ms: 20, groups: [
        { key: 'aerb:gate_incomplete', label: 'Completeness gate (partial table read)', n: 3, late: 3, refs: ['a1', 'a2', 'a3'], recovery: true },
        { key: 'aer:audit_sample', label: 'Audit sample (a person checks it)', n: 1, late: 0, refs: ['s1'] }] } })
      if (b.p_action === 'rule_group_items') return route.fulfill({ json: { items: b.p_args.refs.map((r) => items[r]).filter(Boolean), ms: 9 } })
      if (b.p_action === 'aer_det_reread') return route.fulfill({ json: { action: 'apply', superseded: b.p_args.refs.length, skipped: {} } })
      if (b.p_action === 'aer_page_fetch') return route.fulfill({ json: { action: 'fetch', fetch_queued: b.p_args.refs.length, skipped: {} } })
      return route.fulfill({ json: {} })
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/layer4_aer_review_read', (route) => route.fulfill({ json: { rows: [] } }))
    await page.goto('/#layer-4-review')
    await expect(page.locator('[data-l4-focus-section="reviewer"]')).toContainText('Human Action Required')
    await expect(page.locator('[data-l4-focus-section="reviewer"] [data-l4-focus-group="aer:audit_sample"]')).toBeVisible()
    await expect(page.locator('[data-l4-focus-section="recovery"]')).toContainText('System Queues (Auto-Recovering)')
    await expect(page.locator('[data-l4-focus-section="recovery"] [data-l4-focus-group="aerb:gate_incomplete"]')).toContainText('3')
    await page.locator('[data-l4-focus-group="aerb:gate_incomplete"]').click()
    const card = page.locator('[data-l4-focus-card] [data-l4-item="aer_review"]')
    await expect(card.locator('[data-l4-recovery="aer_det_reread"] [data-l4-recovery-go]')).toHaveText('Re-read from stored copy ($0)')
    await card.locator('[data-l4-recovery-go]').click()
    await expect.poll(() => calls.find((c) => c.p_action === 'aer_det_reread')?.p_args?.refs).toEqual(['a1'])
    await expect(page.locator('[data-l4-focus-pos]')).toContainText('Card 1 of 2')        // the re-read card left the queue
    await page.locator('[data-l4-batch-open]').click()
    const pv = page.locator('[data-l4-batch-preview="aerb:gate_incomplete"]')
    await expect(pv).toContainText('$0: no AI, no Firecrawl')
    await expect(pv.locator('[data-l4-batch-reread]')).toHaveText('Re-read 1 from stored copy ($0)')
    await expect(pv.locator('[data-l4-batch-fetch]')).toHaveText('Queue stored-page fetch for 1')
    const n = calls.filter((c) => c.p_action === 'aer_det_reread').length
    await pv.locator('[data-l4-batch-reread]').click()
    expect(calls.filter((c) => c.p_action === 'aer_det_reread').length).toBe(n)       // the first click only asks for confirmation
    await pv.locator('[data-l4-batch-reread-confirm]').click()
    await expect(pv.locator('[data-l4-batch-run="done"]')).toContainText('Re-read asked for 1 of 1')
    expect(calls.filter((c) => c.p_action === 'aer_det_reread').at(-1).p_args.refs).toEqual(['a2'])
    expect(calls.some((c) => c.p_action === 'decide')).toBe(false)                    // nothing is approved
  })
})
