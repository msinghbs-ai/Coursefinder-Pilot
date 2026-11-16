// Guards: Consolidation PR 3, coverage lane dispatch in shadow (Platform Admin 16 Nov 2026 10:59, 16:26, 16:52 and 22:45): pipeline.field_execution_registry holds the 13 coverage worker lanes (coverage-ai-match left out: switched off on live 17 Nov 06:00, Platform Admin 06:15) registered byte for byte with their own cron schedules (shadow records what was due and runs nothing; the legacy jobs are not touched) and the seven API v3 field lanes declared disabled and never dispatched; three lanes never run a coverage lane twice; live dispatch is budgeted, isolated, md5-guarded and behind a per-lane circuit breaker; calendar-reread, the 30-second coverage-read jobs and every job held by PR 1 or PR 2 stay out
// CF-247 S567. Migration 20261116220000_cf247_pr3_coverage_lane_dispatch_shadow. 24-hour shadow cycle (CLAUDE.md, cron dispatchers).
// G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57; this spec guards the dispatcher's own behaviour.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261116220000_cf247_pr3_coverage_lane_dispatch_shadow.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const body = (name) => {
  const i = code.indexOf(`create or replace ${name}`)
  return code.slice(i, code.indexOf('$function$;', i))
}
const LANES = ['course-link-search-worker', 'coverage-find-site', 'coverage-reextract', 'coverage-reidentify', 'provider-contact-page',
  'provider-facts', 'companion-read', 'course-list-read', 'credential-read', 'policy-add-tests', 'programme-discover', 'programme-read', 'source-find']
const FIELDS = ['campus_is_primary', 'course_empty_reason', 'course_study_load', 'provider_accreditations', 'grade_scale_conversions', 'destination_editions', 'api_field_dictionary']

test('13 worker lanes copied from live byte for byte with their own schedules and budgets, all in shadow; the separate jobs are not registered', () => {
  const list = /j\.active and j\.jobname in \(([^)]+)\)/.exec(code)[1]
  expect([...list.matchAll(/'([^']+)'/g)].map((m) => m[1]).sort()).toEqual([...LANES].sort())
  expect(code).toContain("select j.jobname, 'worker_lane', j.jobname, j.command, md5(j.command), j.schedule, 50, 'shadow',")
  expect(code).toContain('not exists (select 1 from pipeline.rollup_targets t where t.legacy_job = j.jobname)')
  expect(code).toContain('not exists (select 1 from pipeline.admission_rules a where a.legacy_job = j.jobname)')
  expect(code).toContain("if v_n <> 13 then raise exception 'post-check: % of 13 coverage lanes match their live legacy job', v_n; end if;")
  expect(code).toContain("raise exception 'post-check: a lane is live (this change is shadow only)'")
  expect(list).not.toMatch(/'(calendar-reread|coverage-read|coverage-read-2|coverage-ai-match|platform-health)'/)
})

test('the seven API v3 field lanes are declared disabled with owner, mode, fill function and request ids, and are never dispatched', () => {
  for (const f of FIELDS) expect(code).toContain(`('${f}', 'field_lane', 'disabled', false,`)
  expect(code).toContain("or (kind = 'field_lane' and field is not null and execution_mode is not null and uses_ai is not null and owner is not null and call_sql is null and mode = 'disabled'))")
  expect(code).toContain("raise exception 'post-check: the seven field lanes are declared disabled'")
  const run = body('function security.coverage_lane_run_v1')
  expect(run.indexOf("if v_r.kind <> 'worker_lane' then return 'not_a_worker_lane'; end if;")).toBeLessThan(run.indexOf("if v_r.mode = 'shadow' then"))
  expect(body('procedure security.coverage_lane_tick_v1')).toContain("from (select * from pipeline.field_execution_registry where kind = 'worker_lane') r")
})

test('shadow: the legacy jobs are not touched, and a shadow dispatch records and runs nothing', () => {
  expect(code).not.toMatch(/cron\.(alter_job|unschedule)/)
  expect(code).not.toMatch(/update cron\.job/i)
  const run = body('function security.coverage_lane_run_v1')
  const shadow = run.slice(run.indexOf("if v_r.mode = 'shadow' then"), run.indexOf("return 'shadow_due';"))
  expect(shadow).not.toContain('execute')
  expect(run.indexOf("if v_r.mode = 'shadow' then")).toBeLessThan(run.indexOf('execute v_sql into v_out'))
})

test('lanes never run a coverage lane twice, and live dispatch is md5-guarded, isolated, budgeted and behind a circuit breaker', () => {
  const run = body('function security.coverage_lane_run_v1')
  expect(run).toContain('for update skip locked')
  expect(run).toContain("if v_r.last_due_at is not null and v_r.last_due_at >= p_due then return 'already'; end if;")
  expect(run).toContain('if md5(v_r.call_sql) <> v_r.call_md5 then')
  expect(run).toMatch(/begin\s+if position\(';' in v_sql\) = 0 then execute v_sql into v_out; else execute v_r\.call_sql; end if;[\s\S]*exception when others then/)
  expect(run).toContain('least(v_max, v_back * power(2, greatest(0, v_r.consecutive_failures + 1 - v_after)))')
  expect(run).toContain("check_key = 'coverage_lane_breaker:' || p_code and resolved_at is null")
  expect(run).toContain("'warning', 'coverage sweep',")
  for (const k of ['coverage_lane.breaker_after_failures', 'coverage_lane.breaker_backoff_minutes', 'coverage_lane.breaker_backoff_max_minutes']) expect(run).toContain(`'${k}'`)
  for (const lane of ['a', 'b', 'c']) expect(code).toContain(`$j$call security.coverage_lane_tick_v1('${lane}')$j$`)
  const tick = body('procedure security.coverage_lane_tick_v1')
  expect(tick).toMatch(/pg_try_advisory_lock\(hashtext\('cf247:coverage_lane_tick:' \|\| p_lane\)\)/)
  expect(tick).toContain('if v_n > 0 and (v_el > v_budget or v_el + v_r.exp_ms / 1000.0 > v_finish) then')
  expect(tick.match(/\bcommit;/g).length).toBeGreaterThanOrEqual(2)
})

test('the 24-hour shadow report covers worker lanes only: dispatches against legacy starts, lag and projected load', () => {
  const rep = body('function security.coverage_lane_shadow_report_v1')
  expect(rep).toContain('p_hours int default 24')
  expect(rep).toContain("where r.kind = 'worker_lane') z(x);")
  for (const k of ["'runner_dispatches'", "'legacy_starts'", "'max_lag_seconds'", "'all_match'", "'capacity_seconds_per_minute'", "'minutes_over_capacity'"]) expect(rep).toContain(k)
})
