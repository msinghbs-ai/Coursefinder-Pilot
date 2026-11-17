// Guards: Boost on demand (Platform Admin 17 Nov 2026 22:48): until the time in setting boost.on_demand_until_epoch the overnight window of the Boost gate and the quiet window of Boost promotion do not apply; the migration squash blackout, Maintenance Mode, housekeeping-daily and the dispatcher locks still hold Boost, and promotion itself is refused inside the squash blackout; the change qualifies no model and writes only where a course has no study load
// CF-247 S588. Migration 20261118000100_cf247_boost_on_demand. It replaces the gate of migration 20261117163500 (s580) and the promotion function of 20261117223000 (s586); their other rules are unchanged and re-checked here. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118000100_cf247_boost_on_demand.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (src, name) => { const i = src.indexOf(`create or replace function ${name}`); return src.slice(i, src.indexOf('end $function$;', i)) }
const strip = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const gate = fn(code, 'security.boost_ingest_gate_v1'), promote = fn(code, 'security.boost_promote_v1')
const oldGate = strip(fn(fs.readFileSync('supabase/migrations/20261117163500_cf247_boost_bulk_ingest.sql', 'utf8'), 'security.boost_ingest_gate_v1'))
const oldPromote = strip(fn(fs.readFileSync('supabase/migrations/20261117223000_cf247_boost_matrix_settings_and_admitted_count.sql', 'utf8'), 'security.boost_promote_v1'))

test('on demand is a setting with an end time; the functions hold no time', () => {
  expect(code).toContain("('pipeline', 'boost.on_demand_until_epoch', 'Boost: run on demand until (Unix time, seconds)',")
  expect(code).toContain("select extract(epoch from p_now) < security.pipeline_num_v1('boost.on_demand_until_epoch', 0)")
  expect(code).toContain("if v_until <> '2026-11-18 01:05+11'::timestamptz then raise exception")
  expect(new Date(1794924300 * 1000).toISOString()).toBe('2026-11-17T14:05:00.000Z')   // Wed 18 Nov 2026 01:05 Melbourne
  expect(code).toContain('revoke all on function security.boost_on_demand_v1(timestamptz) from public, anon, authenticated;')
  expect(code).not.toMatch(/grant execute[^;]*(anon|authenticated)/)
})

test('the gate: only the window check changes; the blackout, Maintenance Mode, housekeeping and the locks are as they were', () => {
  expect(gate.replace(' and not security.boost_on_demand_v1(p_now) then', ' then')).toBe(oldGate)
  expect(gate.indexOf('security.boost_on_demand_v1(p_now)')).toBeLessThan(gate.indexOf("'reason', 'blackout (migration squash)'"))
  for (const kept of ["'reason', 'Pipeline Maintenance Mode'", "'reason', 'blackout (migration squash)'", "'reason', 'housekeeping-daily running or just started'", "'reason', 'a dispatcher tick is running'"]) expect(gate, kept).toContain(kept)
  expect(code).toContain("<> '9406870cde770d5e5b3be383a99aafd9' then")
})

test('promotion: only the window check changes and the squash blackout is added; one row per course, only where empty, updated_at untouched', () => {
  const added = "\n  if not p_dry and extract(epoch from p_now) >= security.pipeline_num_v1('boost.ingest_blackout_start_epoch', 0)\n     and extract(epoch from p_now) < security.pipeline_num_v1('boost.ingest_blackout_end_epoch', 0) then\n    raise exception 'migration squash blackout: Boost promotion is held';\n  end if;"
  expect(promote).toContain(added)
  expect(promote.replace(added, '').replace(' and not security.boost_on_demand_v1(p_now) then', ' then')).toBe(oldPromote)
  expect(promote).toContain('where c.id = p.entity_id and c.study_load is null;')
  expect(promote).toContain("set state = 'refused', note = 'an earlier row of this batch fills this course''s study load'")
  expect(promote).not.toContain('updated_at =')
  expect(promote).not.toMatch(/boost_country_category|boost\.matrix/)
  expect(code).toContain("<> 'c9239d35c718c69eff127c54a647594c' then")
})

test('the change is proven in its own post-checks and qualifies no model', () => {
  for (const check of ['post-check: the gate still closes on the window while on demand', 'post-check: a Boost gate is open inside the squash blackout', 'post-check: promotion ran inside the squash blackout',
    'post-check: promotion ran outside the window after on demand ended', 'post-check: no model may be qualified by this change']) expect(code, check).toContain(check)
  expect(code).not.toMatch(/insert into pipeline\.boost_model_qualifications/)
  expect(code.replace('on commit drop', '').replace('truncate cf_boost_plan', '')).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(code).not.toMatch(/cron\.(schedule|alter_job|unschedule)/)
})
