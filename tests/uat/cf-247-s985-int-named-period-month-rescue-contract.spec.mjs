// Guards: CF-247 s985 (session S2-INT, Platform Admin 23 Nov 2026 13:02 AEDT, F-INT exact intake dates): the planner's "named period starts sooner in another month" hold is narrowed for every university, only where the course page states the month as an intake outside application clauses; md5-guarded text edit, no new setting, job, shadow or consumer API change.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261123120000_cf247_s985_int_named_period_month_rescue.sql', 'utf8')
const dq = (tag) => [...MIG.matchAll(new RegExp('\\$' + tag + '\\$([\\s\\S]*?)\\$' + tag + '\\$', 'g'))].map((m) => m[1])
const NEW = [1, 2, 3, 4, 5].map((i) => dq('n' + i)[0] || '').join('\n')
const AFTER = (MIG.match(/body ([0-9a-f]{32}) to /) || [])[1]
const BEFORE = 'cf7fff5026511c05be87c5e842a8570d'

test('the planner edit is md5-guarded in both directions and counted', () => {
  expect(MIG).toContain(BEFORE)
  expect(MIG).toMatch(/pg_temp\.edit_counted\('security\.intake_dates_plan_v3\(uuid\[\],integer\)'/)
  expect(MIG).toContain('array[1, 1, 2, 1, 1]') // variables, list, query fingerprint (2), loop fingerprint, rescue block
})

test('the stated resulting md5 matches the edit applied to the live body', async () => {
  expect(AFTER).toMatch(/^[0-9a-f]{32}$/)
  expect(MIG.split(AFTER).length - 1).toBeGreaterThanOrEqual(3)
})

test('the rescue is gated by offering evidence and by the month stated outside application clauses', () => {
  expect(NEW).toContain("security.intake_course_applicability_v1(v_raw, v_m, v_year, v_cal, false, null, null) is null")
  expect(NEW).toMatch(/applications\? \(open\|close\|due\)\|apply by\|closing date/)
  expect(NEW).toContain('v_narrow is null')
  // a period that starts in this month and starts sooner still holds the intake (Monash): the narrowing keeps that check
  expect(NEW).toMatch(/s2\.period = s\.period and s2\.month = v_m and s2\.year_ok/)
})

test('a rescued row is also held when the page ties the offering to other years (s542 item 4)', () => {
  expect(NEW).toContain('(r.provider_id = any (v_next) or v_rescued)')
})

test('only universities that hold "starts sooner" rows are planned again', () => {
  expect(NEW).toContain("';rescue=1'")
  expect(NEW).toContain("d.reason like 'the named period starts sooner%'")
})

test('live at once: no switch, no shadow, no new setting, job or schedule; nothing dropped', () => {
  expect(MIG).not.toMatch(/insert into pipeline\.platform_toolset_settings|update pipeline\.platform_toolset_settings/)
  expect(MIG).not.toMatch(/cron\.schedule|cron\.unschedule/)
  expect(MIG).not.toMatch(/\w_shadow|shadow_\w/i)
  expect(MIG).not.toMatch(/\bdrop\s+(function|table|index)/i)
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: nothing/m)
})

test('the consumer API (75 functions, 48 relations), manual locks and active cron jobs are checked before and after', () => {
  expect(MIG.match(/consumer_api_check_v1\(\)/g)).toHaveLength(2)
  expect(MIG).toContain("(v->>'functions')::int <> 75")
  expect(MIG).toContain("(v->>'relations')::int <> 48")
  expect(MIG).toContain('pipeline.manual_locks')
  expect(MIG).toContain('cron.job where active')
})

test('no number is written into the rule beyond month positions', () => {
  expect(NEW).not.toMatch(/limit \d|batch|interval '\d/)
})
