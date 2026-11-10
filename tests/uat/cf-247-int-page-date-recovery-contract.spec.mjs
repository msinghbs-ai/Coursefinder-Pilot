// Guards: Platform Admin directive 10 Nov 2026 14:02 (admit verified exact intake dates and deadlines faster from stored sources; never invent a day, month, year or deadline; no blanket switch-on of central.auto_approve_calendar_dates or intake_dates.month_unique_match): source contract over migrations 20261110170000 and 20261110171000, their forward recoveries, the CI wiring and the screen key. The behaviour is proved by tests/fixtures/intake-page-date-recovery/run.sh.
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M1 = fs.readFileSync('supabase/migrations/20261110170000_cf247_intake_page_date_recovery.sql', 'utf8')
const M2 = fs.readFileSync('supabase/migrations/20261110171000_cf247_dd_intake_delivery.sql', 'utf8')
const R1 = fs.readFileSync('supabase/held/intake_page_date_recovery_forward_recovery.sql', 'utf8')
const R2 = fs.readFileSync('supabase/held/dd_intake_delivery_forward_recovery.sql', 'utf8')
const WF = fs.readFileSync('.github/workflows/intake-run-validate-test.yml', 'utf8')
const UI = fs.readFileSync('src/DataDelivery.jsx', 'utf8')
const RUN = fs.readFileSync('tests/fixtures/intake-page-date-recovery/run.sh', 'utf8')
const DDFN = M2.slice(M2.indexOf('create or replace function security.data_delivery_intake_v1'), M2.indexOf('$int$;', M2.indexOf('as $int$')))

const PLAN = ['0d11bc5dfc4b0705f0722a1aa7905db6', '06255497ef431b0ae0d9fca6460c6cb5']
const PD = ['80eb7b805fa1d68910623c46308c15da', '52bad9ded722b889b97c746b7209e63a']
const HINT = '6adf9102074633735e9f30ffe529072c'

test('the page-date migration follows the house pattern: header, md5-guarded edits of two functions, one read-only function, nothing dropped, no setting touched', () => {
  expect(M1).toMatch(/^-- Replaces: security\.intake_dates_plan_v3 and security\.intake_page_date_v1 are edited in place/m)
  expect(M1).toMatch(/^-- Retires: nothing$/m)
  expect(M1).toContain(`--   security.intake_dates_plan_v3(uuid[],integer) ${PLAN[0]} -> ${PLAN[1]}`)
  expect(M1).toContain(`--   security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer) ${PD[0]} -> ${PD[1]}`)
  expect(M1).toContain(`--   security.intake_page_date_hint_v1(uuid,uuid,text) (new) -> ${HINT}`)
  expect(M1).toContain("raise exception 'live % differs from the definition this change edits (body md5 %)'")
  expect(M1).toContain('supabase/held/intake_page_date_recovery_forward_recovery.sql')
  expect(M1).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(M1).not.toMatch(/\balter\s+table\b/i)
  expect(M1).not.toMatch(/^\s*(insert into|update)\s+(?!pipeline\.component_register)/im)   // the only write is the component register row
  expect(M1).not.toMatch(/platform_toolset_settings/)                                        // no setting value is written or created
  expect(M1).toContain('revoke all on function security.intake_page_date_hint_v1(uuid, uuid, text) from public, anon, authenticated;')
  expect(M1).not.toMatch(/\bgrant\b/i)
})

test('the three protected controls are not switched on, and nothing consumer-facing is read or changed (G3)', () => {
  expect(M1).not.toMatch(/auto_approve_calendar_dates['"]?\s*[,)]?\s*(=|to_jsonb|,)\s*['"]?1/)
  expect(M1).not.toMatch(/month_unique_match['"]?\s*[,)]?\s*(=|to_jsonb)/)
  for (const t of [M1, M2]) expect(t.replace(/^--.*$/gm, '')).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  // the fill is still written by the existing job: this change adds no job, table or setting
  expect(M1).not.toMatch(/cron\.schedule|create table|create index/i)
  expect(M2).not.toMatch(/cron\.schedule|create table|create index/i)
})

test('the plan looks at a row whose stored page prints a date only while the page-date switch is on, takes it first and keeps the batch size', () => {
  expect(M1).toContain('case when v_page_admit and i.start_date is null then security.intake_page_date_hint_v1(i.course_id, i.evidence_id, i.intake_label) else false end as ready')
  expect(M1).toContain("case when pd.sfx then ';pagedate=1' else '' end")
  expect(M1).toContain('order by case when q.pdready then 0 when q.pilot and q.pilot_seq <= v_pilot_rows then 1 when not q.pilot then 2 else 3 end')
  expect(M1).toContain("row_number() over (partition by c.provider_id, pd.ready order by i.course_id, i.id)")   // fair by university within the tier
  expect(M1).not.toMatch(/\blimit\s+\d/i)
  // a held exact date keeps its rule and quote
  expect(M1).toContain("rule := coalesce(rule, 'calendar-v3'); outcome := 'nothing_new';")
})

test('the page reader never takes a year heading for the year of the date before it, and never admits a day without a year, a range or an unproven audience', () => {
  expect(M1).toContain('(?!\\s*:)')
  expect(M1).toContain("'the course page prints ' || d || ' but no approved main calendar start is on that day and the page does not show the audience (page only): not admitted'")
  expect(M1).toContain("'the course page prints a range of days for '")
  expect(M1).toContain("'the course page prints several different '")
  expect(M1).toContain('a rejected value, or a value withdrawn from this intake, is never admitted again')
})

test('the Data Delivery migration adds one read-only function and one key for the intake stream only, md5-guarded', () => {
  expect(M2).toMatch(/^-- Replaces: security\.data_delivery_v1 is edited in place/m)
  expect(M2).toMatch(/^-- Retires: nothing$/m)
  expect(M2).toContain('--   security.data_delivery_v1() 849453412a8b9a448118e7b87362752a -> 630f8696c18ff05703bb9798ed6fe8fa')
  expect(M2).toContain('--   security.data_delivery_intake_v1() (new) -> ed0361e1ab65cf4525836f4fdd055287')
  expect(M2).toContain("'intake_delivery', case when s.stream = 'int' then security.data_delivery_intake_v1() end,")
  expect(M2).toContain("if md5(v_src) = r.md5_after then continue; end if; -- already applied")
  expect(M2).toContain('revoke all on function security.data_delivery_intake_v1() from public, anon, authenticated;')
  expect(M2.match(/create or replace function /g)).toHaveLength(1)
  expect(M2).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(DDFN).toMatch(/language plpgsql stable security definer set search_path to ''/)
  expect(DDFN).not.toMatch(/\b(insert|update|delete|truncate)\b/i)
  expect(DDFN).toContain("'known', false, 'reason', 'the intake delivery counts could not be made: ' || sqlerrm")
})

test('no operational value is written into the Data Delivery function (G2): the windows and switches are settings, the only literals are text rules', () => {
  expect(DDFN).toContain("security.pipeline_num_v1('data_delivery.net_short_hours', 24)")
  expect(DDFN).toContain("security.pipeline_num_v1('data_delivery.net_long_hours', 168)")
  expect(DDFN).toContain("security.toolset_setting('pipeline', 'intake_dates.apply_enabled')")
  expect(DDFN).toContain("security.pipeline_num_v1('intake_dates.page_date_admit', 0)")
  expect(DDFN).not.toMatch(/\blimit\s+\d/i)
  expect(DDFN).not.toMatch(/interval\s+'\d/i)
  // the causes are kept apart: month-only is not mixed with what a run can still take
  expect(DDFN).toContain("when c.reason like '%(month only)%' then 'month_only'")
  expect(DDFN).toContain("security.intake_page_date_hint_v1(c.course_id, c.evidence_id, c.intake_label) then 'page_date_waiting'")
  expect(DDFN).toContain("when c.reason like '%page does not show the audience%'")
})

test('the forward recoveries restore the live text and are guarded by the md5 of what is live', () => {
  expect(R1).toContain(`v_p not in ('${PLAN[0]}', '${PLAN[1]}') or v_d not in ('${PD[0]}', '${PD[1]}')`)
  expect(R1).toContain("raise exception 'live security.intake_dates_plan_v3 or security.intake_page_date_v1 differs from both texts this recovery knows")
  expect(R1).toContain(`<> '${PLAN[0]}' then raise exception 'the plan was not restored byte for byte'`)
  expect(R1.slice(R1.indexOf('CREATE OR REPLACE FUNCTION'))).not.toContain('pagedate=1')   // the restored plan has no suffix
  expect(R2).toContain("if v not in ('630f8696c18ff05703bb9798ed6fe8fa', '849453412a8b9a448118e7b87362752a') then raise exception 'live security.data_delivery_v1() differs from both texts this recovery knows")
  expect(R2.slice(R2.indexOf('CREATE OR REPLACE FUNCTION'))).not.toContain('intake_delivery')
  for (const r of [R1, R2]) expect(r).not.toMatch(/^\s*drop\b/im)
})

test('the screen draws the new key in the existing panel; a missing key is Not measured; no second dashboard', () => {
  expect(UI).toContain("{s.stream==='int'&&<IntakeDelivery d={s.intake_delivery}/>}")
  expect(UI).toContain('data-dd-intake-delivery="unknown"')
  expect(UI).toContain('d==null||d.known===false')
  expect(UI).toContain("month_only:['Month or season only: no day (or no year) is printed','unresolvable']")
  expect((UI.match(/export default function/g) || []).length).toBe(1)
})

test('CI runs the fixture after the self-driving harness and keeps the log', () => {
  expect(WF).toContain('run: bash tests/fixtures/intake-page-date-recovery/run.sh | tee intake-page-date-recovery-results.log')
  expect(WF.indexOf('intake-page-date-recovery/run.sh')).toBeGreaterThan(WF.indexOf('intake-self-driving/run.sh'))
  expect(WF).toContain("'tests/fixtures/intake-page-date-recovery/**'")
  expect(RUN).toContain('PLAN_BEFORE=0d11bc5dfc4b0705f0722a1aa7905db6; PLAN_AFTER=06255497ef431b0ae0d9fca6460c6cb5')
  expect(RUN).toContain('DD_BEFORE=849453412a8b9a448118e7b87362752a; DD_AFTER=630f8696c18ff05703bb9798ed6fe8fa')
})
