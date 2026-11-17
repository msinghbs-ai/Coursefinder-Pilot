// Guards: Cron dispatchers rule (Platform Admin 15 Nov 2026 22:36) for the consolidation PR 3 cutover, brought forward by the Platform Admin 17 Nov 2026 23:02 (24-hour window waived): it applies only after #1227 and a clean last-hour shadow report for all 13 lanes with every legacy job unchanged; in one transaction the lanes go live (held exactly where the legacy job was idle-paused) and the legacy jobs are switched off and marked retiring; nothing is unscheduled or dropped by the migration
// CF-247 S595. Migration 20261118012000_cf247_pr3_coverage_lane_dispatch_cutover.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118012000_cf247_pr3_coverage_lane_dispatch_cutover.sql', 'utf8')

test('the gate: once only, prerequisite applied, last-hour shadow clean for 13 lanes, legacy commands and schedules unchanged, no person-paused job', () => {
  expect(M).toContain("raise exception 'gate: a lane is already live; this cutover runs once'")
  expect(M).toContain("raise exception 'gate: the prerequisite 20261118001000 (#1227) is not applied'")
  expect(M).toContain("v_rep jsonb := security.coverage_lane_shadow_report_v1(1)")
  expect(M).toContain("coalesce((v_rep->>'all_match')::boolean, false) is not true or coalesce((v_rep->>'targets')::int, 0) <> 13")
  expect(M).toContain("md5(j.command) = fr.call_md5 and md5(fr.call_sql) = fr.call_md5 and j.schedule = fr.schedule")
  expect(M).toContain("raise exception 'gate: a legacy job is switched off without a raised idle flag")
})

test('the cutover: lanes live and held where the legacy job was off, legacy jobs off and retiring, every change logged', () => {
  expect(M).toContain("perform cron.alter_job(r.jobid, active => false);")
  expect(M).toContain("update pipeline.field_execution_registry set mode = 'live', enabled = r.active, updated_at = now(),")
  expect(M).toContain("'dispatcher_cutover'")
  expect(M).toContain("set status = 'retiring', replaced_by = 'coverage-lane-dispatch (pipeline.field_execution_registry, mode live)',")
  expect(M).toContain("retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int")
  expect(M).toContain("raise exception 'post-check: a legacy coverage job is still switched on'")
  expect(M).toContain("raise exception 'post-check: a field lane is not disabled'")
})

test('housekeeping: replaces and retires lines; nothing unscheduled, dropped or deleted', () => {
  expect(M).toMatch(/-- Replaces: .+\n-- Retires: .+/)
  expect(M).toContain('PASTE-20261118-coverage-lane-legacy-unschedule.sql')
  expect(M).not.toMatch(/cron\.(schedule|unschedule)\s*\(/)
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
