// Guards: Platform Admin 12 Nov 2026 22:25 ("Procced with automatic approve"): machine Approve except admits the rows of a country-table read that pass every row rule and holds back the rows that fail one; item rules still hold the whole read
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261113203100_cf247_aer_machine_approve_except.sql', 'utf8')

test('a failing row is held back with its rule, the same rules as the whole-item check; applicability is never inferred', () => {
  expect(M).toContain('create or replace function security.aer_matrix_machine_exclusions_v1(p_run uuid)')
  for (const rule of ['low_confidence', 'short_quote', 'level_unmapped', 'no_minimum', 'minimum_not_in_quote', 'course_unlinked', 'duplicate_identity', 'conflicting_active'])
    expect(M).toContain(`'${rule}'`)
  expect(M).toContain("when q.applicability = 'unresolved' then 'applicability_unresolved'")
  expect(M).toContain("'aer.matrix_machine_except_on'")
})

test('the item rules still hold the whole read; the gate is judged on the admitted rows; a person\'s apply does the work', () => {
  expect(M).toContain("'0eadc57e9c42926b545c076d5236b502'")
  expect(M).toContain("'004dc22b5bbc7d7da633792ace98be20'")
  expect(M).toContain("'39f99e0bb589daea7f57afbc1fe3a41d'")
  expect(M).toContain('g := security.entry_matrix_gate_v1(r.id, v_exids);')
  expect(M).toContain("'rule', 'all_rows_held'")
  // only the row-level holds are relaxed under the switch; lock, rejection, evidence, host, gate, completeness and the audit sample are not edited
  expect(M).not.toMatch(/\$o\$[^$]*(manual_lock|earlier_rejection|source_not_official_host|audit_sample|completeness)/)
  expect(M).toContain("'exclude_row_ids', coalesce(v->'checks'->'exclude_row_ids', '[]'::jsonb)), v_reason);")
  expect(M).toContain('and not (q.id = any (v_ex));')
  expect(M).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
