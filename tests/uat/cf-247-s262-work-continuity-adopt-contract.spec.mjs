// Guards: CF-247 SS-021 work continuity adopted in the lanes the blocking audit ranked worst (overnight mandate 3 Nov 2026 21:59 §2 P0 work
// continuity and P1 AER, §3 acceptance; audit 2026-11-03-work-continuity-blocking-audit.md F4 IQ-00128, F3 IQ-00130, F9 IQ-00134, F2 IQ-00077).
// AER keeps its 600 limit unchanged but counts distinct review-ready decisions, takes universities in turn within a share and a reserve, and
// sends technically held and duplicate items to bounded technical recovery, never to an automatic decision; Find course pages work held by the
// paid search cap is parked until the reset and gives back its plan, and a task that can never run ends at once with its blocker; the fee
// reader claims page by page; course page searches are isolated and capped; the governed issue writer maps refused values instead of
// raising. Recording, parking and ending impossible work ship on; anything that changes admission or spend ships off. The behaviour runs on
// isolated fixtures by tests/fixtures/continuity-adopt/run.sh (scratch PostgreSQL 16; the edited and called definitions checked against their
// live md5s; applied, applied again unchanged; the §3 cases asserted). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104320000_cf247_work_continuity_adopt.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/continuity-adopt'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')

const EDITS = [
  ['security.integration_issue_upsert_v1(jsonb,text)', 'c5ce0cb9c431a337789d67bc1878be62'],
  ['security.work_review_room_v1(text)', 'a7542c70665220ba53a1d6e5bed05a1b'],
  ['security.aer_schedule_tick_v1(boolean)', 'bc28099db02a26344fae2527b624a8c7'],
  ['security.fee_reader_tick_v1()', '0c93b20de02d1714cd6672c259fddb20'],
  ['security.course_link_search_tick_v1(integer)', 'ffc9fb647925f689678a035cdd64b3e1'],
]

test('lands on the v2.15.443 contract; edits exactly five live functions, md5-guarded, with their before and after md5s', () => {
  expect(m).toContain("raise exception 'the SS-021 work continuity contract (migration 20261104170000) must be applied before this change'")
  for (const [sig, md5] of [['security.work_item_report_v1(text,text,text,text,jsonb)', '6a15318c0ecd6644b32f1883463c542e'],
    ['security.work_fair_pick_v1(text,text,jsonb,integer)', 'c1e63976b1ff6be67f5a4477baa09588'],
    ['security.work_item_eligible_v1(text,text,text)', '3d7b00a65efca566a464919c5aa3be6d'], ['security.lane_paid_hold_v1(text)', '99ec517b8b51b0d1305b739e7f1562fb']]) {
    expect(m).toContain(`('${sig}', '${md5}')`)
    expect(run).toContain(`["${sig}"]=${md5}`)
  }
  expect(m.match(/select pg_temp\.(edit_once|replace_once)\(/g)).toHaveLength(EDITS.length)
  for (const [sig, before] of EDITS) {
    const header = m.match(new RegExp(`^--   ${sig.replace(/[.()]/g, '\\$&')} +${before} -> ([0-9a-f]{32})$`, 'm'))
    expect(header, sig).not.toBeNull()
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${before}', '${header[1]}',`)
    expect(run).toContain(`["${sig}"]=${before}`)
  }
  expect(m).toContain('Not edited: security.provider_identity_check_v1')
  expect(m).not.toMatch(/edit_once\('security\.provider_identity_check_v1/)
  expect(m).toMatch(/^-- Replaces: security\.integration_issue_upsert_v1, security\.work_review_room_v1, security\.aer_schedule_tick_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(run).toContain('applied: only the five guarded edits changed existing functions')
  expect(run).toContain('applied twice: the second run changed nothing')
})

test('F4 AER: the limit is read, never raised; distinct review-ready decisions count; universities in turn; refreshes not gated', () => {
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings[^;]*aer\.schedule_layer4_max/)
  expect(m).toContain("v_lim numeric := security.pipeline_num_v1('aer.schedule_layer4_max', 600)")
  expect(m).toContain("update pipeline.work_review_categories set count_rule = 'distinct_ready', count_switch_key = 'wc.aer_fair_on'")
  expect(m).toContain("coalesce(w.readiness, 'judgement_ready') not in ('technical_blocked', 'resolvable', 'closed')")
  expect(m).toContain("from security.work_fair_pick_v1('aer', 'entry_read', coalesce(v_cands, '[]'::jsonb), p_room * 2) p")
  expect(m).toContain('where e.waiting + e.k <= v_share and (v_room > v_reserve or e.waiting = 0);')
  expect(m).toContain("if (not v_bp or v_fair) and v_aim is null and v_mxmax > 0 then")
  expect(m).toContain("('technical_hold', 'A Layer 4 item is held for a technical reason', 'retry_backoff', true, 'wc.aer_tech_max_attempts'")
  expect(m).toContain("('duplicate', 'A Layer 4 item duplicates an older waiting item', 'park', false")
  // nothing here decides, approves or writes a Layer 4 item
  expect(m).not.toMatch(/(update|insert into|delete from) pipeline\.layer4_review_items/)
  for (const s of ['F4 switch off: back-pressure stops new reads and refreshes, as before',
    'F4: same limit (10); 12 raw items are 5 distinct review-ready decisions (2 technically held, 5 duplicates not counted): room 5',
    'F4: one university cannot starve others', 'F4: decisions waiting plus reads in progress now equal the limit, never more',
    'F4: at the limit the next run starts no read (the limit is never bypassed)', 'F4: at the limit the due matrix refresh of P6 (nothing waiting) still runs',
    'F4: Layer 4 admission unchanged: no item created, decided, approved or changed (never an automatic entry approval)',
    'F4: a technically held item is parked after wc.aer_tech_max_attempts (3) re-checks, no endless retry', 'F4: the reserve keeps the last room',
    'AER at its limit: the fee worker is still called for its due page', 'AER at its limit: intake work with no review category is still selected'])
    expect(fixtures).toContain(s)
})

test('F3 Find course pages: parked through the shared report at the cap reset, released only behind its switch, impossible work ends at once', () => {
  expect(m).toContain("perform security.work_item_report_v1('page_find', r.pid::text, 'find', 'budget', jsonb_build_object('purpose', 'course_link_search'")
  expect(m).toContain('update pipeline.work_items w set next_eligible_at = v_at, updated_at = now()')
  expect(m).toContain("if security.pipeline_num_v1('wc.page_find_release_on', 0) >= 1 then")
  expect(m).toContain("perform security.job_outcome_set_v1(r.id, 'deferred_dependency'")
  expect(m).toContain("perform security.work_item_report_v1('page_find', r.pid::text, 'find', 'failed', jsonb_build_object('class', 'authority'")
  expect(m).not.toMatch(/(delete from|update) pipeline\.course_link_search[^;]*page_find/)
  for (const s of ['F3: a skip-listed task ends at once, failed, with its blocker (not held for 24 hours)',
    'F3: the capped task is parked as budget exhausted, next eligible at the cap reset, no attempt used', 'F3: an unchanged park is not reported again',
    'F3: wc.page_find_release_on 0: the parked task stays running (release ships off)',
    'F3: released, the parked task ends (deferred_dependency) and gives back its plan slot', 'F3: no queued search is removed or sent by the park',
    'F3: after the reset the lane resumes and the parked work is eligible again', 'F3: the re-planned task moving again records the recovery'])
    expect(fixtures).toContain(s)
})

test('F9 fee reader and course page search: page claims, per-search isolation, send cap and next-eligible time', () => {
  expect(m).toContain("and (case when security.pipeline_num_v1('wc.fee_item_claims_on', 0) >= 1")
  expect(m).toContain("      if not v_wc_on then raise; end if;")
  expect(m).toContain("elsif security.work_item_eligible_v1('course_link_search', r.course_id::text, 'search') then")
  expect(m).toContain("('search_unanswered', 'A course page search failed or went unanswered', 'retry_backoff', true, 'wc.link_search_max_attempts'")
  for (const s of ['F9 switch off: a live lease anywhere holds the fee worker (as before)', 'F9: with page claims, a due page is read while another page is leased',
    'F9 switch off: one bad answer body stops the whole run (as before)', 'F9: the good search is harvested and bound although two others fail in the same run',
    'F9: an unanswered search is recorded once and not re-sent before its next attempt', 'F9: a search unanswered for the third send ends in error and is parked (the send cap)',
    'F9: once due it is queued again for the search lane'])
    expect(fixtures).toContain(s)
})

test('F2 the governed issue writer maps refused values from the checks themselves and keeps what was sent', () => {
  expect(m).toContain("from pg_constraint c where c.conrelid = 'pipeline.integration_issues'::regclass and c.conname = p_check), true)")
  expect(m).toContain("v_unmapped := v_unmapped || jsonb_build_object('root_cause_class', v_rcc); v_rcc := 'unclassified'; end if;")
  expect(m).toContain("v_unmapped := v_unmapped || jsonb_build_object('workstream', v_ws); v_ws := 'A10'; end if;")
  expect(fixtures).toContain('F2: root_cause_class data, workstream G and validation layer V9 are mapped (unclassified, A10, manual) instead of raising')
  expect(fixtures).toContain('F2: an unknown severity still raises')
})

test('activation: recording, parking and ending impossible work ship on; admission and spend switches ship off', () => {
  for (const k of ['wc.page_find_park_on', 'wc.page_find_never_end_on', 'wc.link_search_continuity_on'])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace(/\./g, '\\.')}',[\\s\\S]*?'number', to_jsonb\\(1\\), 0, 1,`))
  for (const k of ['wc.aer_fair_on', 'wc.page_find_release_on', 'wc.fee_item_claims_on'])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace(/\./g, '\\.')}',[\\s\\S]*?'number', to_jsonb\\(0\\), 0, 1,`))
  expect(fixtures).toContain('shipped OFF: AER readiness counting, plan release and fee page claims (they change admission or spend)')
})
