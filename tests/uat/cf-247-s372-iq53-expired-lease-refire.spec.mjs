// Guards: IQ-00053 (Platform Admin follow-up 8 Nov 2026 18:27, item 1): a failed AI worker call must not strand its items, and a running task must show how its worker calls went
// Production, 8 Nov 2026: 13 enrich_ai calls started together answered 546 WORKER_RESOURCE_LIMIT; the 390 items they had leased stayed "leased" for 74 minutes because
// security.enrich_fields_slice_v1 asked the worker again only for items in state "ai". The behaviour runs on isolated fixtures by tests/fixtures/iq-00053-lease-refire/run.sh
// (scratch PostgreSQL; today's live slice rebuilt and checked against the live md5; the migration applied twice; every case asserted). This spec holds the contract of the change.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261108190000_cf247_iq53_expired_lease_refire.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/iq-00053-lease-refire'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')

test('the slice is edited only from its live md5 (c385d9c3...) and asks the worker again for an expired lease with fewer than 3 tries, the rule svc_enrich_ai_next uses', () => {
  expect(m).toContain("select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', 'c385d9c3a9fd33614f189773e45683f3', 'd68665cb163bb99f7cca088d39cf595b'")
  expect(m).toContain("(state = 'ai' or (state = 'leased' and leased_until < now() and attempts < 3))) then perform security.enrich_ai_fire_v1(); end if;")
  expect(m).toContain('array[1, 1]')
  expect(m).toMatch(/^-- Replaces: security\.enrich_fields_slice_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(run).toContain('c385d9c3a9fd33614f189773e45683f3')
  expect(run).toContain('d68665cb163bb99f7cca088d39cf595b')
})

test('the worker read-out uses the integration yield check\'s own failure test and an existing setting; the task progress carries it', () => {
  expect(m).toContain('create or replace function security.enrich_worker_health_v1() returns jsonb')
  expect(m).toContain("security.pipeline_num_v1('integration.hidden_error_window_minutes', 120)")
  expect(m).toContain("coalesce(r.status_code, 0) >= 400 or r.timed_out is true or r.error_msg is not null")
  expect(m).toContain(`left(r.content, 2000) ~ '"ok"\\s*:\\s*false'`)
  expect(m).toContain("'worker', security.enrich_worker_health_v1(), 'phase'")
  expect(m).toContain('-- fixed: the open-call window security.enrich_ai_fire_v1 uses')
  expect(m).toContain('revoke all on function security.enrich_worker_health_v1() from public, anon, authenticated;')
})

test('the one setting changes through the register with a reason and an audit event, from the value the change was written against, and nothing is dropped', () => {
  expect(m).toContain("v_before->'value' <> to_jsonb(20)")
  expect(m).toContain("set value = to_jsonb(8)")
  expect(m).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
  expect(m).toContain("'pipeline/enrich.ai_calls_at_once'")
  expect(m).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('the fixtures cover an expired lease, a running lease, a spent item, the existing ai state, the read-out and the setting; the harness applies the migration twice', () => {
  for (const n of ['ok 1 ', 'ok 2 ', 'ok 3 ', 'ok 4 ', 'ok 5 ', 'ok 6 ']) expect(fixtures).toContain(`notice '${n}`)
  expect(run).toContain('a second run changed the guarded function')
  expect(run).toContain('a second run changed a setting or wrote a second audit event')
})
