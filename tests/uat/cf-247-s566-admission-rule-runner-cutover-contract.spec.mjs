// Guards: Cron dispatchers rule (Platform Admin 15 Nov 2026 22:36) for the consolidation PR 2 cutover: it applies only after a full 24-hour shadow report with all 20 rules matching and every legacy job unchanged; in one transaction the rules go live and the legacy jobs are switched off and marked retiring; nothing is unscheduled or dropped by the migration
// CF-247 S566. Migration 20261116190000_cf247_admission_rule_runner_cutover.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261116190000_cf247_admission_rule_runner_cutover.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the gate: 24-hour report window, all_match for 20 rules, legacy jobs unchanged, runs once', () => {
  expect(code).toContain("v_from > now() - interval '24 hours'")
  expect(code).toContain("coalesce((v_rep->>'all_match')::boolean, false) is not true or coalesce((v_rep->>'rules')::int, 0) <> 20")
  expect(code).toContain('md5(j.command) = ar.call_md5 and j.schedule = ar.schedule')
  expect(code).toContain("raise exception 'gate: a rule is already live; this cutover runs once'")
})

test('the cutover: rules live, legacy jobs off and retiring, each change logged, post-checks', () => {
  expect(code).toContain('perform cron.alter_job(r.jobid, active => false);')
  expect(code).toContain("update pipeline.admission_rules set mode = 'live'")
  expect(code).toContain("set status = 'retiring', replaced_by = 'admission-rule-runner")
  expect(code).toContain("security.pipeline_num_v1('hygiene.retire_after_days', 14)")
  expect(code).toContain("raise exception 'post-check: a legacy admission job is still switched on'")
})

test('nothing unscheduled or dropped by the migration', () => {
  expect(code).not.toMatch(/cron\.unschedule|^\s*(drop|delete|truncate)\b/im)
})
