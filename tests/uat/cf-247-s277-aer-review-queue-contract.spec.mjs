// Guards: Platform Admin direction 4 Nov 2026 10:00 §3 and §4 (AER: reviewer-ready items separated from technical recovery; a university-by-
// university review queue in the existing Layer 4 Inbox with the review packet on each card; one item-level decision and audit event at a time,
// no bulk approval, no AI admission authority; exclusive ownership through pipeline.layer4_review_owners; held reads classified and routed, with
// one deduplicated Human-assisted recovery intervention where no automatic remedy can fix them; the E13 recovery pilot bounded to listed
// universities and a total, never re-reading unchanged evidence it cannot fix; wc.aer_fair_on evaluated, not switched). The behaviour runs on a
// production-shaped seed by tests/fixtures/aer-review-queue/run.sh (scratch PostgreSQL 16; live md5s checked; applied twice). This spec holds
// the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104490000_cf247_aer_review_queue.sql'
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
  expect(fixtures).toContain("ready: 169 complete course reads, 25 with rows to leave out, 2 complete and 22 except-only matrix runs")
  expect(fixtures).toContain('held by route: row limit 162, identity 45, matrix source 17')
})
