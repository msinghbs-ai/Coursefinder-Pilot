// Guards: F-AER.03 AER machine admission validation fits its time limit (Platform Admin 11 Nov 2026 14:39 AEDT "Go")
// Production 11 Nov 2026: security.aer_machine_history_v1() took 120 s (three unindexed lookups by provenance->>'review_item_id' per past decision), so
// security.aer_machine_validate_v1() could not finish inside the API limit. Migration 20261111235000 adds one expression index; it switches nothing.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261111235000_cf247_aer_machine_validate_index.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('one additive expression index on the lookup the validation history uses, and nothing else', () => {
  expect(code).toContain("create index if not exists course_entry_requirements_review_item_idx on catalogue.course_entry_requirements ((provenance->>'review_item_id'));")
  expect(code).not.toMatch(/\b(alter|drop|delete|truncate|update|insert)\b/i)
  expect(code).not.toMatch(/aer\.machine_mode|create\s+or\s+replace\s+function/i)
  expect(m).toMatch(/^-- Replaces: nothing\. Retires: nothing\./m)
})

test('the version is used by no other migration', () => {
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.startsWith('20261111235000_'))).toEqual(['20261111235000_cf247_aer_machine_validate_index.sql'])
})
