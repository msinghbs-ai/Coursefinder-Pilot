// Guards: F-AER.04 machine admission of country tables and qualification rows (Platform Admin decision D1, 11 Nov 2026): audited activation after a passing validation
// The class is switched on by this migration only when security.aer_matrix_machine_validate_v1 passes in the same transaction and the quote proof is live; otherwise it stays
// in shadow with the failed validation recorded. A pass never switches anything on by itself: this migration is the decision D1 carried out, recorded as control events.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261112143700_cf247_aer_matrix_machine_enable.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('mode 2 only after a passing validation in the same run, with the quote proof live; from shadow only', () => {
  expect(code).toContain("key = 'aer.matrix_machine_mode') <> '1' then")
  expect(code).toContain("position('minimum_not_in_quote' in")
  expect(code).toContain('v := security.aer_matrix_machine_validate_v1();')
  const i = code.indexOf("if coalesce((v->>'passed')::boolean, false) then"), j = code.indexOf('set value = to_jsonb(2)')
  expect(i).toBeGreaterThan(0)
  expect(j).toBeGreaterThan(i)
  expect((code.match(/to_jsonb\(2\)/g) || []).length).toBe(1)
  expect(code).toContain("'matrix_machine_validate'")
  expect(code).toContain("'matrix_machine_mode_set'")
  expect(m).toMatch(/^-- Replaces: nothing\./m)
  expect(m).toMatch(/^-- Retires: nothing\./m)
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.startsWith('20261112143700_'))).toEqual(['20261112143700_cf247_aer_matrix_machine_enable.sql'])
})
