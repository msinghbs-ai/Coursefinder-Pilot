// Guards: Platform Admin mandate 4 Nov 2026 16:32 §4-§6 and §10 items 1-5, 7-10 for AER (stop ineffective AER recovery: one shared eligibility
// rule; a deterministic refusal is never repeated against unchanged evidence and settings; changed evidence or an authorised setting makes a
// parked item eligible again; transient failures keep bounded retries; duplicates make no work; every technical hold keeps its class, last
// attempt, evidence and reader version, next action and time or authority blocker, why an identical retry is prohibited and its intervention;
// the recovery panel does not recommend a repeat or typed rows that resume the same refused read; IQ-00232, IQ-00279). The behaviour runs on a
// production-shaped seed by tests/fixtures/aer-recovery-selector/run.sh (scratch PostgreSQL 16; live md5s checked; the live lane reproduced
// before the change; applied twice). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104550000_cf247_aer_recovery_selector.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/aer-recovery-selector'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const EDITS = {
  'security.aer_schedule_held_v1(integer)': '2a0d51faada02e5e36dafb88749b4707',
  'security.aer_e13_recover_v1(boolean)': '1bd8be8be44d5cd6e25a41a337b43f61',
  'security.har_aer_item_generate_v1(integer)': '22cb0e540469b5f2ed69a85ecacf5aa2',
  'security.layer4_reread_repeat_v1(uuid)': '80c53ac44d4309279eeb1835d9f7fc21',
  'security.layer4_aer_recovery_detail_v1(text)': 'dbf06336a7ee14fd0a84697d616cb67c',
}

test('every live function this change edits is guarded on its live md5, with a recorded after md5', () => {
  for (const [sig, before] of Object.entries(EDITS)) {
    expect(m).toMatch(new RegExp(`select pg_temp\\.edit_once\\('${sig.replace(/[()]/g, '\\$&')}', '${before}', '[0-9a-f]{32}'`))
    expect(m).toMatch(new RegExp(`--   ${sig.replace(/[()]/g, '\\$&')} ${before} -> [0-9a-f]{32}`))
  }
  expect(m).toMatch(/not in \('370baa57bfb81fe58df767ad852ca9dd', '[0-9a-f]{32}'\)/)
  expect(m).toMatch(/--   security\.aer_technical_recovery_v1\(\) 370baa57bfb81fe58df767ad852ca9dd -> [0-9a-f]{32}/)
  expect(run).toContain('the migration changed a function it does not own')
  expect(run).toContain('the seed does not reproduce the production lane')
})

test('one shared rule: deterministic classes are parked with their blocker and never counted as attempts; changed conditions reconsider', () => {
  expect(m).toContain('create or replace function security.aer_recovery_rule_v1(p_item uuid) returns jsonb')
  expect(m).toContain('v_rep := security.layer4_reread_repeat_v1(p_item);')  // the lifecycle's repeat rule and its change keys, reused
  for (const c of ["'row_limit'", "'unchanged_evidence'", "'transient'", "'human_assisted'", "'changed_conditions'", "'reread_eligible'"]) expect(m).toContain(c)
  expect(m).toMatch(/\('aer_row_limit', [^)]*'park', false/)
  expect(m).toMatch(/\('aer_unchanged_evidence', [^)]*'park', false/)
  expect(m).toContain("raise exception 'post-check: a deterministic AER hold would be retried or counted as an attempt'")
  for (const f of ["'next_action'", "'next_at'", "'authority'", "'retry_prohibited'", "'intervention'", "'last_attempt'", "'evidence_used'", "'reader_revision'"]) expect(m).toContain(f)
  expect(fixtures).toContain('the next run reports nothing again: every condition is unchanged')
  expect(fixtures).toContain('a new stored copy: the refused item is eligible again (changed_conditions)')
  expect(fixtures).toContain('an authorised row limit (entry.max_rows_by_provider) makes the row-limit hold eligible again')
})

test('the selectors read the rule; no cap, spending limit or switch changes; nothing is enqueued by hand', () => {
  expect(m).toContain("elsif not coalesce((security.aer_recovery_rule_v1(r.id)->>'eligible')::boolean, false) then")
  expect(m).toContain("and coalesce((security.aer_recovery_rule_v1(i.id)->>'eligible')::boolean, false)")
  expect(m).not.toMatch(/'(aer\.schedule_daily_max|batch\.aer_schedule_held|aer\.e13_recover_on|wc\.aer_tech_max_attempts)'[^\n]*to_jsonb/)
  expect(m).not.toMatch(/course_entry_read_enqueue_v1\(|course_entry_correction_v1\(/)
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(fixtures).toContain('the scheduled held step selects nothing the rule does not make eligible')
})

test('the panel and the repeat explanation agree with the rule: a row-limit repeat goes to the row-limit decision, never typed rows', () => {
  expect(m).toContain("when v_repeat and coalesce((v_rep->>'row_limit')::boolean, false) then 'row_limit_decision'")
  expect(m).toContain("jsonb_build_object('key', 'open_intervention', 'allowed', v_iv.id is null and not v_repeat,")
  expect(m).toContain('Typed rows would resume the same refused read')
  expect(m).toContain('or (false and h.rt->>')  // the generator no longer raises rows requests
  expect(fixtures).toContain('the panel recommends the row-limit decision (Platform Admin)')
})

test('one recoverable item end to end, measured as transitions; other universities keep progressing', () => {
  expect(m).toContain('create or replace function security.aer_recovery_report_v1(p_since timestamptz) returns jsonb')
  expect(fixtures).toContain('measured as transitions: asked 1, replaced 1, recovered, 1 active row, 1 course published')
  expect(fixtures).toContain("other universities' eligible reads proceed; RMIT''s deterministic holds take no place".replace("universities'", "universities''"))
})
