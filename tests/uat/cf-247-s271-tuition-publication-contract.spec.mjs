// Guards: CF-247 IQ-00116 (Platform Admin mandate 4 Nov 2026 05:08 §7): a Layer 4 tuition approval that reaches the catalogue also reaches the
// search projection the website reads. The apply path opens the fee's source to the projection as every other fee writer does (never a blocked
// source or one holding unreviewed fees); a read-only check compares catalogue, projection and the fee rule Zoho reads; an automatic remedy
// opens the sources of approvals already saved and is verified by that check. The consumer API and the projection builder are not changed.
// The behaviour runs on isolated fixtures by tests/fixtures/tuition-publication/run.sh (scratch PostgreSQL; the live projection builder via the
// E16 fixture; the edited and called definitions checked against the live md5s; the live mismatch reproduced; the migration applied twice).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261104380000_cf247_tuition_publication.sql', 'utf8')
const FX = 'tests/fixtures/tuition-publication'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')

test('one live definition is edited, md5-guarded both ways; the functions it calls are checked; the builder is not edited', () => {
  expect(m).toContain("select pg_temp.edit_once('security.layer4_tuition_apply_impl(uuid,uuid,jsonb,text)', 'ef89bdd9ad75a12ecd42ff83e5abc9cb', 'a6148e357decf7611eae1ebd2ce5ae76',")
  for (const [sig, md5] of [['search.refresh_course_enrichment_scoped_v1(uuid[],boolean)', 'fb55e935a8d1c6c7b8cd1c476362cc60'],
    ['security.course_fee_used_v1(uuid)', 'e3cd801549ebf1883bb988fa24a3c909'], ['security.layer4_admission_record_v1(uuid)', 'b47d337ce40e075fe47d751ba564df64']]) {
    expect(m).toContain(`('${sig}', '${md5}')`)
    expect(run).toContain(md5)
  }
  expect(m).not.toMatch(/create or replace function search\.refresh_course_enrichment|create or replace function security\.course_fee_used_v1/)
  expect(run).toContain('"04fa25d82c373de08767d5573d4caabc 5b45bbf1e39d9098d5f23de729418b2d"')
  expect(run).toContain('ef89bdd9ad75a12ecd42ff83e5abc9cb fb55e935a8d1c6c7b8cd1c476362cc60 e3cd801549ebf1883bb988fa24a3c909 b47d337ce40e075fe47d751ba564df64 a03e1c3d26237f33b3e38dd81377b744')
  expect(run).toContain("grep -c 'already applied' | grep -qx 1")
})

test('the apply path opens the source only for reviewed fees and never over a blocked gate', () => {
  expect(m).toContain("v_gate := security.layer4_tuition_gate_open_v1(v_source, ''review item '' || v_item.id);")
  expect(m).toContain("if v_status is not null then return 'gate_' || v_status; end if;")
  expect(m).toContain("and coalesce(f.notes, '') not like 'CF-247 Layer 4 human decision; review item %';")
  expect(m).toContain("if v_other > 0 then return 'mixed_source'; end if;")
  expect(fixtures).toContain("'apply: a blocked gate is kept and the fee stays off the projection'")
  expect(fixtures).toContain("'apply: a source with an unreviewed fee stays closed; neither fee is published'")
})

test('the check names a cause for every approval missing from the projection and compares the fee rule Zoho reads', () => {
  for (const c of ['published', 'course_not_active', 'waiting', 'course_not_projected', 'audience', 'source_gate_closed', 'outside_validity', 'refresh_pending', 'projection_rule_other'])
    expect(m).toMatch(new RegExp(`(then|else) '${c}'`))
  expect(m).toContain('security.course_fee_used_v1(f.course_id) used')
  expect(m).toContain("security.pipeline_num_v1('layer4.verify_wait_minutes', 90)")
  expect(m).toMatch(/create or replace function security\.tuition_publication_check_v1\(p_wide boolean default false\) returns jsonb\s+language plpgsql stable/)
  expect(before).toContain("'live: the admission check records admitted_not_published / projection_has_no_fee (IQ-00116 fingerprint)'")
})

test('the remedy is automatic, registered through the operations contract, and verified by the check', () => {
  expect(m).toContain("'treats', jsonb_build_array('layer4_tuition_source_gate_closed'), 'authority', 'auto',")
  expect(m).toContain("'action_fn', 'security.layer4_tuition_publication_repair_v1(bigint)', 'verify_fn', 'security.layer4_tuition_publication_verify_v1(bigint)',")
  expect(m).toContain("'priority', 47")
  expect(m).toContain("'l4\\_not\\_published:provider\\_current\\_tuition\\_validation:projection\\_has\\_no\\_fee'")
  expect(m).toContain("security.pipeline_num_v1('layer4.tuition_publication_batch', 200)")
  expect(m).toContain("('pipeline', 'layer4.tuition_publication_batch',")
  expect(fixtures).toContain("'repair: nothing without a Layer 4 approval is published (Layer 2 and unreviewed fees stay off)'")
  expect(fixtures).toContain("'verify: passes with every approval published: '")
  expect(fixtures).toContain("'repair: a second run changes nothing'")
})
