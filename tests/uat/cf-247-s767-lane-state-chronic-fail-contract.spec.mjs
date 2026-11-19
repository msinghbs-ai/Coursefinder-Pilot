// Guards: Platform Admin 19 Nov 2026 11:34 AEDT (chat S1-Build, s767): consolidated lanes read as live in the idle pause (security.flag_jobs_v1 reads pipeline.field_execution_registry, so the PR 3 and PR 4 unschedule paste files can run) and in the telemetry (security.job_effective_state_v1); the three CHRONIC_FAIL jobs are brought under the 120-second statement limit (waste-guard's cost measure becomes rollup target ops-cost-guard; two per-run sizes lowered with reasons); the idle guard never switches a retiring job on again (UR-07).
// The live rolled-back dry run (label live-dry-run) runs the migration's pre- and post-checks against production; these checks keep the rules in the file.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const m = fs.readFileSync(migrationPath('20261119120000_cf247_s767_lane_state_and_chronic_fail.sql'), 'utf8')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name) => { const a = c.indexOf(`create or replace function ${name}(`); expect(a, name).toBeGreaterThan(-1); return c.slice(a, c.indexOf('$function$;', a)) }

test('each live function is replaced only from the definition that was read', () => {
  for (const [sig, md5] of [['security.flag_jobs_v1()', 'd9e713cb99b993bb3d8aa70cbdcffb53'], ['security.waste_guard_v1()', '49b86d8c8cac388957761e17b9f2dc28'], ['security.waste_idle_guard_v1()', 'fd568881335072f7ca0ff3a7b4560a65']])
    expect(c).toContain(`if md5(pg_get_functiondef('${sig}'::regprocedure)) <> '${md5}' then`)
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: nothing/m)
})

test('the idle pause finds live registry lanes once their cron.job row is gone, and decides them through the registry', () => {
  const f = fn('security.flag_jobs_v1')
  expect(f).toContain("from cron.job c where c.command like '%svc_pilot_submit_nonce(''coverage-sweep''%'")
  expect(f).toContain('from pipeline.field_execution_registry r')
  expect(f).toContain("where r.kind = 'worker_lane' and r.mode = 'live' and r.legacy_job is not null")
  expect(f).toContain('and not exists (select 1 from cron.job c2 where c2.jobname = r.legacy_job) loop')
  expect(f).toContain('security.job_switched_on_v1(j.jobid, j.jobname)')
  expect(f).toContain('perform security.job_switch_v1(j.jobid, j.jobname, false);')
  expect(c).toContain("raise exception 'post-check: flag_jobs_v1 does not read the registry'")
})

test('the telemetry reads a job a live dispatcher holds from its dispatcher; the function only reads', () => {
  const f = fn('security.job_effective_state_v1')
  for (const t of ['pipeline.field_execution_registry', 'pipeline.rollup_targets', 'pipeline.admission_rules', 'pipeline.coverage_lane_runs', 'pipeline.rollup_runs', 'pipeline.admission_rule_runs'])
    expect(f).toContain(t)
  expect(f).toContain(' stable\n')
  expect(f).not.toMatch(/\b(insert|update|delete)\b|alter_job/i)
  expect(c).toContain('revoke all on function security.job_effective_state_v1(timestamptz, timestamptz) from public, anon, authenticated, service_role;')
  expect(c).toContain("raise exception 'post-check: % of 3 PR 4 lanes read as live through job_effective_state_v1', v_n;")
})

test('waste-guard keeps its three guards; the cost measure is rollup target ops-cost-guard; no cron job changes', () => {
  const g = fn('security.waste_guard_v1')
  for (const k of ['security.waste_idle_guard_v1()', 'security.waste_flipflop_guard_v1()', 'security.enrichment_flags_refresh_v1()']) expect(g).toContain(k)
  expect(g).not.toContain('security.ops_cost_guard_v1()')
  expect(c).toContain("values ('ops-cost-guard', null, 'select security.ops_cost_guard_v1()', md5('select security.ops_cost_guard_v1()'), '43 * * * *', 'A', 90, true, 'live', 45000,")
  expect(c).not.toMatch(/cron\.(schedule|unschedule|alter_job)\s*\(\s*'/)
  expect(c).not.toMatch(/\b(drop|truncate)\b|\bdelete from\b/i)
  expect(c).not.toMatch(/create table/i)
})

test('two per-run sizes are lowered from the value that was read, each with its reason', () => {
  expect(c).toContain("where toolset_key = 'pipeline' and key = 'batch.sch_coverage_classify' and value = to_jsonb(120);")
  expect(c).toContain("where toolset_key = 'pipeline' and key = 'bind.no_page_providers_per_run' and value = to_jsonb(40);")
  expect((c.match(/updated_by = 'migration 20261119120000'/g) || []).length).toBe(2)
})

test('the idle guard never switches a retiring or retired job on again (UR-07)', () => {
  const f = fn('security.waste_idle_guard_v1')
  expect(f).toContain("continue when exists (select 1 from pipeline.component_register r where r.kind = 'job' and r.name = w.jobname and r.status in ('retiring', 'retired'));")
  expect(c).toContain("raise exception 'post-check: course-link-reverse (retiring) is switched on';")
})
