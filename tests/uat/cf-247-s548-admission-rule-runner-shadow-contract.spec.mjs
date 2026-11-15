// Guards: Consolidation PR 2, admission rule runner in shadow (Platform Admin 15 Nov 2026 20:38 and 22:36): 20 admission rule jobs registered byte for byte with their own cron schedules; shadow records what was due and runs nothing; the legacy jobs are not touched; three lanes never run a rule twice; live dispatch is budgeted, isolated, md5-guarded and behind a per-rule circuit breaker with back-off and a Platform health issue; aer-machine-admission, layer4-drain and calendar-reread stay separate
// CF-247 S548. Migration 20261115220000_cf247_admission_rule_runner_shadow. 24-hour shadow cycle (CLAUDE.md, cron dispatchers).
// G1 (catalogued before scheduled), G2 (settings, no number in a job), G3 (consumer API frozen) and housekeeping are guarded centrally by
// s42, s32 and s57; this spec guards the runner's own behaviour.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261115220000_cf247_admission_rule_runner_shadow.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const body = (name) => {
  const i = code.indexOf(`create or replace ${name}`)
  return code.slice(i, code.indexOf('$function$;', i))
}
const RULES = ['adapter-overwrite', 'coverage-admit', 'coverage-admit-intakes', 'exit-awards-apply', 'fee-period-settle', 'fee-wording-rules',
  'host-pages-apply', 'intake-dates-apply', 'l4-rule-fee-year-align', 'l4-rule-unofficial-source', 'policy-auto-approve', 'process-results',
  'provider-basis-rule-admit', 'provider-english-defaults', 'provider-fee-profiles-apply', 'provider-rule-admit',
  'aer-v2-identity-settle', 'layer4-auto-admit', 'intake-rule-b-qualify', 'scholarship-discovery-settle']

test('20 rules copied from live byte for byte with their own schedules and budgets, all in shadow; the separate jobs are not registered', () => {
  const list = /j\.jobname in \(([^)]+)\)\s*on conflict \(rule_code\) do nothing;/.exec(code)[1]
  expect([...list.matchAll(/'([^']+)'/g)].map((m) => m[1]).sort()).toEqual([...RULES].sort())
  expect(code).toContain("select j.jobname, j.jobname, j.command, md5(j.command), j.schedule, 50, 'shadow',")
  expect(code).toContain('(select round(max(extract(epoch from d.end_time - d.start_time)) * 1000)::int')
  expect(code).toContain("if v_n <> 20 then raise exception 'post-check: % of 20 admission rules match their live legacy job', v_n; end if;")
  expect(code).toContain("raise exception 'post-check: a rule is live (this change is shadow only)'")
  expect(code).toContain("raise exception 'post-check: a job kept separate was registered'")
  expect(list).not.toMatch(/'(aer-machine-admission|layer4-drain|calendar-reread|l4-rule-low-agreement|provider-calendar-defaults|provider-calendar-intakes)'/)
})

test('shadow: the legacy jobs are not touched, and a shadow dispatch records and runs nothing', () => {
  expect(code).not.toMatch(/cron\.(alter_job|unschedule)/)
  expect(code).not.toMatch(/update cron\.job/i)
  const run = body('function security.admission_rule_run_v1')
  const shadow = run.slice(run.indexOf("if v_r.mode = 'shadow' then"), run.indexOf("return 'shadow_due';"))
  expect(shadow).not.toContain('execute')
  expect(run.indexOf("if v_r.mode = 'shadow' then")).toBeLessThan(run.indexOf('execute v_sql into v_out'))
})

test('lanes never run a rule twice: claimed with skip locked, then checked again that it is still due', () => {
  const run = body('function security.admission_rule_run_v1')
  expect(run).toContain('for update skip locked')
  expect(run).toContain("if v_r.last_due_at is not null and v_r.last_due_at >= p_due then return 'already'; end if;")
  for (const lane of ['a', 'b', 'c']) expect(code).toContain(`$j$call security.admission_rule_tick_v1('${lane}')$j$`)
  const tick = body('procedure security.admission_rule_tick_v1')
  expect(tick).toMatch(/pg_try_advisory_lock\(hashtext\('cf247:admission_tick:' \|\| p_lane\)\)/)
  expect(tick).toContain("if v_res not in ('locked', 'already') then v_n := v_n + 1; end if;")
})

test('live: md5-guarded, isolated, budgeted, the answer kept as telemetry, and a circuit breaker with back-off and a health issue', () => {
  const run = body('function security.admission_rule_run_v1')
  expect(run).toContain('if md5(v_r.call_sql) <> v_r.call_md5 then')
  expect(run).toMatch(/begin\s+if position\(';' in v_sql\) = 0 then execute v_sql into v_out; else execute v_r\.call_sql; end if;[\s\S]*exception when others then/)
  expect(run).toContain('v_ms > coalesce(v_r.budget_ms, v_ms)')
  expect(run).toContain('consecutive_failures = 0, open_until = null')
  expect(run).toContain('consecutive_failures = consecutive_failures + 1')
  expect(run).toContain("if v_r.open_until is not null and v_r.open_until > now() then")
  expect(run).toContain("'skipped_open'")
  expect(run).toContain('least(v_max, v_back * power(2, greatest(0, v_r.consecutive_failures + 1 - v_after)))')
  expect(run).toContain("insert into pipeline.platform_issues(check_key, severity, area, title, detail)")
  expect(run).toContain("check_key = 'admission_rule_breaker:' || p_code and resolved_at is null")
  for (const k of ['admission_runner.breaker_after_failures', 'admission_runner.breaker_backoff_minutes', 'admission_runner.breaker_backoff_max_minutes']) expect(run).toContain(`'${k}'`)
  const tick = body('procedure security.admission_rule_tick_v1')
  expect(tick).toContain('if v_n > 0 and (v_el > v_budget or v_el + v_r.exp_ms / 1000.0 > v_finish) then')
  expect(tick).toContain('v_tick - make_interval(mins => v_back)')
  expect(tick.match(/\bcommit;/g).length).toBeGreaterThanOrEqual(2)
  expect(code).toMatch(/create or replace procedure security\.admission_rule_tick_v1\(p_lane text\)\s+language plpgsql\s+as \$function\$/)
})

test('the 24-hour shadow report: dispatches against legacy starts, lag, lanes and the projected load against capacity', () => {
  const rep = body('function security.admission_rule_shadow_report_v1')
  expect(rep).toContain('p_hours int default 24')
  for (const k of ["'runner_dispatches'", "'legacy_starts'", "'max_lag_seconds'", "'lanes_used'", "'all_match'", "'capacity_seconds_per_minute'", "'minutes_over_capacity'"]) expect(rep).toContain(k)
})
