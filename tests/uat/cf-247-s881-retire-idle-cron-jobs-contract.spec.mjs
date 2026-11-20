// Guards: CF-247 s881 (Platform Admin 20 Nov 2026 17:14 and 17:15, chat S1-Build): active pg_cron jobs at most 136 with 0 unregistered — six
// jobs with no work left are switched off and marked retiring only while their evidence holds, the protected sweeps and pipelines stay on,
// nothing is unscheduled or dropped by the migration; one-off auto-merge checks report without failing
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120181000_cf247_s881_retire_idle_cron_jobs.sql', 'utf8')
const MERGE = fs.readFileSync('scripts/ci/auto-merge.sh', 'utf8')
const SIX = ['boost-benchmark', 'lean-sections-eval', 'lean-qualify', 'aer-v2-shadow', 'course-url-fill', 'reread-pilot']

test('only the six idle jobs, each switched off only while its evidence holds', () => {
  expect(MIG).toContain(`j.jobname in (${SIX.map((s) => `'${s}'`).join(', ')})`)
  for (const s of [
    "v_ok := coalesce(security.boost_benchmark_gate_v1() ->> 'reason', '') = 'nothing left to do'",
    "v_ok := not exists (select 1 from pipeline.lean_section_eval_cases c where c.state = 'pending');",
    "v_ok := security.pipeline_num_v1('reading.lean_qualify_on', 0) = 0;",
    "v_ok := security.pipeline_num_v1('aer.v2_shadow_on', 0) = 0;",
    "v_ok := security.pipeline_num_v1('course_url.fill_enabled', 1) <> 1;",
    "v_ok := not coalesce((security.toolset_setting('pipeline', 'reread.pilot_enabled') #>> '{}')::boolean, false)",
    "raise notice 's881: % kept on: its evidence no longer holds', r.jobname;",
  ]) expect(MIG).toContain(s)
})

test('switched off and retiring, never unscheduled, dropped or removed from the catalogue', () => {
  expect(MIG).toContain('perform cron.alter_job(r.jobid, active => false);')
  expect(MIG).toContain("set status = 'retiring', replaced_by = 'nothing: no work left (' || v_why || ')',")
  expect(MIG).toContain("retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int")
  expect(MIG).not.toMatch(/cron\.unschedule|delete from pipeline\.automation_catalogue|^\s*(drop|delete|truncate)\b/im)
  expect(MIG).toContain("values ('scheduler', 'job_retire', r.jobname,")
})

test('the protected sweeps and pipelines must still be on, and no active job is unregistered', () => {
  for (const j of ['aer-det-sweep', 'struct-det-sweep', 'elr-det-sweep', 'scholarship-coverage-classify', 'coverage-reconcile', 'ops-pulse-refresh',
                   'admission-rule-runner', 'coverage-lane-dispatch', 'rollup-scheduler', 'enrich-plan-run']) expect(MIG).toContain(`'${j}'`)
  expect(MIG).toContain("raise exception 'post-check: a protected job is not switched on: %', v_missing;")
  expect(MIG).toContain("if v_unreg > 0 then raise exception 'post-check: % active jobs are not catalogued and registered', v_unreg; end if;")
  expect(MIG).toMatch(/^-- Replaces: .+$/m)
  expect(MIG).toMatch(/^-- Retires: .+$/m)
})

test('auto-merge: a one-off check on a finished check suite reports a stop without failing or commenting', () => {
  expect(MERGE).toContain('stop() { say "$1"; if [ "$MODE" = wait ]; then comment "$2"; exit 1; fi; exit 0; }')
  expect(MERGE).toContain('stop "#$PR has failing checks: ${failed:-commit status $sstate}."')
  expect(MERGE).toContain('stop "#$PR has merge conflicts with main."')
})
