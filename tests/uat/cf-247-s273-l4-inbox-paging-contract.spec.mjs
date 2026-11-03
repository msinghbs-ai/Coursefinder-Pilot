// Guards: Layer 4 Inbox performance (Platform Admin 4 Nov 2026 06:53 §1 and §6) and AER pill navigation, E13 card and recovery hooks (06:58 §1 to §4): bounded first reads, paging per university and kind, lazy detail, kind hooks
// Migration 20261104440000; contract admin docs/platform/ui-audit/2026-11-04-layer4-inbox-paging-contract.md. Performance and exactly-once
// paging are proved at production scale by tests/fixtures/l4-inbox-perf (PostgreSQL 16). Mocked admin here; nothing reaches a real backend.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const m = fs.readFileSync('supabase/migrations/20261104440000_cf247_l4_inbox_paging.sql', 'utf8')
const fx = fs.readFileSync('tests/fixtures/l4-inbox-perf/fixtures.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')
const screenFn = code(m.slice(m.indexOf("CREATE OR REPLACE FUNCTION public.admin_layer4_inbox"), m.indexOf("-- 7 component register")))

test('md5-guarded replacements of the live definitions; items_v1 keeps its output from one definition', () => {
  expect(m).toContain("select pg_temp.replace_once('security.layer4_inbox_items_v1()', '4fc05d14f4ba49335ff90496a20f582d', '2fa8b921d19f05dbd147f6833c71b784', $def$")
  expect(m).toContain("select pg_temp.replace_once('public.admin_layer4_inbox(text,jsonb)', '1fb975482d29c7c9f1ecdf3cdb011a10', '29705b99108e7a0b4d68fea398565d36', $def$")
  expect(m).toContain('select * from security.layer4_inbox_items_v2(null, null, null, true)')
  expect(fx).toContain("raise exception 'F1: items_v1 output changed (% missing, % new)'")
})

test('first reads are bounded: no screen read builds every item; counts without detail; a page is built for its own items only', () => {
  expect(screenFn).not.toContain('create temp table')
  expect(screenFn).not.toContain('security.layer4_inbox_items_v1()')
  expect(screenFn).toContain('security.layer4_inbox_counts_v1(v_target)')
  expect(m).toContain('from security.layer4_inbox_items_v2(null, null, null, false) i group by 1, 2')
  // keys first without detail, then the detail of the page's keys only
  expect(screenFn).toContain('from security.layer4_inbox_items_v2(v_prov, v_bkind, null, false) i join k on k.kind = i.kind')
  expect(screenFn).toContain('from security.layer4_inbox_items_v2(v_prov, v_bkind, v_keys, true) i')
  // a decision finds its one item by key
  expect(screenFn).toContain("from security.layer4_inbox_items_v2(null, v_kind, array[v_kind || ':' || v_ref], true) i;")
  // filters inside each source, before anything is built
  expect(m).toContain("and (p_provider_id is null or z.pid = p_provider_id) and (p_kind is null or z.k = p_kind)")
  // the same cursor (UR-04) and the same page-size bound
  expect(screenFn).toContain("v_ao := (p_args->>'after_o')::int; v_aat := (p_args->>'after_at')::timestamptz; v_ak := p_args->>'after_kind'; v_ar := p_args->>'after_ref';")
  expect(screenFn).toContain("v_lim := least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200);")
  for (const k of ['layer4.inbox_page_size', 'layer4.inbox_universities_page_size', 'layer4.inbox_detail_parallel', 'layer4.inbox_hooks_on']) expect(m).toContain(`'${k}'`)
  // proved at production scale: the budget, every item exactly once by university and by kind
  expect(fx).toContain('insert into fx.budget values (300);')
  for (const s of ["'F4: an item was shown twice'", "'F5: an item was shown twice'", "'F3: % took % ms (budget % ms)'"]) expect(fx).toContain(s)
})

test('decisions, choices and audit unchanged; kind hooks are found in schema security only, decide and audit themselves, and never break the Inbox', () => {
  for (const s of ["if v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;",
    "if v_rank < coalesce((v_c->>'rank')::int, 4) then raise exception 'your role cannot make this choice' using errcode = '42501'; end if;",
    "insert into pipeline.admin_control_events(area, action, target, detail, actor)\n  values ('layer4', 'inbox_decide', v_kind || ':' || v_ref,",
    "v_r := public.layer4_review_decide(v_ref::uuid, case v_choice when 'keep' then 'reject' when 'use' then 'approve' else 'edit_and_approve' end, v_reason,"]) expect(screenFn).toContain(code(s))
  expect(m).toContain("where p.oid = pg_catalog.to_regprocedure(p_sig) and n.nspname = 'security'")
  expect(m).toContain("and (h.mode = 'kind' or not exists (select 1 from jsonb_array_elements(v_builtin->h.kind->'choices') b where b->>'key' = c->>'key'))")
  expect(screenFn).toContain("if v_c ? 'hook' then")
  expect(m).toContain("('intervention', 'kind', 'security.layer4_intervention_kind_v1()', 'security.layer4_intervention_inbox_counts_v1()', 'security.layer4_intervention_inbox_page_v1(jsonb)'")
  expect(m).toContain("('aer_review', 'extend', 'security.layer4_aer_recovery_kind_v1()', null, null, 'security.layer4_aer_recovery_detail_v1(text)'")
  expect(fx).toContain("raise exception 'F8: approve reached the recovery hook'")
  expect(fx).toContain("raise exception 'F9: a failing page broke the items'")
})

// the mocked Inbox: one university with two AER items and five course links, and a registered kind
const KINDS = {
  course_link: { label: 'Course link', order: 1, choices: [{ key: 'keep', label: 'Keep the page we hold', returns: 'Closed' }, { key: 'use', label: 'Use the new page', returns: 'Used' }, { key: 'enter', label: 'Enter another address', input: 'url', returns: 'Entered' }] },
  aer_review: { label: 'Entry requirements (AER)', order: 17, extension: 'aer_review:extend', detail: true, choices: [
    { key: 'approve', label: 'Approve all rows', rank: 6, returns: 'Active' }, { key: 'approve_except', label: 'Approve except…', rank: 6, input: 'rows', returns: 'Active except' },
    { key: 'reject', label: 'Reject the read', rank: 6, returns: 'Withdrawn' },
    { key: 'reread_stored', label: 'Re-read from stored evidence', returns: 'Read again from the stored copy', hook: 'aer_review:extend' },
    { key: 'ai_analyse', label: 'Ask AI to analyse the failure', returns: 'Analysed', hook: 'aer_review:extend' }] },
  intervention: { label: 'Human input needed', order: 20, hook: 'intervention:kind', detail: true, choices: [
    { key: 'supply', label: 'Supply the fact', input: 'text', returns: 'The work resumes', hook: 'intervention:kind' },
    { key: 'close', label: 'Close', rank: 5, returns: 'Closed', hook: 'intervention:kind' }] },
}
const UNI = { provider_id: 'p1', name: 'UNSW Sydney', country: 'AU', courses: 667, n: 8, oldest: '2026-10-19T00:00:00Z', late: false, by_kind: { course_link: 5, aer_review: 2, intervention: 1 } }
const aerItem = (i) => ({ kind: 'aer_review', ref: `a${i}`, provider_id: 'p1', subject: i ? 'Bachelor of Actuarial Studies (Honours)' : 'Bachelor of Actuarial Studies', why: 'Entry requirements to review', created_at: `2026-10-2${i}T00:00:00Z`, late: false, o: 17, detail: { field_code: 'course_entry_first_read' } })
const AER_READ = { kind: 'course_entry_first_read', status: 'pending', evidence_id: 'e1', lineage: { source_url: 'https://www.unsw.edu.au/study/actuarial' },
  completeness_gate: { complete: false, reasons: ['requirements were dropped during extraction'], drops_uncovered: [{ id: 'd1' }, { id: 'd2' }], rows_cut: 0 },
  rows: [{ id: 'r1', status: 'proposed', kind: 'atar', description: 'ATAR 95', score: 95 }] }

async function inbox(page, { calls, aerCalls, delay = 0, decide } = {}) {
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
    const b = route.request().postDataJSON(); calls?.push(b)
    const a = b.p_args || {}
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 8, universities: 1, late: 0, by_kind: { course_link: { n: 5 }, aer_review: { n: 2 }, intervention: { n: 1 } }, paging: { items: 25, universities: 25, detail_parallel: 2 } } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [UNI] } })
    if (b.p_action === 'items') {
      const all = [...[0, 1, 2, 3, 4].map((i) => ({ kind: 'course_link', ref: `c${i}`, provider_id: 'p1', subject: `Course ${i}`, why: 'Different page', created_at: '2026-10-19T00:00:00Z', late: false, o: 1, detail: { before: ['https://unsw.edu.au/a'], proposed: ['https://unsw.edu.au/b'] } })),
        aerItem(0), aerItem(1),
        { kind: 'intervention', ref: '41', provider_id: 'p1', subject: 'Fee year missing', why: 'Needs a fact', created_at: '2026-11-03T00:00:00Z', late: false, o: 20, hook: true, detail: {} }]
      const list = all.filter((x) => !a.kind || x.kind === a.kind)
      return route.fulfill({ json: { total: list.length, before: 0, more: false, items: list.slice(0, a.limit) } })
    }
    if (b.p_action === 'detail') {
      const it = a.items[0]
      const hook_detail = it.kind === 'intervention'
        ? { sections: [{ key: 'issue', title: 'Issue', body: 'The fee year is not printed' }, { key: 'recommended', title: 'Recommended', body: { action: 'Supply the fee year' } }], actions: [{ key: 'supply', allowed: true }, { key: 'close', allowed: false }] }
        : { sections: [{ key: 'recovery', title: 'Recovery', body: { owner: 'AER reader', next_attempt: 'after the evidence arrives', last_attempt: 'dropped 2 requirements', human_input_needed: 'no' } }], actions: [{ key: 'reread_stored', allowed: true }, { key: 'ai_analyse', allowed: false }] }
      return route.fulfill({ json: { items: [{ kind: it.kind, ref: it.ref, detail: {}, hook_detail }] } })
    }
    if (b.p_action === 'decide') return route.fulfill({ json: decide ? decide(a) : { ok: true, returns: 'Done', event_id: 9 } })
    return route.fulfill({ json: {} })
  })
  let inflight = 0
  await page.route('https://example.supabase.co/rest/v1/rpc/layer4_aer_review_read', async (route) => {
    inflight++; aerCalls?.push({ id: route.request().postDataJSON().p_review_item_id, inflight })
    if (delay) await new Promise((r) => setTimeout(r, delay))
    inflight--
    return route.fulfill({ json: AER_READ })
  })
}

test.describe('mocked browser', () => {
  test('a kind pill shows only that university\'s waiting items of that kind, with the exact count; it stays through refresh, decisions and a reload; the name shows every kind', async ({ page }) => {
    await mockAdmin(page, { rank: 6 }); const calls = []
    await inbox(page, { calls })
    await page.goto('/#layer-4-review')
    await expect(page.locator('[data-l4-inbox]')).toBeVisible()
    const items = () => calls.filter((c) => c.p_action === 'items')
    await expect.poll(() => items().length).toBeGreaterThan(0)
    expect(items()[0].p_args).toEqual({ provider_id: 'p1', limit: 25 })
    expect(calls.find((c) => c.p_action === 'universities').p_args).toMatchObject({ limit: 25 })
    await page.locator('[data-l4-uni="UNSW Sydney"] [data-l4-pill="aer_review"]').click()
    await expect(page.locator('[data-l4-pending]')).toContainText('2 waiting Entry requirements (AER)')
    await expect(page.locator('[data-l4-pending]')).not.toContainText('667')
    expect(items().at(-1).p_args).toEqual({ provider_id: 'p1', kind: 'aer_review', limit: 25 })
    await expect(page.locator('[data-l4-item]')).toHaveCount(2)
    await expect(page.locator('[data-l4-item="course_link"]')).toHaveCount(0)
    // refresh and a decision keep the pill
    await page.getByRole('button', { name: 'Refresh' }).click()
    await expect.poll(() => items().at(-1).p_args).toEqual({ provider_id: 'p1', kind: 'aer_review', limit: 25 })
    const card = page.locator('[data-l4-item="aer_review"]').first()
    await card.locator('[data-l4-choice="reread_stored"]').click()
    await card.getByLabel('Reason').fill('Two requirements were dropped: read the stored copy again')
    const n = items().length
    await card.locator('[data-l4-confirm]').click()
    await expect.poll(() => items().length).toBeGreaterThan(n)
    expect(items().at(-1).p_args).toMatchObject({ provider_id: 'p1', kind: 'aer_review' })
    // a reload keeps the university and the pill (this browser tab)
    await page.reload()
    await expect(page.locator('[data-l4-pending]')).toContainText('2 waiting Entry requirements (AER)')
    // the name shows every kind again
    await page.locator('[data-l4-uni-name="UNSW Sydney"]').click()
    await expect(page.locator('[data-l4-pending]')).toContainText('8 waiting review items')
    expect(items().at(-1).p_args).toEqual({ provider_id: 'p1', limit: 25 })
  })

  test('E13: approval stays held; the card counts waiting rows and dropped requirements apart, shows the recovery detail, and offers only the recovery choices allowed', async ({ page }) => {
    await mockAdmin(page, { rank: 6 }); const calls = []
    await inbox(page, { calls })
    await page.goto('/#layer-4-review')
    await page.locator('[data-l4-uni="UNSW Sydney"] [data-l4-pill="aer_review"]').click()
    const card = page.locator('[data-l4-item="aer_review"]').first()
    await expect(card.locator('[data-l4-aer-gate="held"]')).toContainText('Requirements were dropped during extraction')
    await expect(card.locator('[data-l4-aer-e13-counts]')).toContainText('1 waiting row · 2 dropped requirements')
    await expect(card.locator('[data-l4-choice="approve"]')).toBeDisabled()
    await expect(card.locator('[data-l4-choice="approve_except"]')).toBeDisabled()
    await expect(card.locator('[data-l4-choice="reject"]')).toBeEnabled()
    await expect(card.locator('[data-l4-choice="reread_stored"]')).toBeEnabled()
    await expect(card.locator('[data-l4-choice="ai_analyse"]')).toHaveCount(0)
    await expect(card.locator('[data-l4-section="recovery"]')).toContainText('Recovery')
    await expect(card.locator('[data-l4-section="recovery"]')).not.toHaveAttribute('open', '')
    await card.locator('[data-l4-section="recovery"] summary').click()
    await expect(card.locator('[data-l4-section="recovery"]')).toContainText('after the evidence arrives')
  })

  test('a registered kind: its detail is read lazily, only allowed choices show, text input is a text area, ok false shows what is still needed', async ({ page }) => {
    await mockAdmin(page, { rank: 6 }); const calls = []
    let tries = 0
    await inbox(page, { calls, decide: (a) => (++tries === 1 ? { ok: false, request: 'Enter the fee year as printed on the page' } : { ok: true, returns: 'The work resumes', event_id: 12 }) })
    await page.goto('/#layer-4-review')
    await page.locator('[data-l4-uni="UNSW Sydney"] [data-l4-pill="intervention"]').click()
    const card = page.locator('[data-l4-item="intervention"]')
    await expect(card.locator('[data-l4-section="issue"]')).toContainText('Issue')
    expect(calls.filter((c) => c.p_action === 'detail').map((c) => c.p_args.items)).toContainEqual([{ kind: 'intervention', ref: '41' }])
    await expect(card.locator('[data-l4-choice="supply"]')).toBeVisible()
    await expect(card.locator('[data-l4-choice="close"]')).toHaveCount(0)
    await card.locator('[data-l4-choice="supply"]').click()
    await expect(card.locator('textarea[data-l4-text]')).toBeVisible()
    await card.getByLabel('Reason').fill('Fee year from the page')
    await card.locator('[data-l4-confirm]').click()
    await expect(card.locator('[data-l4-request]')).toContainText('Enter the fee year as printed on the page')
    await card.locator('textarea[data-l4-text]').fill('2026')
    await card.locator('[data-l4-confirm]').click()
    await expect(page.getByRole('status').first()).toContainText('Done.')
    expect(calls.filter((c) => c.p_action === 'decide').at(-1).p_args).toMatchObject({ kind: 'intervention', ref: '41', choice: 'supply', value: '2026' })
  })

  test('AER rows are read only when their card is on screen, a set number at once', async ({ page }) => {
    await mockAdmin(page, { rank: 6 }); const aerCalls = []
    await page.setViewportSize({ width: 1440, height: 700 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON()
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 25, universities: 1, late: 0, by_kind: { aer_review: { n: 25 } }, paging: { items: 25, universities: 25, detail_parallel: 2 } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ ...UNI, by_kind: { aer_review: 25 } }] } })
      if (b.p_action === 'items') return route.fulfill({ json: { total: 25, before: 0, more: false, items: Array.from({ length: 25 }, (_, i) => ({ ...aerItem(i % 2), ref: `a${i}` })) } })
      if (b.p_action === 'detail') return route.fulfill({ json: { items: [{ kind: 'aer_review', ref: b.p_args.items[0].ref, detail: {}, hook_detail: { sections: [], actions: [] } }] } })
      return route.fulfill({ json: {} })
    })
    let inflight = 0, max = 0
    await page.route('https://example.supabase.co/rest/v1/rpc/layer4_aer_review_read', async (route) => {
      inflight++; max = Math.max(max, inflight); aerCalls.push(route.request().postDataJSON().p_review_item_id)
      await new Promise((r) => setTimeout(r, 150)); inflight--
      return route.fulfill({ json: AER_READ })
    })
    await page.goto('/#layer-4-review')
    await expect(page.locator('[data-l4-item="aer_review"]').first().locator('[data-l4-aer-gate="held"]')).toBeVisible()
    await page.waitForTimeout(1500)
    expect(aerCalls.length, 'cards below the screen are not read yet').toBeLessThan(25)
    // a card skipped over is not read; each card scrolled to is
    for (let i = 0; i < 25; i++) await page.locator('[data-l4-item="aer_review"]').nth(i).scrollIntoViewIfNeeded()
    await expect.poll(() => aerCalls.length, { timeout: 15000 }).toBe(25)
    expect(max, 'at most the set number at once').toBeLessThanOrEqual(2)
  })
})

test.describe('phone @responsive', () => {
  test('Layer 4 Review at phone width: kind pills are tap targets, a pill filters the panel, nothing scrolls sideways', async ({ page }) => {
    await mockAdmin(page, { rank: 6 }); const calls = []
    const w = page.viewportSize()?.width || 9999
    expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(480)
    await inbox(page, { calls })
    await page.goto('/#layer-4-review')
    await expect(page.locator('[data-l4-inbox]')).toBeVisible()
    const pill = page.locator('[data-l4-uni="UNSW Sydney"] [data-l4-pill="aer_review"]')
    await pill.scrollIntoViewIfNeeded()
    const b = await pill.boundingBox()
    expect(b.height, 'tap target').toBeGreaterThanOrEqual(24)
    expect(b.x + b.width).toBeLessThanOrEqual(w + 1)
    await pill.click()
    await expect(page.locator('[data-l4-pending]')).toContainText('2 waiting Entry requirements (AER)')
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
  })
})
