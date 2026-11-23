// Guards: CF-247 s987 (session S2-INT, Platform Admin 23 Nov 2026 13:02 AEDT, immediate live activation mandate 21 Nov 2026 10:07): the s986 planner rule is applied to the courses it frees in one run through the existing apply function, in three parts, with no new function, setting, job or consumer API change.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const FILES = [1, 2, 3].map((n) => fs.readFileSync(`supabase/migrations/2026112314000${n - 1}_cf247_s987_int_named_period_rescue_apply_${n}.sql`, 'utf8'))

test('three parts, each applies only after the s986 planner text is live', () => {
  expect(FILES).toHaveLength(3)
  for (const m of FILES) expect(m).toContain("<> 'f05b31dd74378cce5cdc77f0b20abb79'")
})

test('each part runs the existing apply function for the held courses only (same planner, locks and fingerprints)', () => {
  for (const m of FILES) {
    expect(m).toContain('security.intake_dates_apply_v1(v_lim, v_ids)')
    expect(m).toContain("d.reason like 'the named period starts sooner%'")
    expect(m).toContain('i.start_date is null')
    expect(m).toContain("i.status = 'active'")
  }
})

test('the three parts split the courses by a hash and cover 0, 1 and 2 once each; no provider is named', () => {
  expect(FILES.map((m) => (m.match(/, 3\) = (\d);/) || [])[1])).toEqual(['0', '1', '2'])
  for (const m of FILES) expect(m).not.toMatch(/provider_id::text like|36086f5e|c5c5d225/)
})

test('no date is written outside the planner and nothing in the consumer API, locks or cron changes', () => {
  for (const m of FILES) {
    expect(m).not.toMatch(/update catalogue\.course_intakes|insert into catalogue\.course_intakes/)
    expect(m.match(/consumer_api_check_v1\(\)/g)).toHaveLength(2)
    expect(m).toContain("(v->>'functions')::int <> 75")
    expect(m).toContain('pipeline.manual_locks')
    expect(m).toContain('cron.job where active')
    expect(m).toContain('a filled decision lacks its quote or calendar')
  }
})

test('live at once: no setting, job, schedule, shadow or drop; no number in code but the part split', () => {
  for (const m of FILES) {
    expect(m).not.toMatch(/platform_toolset_settings|cron\.schedule|cron\.unschedule|\w_shadow|shadow_\w/i)
    expect(m).not.toMatch(/\bdrop\s+(function|table|index)/i)
    expect(m).toMatch(/^-- Replaces: nothing/m)
    expect(m).toMatch(/^-- Retires: nothing/m)
  }
})
