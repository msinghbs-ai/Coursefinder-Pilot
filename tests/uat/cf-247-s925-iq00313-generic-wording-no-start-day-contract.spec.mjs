// Guards: CF-247 s925 (P0 IQ-00313, Platform Admin 21 Nov 2026 10:57 AEDT, session S1-Fix-IQ00313): calendar-v3 never takes a start day from general course-page wording ("Most courses start in Semester 1 each year, usually in the last week of February"); such an intake keeps year and month only, live at once, and the ECU admissions it made (086244B and two more) are withdrawn to year and month with their history, evidence and locks kept and the Website and Zoho items reconciled
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261121170000_cf247_s925_iq00313_generic_wording_no_start_day.sql', 'utf8')
const edit = MIG.slice(MIG.indexOf("select pg_temp.edit_all('security.intake_dates_plan_v3"), MIG.indexOf('$n2$]);'))
const spec = MIG.slice(MIG.indexOf('create or replace function security.intake_wording_specific_v1'), MIG.indexOf('comment on function security.intake_wording_specific_v1'))
const withdraw = MIG.slice(MIG.indexOf('create or replace function security.intake_date_day_withdraw_v1'), MIG.indexOf('comment on function security.intake_date_day_withdraw_v1'))
const remedy = MIG.slice(MIG.indexOf('do $r$'), MIG.indexOf('end $r$;'))

// the sentence rule of security.intake_wording_specific_v1, in JavaScript (\m and \M are \b)
const pat = (name) => new RegExp(spec.match(new RegExp(`${name} ~\\* '([^']+)'`))[1].replace(/\\m|\\M/g, '\\b'), 'i')
const GENERAL = pat('t\\.x')
const HEDGE = new RegExp(spec.match(/t\.x ~\* '(\\m\(usually[^']+)'/)[1].replace(/\\m|\\M/g, '\\b'), 'i')
const THIS = new RegExp(spec.match(/t\.x !~\* '([^']+)'/)[1].replace(/\\m|\\M/g, '\\b'), 'i')
const specific = (text) => text.split(/\s*\|\s*|[.!?;]\s+/).filter((x) => x.trim() && !(GENERAL.test(x) || (HEDGE.test(x) && !THIS.test(x)))).join(' | ')

test('the general ECU sentence is not course-specific wording; course listings stay', () => {
  const ecu = 'ithin the duration of the student visa. Semester 1 Most courses start in Semester 1 each year, usually in the last week of February | visa. Semester 1'
  expect(specific(ecu)).not.toMatch(/february/i)
  expect(specific(ecu)).not.toMatch(/semester 1 most/i)
  expect(specific('There\'s a week of Orientation before each semester | Semester 2 A lot of our courses start in Semester 2 each year')).not.toMatch(/Semester 2/)
  expect(specific('noting that some programs are only available part time. Location Hobart Semester 1 Launceston Semester 1')).toBe('Location Hobart Semester 1 Launceston Semester 1')
  expect(specific('This course usually starts in Semester 1 (February)')).toMatch(/Semester 1/)
  expect(specific('Start date First Semester (February), Second Semester (July)')).toMatch(/July/)
})

test('the planner edit is md5-guarded both ways and reads periods from the specific wording only', () => {
  expect(edit).toContain("'020a047e45a9c8e82ad45be74a668b2b', 'cf7fff5026511c05be87c5e842a8570d'")
  expect(edit).toContain('v_spec := security.intake_wording_specific_v1(v_raw);')
  expect(edit).toContain('v_pq := security.intake_period_text_canonical_v1(security.intake_period_text_v1(v_spec, v_lists));')
  expect(edit).toContain('v_named_all := v_named;')
})

test('general wording takes no start day by any route: year and month, or month only', () => {
  const block = edit.slice(edit.indexOf('if v_generic then'))
  expect(block).not.toMatch(/new_start\s*:=/)
  expect(block).not.toContain("start_precision := 'day'")
  expect(block).toContain("outcome := 'filled'; new_year := v_year;")
  expect(block).toContain("outcome := 'skipped'; start_precision := 'month';")
  expect(block).toContain("w.outcome = 'withdrawn'")
  expect(block).toContain('make_interval(months => v_ahead)')
  // it runs before the page-date, Rule B and unique-month routes
  expect(block.indexOf('return next; outcome := null; continue;')).toBeGreaterThan(0)
  expect(edit).not.toContain('intake_nearest_start_v1')
})

test('live at once: no switch, no shadow, no new setting or job', () => {
  expect(MIG).not.toMatch(/pipeline_num_v1\('intake_dates\.generic/)
  expect(MIG).not.toMatch(/insert into pipeline\.platform_toolset_settings|update pipeline\.platform_toolset_settings/)
  expect(MIG).not.toMatch(/cron\.schedule|cron\.unschedule/)
  expect(MIG).not.toMatch(/\w_shadow|shadow_\w/i)
})

test('the withdrawal takes back the start day only, keeps the year, places no hold and records the rejected day', () => {
  expect(withdraw).toContain('update catalogue.course_intakes set start_date = null where id = p_intake;')
  expect(withdraw).not.toMatch(/intake_year\s*=/)
  expect(withdraw).not.toMatch(/insert into pipeline\.manual_locks/)
  expect(withdraw).not.toMatch(/\bdelete\b/i)
  expect(withdraw).toContain("'withdrawal', 'withdrawn'")
  expect(withdraw).toContain("k.field in ('all', 'intakes', 'intake')")
})

test('the remediation is found by the same rule, names the three ECU intakes, and checks Website, Zoho, locks, cron and the consumer API', () => {
  for (const id of ['301b33a0-98e0-43f1-8cf2-744507d98413', 'f60ca583-ef95-47d7-9369-989cb368bc8f', '275b1fa8-29a7-481d-b5c9-c7299541923f']) expect(remedy).toContain(id)
  expect(remedy).toContain('security.intake_wording_specific_v1(w.raw)')
  expect(remedy).toContain('security.intake_date_day_withdraw_v1(r.id, v_reason,')
  expect(remedy).toContain('security.intake_projection_reconcile_v1(v_courses)')
  expect(remedy).toContain("api.website_v2_course_item(i.course_id)->'intakes'")
  expect(remedy).toContain("coalesce(c->'zoho', '[]'::jsonb)")
  expect(remedy).toContain('security.intake_dates_plan_v3(v_courses, 50)')
  expect(remedy).toContain("'IQ-00313-GENERIC-WORDING-20261121'")
  expect(MIG).toContain("(select count(*) from pipeline.manual_locks) <> (select n from s925_locks)")
  expect(MIG).toContain("(select count(*) from cron.job where active) <> (select n from s925_cron)")
  expect(MIG).toMatch(/\(v->>'functions'\)::int <> 75 or \(v->>'relations'\)::int <> 48/)
  expect(MIG).not.toMatch(/\bdrop\s+(function|table|index)/i)
})
