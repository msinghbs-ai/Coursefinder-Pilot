// Guards: F-AER.02 AER self-healing: corrected reads keep draining Layer 4 when nobody reviews (Platform Admin 11 Nov 2026 05:42 AEDT "self sustaining")
// CF-247 F-AER.02. Production evidence 11 Nov 2026: Layer 4 held 717 entry items against 600; aer-scheduled-read started 0 reads since 14:13Z 10 Nov (back-pressure and
// the shared 24-hour cap). 160 of the 277 incomplete reads were eligible for a corrected read under security.aer_recovery_rule_v1, but the held picker sent every
// row-limit cut to a person before asking the rule, and corrected reads shared the new-read cap. Migration 20261111110000 fixes both; behaviour is proven on isolated
// PostgreSQL by tests/fixtures/aer-self-healing/run.sh (workflow aer-self-healing-test). These are source contracts of the migration and its recovery.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261111110000_cf247_aer_self_healing_corrections.sql'
const REC = 'supabase/held/aer_self_healing_corrections_forward_recovery.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const rec = fs.readFileSync(REC, 'utf8')

test('the two live functions are edited only from their live md5 and the result md5 is checked', () => {
  expect(m).toContain('--   security.aer_schedule_held_v1(integer) d390d02a5e9b59b6e8ffaadadbf2c7e8 -> d0863451d50241d239a8db2bb62cd15f')
  expect(m).toContain('--   security.aer_schedule_tick_v1(boolean) f995e9521198ae57ab0401564e4e5a20 -> b96163772b72f02b6c9956b1a263224a')
  expect(code).toContain("raise exception 'live % differs from the definition this change edits (body md5 %)'")
  expect(code).toContain("raise exception '% after the edit has body md5 %, expected %'")
  expect(code).toMatch(/edit % must apply exactly once/)
  expect(m).toMatch(/^-- Replaces: security\.aer_schedule_held_v1, security\.aer_schedule_tick_v1/m)
  expect(m).toMatch(/^-- Retires: nothing\./m)
})

test('a row-limit cut is no longer sent to a person before the shared recovery rule is asked', () => {
  // the old line is only in the "olds" array of the guarded edit, never written back
  const news = code.slice(code.indexOf('array[$n$'), code.indexOf("('security.aer_schedule_tick_v1(boolean)', 'f995e9521198ae57ab0401564e4e5a20'"))
  expect(news).not.toContain("'cut at the row limit: for a person'")
  expect(news).toContain("elsif coalesce((g->>'rows_cut')::int, 0) = 0 and jsonb_array_length(coalesce(g->'drops_uncovered', '[]'::jsonb)) = 0 then outcome := 'held only for rows a person leaves out';")
  expect(code).toContain("position('aer_recovery_rule_v1' in")
})

test('corrected reads have their own allowance, a setting with label, range, unit and used_by (G2); the Layer 4 limit and back-pressure stay', () => {
  expect(code).toMatch(/'aer\.schedule_correction_daily_max', 'Scheduled entry reading: corrected reads a day at most',/)
  expect(code).toMatch(/'number', to_jsonb\(100\), 0, 1000, 'reads a day', 946, 'Entry requirements', 'security\.aer_schedule_tick_v1; job aer-scheduled-read'/)
  expect(code).toContain("v_cmax int := security.pipeline_num_v1('aer.schedule_correction_daily_max', 100)::int")
  expect(code).toContain('v_croom := greatest(0, least(v_heldmax, v_cmax - v_cused));')
  expect(code).toContain('security.aer_schedule_held_v1(v_croom)')
  expect(code).toContain('if not v_bp and v_room > 0 then')
  expect(code).toContain("position('v_l4max' in")
  expect(code).not.toMatch(/cron\.(schedule|alter_job)/)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('nothing is switched on: no machine mode, switch or job state is changed', () => {
  expect(code).not.toMatch(/aer\.machine_mode|wc\.aer_fair_on|aer\.e13_recover_on/)
  expect(code).not.toMatch(/set value = /) // existing settings keep their values; only help text and reason change
})

test('the forward recovery reverses the same edits byte for byte and deletes nothing', () => {
  expect(rec).toContain("'d0863451d50241d239a8db2bb62cd15f', 'd390d02a5e9b59b6e8ffaadadbf2c7e8'")
  expect(rec).toContain("'b96163772b72f02b6c9956b1a263224a', 'f995e9521198ae57ab0401564e4e5a20'")
  expect(rec).toContain('v(sig, md5_before, md5_after, news, olds)')
  expect(rec).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('the fixture runs in CI on isolated PostgreSQL only', () => {
  const wf = fs.readFileSync('.github/workflows/aer-self-healing-test.yml', 'utf8')
  expect(wf).toContain('bash tests/fixtures/aer-self-healing/run.sh')
  expect(wf).toContain('postgres:16-alpine')
  expect(fs.readFileSync('tests/fixtures/aer-self-healing/run.sh', 'utf8')).toMatch(/^# Guards: F-AER\.02/m)
})
