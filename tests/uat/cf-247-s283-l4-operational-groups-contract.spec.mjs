// Guards: Platform Admin mandate 4 Nov 2026 16:32 §2, §7, §8 and §10 (Layer 4 simplification): every waiting item in one of four operational groups from one shared server function, with no new admission authority; the Inbox's three choices; shared fixes for duplicate decisions, retries on an unchanged stop, navigation audit, provider and adapter evidence, and re-raised reviews
// Migration 20261104560000. The groups, the guards and the paging budget are proved on PostgreSQL 16 by tests/fixtures/l4-operational-groups (G1-G8:
// Course Link, AER, scholarship and onboarding records). Mocked admin here; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const m = fs.readFileSync('supabase/migrations/20261104560000_cf247_l4_operational_groups.sql', 'utf8')
const fx = fs.readFileSync('tests/fixtures/l4-operational-groups/fixtures.sql', 'utf8')
const ui = fs.readFileSync('src/Layer4Groups.jsx', 'utf8')
const inbox = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
const fn = (name) => { const i = m.indexOf(`create or replace function ${name}(`); return m.slice(i, m.indexOf('$function$;', i)) }

test('one shared classifier; group A only under an existing rule, which is named; no new admission authority', () => {
  const g = fn('security.layer4_groups_v1')
  expect(g).toContain("when ri.readiness = 'resolvable' then 'A'")
  expect(g).toContain("security.layer4_cl_group_call_v1(ri.ref::uuid)")
  expect(fn('security.layer4_cl_group_call_v1')).toContain("to_regprocedure('security.course_link_route_class_v1(uuid)') is null then return jsonb_build_object('grp', 'C'")
  // nothing is decided, superseded or admitted by the classifier or the screen read
  for (const f of ['security.layer4_groups_v1', 'security.layer4_group_counts_v1', 'public.admin_layer4_groups', 'security.layer4_card_evidence_v1'])
    expect(fn(f)).not.toMatch(/\b(insert|update|delete)\b/i)
  expect(m).toContain("if exists (select 1 from security.layer4_groups_v1() g where g.grp = 'A' and g.rule is null) then raise exception 'post-check: a group A item without its existing rule'")
  expect(m).not.toMatch(/create table/i)
  expect(fx).toContain("G1 ok:")
})

test('guarded edits of the live definitions; the item list and the AER recovery detail are not touched', () => {
  for (const [sig, md5] of [['public.admin_layer4_inbox(text,jsonb)', 'c0a972a6d6cc0652ce2dcc8f4d9cbbfc'], ['security.layer4_lifecycle_one_v1(text,text,boolean)', 'a93b2bee90704eb3fbd3e09da350ba53'],
    ['security.layer4_items_lifecycle_v1(jsonb)', 'f6eeef05b818c8818d9eef144ff91a18'], ['security.layer4_item_lifecycle_v1(text,text)', 'a908288151604a4e3d936be5f05a2fad']])
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${md5}',`)
  for (const f of ['layer4_inbox_items_v2', 'layer4_aer_recovery_detail_v1', 'layer4_aer_recovery_decide_v1', 'course_link_route_class_v1', 'layer4_course_link_rule_execute_v1'])
    expect(m).not.toMatch(new RegExp(`create or replace function [a-z]+\\.${f}\\(`))
})

test('shared §8 fixes: a decision that did not apply, the same decision again, retries on an unchanged stop, navigation audit', () => {
  expect(m).toContain("v_r := coalesce(v_r, '{}'::jsonb) || jsonb_build_object('still_waiting', exists (select 1 from security.layer4_inbox_items_v2(null, v_kind, array[v_kind || ':' || v_ref], false)));")
  const guard = fn('security.layer4_decide_guard_v1')
  expect(guard).toContain("security.pipeline_num_v1('layer4.duplicate_decision_seconds', 120)")
  expect(guard).toContain("security.pipeline_list_v1('layer4.once_only_choices', '[\"retry\", \"rebuild\", \"release\"]'::jsonb)")
  expect(m).toContain("values ('layer4', 'inbox_refused', v_kind || ':' || v_ref,")
  expect(fn('public.admin_layer4_navigate')).toContain("values ('layer4', 'inbox_navigate', v_kind || ':' || v_ref,")
  for (const c of ['G4 ok:', 'G4b ok:', 'G5 ok:', 'G6 ok:', 'G7 ok:', 'G8 ok:']) expect(fx).toContain(c)
  expect(inbox).toContain('if(c.link){recordNavigation(it.kind,it.ref,c.key);')
})

test('the Inbox shows three choices; group A as counts only; detailed classes stay in the card', () => {
  for (const l of ['Ready for my decision', 'Information needed from me', 'Technical recovery']) expect(ui).toContain(`'${l}'`)
  expect(ui).toContain('Settled by existing rules:')
  expect(inbox).toContain("<GroupBar active={view==='group'?grp:''}")
  expect(fn('public.admin_layer4_groups')).toContain("raise exception 'group A is settled by existing rules and has no cards; see its rules in the summary'")
})

const KINDS = {
  nothing_ready: { label: 'Adapter has nothing ready', order: 6, choices: [{ key: 'adapter', label: 'Open the adapter', link: 'builder' }, { key: 'rebuild', label: 'Rebuild the adapter', rank: 5 }] },
  aer_review: { label: 'Entry requirements (AER)', order: 17, choices: [{ key: 'reject', label: 'Reject the read', rank: 6 }] },
}
const SUMMARY = { groups: { A: 307, B: 639, C: 3934, D: 530 }, rules: [{ rule: 'security.layer4_reconcile_v1 (off: layer4.reconcile_supersede_on)', class: 'platform:covered_by_active', n: 252 }],
  labels: { C: 'Ready for my decision', D: 'Information needed from me', B: 'Technical recovery', A: 'Settled by existing rules' } }
const ADAPTER = { kind: 'nothing_ready', ref: '6b000000-0000-4000-8000-000000000001', provider_id: 'p-astra', provider: 'Astra College', why: 'Nothing passed after 2 AI attempt(s)',
  created_at: '2026-10-25T01:00:00Z', detail: { stop_reason: 'nothing_ready', onboarding_id: '6b000000-0000-4000-8000-000000000001' }, group: 'B', class: 'kind:nothing_ready' }
const T = (text) => ({ at: '2026-10-25T01:00:00Z', text })

async function screen(page, { calls }) {
  await mockAdmin(page, { rank: 6 })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
    const b = route.request().postDataJSON(); calls.push(['inbox', b.p_action])
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 5410, universities: 1, late: 0, by_kind: { nothing_ready: { n: 317 } }, paging: { items: 25, universities: 25, detail_parallel: 3 } } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p-astra', name: 'Astra College', country: 'AU', courses: 11, n: 1, by_kind: { nothing_ready: 1 } }] } })
    if (b.p_action === 'items') return route.fulfill({ json: { total: 1, before: 0, more: false, items: [ADAPTER] } })
    return route.fulfill({ json: { items: [] } })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_groups', async (route) => {
    const a = route.request().postDataJSON().p_args; calls.push(['groups', a.action, a.group])
    if (a.action === 'summary') return route.fulfill({ json: SUMMARY })
    return route.fulfill({ json: { group: a.group, total: a.group === 'B' ? 1 : 0, offset: 0, limit: 25, items: a.group === 'B' ? [ADAPTER] : [] } })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_lifecycle', (route) => route.fulfill({ json: { items: { [`nothing_ready:${ADAPTER.ref}`]: {
    kind: 'nothing_ready', ref: ADAPTER.ref, found: true, open: true, stage: 'awaiting_decision', stage_label: 'Waiting for a reviewer', why_pending: 'No reviewer action yet',
    group: 'B', group_label: 'Technical recovery', person_needed: 'not yet: the platform is recovering it', times: { first_entered: T('Sun 25 Oct 2026, 12:00 pm AEDT') },
    evidence: { Website: 'https://astra.edu.au', 'Pages read': 3, 'Why each field is held': { english: 'read on 1 of 4 pages, under the share needed' } }, history: [] } } } }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_navigate', (route) => { calls.push(['navigate', route.request().postDataJSON().p_args.choice]); return route.fulfill({ json: { ok: true, event_id: 1 } }) })
}

test.describe('desktop', () => {
  test('the three choices with counts; Technical recovery lists its cards with the person question and the evidence held', async ({ page }) => {
    const calls = []
    await screen(page, { calls })
    await page.goto('/#layer-4-review')
    await expect(page.locator('[data-l4-group-pick="C"]')).toContainText('Ready for my decision (3,934)')
    await expect(page.locator('[data-l4-group-pick="D"]')).toContainText('Information needed from me (530)')
    await expect(page.locator('[data-l4-group-pick="B"]')).toContainText('Technical recovery (639)')
    await expect(page.locator('[data-l4-group-a]')).toContainText('Settled by existing rules: 307')
    await page.locator('[data-l4-group-pick="B"]').click()
    const card = page.locator('[data-l4-group-list="B"] [data-l4-item="nothing_ready"]')
    await expect(card.locator('[data-l4-group="B"]')).toContainText('Technical recovery: not yet: the platform is recovering it')
    await card.locator('[data-l4-evidence-held] summary').click()
    await expect(card.locator('[data-l4-evidence-held]')).toContainText('read on 1 of 4 pages')
    await card.locator('[data-l4-choice="adapter"]').click()
    await expect.poll(() => calls.filter((c) => c[0] === 'navigate').length).toBe(1)
  })
})

test.describe('phone @responsive', () => {
  test('Layer 4 at phone width: the three choices are tap targets, a group opens, nothing scrolls sideways', async ({ page }) => {
    const w = page.viewportSize()?.width || 9999
    expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(480)
    const calls = []
    await screen(page, { calls })
    await page.goto('/#layer-4-review')
    const pick = page.locator('[data-l4-group-pick="D"]')
    const b = await pick.boundingBox()
    expect(b.height, 'tap target').toBeGreaterThanOrEqual(24)
    expect(b.x + b.width).toBeLessThanOrEqual(w + 1)
    await pick.click()
    await expect(page.locator('[data-l4-group-list="D"]')).toContainText('Nothing waits here.')
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
  })
})
