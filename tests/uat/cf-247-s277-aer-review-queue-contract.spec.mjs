// Guards: Platform Admin directions 4 Nov 2026 10:00 §3-§4 and 12:16 (RMIT AER settlement: four settlement classes from stored records, deterministic
// repeats not re-read, review-ready first, a readable recovery case, the university summary, submitted/saved/admitted/published counts) and 10:00 (AER: reviewer-ready items separated from technical recovery; a university-by-
// university review queue in the existing Layer 4 Inbox with the review packet on each card; one item-level decision and audit event at a time,
// no bulk approval, no AI admission authority; exclusive ownership through pipeline.layer4_review_owners; held reads classified and routed, with
// one deduplicated Human-assisted recovery intervention where no automatic remedy can fix them; the E13 recovery pilot bounded to listed
// universities and a total, never re-reading unchanged evidence it cannot fix; wc.aer_fair_on evaluated, not switched). The behaviour runs on a
// production-shaped seed by tests/fixtures/aer-review-queue/run.sh (scratch PostgreSQL 16; live md5s checked; applied twice). This spec holds
// the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = 'supabase/migrations/20261104530000_cf247_aer_review_queue.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/aer-review-queue'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const seed = fs.readFileSync(`${FX}/seed.sql`, 'utf8')

test('one md5-guarded edit; the Inbox functions and the recovery detail are not edited; called definitions checked', () => {
  expect(m).toContain("select pg_temp.edit_once('security.aer_e13_recover_v1(boolean)', '90f80d59db94e29aab3fc520d1c99be6', '1bd8be8be44d5cd6e25a41a337b43f61'")
  expect(m).toContain('--   security.aer_e13_recover_v1(boolean) 90f80d59db94e29aab3fc520d1c99be6 -> 1bd8be8be44d5cd6e25a41a337b43f61')
  expect(m).toContain("('security.layer4_intervention_raise_v1(jsonb)', '8fcabf1137cf126158c260759ac9f9aa')")
  expect(m).not.toMatch(/edit_once\('(security\.layer4_inbox_items_v[12]|public\.admin_layer4_inbox|security\.layer4_aer_recovery_detail_v1)/)
  expect(m).not.toMatch(/create or replace function (security\.layer4_inbox_items_v[12]|public\.admin_layer4_inbox|security\.layer4_aer_recovery_detail_v1)\(/)
  expect(run).toContain('the migration changed a function it does not own')
  expect(run).toContain('the second run changed the hook register')
})

test('the review card: the packet through the existing aer_review extend hook, then the recovery detail unchanged and isolated', () => {
  expect(m).toContain("update pipeline.layer4_inbox_kind_hooks set detail_fn = 'security.layer4_aer_review_detail_v1(text)'")
  expect(m).toContain("where kind = 'aer_review' and mode = 'extend' and detail_fn = 'security.layer4_aer_recovery_detail_v1(text)'")
  expect(m).toContain('h := security.layer4_aer_recovery_detail_v1(p_ref);')
  for (const k of ["'University'", "'Course'", "'Qualification'", "'Country'", "'Audience'", "'Stored copy'", "'Recommended decision'", "'If approved'", "'If rejected'", "'Owner'", "'Queue'"])
    expect(m).toContain(k)
  expect(fixtures).toContain('the recovery detail failing (time-out) leaves the review card')
})

test('no gate per row: the packet uses the stored gate while current; queue, position and generator read stored classes', () => {
  expect(m).toContain("if x.gate_checked_at is not null and x.gate_checked_at > now() - make_interval(mins => security.pipeline_num_v1('layer4.readiness_recheck_minutes', 120)::int) then")
  const queue = m.slice(m.indexOf('create or replace function security.layer4_aer_queue_v1'), m.indexOf('create or replace function public.admin_layer4_aer_queue'))
  const gen = m.slice(m.indexOf('create or replace function security.har_aer_item_generate_v1'), m.indexOf('update pipeline.layer4_intervention_handlers'))
  for (const body of [queue, gen]) { expect(body).not.toContain('course_entry_gate_v1('); expect(body).not.toContain('entry_matrix_gate_v1(') }
  expect(fixtures).toContain('the queue position of a university with 303 items is read from stored classes: no gate per row')
})

test("decisions stay the Inbox's, one at a time; the queue is read only; ownership is exclusive", () => {
  expect(m).not.toMatch(/course_entry_review_apply_v1\(|entry_matrix_review_apply_v1\(|insert into pipeline\.layer4_decisions/)
  expect(m).toContain("raise exception 'Pipeline Operator or above required' using errcode = '42501'")
  expect(m).toContain("if v_other is not null then return jsonb_build_object('claimed', false, 'reason', 'held by ' || v_other); end if;")
  expect(fixtures).toContain('no item decided, no row admitted, no Layer 4 item opened or closed')
})

test('routing: one deduplicated intervention only where no automatic remedy can fix the read; the pilot never re-reads unchanged evidence', () => {
  expect(m).toContain("update pipeline.layer4_intervention_handlers set generate_fn = 'security.har_aer_item_generate_v1(integer)', generate_switch = 'har.generate_aer_item_on'")
  expect(m).toContain('v_res := security.layer4_intervention_raise_v1(')
  expect(m).toContain("(not coalesce(h.stored, false) or h.refused_same or h.tries >= v_tries)")
  expect(m).toContain("where s.old_item_id = i.id and s.state = 'refused' and (fe.evidence_id is null or fe.evidence_id = pg.evidence_id))")
  expect(m).toContain("and co.provider_id::text = any (v_prov)")
  expect(m).toMatch(/'aer\.e13_recover_total_max'[\s\S]*?'number', to_jsonb\(40\)/)
  expect(m).toContain("raise exception 'post-check: aer.e13_recover_on must stay off'")
  expect(m).not.toMatch(/'wc\.aer_fair_on'[^\n]*to_jsonb|set value = '1' where key = 'wc\.aer_fair_on'/)
})

test('the fixture is production-shaped: the live gate split, repeated keys, refused tries, an owner, a lock, active rows', () => {
  expect(run).toContain('$P -d $DB -f $TF/seed.sql')
  expect(seed).toContain('as live 11:16: 2 runs complete, 17 held for dropped published rows (or unscaled values), 22 held only for rows to leave out')
  expect(seed).toContain("'chatgpt', 'university review'")
  expect(fixtures).toContain('every one of the 605 items is in one of the four classes')
  expect(seed).toContain('the Diploma of Commerce shape (live 12:18)')
})

test('RMIT settlement (12:16): four classes from stored records; a row-limit repeat waits for the row boundary, never another read or a rows request', () => {
  const st = m.slice(m.indexOf('create or replace function security.aer_settlement_v1'), m.indexOf('create or replace function security.layer4_aer_queue_v1'))
  for (const c of ["'ready'", "'recoverable'", "'needs_input'", "'stale'"]) expect(st).toContain(c)
  expect(st).not.toContain('course_entry_gate_v1(')
  expect(st).toContain("when r.rt->>'class' = 'drops_uncovered' and r.refusal ilike '%row limit%' then 'row_limit_stored'")
  expect(m).toContain("and coalesce(h.refusal, '') not ilike '%row limit%' and coalesce(h.refusal, '') not ilike '%proof does not admit%'")
  expect(fixtures).toContain('two refusals for the row limit on the same copy: a row boundary is the next action (9 stored rows; no new read)')
  expect(fixtures).toContain('the E13 pilot never picks them')
})

test('the Inbox: ready first, a university summary, a readable recovery case; counts for the execution register', () => {
  const ui = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
  expect(ui).toContain("supabase.rpc('admin_layer4_aer_queue'")
  for (const a of ['data-l4-aer-summary', 'data-l4-aer-ready-first', 'data-l4-aer-ready', 'data-l4-case', 'data-l4-related']) expect(ui).toContain(a)
  expect(ui).not.toMatch(/<dd>\{b!==null&&typeof b==='object'\?JSON\.stringify\(b\)/)
  expect(ui).toContain('<HookValue v={b} label={a}/>')
  expect(m).toContain("if coalesce(p_args, '{}'::jsonb) ? 'summary_provider_id' then return security.layer4_aer_university_summary_v1(")
  expect(m).toContain('create or replace function security.aer_progress_counts_v1(p_since timestamptz, p_provider uuid default null) returns jsonb')
  expect(fixtures).toContain('after one approval: submitted 1, saved 1, admitted 3 rows of 1 course, published 1')
})

// direction 12:16 §5, §7, §8 at phone width: the university's AER summary, review-ready items first (from the queue, decided by the Inbox's own
// decide action), and a recovery case as a sentence with related items, never raw JSON. Mocked admin; nothing reaches a real backend.
const KINDS = { aer_review: { label: 'Entry requirements (AER)', order: 17, extension: 'aer_review:extend', detail: true, choices: [
  { key: 'approve', label: 'Approve all rows', rank: 6, returns: 'Active' }, { key: 'reject', label: 'Reject the read', rank: 6, returns: 'Withdrawn' }] } }
const UNI = { provider_id: 'rmit', name: 'RMIT University (RMIT)', country: 'AU', courses: 507, n: 303, oldest: '2026-10-29T00:00:00Z', late: false, by_kind: { aer_review: 303 } }
const SUMMARY = { provider_id: 'rmit', pending: 303, review_ready: 91, technically_held: 27, human_input_required: 184, stale: 1, unresolved: 212, human_input_open: 3, admitted_courses: 1, admitted_matrix_rows: 380 }
const held = { kind: 'aer_review', ref: 'h1', provider_id: 'rmit', subject: 'Diploma of Commerce', why: 'Entry requirements to review', created_at: '2026-10-29T00:00:00Z', o: 17, detail: { field_code: 'course_entry_first_read' } }
const ready = (i) => ({ kind: 'aer_review', ref: `r${i}`, provider_id: 'rmit', subject: `Ready course ${i}`, why: 'Entry requirements to review', created_at: `2026-10-3${i}T00:00:00Z`, ready: true, detail: { field_code: 'course_entry_first_read' } })
test.describe('settlement on a phone @responsive', () => {
  test('RMIT: the AER summary, ready items first, and a readable recovery case with its related items', async ({ page }) => {
    const w = page.viewportSize()?.width || 9999
    expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(480)
    await mockAdmin(page, { rank: 6 }); const decides = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON(); const a = b.p_args || {}
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 303, universities: 1, late: 0, by_kind: { aer_review: { n: 303 } }, paging: { items: 25, universities: 25, detail_parallel: 2 } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [UNI] } })
      if (b.p_action === 'items') return route.fulfill({ json: { total: 303, before: 0, more: true, items: [held] } })
      if (b.p_action === 'detail') {
        const ref = a.items[0].ref
        const hook_detail = ref === 'h1'
          ? { sections: [{ key: 'summary', title: 'Summary', body: { Class: 'Needs evidence, input or a decision', Failure: 'the corrected read kept every printed requirement (9 rows) but is over the row limit; a re-read gives the same result', 'Next action': 'a row boundary for the university (entry.max_rows_by_provider, Platform Admin); no new re-read until then' } },
                         { key: 'case', title: 'Recovery case', body: { Case: 'the reader dropped 2 printed requirement(s)', 'Other waiting reads of this university and kind': { count: 2, first: [{ ref: 'r0', subject: 'Ready course 0' }, { ref: 'zz', subject: 'Bachelor of Design' }] } } }],
              actions: [] }
          : { sections: [{ key: 'summary', title: 'Summary', body: { Class: 'Ready for a decision', 'Next action': 'decide it in Layer 4: Approve all rows or Reject the read' } }], actions: [] }
        return route.fulfill({ json: { items: [{ kind: 'aer_review', ref, detail: {}, hook_detail }] } })
      }
      if (b.p_action === 'decide') { decides.push(a); return route.fulfill({ json: { ok: true, returns: 'Done', event_id: 7 } }) }
      return route.fulfill({ json: {} })
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_aer_queue', async (route) => {
      const a = route.request().postDataJSON().p_args || {}
      if (a.summary_provider_id) return route.fulfill({ json: SUMMARY })
      return route.fulfill({ json: { ready: 91, limit: 25, offset: 0, items: [ready(0), ready(1)] } })
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/layer4_aer_review_read', (route) => route.fulfill({ json: { kind: 'course_entry_first_read', status: 'pending', completeness_gate: { complete: true }, rows: [] } }))
    await page.goto('/#layer-4-review')
    await page.locator('[data-l4-uni="RMIT University (RMIT)"] [data-l4-pill="aer_review"]').click()
    await expect(page.locator('[data-l4-aer-summary]')).toContainText('303 pending · 91 ready to decide · 27 technically held · 184 need evidence or input')
    await expect(page.locator('[data-l4-aer-ready-first]')).toHaveAttribute('aria-pressed', 'true')
    await expect(page.locator('[data-l4-aer-ready] [data-l4-item]')).toHaveCount(2)
    await expect(page.locator('[data-l4-aer-ready] [data-l4-item]').first()).toContainText('Ready course 0')
    await page.locator('[data-l4-aer-all]').click()
    const card = page.locator('[data-l4-ref="h1"]')
    await expect(card.locator('[data-l4-section="summary"]')).toContainText('over the row limit')
    await card.locator('[data-l4-section="case"] summary').first().click()
    const caseBox = card.locator('[data-l4-case]')
    await expect(caseBox).toContainText('2 other waiting reads')
    await expect(card.locator('[data-l4-section="case"]')).not.toContainText('{"count"')
    await caseBox.locator('summary').click()
    await expect(caseBox.locator('[data-l4-related-ref="zz"]')).toContainText('Bachelor of Design')
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
    expect(decides).toHaveLength(0)
  })
})
