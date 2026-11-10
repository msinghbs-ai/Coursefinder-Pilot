// Guards: Decision 271 (Platform Admin 10 Nov 2026), Rule B in the intake planner for listed providers only: intake_dates.nearest_start_providers decides who takes the nearest main-teaching start; the list ships empty; only listed providers' rows are looked at again; the withdrawn-value and offering checks apply; month_unique_match stays 0 (P0 IQ-00313).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261111130000_cf247_intake_nearest_start_planner.sql', 'utf8')
const helper = MIG.slice(MIG.indexOf('create or replace function security.intake_nearest_start_v1'), MIG.indexOf('revoke all on function security.intake_nearest_start_v1'))

test('the planner edit is md5-guarded both ways and applies each edit exactly once', () => {
  expect(MIG).toContain("select pg_temp.edit_all('security.intake_dates_plan_v3(uuid[],integer)', '33e3fef045dbcfa8a0406c64402d4d29', 'ef496c19edb842c19a6aa1aef19e3644',")
  expect(MIG).toContain("if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)'")
  expect(MIG).toContain("<> 'ef496c19edb842c19a6aa1aef19e3644' then")
})

test('only listed providers take Rule B, and only their rows are looked at again', () => {
  expect(MIG).toContain("s.key = 'intake_dates.nearest_start_providers' and jsonb_typeof(s.value) = 'array'")
  expect(MIG).toContain("if r.provider_id = any (v_near) then")
  expect(MIG.match(/case when [cr]\.provider_id = any \(v_near\) then ';near=' \|\| v_near_days else '' end/g)).toHaveLength(3)   // the query fingerprint, its revisit check and the stored fingerprint
  expect(MIG).toContain("rule := 'calendar-v3-nearest-start'")
})

test('the withdrawn-value and offering checks apply before a fill', () => {
  const branch = MIG.slice(MIG.indexOf('if r.provider_id = any (v_near) then'), MIG.indexOf("rule := 'calendar-v3-nearest-start'"))
  expect(branch).toContain("w.outcome = 'withdrawn'")
  expect(branch).toContain('security.intake_course_applicability_v1(v_raw, v_m,')
})

test('the helper keeps the audit guards and the course-level check', () => {
  expect(helper).toContain("l.code in ('doctorate', 'masters_research')")
  expect(helper).toContain("(rolling|flexible|continuous|any ?time|multiple intakes|throughout the year)")
  expect(helper).toContain("!~* '(applications?\\s+(open|close)|census|orientation|o-?week|enrol)'")
  expect(helper).toContain('another academic calendar applies')
  expect(helper).toContain('would take the same calendar start')
  expect(helper).toContain('the course page gives its own start date for this intake')
  expect(helper).not.toMatch(/\b(insert into|update |delete from)/i)
})

test('nothing is switched on: the list ships empty and the unique-month containment stays', () => {
  expect(MIG).not.toMatch(/update pipeline\.platform_toolset_settings/)
  expect(MIG).toContain("post-check: this change lists no provider; a Platform Admin lists one with a reason")
  expect(MIG).toContain("security.pipeline_num_v1('intake_dates.month_unique_match', 0) <> 0 then raise exception")
})
