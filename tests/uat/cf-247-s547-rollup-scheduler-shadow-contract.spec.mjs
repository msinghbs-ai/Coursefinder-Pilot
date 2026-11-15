// Guards: Consolidation PR 1, rollup scheduler in shadow (Platform Admin 15 Nov 2026 20:38 and choices 21:1x): 26 Group A report and cache jobs registered byte for byte with their own cron schedules; shadow records what was due and runs nothing; the legacy jobs are not touched; live dispatch is budgeted, isolated and md5-guarded; consumer-facing caches and the search writers are not registered
// CF-247 S547. Migration 20261115210000_cf247_rollup_scheduler_shadow. Scope: project doc claude/rollup-scheduler-pr1-scope.md.
// G1 (catalogued before scheduled), G2 (settings, no number in a job), G3 (consumer API frozen) and housekeeping are guarded centrally by
// s42, s32 and s57; this spec guards the scheduler's own behaviour.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261115210000_cf247_rollup_scheduler_shadow.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const body = (name) => {
  const i = code.indexOf(`create or replace ${name}`)
  return code.slice(i, code.indexOf('$function$;', i))
}
const GROUP_A = ['admin-read-snapshots', 'data-delivery', 'lane-funnel', 'aer-outcome-register', 'course-coverage-snapshot', 'firecrawl-panel-figures',
  'admin-summary-snapshots-refresh', 'stats-15m', 'course-completeness-build', 'course-coverage-build', 'course-field-source-build',
  'coursefinder-cf245-enrichment-coverage-snapshot', 'coursefinder-cf245-enrichment-hourly-admin-cache', 'enrich-coverage-snapshot', 'progress-snapshot',
  'provider-fee-ranges-refresh', 'adapter-build-readiness', 'evidence-filter-options-refresh', 'layer2-onboarding-snapshot',
  'coursefinder-data-quality-overview-refresh', 'ops-scorecard', 'provider-field-daily', 'toolset-use-daily', 'storage-size-daily', 'api-usage-rollup',
  'provider-priority-refresh']

test('Group A: 26 jobs copied from live byte for byte with their own schedules, all in shadow; nothing consumer-facing or search', () => {
  const list = /j\.jobname in \(([^)]+)\)\s*on conflict \(target_code\) do nothing;/.exec(code)[1]
  const names = [...list.matchAll(/'([^']+)'/g)].map((m) => m[1])
  expect(names.sort()).toEqual([...GROUP_A].sort())
  expect(code).toContain("select j.jobname, j.jobname, j.command, md5(j.command), j.schedule, 'A',")
  expect(code).toContain("if v_n <> 26 then raise exception 'post-check: % of 26 Group A targets match their live legacy job', v_n; end if;")
  expect(code).toContain("raise exception 'post-check: a target is live (this change is shadow only)'")
  for (const j of ['consumer-reference-bundle-refresh', 'website-reference-cache', 'campus-regional-class-refresh', 'search-refresh-requested', 'search-course-refresh', 'aer-reconcile'])
    expect(code, j).not.toContain(`'${j}'`)
})

test('shadow: the legacy jobs are not touched, and a shadow dispatch records and runs nothing', () => {
  expect(code).not.toMatch(/cron\.(alter_job|unschedule)/)
  expect(code).not.toMatch(/update cron\.job/i)
  const run = body('function security.rollup_run_target_v1')
  const shadow = run.slice(run.indexOf("if v_t.mode = 'shadow' then"), run.indexOf("return 'shadow_due';"))
  expect(shadow).not.toContain('execute')
  expect(shadow).toContain("'shadow_due'")
})

test('one dispatch: md5-guarded, isolated in its own exception block, the result recorded either way', () => {
  const run = body('function security.rollup_run_target_v1')
  expect(run).toContain('if md5(v_t.call_sql) <> v_t.call_md5 then')
  expect(run).toContain("'refused'")
  expect(run).toMatch(/begin\s+execute v_t\.call_sql;[\s\S]*'succeeded'[\s\S]*exception when others then[\s\S]*'failed'/)
  expect(run).toContain('for update skip locked')
})

test('the tick: one at a time, due by schedule with a bounded catch-up, frequent first, budgeted, each dispatch committed on its own', () => {
  const tick = body('procedure security.rollup_tick_v1')
  expect(tick).toContain("if security.pipeline_num_v1('rollup.scheduler_on', 0) < 1 then return; end if;")
  expect(tick).toMatch(/pg_try_advisory_lock\(hashtext\('cf247:rollup_tick'\)\)/)
  expect(tick).toContain('v_tick - make_interval(mins => v_back)')
  expect(tick).toContain('where security.cron_matches_v1(t.schedule, m)')
  expect(tick).toContain('order by t.priority, d.due_at, t.target_code')
  expect(tick).toContain('if v_n > 0 and (v_el > v_budget or v_el + v_r.exp_ms / 1000.0 > v_finish) then')
  expect(tick.match(/\bcommit;/g).length).toBeGreaterThanOrEqual(3)
  for (const k of ['rollup.tick_budget_seconds', 'rollup.tick_finish_by_seconds', 'rollup.keep_days', 'rollup.catch_up_minutes']) expect(tick).toContain(`'${k}'`)
  // a procedure that commits cannot be security definer
  expect(code).toMatch(/create or replace procedure security\.rollup_tick_v1\(\)\s+language plpgsql\s+as \$function\$/)
  expect(code).toContain("perform cron.schedule('rollup-scheduler', '* * * * *', $j$call security.rollup_tick_v1()$j$);")
})

test('the shadow report compares dispatches with the legacy starts and states whether all match', () => {
  const rep = body('function security.rollup_shadow_report_v1')
  expect(rep).toContain("'scheduler_dispatches', coalesce(s.dispatches, 0)")
  expect(rep).toContain("'legacy_starts', coalesce(l.starts, 0)")
  expect(rep).toContain("'max_lag_seconds'")
  expect(rep).toContain("'all_match'")
})
