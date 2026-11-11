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

const ENA = 'supabase/migrations/20261112001700_cf247_aer_machine_enable.sql'
const e = fs.readFileSync(ENA, 'utf8')
const ecode = e.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('machine admission is switched on only by the recorded decision and only when the validation passes', () => {
  expect(e).toMatch(/^-- CF-247 F-AER\.03 AER machine admission switched on after validation \(Platform Admin 11 Nov 2026 14:39 AEDT "Go"/m)
  expect(ecode).toContain("raise notice 'aer.machine_mode is not 1 (shadow): nothing done'; return;")
  expect(ecode).toContain('v := security.aer_machine_validate_v1();')
  const gate = ecode.indexOf("if coalesce((v->>'passed')::boolean, false) then"), set2 = ecode.indexOf('set value = to_jsonb(2)')
  expect(gate).toBeGreaterThan(0)
  expect(set2).toBeGreaterThan(gate) // mode 2 is written only inside the passed branch
  expect((ecode.match(/to_jsonb\(2\)/g) || []).length).toBe(1)
  expect(ecode).toContain("key = 'aer.machine_shadow_min_hours'")
  expect(ecode).not.toMatch(/\b(drop|delete|truncate)\b|create\s+or\s+replace\s+function|cron\./i)
  expect(e).toMatch(/^-- Replaces: nothing\. Retires: nothing\./m)
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.startsWith('20261112001700_'))).toEqual(['20261112001700_cf247_aer_machine_enable.sql'])
})
