// Guards: Decision 271 (Platform Admin 10 Nov 2026), Rule B shadow only: a stated month takes the one main-teaching start in the month, else the one start within intake_dates.nearest_start_days after it; ambiguity, rolling wording, a differing page date, research degrees and non-teaching calendar lines give no date; nothing is admitted and no provider uses it until listed one at a time (P0 IQ-00313 containment stays).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261111120000_cf247_intake_nearest_start_shadow.sql', 'utf8')
const fn = MIG.slice(MIG.indexOf('create or replace function security.intake_nearest_start_shadow_v1'), MIG.indexOf('revoke all on function security.intake_nearest_start_shadow_v1'))

test('the shadow writes only its own table and admits nothing', () => {
  expect(fn).not.toMatch(/(insert into|update|delete from)\s+(catalogue\.|pipeline\.course_intake_dates)/i)
  expect(fn).toContain('insert into pipeline.intake_nearest_start_shadow(')
  expect(MIG).toContain('alter table pipeline.intake_nearest_start_shadow enable row level security;')
  expect(MIG).toContain('comment on table pipeline.intake_nearest_start_shadow is')
  expect(MIG).toContain('revoke all on function security.intake_nearest_start_shadow_v1() from public, anon, authenticated;')
})

test('Rule B: one start in the month, else one within the window after it; two or more keep the month', () => {
  expect(fn).toContain("security.pipeline_num_v1('intake_dates.nearest_start_days', 35)")
  expect(fn).toContain("case when cardinality(c.s1) = 1 then 'in_month' when c.s1 is null and cardinality(c.s2) = 1 then 'next_start' end as path")
  expect(fn).toContain("when g.same_date_months > 1 then 'ambiguous'")
  expect(fn).toContain('security.calendar_dated_periods_v2(p.provider_id)')
  expect(fn).toContain('pipeline.intake_date_rejections')
  expect(fn).toContain("security.pipeline_num_v1('intake_dates.max_months_ahead', 18)")
})

test('the audit guards: research degrees, non-teaching calendar lines, rolling wording and a differing page date give no date', () => {
  expect(fn).toContain("coalesce(l.code, '') in ('doctorate', 'masters_research') as research")
  expect(fn).toContain("case when g.research then 'research_degree'")
  expect(fn).toContain("!~* '(applications?\\s+(open|close)|census|orientation|o-?week|enrol)'")
  expect(fn).toContain("(rolling|flexible|continuous|any ?time|multiple intakes|throughout the year)")
  expect(fn).toContain("then 'page_date_differs'")
  expect(fn).toContain('central.calendar_qualify_blocked_period_words')
})

test('no provider uses Rule B and the unique-month containment stays', () => {
  expect(MIG).toMatch(/'intake_dates\.nearest_start_providers'[\s\S]*?'list', '\[\]'::jsonb/)
  expect(MIG).toContain("security.pipeline_num_v1('intake_dates.month_unique_match', 0) <> 0 then raise exception")
  expect(MIG).toContain("post-check: no provider may use the nearest start yet")
  expect(MIG).not.toMatch(/update pipeline\.platform_toolset_settings/)
})
