// Guards: CF-247 P0 Layer 4 technical readiness and admission throughput (Platform Admin 3 Nov 2026 18:14 "Prioritise Layer 4 admission throughput";
// mandate 15:37 §10, acceptance mandate 15:52 §16-§17): every waiting Layer 4 item is classified judgement-ready, technically blocked (with the
// blocker and repair route) or resolvable by the platform; repeats, already-decided and already-active proposals and retired entities are settled
// only by supersession with a recorded reason and cover, behind switches that ship off; every approval is checked in the catalogue and the search
// projection; root causes and remedies go through workstream A's contract; nothing decides an item, weakens admission or touches a manual lock.
// The behaviour runs on isolated fixtures by tests/fixtures/ops-layer4/run.sh (scratch PostgreSQL; workstream A's real controller loaded from its
// migration; the called contract functions checked against the live md5s; the migration refused without A, applied, applied again unchanged;
// every case asserted). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104120000_cf247_ops_layer4_throughput.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/ops-layer4'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const seed = fs.readFileSync(`${FX}/seed.sql`, 'utf8')

test('codes against workstream A\'s live contract and edits no existing function', () => {
  expect(m).toContain("if to_regclass('pipeline.ops_remedies') is null then")
  expect(m).toContain("('security.integration_issue_upsert_v1(jsonb,text)', 'f292f65689a35e213a3d12a539c11b1d')")
  expect(m).not.toMatch(/edit_once|replace_once/)
  expect(m).toMatch(/^-- Replaces: nothing/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  for (const [sig, md5] of [['security.ops_remedy_register_v1(text,jsonb)', 'cec6cd2f6518b453fbc8ec3137ce39bd'], ['security.ops_root_cause_register_v1(text,jsonb)', '591616a6a0bd60d607f65c41c18e2968'],
    ['security.integration_issue_upsert_v1(jsonb,text)', 'f292f65689a35e213a3d12a539c11b1d'], ['security.pipeline_list_v1(text,jsonb)', 'c33c2152bbadc8d01625ced9bf2c9bda']])
    expect(run).toContain(`["${sig}"]=${md5}`)
  expect(run).toContain('supabase/migrations/20261104010000_cf247_ops_controller.sql')
  expect(run).toContain("without A's contract: refused, nothing left")
  expect(run).toContain('applied: no existing function changed')
  expect(run).toContain('applied twice: the second run changed nothing')
})

test('switches: classification and verification ship on; the arrival guard and settling ship off; the settle remedy is registered inactive', () => {
  for (const [k, v] of [['layer4.readiness_on', 1], ['layer4.verify_on', 1], ['layer4.arrival_guard_on', 0], ['layer4.reconcile_supersede_on', 0]])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}',[\\s\\S]*?'number', to_jsonb\\(${v}\\), 0, 1, 'on \\(1\\) or off \\(0\\)'`))
  expect(m).toContain("'layer4.platform_kinds'")
  expect(m).toContain('\'list\', \'["official_course_url", "provider_current_tuition_validation", "provider_current_tuition", "course_english"]\'::jsonb')
  expect(m).toMatch(/\('layer4_supersede_resolvable', jsonb_build_object\([\s\S]*?'authority', 'auto',[\s\S]*?'active', false,/)
  expect(m).toContain("perform cron.schedule('layer4-readiness', '22,52 * * * *', $j$select security.layer4_readiness_tick_v1()$j$);")
  expect(fixtures).toContain('R1 ok: readiness and verification on, arrival guard and settling off')
})

test('identity: the same question is the same page, fee or matrix source, so different sources are never duplicates (IQ-00038)', () => {
  expect(m).toContain("'#.*$', ''), '/+$', '')")
  expect(m).toContain("then coalesce(p_l2->>'entry_matrix_source_id', p_value->>'source_id', p_value->>'run_id', '') else '' end")
  expect(fixtures).toContain('I1 ok: identity keys (page, fee, matrix source)')
  expect(fixtures).toContain("raise exception 'C1: matrix sources (IQ-00038 shape: two sources, not duplicates)'")
  expect(m).toContain("('layer4_duplicate_distinct_sources', jsonb_build_object('class', 'rule'")
})

test('classification: blockers mirror what the apply refuses or a gate holds; gates are bounded; nothing is decided', () => {
  for (const code of ['manual_lock', 'invalid_link', 'evidence_missing', 'evidence_stale', 'value_moved', 'completeness_gate', 'nothing_to_admit'])
    expect(m).toContain(`'code', '${code}'`)
  expect(m).toContain("security.reference_url_has_use(v_url, 'not_course_page')")
  expect(m).toContain("v_gate := security.course_entry_gate_v1(i.id, '{}'::uuid[]);")
  expect(m).toContain("security.pipeline_num_v1('layer4.gate_batch', 20)")
  expect(fixtures).toContain('C1 ok: 19 items classified')
  expect(fixtures).toContain('C2 ok: settling off: all 19 items still wait; no decision, lock, link or fee changed')
  expect(fixtures).toContain('C3 ok: nothing reclassified inside the recheck time; layer4.gate_batch bounds gate calls; an unevaluated hold keeps holding')
})

test('settling is supersession only, with reason and cover; new evidence and non-platform kinds stay with a person; reversals stick', () => {
  expect(m).toContain("check (reason in ('duplicate_pending', 'decided_before', 'covered_by_active', 'entity_retired'))")
  expect(m).toContain("update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),")
  expect(m).not.toMatch(/set status = '(approved|edited_approved|rejected)'/)
  expect(m).not.toMatch(/(insert into|update|delete from) pipeline\.manual_locks/)
  expect(m).not.toMatch(/insert into pipeline\.layer4_decisions/)
  expect(m).toContain('and (p_evidence is null or i.evidence_id = p_evidence')
  expect(m).toContain('-- An item whose supersession the Platform Admin reversed is never settled again.')
  expect(fixtures).toContain('S1 ok: 5 superseded')
  expect(fixtures).toContain("S2 ok: the remedy supersedes inside A''s boundary; an approval is refused there")
  expect(fixtures).toContain('A1 ok: on: a repeat arrives superseded (after reroute)')
  expect(m).toMatch(/\('pipeline', 'layer4\.same_page_new_copy_settles',[\s\S]*?'number', to_jsonb\(0\), 0, 1,/)
  expect(fixtures).toContain('S3 ok: off: a newer copy waits for a person; on: settled as decided before (same page address, newer copy)')
  expect(fixtures).toContain('X1 ok: a curator is refused; the Platform Admin reverses')
  expect(fixtures).toContain('Z1 ok: no decision written, no lock touched, no catalogue value changed by any case')
  expect(seed).toContain('IQ-00040 shape')
})

test('every approval is checked in the catalogue and the projection; failures raise one issue per kind and reason and reach the controller', () => {
  expect(m).toContain("'reason', case when v_lock then 'manual_lock_kept'")
  expect(m).toContain("'l4_not_admitted:' else 'l4_not_published:' end || r.field_code || ':' || r.reason")
  for (const rc of ['layer4_approval_lock_conflict', 'layer4_approval_not_admitted', 'layer4_approval_not_published', 'layer4_regenerated_after_decision', 'layer4_orphan_pending', 'layer4_duplicate_pending'])
    expect(m).toContain(`('${rc}', jsonb_build_object(`)
  expect(m).toMatch(/\('layer4_admission_recheck', jsonb_build_object\([\s\S]*?'authority', 'auto',\n\s+'action_fn', 'security\.layer4_remedy_recheck_v1\(bigint\)', 'verify_fn', 'security\.layer4_remedy_recheck_verify_v1\(bigint\)'/)
  expect(m).toMatch(/\('layer4_lock_conflict_decision', jsonb_build_object\([\s\S]*?'authority', 'admin'/)
  expect(fixtures).toContain('V1 ok: admitted and shown; lock kept (approval never took effect)')
  expect(fixtures).toContain('V2 ok: two issues')
  expect(fixtures).toContain("O1 ok: lock case -> needs_decision; projection -> automatic re-check acted; matrix -> check-key release; repeats and orphans -> the Platform Admin''s switch")
  expect(fixtures).toContain('O2 ok: not closed while the page is not shown; re-checked, then verified on a later run and closed')
})

test('the reviewer-throughput view reports ready items with measured minutes, blockers, what the platform settled and admission results', () => {
  for (const k of ["'judgement_ready'", "'technical_blocked'", "'resolvable_by_platform'", "'resolved_by_platform'", "'admission'", "'pace'", "'judgement_ready_reviewer_hours'"])
    expect(m).toContain(k)
  expect(m).toContain("security.pipeline_num_v1('layer4.pace_gap_minutes', 15)")
  expect(m).toContain("d.gap > security.pipeline_num_v1('layer4.pace_min_gap_seconds', 20) / 60.0")
  expect(fixtures).toContain('T1 ok: throughput view')
})
