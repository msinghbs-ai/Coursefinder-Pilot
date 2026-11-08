// Guards: Platform Admin directive 8 Nov 2026 (run readiness assessment for newly replayed items; complete technical recovery and review-ready progression; no AI approval of human review); nothing decided, approved or admitted by the replay.
// CF-247 AER lane aer2: migration 20261108150000 has aer-replay (security.aer_replay_v1) assess the items it creates in the same run through security.layer4_readiness_items_v1.
// The PostgreSQL 16 run is tests/fixtures/aer-replay-readiness/run.sh (live definition rebuilt and md5-checked, the gap shown BEFORE, the migration applied twice, six behaviours).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261108150000_cf247_aer_replay_marks_new_items_ready.sql', 'utf8')
const run = fs.readFileSync('tests/fixtures/aer-replay-readiness/run.sh', 'utf8')
const fx = fs.readFileSync('tests/fixtures/aer-replay-readiness/fixtures.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C = code(M)

test('one live function is edited under its live md5 with a recorded after md5, and nothing else is edited', () => {
  expect(M).toMatch(/--   security\.aer_replay_v1\(boolean\) eccd0e821b5cffa733af3adc0162c0ea -> [0-9a-f]{32}/)
  expect(M).not.toMatch(/AFTER_MD5|00000000000000000000000000000000/)
  expect(C).toContain("pg_temp.edit_once('security.aer_replay_v1(boolean)', 'eccd0e821b5cffa733af3adc0162c0ea'")
  expect(C).not.toMatch(/create or replace function security\.(aer_replay_plan_v1|aer_replay_apply_v1|aer_matrix_rank_repair_v1|layer4_readiness_item[s]?_v1)/)
  expect(M).toMatch(/^-- Replaces: .+/m)
  expect(M).toMatch(/^-- Retires: nothing/m)
})

test('the replay collects each applied replacement\'s new item and assesses them after the loop, in their own exception block, never in a preview', () => {
  expect(C).toContain("if a->>''new_item'' is not null then v_new := v_new || (a->>''new_item'')::uuid; end if;")
  expect(C).toContain('if not p_preview and cardinality(v_new) > 0 then')
  expect(C).toContain('begin v_rd := security.layer4_readiness_items_v1(v_new);')
  expect(C).toContain("exception when others then v_rd := jsonb_build_object(''error'', left(sqlerrm, 200));")
  expect(C).toContain("''matrix_rank_repair'', v_mx, ''readiness'', v_rd);")
})

test('no number, setting, job, table or decision is added; the callee must exist; nothing is dropped', () => {
  expect(C).not.toMatch(/insert into pipeline\.(platform_toolset_settings|automation_catalogue)|cron\.schedule|create table|\b(drop|delete|truncate)\b/i)
  expect(C).not.toMatch(/layer4_decisions|layer4_decide|status = 'approved'|course_entry_review_apply/)
  expect(C).toContain("to_regprocedure('security.layer4_readiness_items_v1(uuid[])') is null")
})

test('the PostgreSQL fixture proves the gap BEFORE, the md5 guard, a second run, and six behaviours', () => {
  for (const t of ['loaded security.aer_replay_v1 = live (eccd0e82)', 'PASS before: the replay created item', 'PASS migration applied twice: already applied', 'PASS the md5 guard refuses a replay that is not the live definition']) expect(run).toContain(t)
  for (const t of ['PASS preview', 'PASS real run assesses the new item', 'PASS no replacement, no call', 'PASS several items, one call', 'PASS a failing assessment does not undo the replay', 'PASS switch']) expect(fx).toContain(t)
  expect(fx).toContain('nothing is approved or admitted')
})
