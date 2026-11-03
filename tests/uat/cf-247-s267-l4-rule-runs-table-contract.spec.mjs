// Guards: mandate 3 Nov 2026 20:47 §4 and overnight mandate 21:59 D1–D2 (approved Course Link rules applied item by item); v2.15.447 production defect (rule executor wrote into a live-only table)
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const mig = fs.readFileSync('supabase/migrations/20261104280000_cf247_l4_rule_runs_table.sql', 'utf8')

test('the course-link rule executor records its runs and items in its own tables', () => {
  expect(mig).toContain('create table if not exists pipeline.layer4_course_link_rule_runs (')
  expect(mig).toContain('create table if not exists pipeline.layer4_course_link_rule_run_items (')
  expect(mig).toContain("array['pipeline.layer4_rule_run_items', 'pipeline.layer4_course_link_rule_run_items']")
  expect(mig).toContain("array['pipeline.layer4_rule_runs', 'pipeline.layer4_course_link_rule_runs']")
})

test('md5-guarded edit from the live executor; nothing else in it changes', () => {
  expect(mig).toContain("pg_temp.edit_once('security.layer4_course_link_rule_execute_v1(text,integer,boolean)', 'd4aa914546830dd299ace2b000725643', '86e1089a5e93e1e2cce9a0ffd29aa22b',")
  expect(mig).toContain('array[4, 2]')
})

test('the live-only table keeps its rows and writers; the empty misnamed items table is only marked retiring', () => {
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(mig).toContain("comment on table pipeline.layer4_rule_runs is 'Runs of the Layer 4 automatic rules")
  expect(mig).toMatch(/set status = 'retiring', replaced_by = 'pipeline\.layer4_course_link_rule_run_items'/)
  expect(fs.existsSync('tests/fixtures/l4-rule-runs-table/run.sh')).toBe(true)
})
