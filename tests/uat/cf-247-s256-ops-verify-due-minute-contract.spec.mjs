// Guards: P0 Autonomous AI Operations, workstream A (Integration Controller 3 Nov 2026 20:05): a remedy verification due within a controller
// run's minute is done in that run (IQ-00067: due 19:54:00.369, the 19:54 run started 19:54:00.312 and skipped it silently); a verification not
// yet due is counted (not_due); a verification still never runs in the same run as its action. The behaviour runs on isolated fixtures by
// tests/fixtures/ops-due/run.sh (scratch PostgreSQL; the v2.15.436 tick checked against its live md5; the live 19:24 and 19:54 sequence replayed
// before and after the change). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104130000_cf247_ops_verify_due_minute.sql'
const m = fs.readFileSync(MIG, 'utf8')
const run = fs.readFileSync('tests/fixtures/ops-due/run.sh', 'utf8')
const before = fs.readFileSync('tests/fixtures/ops-due/fixtures-before.sql', 'utf8')
const fixtures = fs.readFileSync('tests/fixtures/ops-due/fixtures.sql', 'utf8')

test('the tick is edited only from its live v2.15.436 md5 and checked after', () => {
  const a = m.match(/^--   security\.ops_controller_tick_v1\(\) +b4df5f8106fcbaca1bfcd933f532a55f -> ([0-9a-f]{32})$/m)
  expect(a).not.toBeNull()
  expect(m).toContain(`select pg_temp.edit_once('security.ops_controller_tick_v1()', 'b4df5f8106fcbaca1bfcd933f532a55f', '${a[1]}', array[`)
  expect(run).toContain('LIVE=b4df5f8106fcbaca1bfcd933f532a55f')
  expect(run).toContain("grep -c ': applied$')\" = 1 ]")
  expect(run).toContain("grep -c ': already applied$')\" = 1 ]")
})

test('due within the run minute in both comparisons; not-due counted; same-run verification still refused', () => {
  expect(m).toContain("if coalesce(i.next_action_at, '-infinity') >= date_trunc('minute', v_t0) + interval '1 minute' then  -- fixed: one scheduler minute")
  expect(m).toContain("v_n := v_n || jsonb_build_object('not_due', coalesce((v_n->>'not_due')::int, 0) + 1); continue;")
  expect(m).toContain("(coalesce(x.next_action_at, '-infinity') < date_trunc('minute', v_t0) + interval '1 minute' or")
  expect(m).not.toMatch(/finished_at < v_t0/)
  expect(before).toContain("'before: 19:54 the run starts just before next_action_at: no verification and no close, although the verification would pass (as live)'")
  for (const k of ["D1 IQ-00067 sequence: due within the run''s minute, verified and closed again with its evidence", 'D2 due in a later minute: not verified, and counted as not_due in the run summary',
    'D3 an action finished after the run started is never verified in that run']) expect(fixtures).toContain(k)
})
