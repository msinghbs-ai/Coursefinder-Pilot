// Guards: IQ-00355 planner head-of-queue starvation (CF-247 F-OPS): the hourly automatic planner must remember every university whose plan has no step and leave it out of the candidate list for plans.noop_wait_hours, so universities that can be planned are reached. The behaviour is proved by the PostgreSQL fixture tests/fixtures/planner-noop-memory/run.sh; this is the source contract over the migration and its forward recovery.
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261110240000_cf247_planner_noop_memory.sql', 'utf8')
const R = fs.readFileSync('supabase/held/planner_noop_memory_forward_recovery.sql', 'utf8')
const BEFORE = '5a3874e777ae649916d61575e2692609'
const AFTER = 'f0c95d0bbef3ccac550585185c9784c9'
// the function text each file carries
const body = (s) => s.match(/as \$function\$([\s\S]*?)\$function\$/)[1]

test('the migration follows the house pattern: header, one md5-guarded body replacement, the setting added, nothing dropped', () => {
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
  expect(M).toContain('security.enrich_plan_auto_v1()')
  expect(M).toContain(`--   security.enrich_plan_auto_v1()   ${BEFORE} -> ${AFTER}`)
  expect(M).toContain(`md5(v_src) = '${AFTER}' then raise notice 'security.enrich_plan_auto_v1(): already applied'`)
  expect(M).toContain(`md5(v_src) <> '${BEFORE}' then raise exception`)
  expect(M).toContain('supabase/held/planner_noop_memory_forward_recovery.sql')
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(M).not.toMatch(/\balter\s+table\b/i)
  expect(M.match(/create or replace function/g)).toHaveLength(1)
})

test('the setting plans.noop_wait_hours is added once, with a label, a range, a unit and a used_by line, and is read with its default', () => {
  const ins = M.match(/insert into pipeline\.platform_toolset_settings[\s\S]*?on conflict \(toolset_key, key\) do nothing;/)[0]
  expect(ins.match(/\('pipeline', 'plans\./g)).toHaveLength(1)
  expect(ins).toContain("'plans.noop_wait_hours'")
  expect(ins).toMatch(/'number', '24'::jsonb, 1, 168, 'hours', \d+, 'Onboarding', 'security\.enrich_plan_auto_v1/)
  expect(body(M)).toContain("v_noop_wait int := security.pipeline_num_v1('plans.noop_wait_hours', 24)::int;")
})

test('every candidate whose plan has no step, or only steps for a person, is remembered and counted, not only an early re-plan', () => {
  const b = body(M)
  const noStep = b.slice(b.indexOf('if jsonb_array_length(v_steps) = 0'), b.indexOf('insert into pipeline.enrich_plan_runs'))
  expect(noStep).toContain('insert into pipeline.enrich_plan_noop as n(provider_id, fingerprint, at) values (q.provider_id, v_fp, now())')
  expect(noStep).toContain('v_same := v_same + 1;')
  expect(noStep).toContain('continue;')
  expect(noStep).not.toContain('if v_is_re')
  // the old text recorded it only for an early re-plan
  const old = body(R)
  expect(old.slice(old.indexOf('if jsonb_array_length(v_steps) = 0'), old.indexOf('insert into pipeline.enrich_plan_runs'))).toContain('if v_is_re then')
})

test('a candidate that is not an early re-plan is left out while its memory row is newer than the wait; the early re-plan fingerprint rule is kept as it was', () => {
  const b = body(M)
  expect(b).toContain('and (i.fp is not null or not exists (select 1 from pipeline.enrich_plan_noop n where n.provider_id = x.provider_id and n.at > now() - make_interval(hours => v_noop_wait)))) z')
  // the original fingerprint test is untouched
  expect(b).toContain("and not exists (select 1 from pipeline.enrich_plan_noop n where n.provider_id = x.provider_id and n.fingerprint = i.fp)))")
  // the window, the order and the re-plan cap are unchanged
  expect(b).toContain('z.missing desc, z.best_rank nulls last limit v_room * 3 loop')
  expect(b).toContain('if v_is_re and v_re_used + v_re >= v_re_max then v_capped := v_capped + 1; continue; end if;')
})

test('the forward recovery restores the previous body and keeps the setting', () => {
  expect(R).toContain(BEFORE)
  expect(R).toContain(AFTER)
  expect(R).toContain("raise notice 'already the original'")
  expect(R).toContain('differs from both texts this recovery knows')
  expect(R).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(R).not.toMatch(/(insert into|update|delete from) pipeline\.platform_toolset_settings/i)
  // the two bodies differ only by this change
  expect(body(R)).not.toContain('v_noop_wait')
  expect(body(R).length).toBe(11126)
})

test('the database fixture exists and runs the migration and the recovery', () => {
  const run = fs.readFileSync('tests/fixtures/planner-noop-memory/run.sh', 'utf8')
  expect(run).toContain(`BEFORE=${BEFORE}`)
  expect(run).toContain(`AFTER=${AFTER}`)
  expect(run).toContain('supabase/held/planner_noop_memory_forward_recovery.sql')
})
