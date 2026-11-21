// Guards: Platform Admin 20 Nov 2026 17:13 (S1-RM-Design s872 to s874, universal minimum-effort Layer 4 overhaul): in all 19 Layer 4 queues the rule rail
// separates Human Action Required from System Queues (Auto-Recovering) (s872); every card follows one plain-English contract: the amber Main hold reason with
// no raw code (codes such as D-R3 or gate_incomplete only under Technical detail), and one standard action bar (admit first, then Save Edit & Admit and
// re-categorise, the set-aside decisions on the right) (s873); and every rule group offers Preview & Settle Batch, which settles a group with one decision,
// one reason and a typed confirmation where the queue allows it (never entry requirements, departures or descriptions, as Grid › Clusters) (s874).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { L4_QUEUES, choiceRole, orderChoices, plainHold, settleChoices } from '../../src/lib/l4-rules.js'

const MIG = fs.readFileSync('supabase/migrations/20261120174700_cf247_s872_l4_system_queues_apart.sql', 'utf8')
const c = (key, extra = {}) => ({ key, label: key.replace(/_/g, ' '), returns: `${key} happens`, ...extra })
// the 19 queues with their live decisions (read 20 Nov 2026 17:20 AEDT from security.layer4_inbox_hooks_v1)
const QUEUES = {
  course_link: [c('keep'), c('use'), c('enter', { input: 'url' }), c('refuse')],
  held_scholarship: [c('publish'), c('not_international'), c('not_scholarship'), c('duplicate', { input: 'scholarship' })],
  website_needed: [c('website', { input: 'url' }), c('cricos_only'), c('archive', { rank: 5 })],
  pages_not_found: [c('website', { input: 'url' }), c('pages'), c('release', { rank: 4 }), c('cricos_only')],
  too_few_pages: [c('pages'), c('cricos_only')],
  nothing_ready: [c('adapter'), c('rebuild', { rank: 5 }), c('cricos_only')],
  central_to_approve: [c('open')],
  onboarding_failed: [c('retry', { rank: 5 }), c('builder')],
  site_down: [c('website', { input: 'url' }), c('archive', { rank: 5 }), c('wait')],
  not_offered: [c('archive_course', { rank: 5 }), c('keep')],
  fee_check: [c('course'), c('keep')],
  counsellor_report: [c('report_fixed'), c('report_not_changed'), c('course')],
  not_on_site: [c('archive_course', { rank: 5 }), c('keep'), c('course')],
  provider_departure: [c('closed', { rank: 6 }), c('merged', { input: 'provider', rank: 6 }), c('reviewed', { rank: 6 })],
  no_page_first_run: [c('approve'), c('has_page', { input: 'courses' }), c('reject')],
  conjoint_first_run: [c('approve'), c('parent', { input: 'url' }), c('reject')],
  aer_review: [c('approve', { rank: 6 }), c('approve_except', { input: 'rows', rank: 6 }), c('reject', { rank: 6 })],
  provider_description: [c('approve', { rank: 4 }), c('reject', { rank: 4 }), c('edit_approve', { input: 'text', editor: true, rank: 4 })],
  course_page_needed: [c('add_page', { input: 'url' }), c('search_again'), c('no_page', { input: 'url' })]
}
const RAW = 'Machine rule demo-machine-v1 did not admit this: gate_incomplete. Partial table read held by D-R3 (completeness_not_applicable)'

test('s872 migration: system queues apart in every queue (md5-guarded), no public object, G3 before and after', () => {
  expect((MIG.match(/consumer_api_check_v1/g) || []).length).toBeGreaterThanOrEqual(2)
  expect(MIG).toMatch(/^-- Replaces:/m); expect(MIG).toMatch(/^-- Retires:/m)
  expect(MIG).not.toMatch(/create\s+(or replace\s+)?function\s+public\.|create\s+(table|view)\b|^\s*(drop|delete|truncate)\b/im)
  expect(MIG).toContain("'8e649c381711b259f93382e5f4764f87'")
  expect(MIG).toContain("x.grp in ('A', 'B') and x.state = 'waiting') sys")
  expect(MIG).toContain("(case when k.sys and v_kind <> 'aer_review' then 'sys~' else '' end) || k.gkey gkey")
})

test('s873: plain English, the standard bar order and the batch rule, for all 19 queues', () => {
  expect(L4_QUEUES).toHaveLength(19); expect(Object.keys(QUEUES).sort()).toEqual([...L4_QUEUES].sort())
  expect(plainHold(RAW)).toBe('Gate incomplete. Partial table read held by (completeness not applicable)')
  expect(plainHold(RAW)).not.toMatch(/D-R3|_|v1/)
  for (const k of L4_QUEUES) {
    const roles = orderChoices(QUEUES[k]).map((x) => x.role)
    expect(roles.join(','), k).toBe([...roles].sort((a, b) => ['primary', 'edit', 'recategorise', 'aside'].indexOf(a) - ['primary', 'edit', 'recategorise', 'aside'].indexOf(b)).join(','))
    for (const x of QUEUES[k]) if (x.input) expect(['edit', 'recategorise', 'aside'], `${k}.${x.key}`).toContain(choiceRole(x))
  }
  for (const k of ['aer_review', 'provider_departure', 'provider_description']) expect(settleChoices(k, QUEUES[k])).toEqual([])
  expect(settleChoices('site_down', QUEUES.site_down).map((x) => x.key)).toEqual(['archive', 'wait'])
})

test.describe('mocked browser', () => {
  test('every one of the 19 queues: plain Main hold reason, codes only under Technical detail, one action bar, Preview & Settle Batch on the group', async ({ page }) => {
    test.setTimeout(240_000)
    await page.setViewportSize({ width: 1440, height: 1000 })
    await mockAdmin(page, { rank: 6 })
    const kinds = Object.fromEntries(L4_QUEUES.map((k, i) => [k, { label: `Queue ${k.replace(/_/g, ' ')}`, order: i + 1, choices: QUEUES[k] }]))
    const item = (k, r) => ({ kind: k, ref: `${k}-${r}`, provider_id: 'p1', provider: 'Demo University', subject: `Record ${r} of ${k}`, created_at: '2026-11-15T01:00:00Z', why: RAW,
      detail: k === 'provider_description' ? { field_code: 'provider_description', proposed: { description: 'Demo University teaches in Sydney.', sentences: [] }, machine: { reason_code: 'identity_margin_thin' } } : {} })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON(); const k = b.p_args?.kind
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 38, universities: 1, late: 0, by_kind: Object.fromEntries(L4_QUEUES.map((x) => [x, { n: 2 }])) } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 0, items: [] } })
      if (b.p_action === 'rule_groups') return route.fulfill({ json: { kind: k, built_in: true, total: 2, batch_max: 50, ms: 5, groups: [
        { key: `${k}:held`, label: k === 'aer_review' ? 'Completeness gate (partial table read)' : 'Machine rule demo-machine-v1 did not admit this: gate_incomplete', n: 1, late: 0, refs: [`${k}-1`] },
        { key: k === 'aer_review' ? 'aerb:gate_incomplete' : `sys~${k}:recovering`, label: 'Recovering by itself', n: 1, late: 0, refs: [`${k}-2`], recovery: true }] } })
      if (b.p_action === 'rule_group_items') return route.fulfill({ json: { items: (b.p_args.refs || []).map((r) => item(b.p_args.kind, r.split('-').pop())), ms: 3 } })
      if (b.p_action === 'description_rules') return route.fulfill({ json: { provider: { words: [] }, course: { words: [] } } })
      if (b.p_action === 'detail') return route.fulfill({ json: { items: [] } })
      return route.fulfill({ json: {} })
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/layer4_aer_review_read', (route) => route.fulfill({ json: { rows: [] } }))
    await page.goto('/#layer-4-review')
    for (const k of L4_QUEUES) {
      await page.locator('[data-l4-module-toggle]').click()                                  // s931: Module / Field lists the queues
      await page.locator(`[data-l4-kind="${k}"]`).click()
      await expect(page.locator(`[data-l4-focus="${k}"]`), k).toBeVisible()
      await expect(page.locator('[data-l4-focus-section="reviewer"]'), k).toContainText('Human Action Required')
      await expect(page.locator('[data-l4-focus-section="recovery"]'), k).toContainText('System Queues (Auto-Recovering)')
      const card = page.locator(`[data-l4-focus-card] [data-l4-item="${k}"]`)
      await expect(card, k).toBeVisible()
      const banner = card.locator('[data-l4-hold] strong, [data-dea-hold] strong').first()
      await expect(banner, k).toContainText('Main hold reason')
      expect(await banner.innerText(), k).not.toMatch(/D-R3|gate_incomplete|completeness_not_applicable|demo-machine-v1/)
      expect(await card.locator('[data-dea-hold-code]').first().textContent(), k).toContain('D-R3')       // the code is kept, under Technical detail
      if (k === 'provider_description') await expect(card.locator('[data-dea-bar]'), k).toBeVisible()
      else {
        const bar = card.locator('[data-l4-bar]'); await expect(bar, k).toBeVisible()
        // s931 (Decision 279 §4.2): the three decisions in their order, then More options with the queue's other choices in role order
        const dec = await bar.locator('button[data-l4-decision]').evaluateAll((bs) => bs.map((b) => b.getAttribute('data-l4-decision')))
        const want = ['yes', 'no', 'resubmit']
        expect(dec.map((r) => want.indexOf(r)), k).toEqual([...dec.map((r) => want.indexOf(r))].sort((a, b) => a - b))
        const roles = await card.locator('[data-l4-more] button[data-l4-role]').evaluateAll((bs) => bs.map((b) => b.getAttribute('data-l4-role')))
        const order = ['primary', 'edit', 'recategorise', 'aside']
        expect(roles.map((r) => order.indexOf(r)), k).toEqual([...roles.map((r) => order.indexOf(r))].sort((a, b) => a - b))
      }
      await page.locator(`[data-l4-group-settle="${k}:held"]`).click()
      const pv = page.locator(`[data-l4-batch-preview="${k}:held"]`)
      await expect(pv, k).toContainText('Preview & Settle Batch')
      await expect(pv.locator('[data-l4-settle]'), k).toHaveCount(settleChoices(k, QUEUES[k]).length ? 1 : 0)
      await pv.locator('[data-l4-batch-close]').click()
    }
  })

  test('Preview & Settle Batch settles a group with one decision only after the reason and the typed confirmation', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1000 })
    await mockAdmin(page, { rank: 6 })
    const calls = []
    const kinds = { site_down: { label: 'Site down', order: 1, choices: QUEUES.site_down } }
    const it = (r) => ({ kind: 'site_down', ref: r, provider_id: 'p1', provider: 'Demo University', subject: `Site ${r}`, created_at: '2026-11-15T01:00:00Z', why: 'Website did not answer: home page not read (fetch_failed)', detail: {} })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON(); calls.push(b)
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 2, universities: 1, late: 0, by_kind: { site_down: { n: 2 } } } })
      if (b.p_action === 'rule_groups') return route.fulfill({ json: { kind: 'site_down', built_in: true, total: 2, batch_max: 50, ms: 5, groups: [{ key: 'site_down:website did not answer', label: 'Website did not answer', n: 2, late: 0, refs: ['s1', 's2'] }] } })
      if (b.p_action === 'rule_group_items') return route.fulfill({ json: { items: b.p_args.refs.map(it), ms: 3 } })
      if (b.p_action === 'decide') return route.fulfill({ json: { ok: true } })
      return route.fulfill({ json: {} })
    })
    await page.goto('/#layer-4-review')
    await page.locator('[data-l4-group-settle="site_down:website did not answer"]').click()
    const pv = page.locator('[data-l4-batch-preview="site_down:website did not answer"]')
    await pv.locator('[data-l4-settle-choice]').selectOption('wait')
    await pv.locator('[data-l4-settle-reason]').fill('The sites answer again after the weekend')
    await expect(pv.locator('[data-l4-settle-go]')).toBeDisabled()
    await pv.locator('[data-l4-settle-typed]').fill('SETTLE 2')
    await pv.locator('[data-l4-settle-go]').click()
    await expect(pv.locator('[data-l4-batch-run="done"]')).toContainText('Settled 2 of 2: wait')
    const d = calls.filter((x) => x.p_action === 'decide').map((x) => x.p_args)
    expect(d).toEqual([{ kind: 'site_down', ref: 's1', choice: 'wait', reason: 'The sites answer again after the weekend', value: '' }, { kind: 'site_down', ref: 's2', choice: 'wait', reason: 'The sites answer again after the weekend', value: '' }])
  })
})
