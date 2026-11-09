// Guards: F-INT (valid course intake dates; Platform Admin data population first delivery mandate, 9 Nov 2026, coordinator extension 9 Nov 2026): the applicability gate no longer raises on "<Month> <Year>" wording (migration 20261109041000), and a start date printed on the course page is admitted only behind a switch that is off, only when corroborated, never for page-only evidence, a how-to-apply page, a rejected or withdrawn value or a date outside the horizon (migration 20261109042000); G2 (the switch is a setting), G3 (consumer API untouched), Decision 266, and the Platform Admin keeps central.auto_approve_calendar_dates and central.calendar_excluded_words.
// Source contract over migrations 20261109041000 and 20261109042000 and the isolated-PostgreSQL fixture tests/fixtures/intake-self-driving (cases-d1-before.sql, cases-d1-after.sql, run by .github/workflows/intake-run-validate-test.yml; its result is reported with the branch).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M41 = 'supabase/migrations/20261109041000_cf247_intake_applicability_month_year.sql'
const M42 = 'supabase/migrations/20261109042000_cf247_intake_page_date_admission.sql'
const FX = 'tests/fixtures/intake-self-driving'
const read = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')
const sql41 = fs.readFileSync(M41, 'utf8')
const sql42 = fs.readFileSync(M42, 'utf8')
const strip = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const body41 = strip(sql41)
const body42 = strip(sql42)

test('applicability fix: one md5-guarded edit makes the month group non-capturing, so the year is the group read; nothing else changes', () => {
  expect(sql41).toContain("'security.intake_course_applicability_v1(text,integer,integer,jsonb,boolean,text[],text)', 'd3789be9c8dee10f31868700b11abf89'")
  expect(sql41.replace(/\s+/g, ' ')).toContain("array[$o$v_w := '(' || v_names[k]$o$], array[$n$v_w := '(?:' || v_names[k]$n$], array[1]")
  expect(sql41).toMatch(/^-- Replaces: .*intake_course_applicability_v1/m)
  expect(sql41).toMatch(/^-- Retires: nothing/m)
  expect(body41).toContain('comment on function security.intake_course_applicability_v1(')
  expect(body41).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(body41).not.toMatch(/create table|cron\.schedule|insert into pipeline\.platform_toolset_settings/i)
  const before = read('cases-before.sql')
  for (const t of ['Start dates: February 2027 intake', 'Start dates 25 January 2027 for international students', "'ERROR 22P02'"]) expect(before).toContain(t)
  const after = read('cases-after.sql')
  expect(after).toContain('PASS applicability fix')
})

test('D1: the route is a setting that is off by default, with label, range, unit, section and used_by (G2); nothing operational is written into code', () => {
  expect(body42).toMatch(/insert into pipeline\.platform_toolset_settings[\s\S]*'intake_dates\.page_date_admit'/)
  expect(body42).toMatch(/'number', to_jsonb\(0\), 0, 1, 'on\/off', 1014, 'Intake dates'/)
  expect(body42).toContain('on conflict (toolset_key, key) do nothing')
  expect(body42).toContain("security.pipeline_num_v1('intake_dates.page_date_admit', 0) = 1")
  // the horizon is the existing setting, passed in; no number of months or days is written into the helper
  expect(body42).not.toMatch(/interval\s+'\d/i)
  expect(body42).not.toMatch(/\blimit\s+\d+/i)
  expect(body42).toContain('make_interval(months => p_ahead)')
})

test('D1: the helper is read-only and admits only with every condition: one full date with its year, label, horizon, no rejected or withdrawn value, and P1 or P2', () => {
  const fn = body42.slice(body42.indexOf('create or replace function security.intake_page_date_v1'), body42.indexOf('comment on function security.intake_page_date_v1'))
  expect(fn).toContain('stable security definer set search_path to')
  expect(fn).not.toMatch(/\b(insert|update|delete)\b\s+(into|pipeline|catalogue|public)/i)
  expect(fn).not.toMatch(/net\.http|http_post|crawl\(|firecrawl|openrouter|pg_net/i)
  // single distinct date, a range is refused, a closing/census/orientation sentence is ignored
  expect(fn).toContain('cardinality(v_dates) > 1')
  expect(fn).toContain('v_range')
  expect(fn).toMatch(/deadlines\?\|clos/)
  expect(fn).toMatch(/census\|orientation/)
  // the year is printed and equals the intake's year; not past; inside the horizon
  expect(fn).toContain('p_intake_year <> v_y')
  expect(fn).toContain('d < p_today')
  expect(fn).toContain('p_ahead')
  // a rejected value and a withdrawn value are never admitted again
  expect(fn).toContain('pipeline.intake_date_rejections')
  expect(fn).toContain("w.outcome = 'withdrawn'")
  // the section label is required before the date; the quote is the stored snippet
  expect(fn).toContain('without a section label')
  // P1: an approved calendar start on that day, pathway and foundation excluded, excluded words read from the setting (not edited here)
  expect(fn).toContain("s.kind = 'start' and s.on_date = d and coalesce(s.year_ok, false)")
  expect(fn).toContain("(pathway|foundation)")
  expect(fn).toContain("security.toolset_setting('pipeline', 'central.calendar_excluded_words')")
  // P2: the audience is shown; P3 is not admitted
  expect(fn).toContain("v_route := 'P2'")
  expect(fn).toContain('page only): not admitted')
  expect(fn).toContain('pipeline.uni_adapters')
})

test('D1: the plan edit is md5-guarded, adds the route behind the switch before the calendar route, and records the fill as every fill is recorded', () => {
  expect(body42).toContain("'security.intake_dates_plan_v3(uuid[],integer)', '1c42216aec7113b5b628396edbe42386'")
  expect(body42).toContain('array[1, 1]')
  expect(body42).toContain("if v_page_admit and v_named is null and r.start_date is null and coalesce(v_raw, '') <> ''")
  // the instruction: E16 and refusal come first in the plan (this edit sits after them); the offering gate and the course lock/hold are still the plan's own
  expect(body42).toContain("rule := 'page-date-v1'; start_precision := 'day'; start_quote := v_pd->>'quote'; deadline_kind := 'not_stated'")
  expect(body42).toContain('security.intake_course_applicability_v1(')
  expect(body42).toContain("when reason like 'withdrawn:%' then 'human_decision_required'")
  expect(body42).toContain('and not v_unique')
  // the existing paths write it: no write, no event, no table is added
  expect(body42).not.toMatch(/create table|cron\.schedule|insert into pipeline\.course_intake_date_events|update catalogue\./i)
  expect(sql42).toMatch(/^-- Replaces: .*intake_dates_plan_v3/m)
  expect(sql42).toMatch(/^-- Retires: nothing/m)
})

test('D1: the Platform Admin keeps the calendar settings (nothing here writes central.auto_approve_calendar_dates or central.calendar_excluded_words)', () => {
  expect(body42).not.toMatch(/(update|insert into|delete from)\s+pipeline\.platform_toolset_settings[^;]*central\./i)
  expect(body42).not.toMatch(/auto_approve_calendar_dates/)
  expect(body42.match(/central\.calendar_excluded_words/g)?.length).toBe(1)   // read in the helper only
  expect(body42).not.toMatch(/set value\s*=[^;]*calendar_excluded_words/i)
  const after = read('cases-d1-after.sql')
  expect(after).toContain("key like 'central.%'")
})

test('governance: nothing is dropped or deleted, no consumer API object is touched, comments and revokes are present', () => {
  for (const b of [body41, body42]) {
    expect(b).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
    expect(b).not.toMatch(/create or replace function (api|public)\./i)
    expect(b).not.toMatch(/(website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1)/)
  }
  expect(body42).toContain('revoke all on function security.intake_page_date_v1(uuid, uuid, uuid, uuid, text, integer, integer, jsonb, date, integer) from public, anon, authenticated;')
  expect(body42).toContain('comment on function security.intake_page_date_v1(')
  expect(body42).toContain('comment on function security.intake_dates_plan_v3(')
  // the numbering follows PR 930 (20261109030000)
  for (const m of [M41, M42]) expect(Number(m.match(/migrations\/(\d{14})/)[1])).toBeGreaterThan(20261109030000)
})

test('fixture: production-shaped cases (Federation P1, Canberra P2, Macquarie and Western Sydney P3, Adelaide how-to-apply, Deakin 2028) and the run are wired in', () => {
  const b = read('cases-d1-before.sql')
  const a = read('cases-d1-after.sql')
  for (const t of ["'Federation'", "'Canberra'", "'Macquarie'", "'Adelaide'", "'Deakin'", 'how-to-apply', 'Open for international admissions', 'Location and start dates', 'Next Start Date']) expect(b).toContain(t)
  for (const t of ['PASS D1 setting', 'PASS D1 default off', 'PASS D1 admit', 'PASS D1 refuse', 'PASS D1 evidence stored', 'PASS D1 job and events', 'PASS D1 consumer path', 'PASS D1 Deakin', 'PASS D1 performance', 'PASS D1 order']) expect(a).toContain(t)
  // the gross, withdrawn and net can be measured by rule from the events
  expect(a).toContain("e.outcome = 'filled' and e.rule = 'page-date-v1'")
  expect(a).toContain("count(*) filter (where e.outcome = 'withdrawn')")
  const run = read('run.sh')
  expect(run).toContain('MIG3=supabase/migrations/20261109042000_cf247_intake_page_date_admission.sql')
  expect(run).toContain('PASS migration 20261109042000 applied twice without change')
  expect(run).toContain('PASS consumer API frozen after 20261109042000')
  expect(run).toContain("'security.intake_course_applicability_v1(text,integer,integer,jsonb,boolean,text[],text) d3789be9c8dee10f31868700b11abf89'")
  const wf = fs.readFileSync('.github/workflows/intake-run-validate-test.yml', 'utf8')
  expect(wf).toContain("'tests/fixtures/intake-self-driving/**'")
})
