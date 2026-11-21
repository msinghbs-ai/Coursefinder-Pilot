// Guards: CF-247 s940 (P0 IQ-00313, Platform Admin 21 Nov 2026 13:51 AEDT, session S1-Fix-IQ00313): a general description of the semesters ("Semesters One: late February to June Semester Two: July to early November") is general wording, so calendar-v3 gives year and month or month only, never an inferred day; Massey MY0418 goes back to July 2027 with no day, with history, evidence and locks kept and the Website and Zoho items reconciled, live at once
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261121220000_cf247_s940_iq00313_general_semester_spans.sql', 'utf8')
const fn = MIG.slice(MIG.indexOf('create or replace function security.intake_wording_specific_v1'), MIG.indexOf('comment on function security.intake_wording_specific_v1'))
const remedy = MIG.slice(MIG.indexOf('do $r$'), MIG.indexOf('end $r$;'))

// the sentence rules of security.intake_wording_specific_v1, in JavaScript (\m and \M are \b)
const js = (re) => new RegExp(re.replace(/\\m|\\M/g, '\\b'), 'i')
const pos = [...fn.matchAll(/t\.x ~\* '([^']+)'/g)].map((m) => js(m[1]))
const THIS = js(fn.match(/t\.x !~\* '([^']+)'/)[1])
const [GENERAL, HEDGE, SPAN_A, SPAN_B] = pos
const general = (x) => GENERAL.test(x) || (HEDGE.test(x) && !THIS.test(x)) || SPAN_A.test(x) || SPAN_B.test(x)
const specific = (text) => text.split(/\s*\|\s*|[.!?;]\s+/).filter((x) => x.trim() && !general(x)).join(' | ')

test('four general-wording rules: the two s925 rules and the two semester-span rules', () => {
  expect(pos).toHaveLength(4)
})

test('the Massey semester description is general wording in every stored window', () => {
  const massey = 'most courses vary from 12 weeks (single semester) to 24 teaching weeks over 2 semesters (7-8 months in total): Semesters One: late February to June | e semester) to 24 teaching weeks over 2 semesters (7-8 months in total): Semesters One: late February to June Semester Two: July to early November T'
  expect(specific(massey)).toBe('')
  expect(general('Semester Two: July to early November')).toBe(true)
  expect(general('Trimester 1: mid-March to the end of June')).toBe(true)
})

test('course-specific period wording is kept', () => {
  expect(specific('Semester 1: Study full-time at City Campus Semester 2: Study full-time at City Campus')).toMatch(/Semester 2/)
  expect(specific('Start date First Semester (February), Second Semester (July)')).toMatch(/July/)
  expect(specific('Location Hobart Semester 1 Launceston Semester 1')).toMatch(/Semester 1/)
  expect(specific('Semester two (July) Apply directly to Monash using course code A6031')).toMatch(/July/)
  expect(specific('Closing Date To commence study in semester 1 - November 30 of the previous year')).toMatch(/semester 1/)
})

test('the function body and the planner are md5-guarded; the planner is not edited', () => {
  expect(MIG).toContain("not in ('b2a128a1eaa26b4ea05fd03a352b9aab', '184872c2b652672715c8b87716361978')")
  expect(MIG).toContain("<> '184872c2b652672715c8b87716361978'")
  expect(MIG).toContain("<> 'cf7fff5026511c05be87c5e842a8570d'")
  expect(MIG).not.toContain('pg_temp.edit_all')
})

test('live at once: no switch, no shadow, no new setting or job', () => {
  expect(MIG).not.toMatch(/insert into pipeline\.platform_toolset_settings|update pipeline\.platform_toolset_settings/)
  expect(MIG).not.toMatch(/cron\.schedule|cron\.unschedule/)
  expect(MIG).not.toMatch(/\w_shadow|shadow_\w/i)
  expect(MIG).not.toMatch(/\bdrop\s+(function|table|index)/i)
})

test('the remediation re-finds MY0418 by the same rule, withdraws the day only, and checks Website, Zoho, the planner, locks, cron and the consumer API', () => {
  expect(remedy).toContain("'b20bfb7e-44c0-4fe4-bc99-6bacc843f97a'")
  expect(remedy).toContain('security.intake_wording_specific_v1(w.raw)')
  expect(remedy).toContain('security.intake_date_day_withdraw_v1(r.id, v_reason,')
  expect(remedy).toContain('security.intake_projection_reconcile_v1(v_courses)')
  expect(remedy).toContain("api.website_v2_course_item(i.course_id)->'intakes'")
  expect(remedy).toContain("coalesce(c->'zoho', '[]'::jsonb)")
  expect(remedy).toContain('security.intake_dates_plan_v3(v_courses, 50)')
  expect(remedy).toContain("'IQ-00313-GENERAL-SEMESTER-SPANS-20261121'")
  expect(MIG).toContain('(select count(*) from pipeline.manual_locks) <> (select n from s925_locks)')
  expect(MIG).toContain('(select count(*) from cron.job where active) <> (select n from s925_cron)')
  expect(MIG).toMatch(/\(v->>'functions'\)::int <> 75 or \(v->>'relations'\)::int <> 48/)
})
