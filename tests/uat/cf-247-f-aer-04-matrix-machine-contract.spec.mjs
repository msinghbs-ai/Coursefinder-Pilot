// Guards: F-AER.04 machine admission of country tables and qualification rows, rule aer-matrix-machine-v1 (Platform Admin decision D1, 11 Nov 2026 20:17 AEDT)
// The class admits only a never-decided first read of the provider's own official source whose every row is source-proved, through the person's apply, as the system actor
// marked machine; everything else stays in Layer 4 with its reason. Behaviour is proven on isolated PostgreSQL by tests/fixtures/aer-matrix-machine/run.sh.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261112093700_cf247_aer_matrix_machine_admission.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('ships in shadow; admission needs mode 2 and a passing validation of its own; a pass switches nothing on', () => {
  expect(code).toContain("'number', to_jsonb(1), 0, 2, 'mode', 1520")
  expect(code).toContain("exists (select 1 from pipeline.aer_matrix_machine_validations x where x.passed and x.validated_at > now() - interval '7 days')")
  expect(code).toContain("if security.aer_matrix_machine_effective_v1() >= 2 then raise exception 'post-check: the class must ship in shadow'")
  expect(code).not.toMatch(/set value = to_jsonb\(2\)/)
})

test('own ledger and validations: never written into the course machine ledger its validation re-checks', () => {
  expect(code).toContain('create table if not exists pipeline.aer_matrix_machine_admissions (')
  expect(code).toContain('create table if not exists pipeline.aer_matrix_machine_validations (')
  expect(code).not.toMatch(/insert into pipeline\.aer_machine_admissions|insert into pipeline\.aer_machine_validations/)
})

test('every D1 condition is a check; nothing is inferred', () => {
  for (const rule of ["'manual_lock'", "'earlier_rejection'", "'evidence_missing'", "'stale_copy'", "'source_not_official_host'", "'host_shared'", "'gate_incomplete'", "'completeness'",
    "'no_rows'", "'duplicate_identity'", "'conflicting_active'", "'change_of_admitted_table'", "'claimed_by_person'", "'decided'", "'audit_sample'"]) expect(code).toContain(rule)
  for (const why of ["'applicability_unresolved'", "'low_confidence'", "'short_quote'", "'level_unmapped'", "'no_minimum'"]) expect(code).toContain(why)
  // a protected rejection is one of the same source
  expect(code).toContain("and (o.layer2_state->>'entry_matrix_source_id' = f.id::text or o.proposed_value->>'url' = f.url)")
})

test('admission is the person\'s apply with the machine records; reversible; the course job steps it in isolation', () => {
  expect(code).toContain("v_res := security.entry_matrix_review_apply_v1(p_item, 'approve', jsonb_build_object('reviewer', 'aer-matrix-machine-v1'), v_reason);")
  expect(code).toContain("jsonb_build_object('machine_rule', 'aer-matrix-machine-v1', 'actor_kind', 'machine'")
  expect(code).toContain('create or replace function security.aer_matrix_machine_withdraw_v1(p_item uuid, p_reason text)')
  expect(code).toContain("return jsonb_build_object('error', left(sqlerrm, 300));")
  expect(m).toContain('--   security.aer_machine_run_v1() ad143b44722ba6fbc0129cd38386661c -> f88ab3f16833dec601786af5c7cdbbcc')
  expect(m).toMatch(/^-- Replaces: security\.aer_machine_run_v1/m)
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.startsWith('20261112093700_'))).toEqual(['20261112093700_cf247_aer_matrix_machine_admission.sql'])
})
