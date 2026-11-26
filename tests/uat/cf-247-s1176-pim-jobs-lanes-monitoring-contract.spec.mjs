// Guards: F-OPS.21 and DR-16 (SS-Programme-Control 26 Nov 2026 21:34 AEDT): PIM monitoring identifies cron jobs by jobid, covers every worker, dispatcher lane, admission rule and rollup target with its state (active, idle, held, degraded, retired, shadow), heartbeat, next run, failure reason and outcomes; counted only in the background PIM snapshot; the pim.operations contract only grows.
// s1176: security.pim_outcome_class_v1, security.data_delivery_jobs_v1 (background, pipeline.data_delivery_job_runs.ops), public.admin_pim_jobs_v1, security.pim_operations_v1 replaced with compatible additions.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261130020000_cf247_s1176_pim_jobs_lanes_monitoring.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1176: scheduler history is keyed by jobid, never by job name', () => {
  expect(code).toContain('from cron.job_run_details d0 cross join st')
  expect(code).toContain('group by d.jobid')
  expect(code).toContain('left join ch h on h.jobid = c.jobid')
  expect(code).not.toMatch(/r\.key\s*=\s*c\.jobname/)
  expect(code).toContain("guard: cron rows not keyed by jobid")
})

test('s1176: every lane, rollup target and admission rule is a component, with its run log', () => {
  for (const t of ['pipeline.field_execution_registry', 'pipeline.rollup_targets', 'pipeline.admission_rules',
                   'pipeline.coverage_lane_runs', 'pipeline.rollup_runs', 'pipeline.admission_rule_runs']) expect(code).toContain(t)
  expect(code).toContain('guard: a component is missing from the jobs helper')
  for (const s of ["'active'", "'idle'", "'held'", "'degraded'", "'retired'", "'shadow'"]) expect(code).toContain(s)
})

test('s1176: unmeasured outcomes and partial history are never reported as zero', () => {
  expect(code).toContain("then 'unmeasured'")
  expect(code).toContain("'partial_since'")
})

test('s1176: counted only in the existing background PIM snapshot; the pim.operations keys of s1175 are kept', () => {
  expect(code).toContain('v_ops := security.data_delivery_jobs_v1();')
  expect(code).toContain('guard: the jobs read is not in the background count')
  expect(code).toContain('add column if not exists ops jsonb')
  expect(code).toContain("guard: security.data_delivery_refresh_v1 is not the s1175 definition")
  expect(code).toContain('guard: the screen read counts operations live')
  for (const k of ["'workers'", "'stalled_workers'", "'expired_leases'", "'freshness_by_country'", "'consumer'", "'requests'", "'jobs_summary_at'",
                   "'job'", "'schedule'", "'last_start'", "'last_success'", "'failed_24h'", "'running'", "'stalled'"]) expect(code).toContain(k)
  expect(code).toContain("guard: security.pim_operations_v1 is not the s1175 definition")
})

test('s1176: thresholds are settings; no job, no schedule change, nothing dropped; G3, locks and cron asserted', () => {
  for (const k of ['pim.jobs_stall_periods', 'pim.jobs_min_runs', 'pim.jobs_empty_share', 'pim.jobs_failure_share', 'pim.jobs_deferred_share'])
    expect(code).toContain(`security.pipeline_num_v1('${k}'`)
  expect(code).not.toMatch(/\b(create table|cron\.schedule|cron\.unschedule|cron\.alter_job|truncate|drop\s+(table|function|column|constraint|trigger)|delete\s+from)\b/i)
  expect(code).not.toMatch(/update\s+(cron\.job|pipeline\.field_execution_registry|pipeline\.rollup_targets|pipeline\.admission_rules)\b/i)
  expect(code).toContain('guard: the scheduler changed')
  expect((code.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(MIG).toMatch(/^-- Replaces:/m)
  expect(MIG).toMatch(/^-- Retires:/m)
})

test('s1176: the full list is an admin read at the Data Delivery gate; the screen payload carries workers and attention only', () => {
  expect(code).toContain('create or replace function public.admin_pim_jobs_v1()')
  expect(code).toContain("coalesce(security.current_role_rank(), 0) < 3")
  expect(code).toContain("revoke all on function public.admin_pim_jobs_v1() from public, anon;")
  expect(code).toContain("'attention'")
  expect(code).not.toMatch(/'components',\s*coalesce\(\(select rows->'components' from js\)/)
})
