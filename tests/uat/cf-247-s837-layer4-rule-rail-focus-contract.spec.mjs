// Guards: Platform Admin 20 Nov 2026 14:40 (S1-UI-Parity s837; mockup s820-s827): Layer 4 Review opens on Review by rule: "Waiting, grouped by rule"
// across the whole queue of a kind (server rule_groups, not the loaded page) on the left and one focused card on the right; the older views sit
// behind Other views; Preview the batch lists the exact records in one keyed read; only a banned-word description group is admitted as a batch,
// one decision per record after a confirmation; AER is never batch-approved.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { batchAdmits, defaultKind, groupLabel, holdLabelOf, refsOf } from '../../src/lib/l4-rules.js'

const MIG = fs.readFileSync('supabase/migrations/20261120145000_cf247_s836_s838_rule_groups_pulse_rates.sql', 'utf8')
const INBOX = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8'), FOCUS = fs.readFileSync('src/Layer4Focus.jsx', 'utf8')

test('s837 migration: two read-only actions through the Inbox dispatcher (md5-guarded), no public object, G3 read before and after, limits are settings', () => {
  expect((MIG.match(/consumer_api_check_v1/g) || []).length).toBeGreaterThanOrEqual(2)
  expect(MIG).toMatch(/^-- Replaces:/m); expect(MIG).toMatch(/^-- Retires:/m)
  expect(MIG).not.toMatch(/create\s+(or replace\s+)?function\s+public\.|create\s+(table|view)\b|^\s*(drop|delete|truncate)\b/im)
  expect(MIG).toContain("pg_temp.cf_edit_def('public.admin_layer4_inbox(text,jsonb)'::regprocedure, 'f458ded21b5c91dbb92a5ac0c9e185b9',")
  expect(MIG).toContain("if p_action in ('rule_groups', 'rule_group_items') then\n    return security.layer4_rule_groups_v1(p_action, p_args, v_kinds, v_target);")
  expect(MIG).toContain("from security.layer4_inbox_items_v2(v_prov, v_kind, null, v_kind = 'provider_description') r")       // the whole queue of the kind
  expect(MIG).toContain("security.layer4_inbox_items_v2(null, v_kind, array(select v_kind || ':' || r from unnest(v_refs) r), true)") // keyed cards
  expect(MIG).toContain("when i.code = 'policy_refused_word' then 'banned_word'")
  for (const k of ['layer4.rule_group_refs_max', 'layer4.rule_batch_max']) expect(MIG).toContain(`security.pipeline_num_v1('${k}'`)
  expect(MIG).toMatch(/revoke all on function security\.layer4_rule_groups_v1\(text, jsonb, jsonb, int\) from public, anon, authenticated/)
  expect(MIG).not.toMatch(/'decide'/) // nothing is decided by the new function
})

test('s837: the rail names, the default queue and the batch rule', () => {
  expect(groupLabel({ key: 'cd:banned_word' })).toBe('Contains a banned word')
  expect(groupLabel({ key: 'cd:identity_margin_thin' })).toBe('Page match not clear enough')
  expect(groupLabel({ key: 'cd:length' })).toBe('Longer than the limit')
  expect(groupLabel({ key: 'cd:duplicate' })).toBe('Same wording as another course')
  expect(groupLabel({ key: 'cd:quote_mismatch' })).toBe('A sentence is not on its page')
  expect(groupLabel({ key: 'aer:gate_incomplete', label: 'Completeness gate (partial table read)' })).toBe('Completeness gate (partial table read)')
  expect(groupLabel({ key: 'course_link:fee reader: course match not sure enough', label: 'Fee reader: course match not sure enough' })).toBe('Fee reader: course match not sure enough')
  expect(holdLabelOf({ kind: 'aer_review', why: 'Machine rule aer-machine-v1 did not admit this: audit_sample' })).toBe('Audit sample (a person checks it)')
  expect(defaultKind({ aer_review: { n: 9 }, provider_description: { n: 2 } }, {})).toBe('provider_description')
  expect(defaultKind({ aer_review: { n: 9 }, course_link: { n: 20 } }, {})).toBe('course_link')
  expect(batchAdmits({ key: 'cd:banned_word' })).toBe(true)
  for (const k of ['aer:audit_sample', 'cd:identity_margin_thin', 'course_link:x']) expect(batchAdmits({ key: k })).toBe(false)
  expect(refsOf([{ key: 'a', refs: ['1', '2'] }, { key: 'b', refs: ['3'] }], '')).toEqual(['1', '2', '3'])
  expect(INBOX).toContain("wantView)?wantView:'focus')"); expect(INBOX).toContain('data-l4-other-views')
  expect(FOCUS).toContain("choice:'edit_approve',value:x.c.text,set_manual_lock:true")
})

const W = ['innovative', 'leading']
const RULES = { provider: { min_chars: 20, max_chars: 1200, min_sentences: 1, max_sentences: 5, words: W }, course: { min_chars: 20, max_chars: 360, min_sentences: 1, max_sentences: 2, words: W }, review_months: 6 }
const KINDS = { provider_description: { label: 'Course and university descriptions', order: 1, choices: [
    { key: 'approve', label: 'Approve as read', rank: 4, returns: 'Published.' }, { key: 'reject', label: 'Reject', rank: 4, returns: 'Read again later.' },
    { key: 'edit_approve', label: 'Save Edit & Admit', input: 'text', editor: true, rank: 4, returns: 'Admitted.' }] },
  aer_review: { label: 'Entry requirements', order: 2, choices: [{ key: 'approve', label: 'Approve', rank: 4, returns: 'x' }] } }
const desc = (ref, text, code, subject) => ({ kind: 'provider_description', ref, provider_id: 'p1', provider: 'Technology University Sydney', subject, created_at: '2026-11-15T01:00:00Z',
  why: `Machine rule cdesc-machine-v1 did not admit this: ${code}`,
  detail: { field_code: 'provider_description', proposed: { description: text, sentences: [{ text, quote: text.slice(0, 20) }], source_url: 'https://uni.example/about' }, machine: { reason_code: code } } })
const ITEMS = {
  b1: desc('b1', 'Technology University Sydney is an innovative university of technology in Sydney.', 'policy_refused_word', 'University A'),
  b2: desc('b2', 'Harbour University is a leading university in Sydney with campuses in the city.', 'policy_refused_word', 'University B'),
  m1: desc('m1', 'Harbour University teaches nursing in Sydney.', 'identity_margin_thin', 'Bachelor of Nursing')
}
const GROUPS = { kind: 'provider_description', built_in: true, total: 3, refs_max: 500, batch_max: 50, ms: 41,
  groups: [{ key: 'cd:banned_word', n: 2, late: 1, refs: ['b1', 'b2'] }, { key: 'cd:identity_margin_thin', n: 1, late: 0, refs: ['m1'] }] }

test.describe('mocked browser', () => {
  test('Review by rule is the default: whole-queue rail, one focused card, batch preview and a confirmed banned-word batch', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1000 })
    await mockAdmin(page, { rank: 6 })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON(); calls.push(b)
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 4, universities: 1, late: 1, by_kind: { provider_description: { n: 3, late: 1 }, aer_review: { n: 1 } } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 0, items: [] } })
      if (b.p_action === 'rule_groups') return route.fulfill({ json: GROUPS })
      if (b.p_action === 'rule_group_items') return route.fulfill({ json: { kind: b.p_args.kind, items: b.p_args.refs.map((r) => ITEMS[r]).filter(Boolean), ms: 12 } })
      if (b.p_action === 'description_rules') return route.fulfill({ json: RULES })
      if (b.p_action === 'decide') return route.fulfill({ json: { ok: true, returns: 'Admitted.' } })
      return route.fulfill({ json: {} })
    })
    await page.goto('/#layer-4-review')
    const rail = page.locator('[data-l4-focus-rail]')
    await expect(rail.locator('[data-l4-focus-group]')).toHaveCount(3)          // All, and the two rules of the whole queue
    await expect(rail.locator('[data-l4-focus-group="cd:banned_word"]')).toContainText('Contains a banned word')
    await expect(rail.locator('[data-l4-focus-group="all"]')).toContainText('3')
    expect(calls.find((c) => c.p_action === 'rule_groups')?.p_args).toEqual({ kind: 'provider_description' })
    expect(calls.some((c) => c.p_action === 'items')).toBe(false)              // the default view reads no page of items
    await expect(page.locator('[data-l4-item]')).toHaveCount(1)                // one focused card
    await expect(page.locator('[data-l4-focus-pos]')).toContainText('Card 1 of 3')
    await expect(page.locator('[data-l4-view="university"]')).toHaveCount(0)   // the older views are behind Other views
    await page.locator('[data-l4-other-views]').click()
    await expect(page.locator('[data-l4-view="university"]')).toBeVisible()
    await page.locator('[data-l4-other-views]').click()

    await rail.locator('[data-l4-focus-group="cd:banned_word"]').click()
    await page.locator('[data-l4-batch-open]').click()
    const pv = page.locator('[data-l4-batch-preview="cd:banned_word"]')
    await expect(pv.locator('[data-l4-batch-rec]')).toHaveCount(2)
    await expect(pv.locator('mark.dea-ban')).toHaveCount(2)
    await expect(pv.locator('[data-l4-batch-clean]').first()).toContainText('Technology University Sydney is a university of technology in Sydney.')
    await expect(pv.locator('[data-l4-batch-ms]')).toContainText(/shown in \d+ ms/)
    expect(calls.filter((c) => c.p_action === 'decide')).toHaveLength(0)
    await pv.locator('[data-l4-batch-admit]').click()                         // the first click only asks for confirmation
    expect(calls.filter((c) => c.p_action === 'decide')).toHaveLength(0)
    await pv.locator('[data-l4-batch-confirm]').click()
    await expect(pv.locator('[data-l4-batch-run="done"]')).toContainText('Admitted 2 of 2')
    const decided = calls.filter((c) => c.p_action === 'decide').map((c) => c.p_args)
    expect(decided).toHaveLength(2)
    expect(decided[1]).toMatchObject({ kind: 'provider_description', ref: 'b2', choice: 'edit_approve', set_manual_lock: true, value: 'Harbour University is a university in Sydney with campuses in the city.' })
    expect(decided[1].reason).toContain('removed leading')
  })

  test('an AER group is previewed and worked card by card: no batch approval', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    const aer = { kind: 'aer_review', ref: 'a1', provider_id: 'p1', provider: 'University of Waikato', subject: 'Bachelor of Science', created_at: '2026-11-15T01:00:00Z',
      why: 'Machine rule aer-machine-v1 did not admit this: audit_sample', detail: {} }
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON()
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 1, universities: 1, late: 0, by_kind: { aer_review: { n: 1 } } } })
      if (b.p_action === 'rule_groups') return route.fulfill({ json: { kind: 'aer_review', built_in: true, total: 1, batch_max: 50, ms: 30, groups: [{ key: 'aer:audit_sample', label: 'Audit sample (a person checks it)', n: 1, late: 0, refs: ['a1'] }] } })
      if (b.p_action === 'rule_group_items') return route.fulfill({ json: { items: [aer], ms: 8 } })
      return route.fulfill({ json: {} })
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/layer4_aer_review_read', (route) => route.fulfill({ json: { rows: [] } }))
    await page.goto('/#layer-4-review')
    await page.locator('[data-l4-focus-group="aer:audit_sample"]').click()
    await page.locator('[data-l4-batch-open]').click()
    const pv = page.locator('[data-l4-batch-preview="aer:audit_sample"]')
    await expect(pv).toContainText('there is no batch approval')
    await expect(pv.locator('[data-l4-batch-admit]')).toHaveCount(0)
    await expect(page.locator('[data-l4-item="aer_review"] [data-l4-hold]')).toContainText('Main hold reason: Audit sample (a person checks it)')
  })
})
