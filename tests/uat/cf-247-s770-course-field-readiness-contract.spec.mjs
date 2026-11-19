// Guards: daily per-course field readiness (Platform Admin 19 Nov 2026 11:41): every active course × the 14 canonical API v3 fields is the admitted value (80 characters at most) or one of TRYING, POSSIBLE_NEEDS_SOURCE, NOT_POSSIBLE, EMPTY_NOT_STARTED; the export is read only, runs daily at 07:30 AEDT through the Management API, and its CSV and three summary tabs go to Google Drive Monitoring.
// CF-247 S770 (the directive's s721 was taken on main). scripts/telemetry/course-field-readiness.sql, .mjs; .github/workflows/course-field-readiness.yml
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build, FIELDS, STATES, DISPLAY_RULES, stateOf, csvCell } from '../../scripts/telemetry/course-field-readiness.mjs'

const SQL = fs.readFileSync('scripts/telemetry/course-field-readiness.sql', 'utf8')
const WF = fs.readFileSync('.github/workflows/course-field-readiness.yml', 'utf8')

test('the 14 canonical fields and the four non-value states, in the directive\'s order', () => {
  expect(FIELDS).toEqual(['official_url', 'description', 'study_load', 'tuition_fee', 'fee_basis', 'intake_dates', 'application_deadlines', 'duration',
    'campus_locality', 'aer_academic', 'english_requirements', 'scholarships', 'destination_city_stats', 'career_outcomes'])
  expect(STATES).toEqual(['TRYING', 'POSSIBLE_NEEDS_SOURCE', 'NOT_POSSIBLE', 'EMPTY_NOT_STARTED'])
  for (const f of FIELDS) expect(SQL).toContain(`'${f}', `)
})

test('the export is read only and parted, and every value is capped at 80 characters', () => {
  expect(SQL).toContain('begin transaction read only;')
  const code = SQL.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
  expect(code).not.toMatch(/\b(insert|update|delete|truncate|drop|alter|grant)\b\s/i)
  expect(code).not.toMatch(/create (table|function|or replace)/i)
  expect(SQL).toContain('mod(abs(hashtext(co.id::text)), __PARTS__) = __PART__')
  expect(SQL).toContain("left(x.url, 80)")
  expect((SQL.match(/left\([^;]*?, 80\)/g) || []).length).toBeGreaterThanOrEqual(10)
  expect(SQL).toContain("when x.label_only > 0 then 'NOT_POSSIBLE'")
  expect(SQL).toContain("when x.cc = 'CA' then 'EMPTY_NOT_STARTED'")
})

test('the renderer: one CSV row per course with the per-course counts, the executive and provider tabs, and the display rules', () => {
  const rows = [
    { course_id: 'c1', country_code: 'AU', provider_id: 'p1', provider_name: 'Uni "A"', course_title: 'Bachelor, of Arts',
      cells: Object.fromEntries(FIELDS.map((f, i) => [f, i < 5 ? `value ${i}` : i < 8 ? 'TRYING' : i < 11 ? 'POSSIBLE_NEEDS_SOURCE' : i < 13 ? 'NOT_POSSIBLE' : 'EMPTY_NOT_STARTED'])) },
    { course_id: 'c2', country_code: 'NZ', provider_id: 'p2', provider_name: 'Uni B', course_title: 'Master',
      cells: JSON.stringify(Object.fromEntries(FIELDS.map((f) => [f, 'POSSIBLE_NEEDS_SOURCE']))) },
  ]
  const { csv, summary } = build(rows, '2026-11-19')
  const lines = csv.trim().split('\n')
  expect(lines).toHaveLength(3)
  expect(lines[0]).toBe(['course_id', 'country_code', 'provider_id', 'provider_name', 'course_title', ...FIELDS,
    'fields_admitted', 'fields_trying', 'fields_possible_needs_source', 'fields_not_possible', 'fields_empty_not_started'].join(','))
  expect(lines[1]).toContain('"Uni ""A""","Bachelor, of Arts"')
  expect(lines[1].endsWith(',5,3,3,2,1')).toBe(true)
  expect(lines[2].endsWith(',0,0,14,0,0')).toBe(true)
  expect(summary.Executive_Summary[2]).toEqual(['official_url', 1, 50, 0, 0, 1, 50, 0, 0, 0, 0])
  expect(summary.By_Provider_Action_List[1].slice(1, 5)).toEqual(['Uni B', 'NZ', 1, 14])
  expect(summary.Dev_Display_Rules).toBe(DISPLAY_RULES)
  expect(DISPLAY_RULES.map(r => r[0])).toEqual(['state', 'ADMITTED (the value)', ...STATES])
  expect(stateOf('AUD 46,800.00 (2027)')).toBe('ADMITTED')
  expect(csvCell('a\nb')).toBe('"a\nb"')
})

test('the workflow: daily 07:30 AEDT, only this project, read in parts with retries, committed to the snapshot branch', () => {
  expect(WF).toContain('- cron: "30 20 * * *"')
  expect(WF).toContain('workflow_dispatch:')
  expect(WF).toContain('if [ "$REF" != "fxcwkweaxjtknorudmwp" ]; then echo "Refusing project $REF"; exit 1; fi')
  expect(WF).toContain('PARTS: "8"')
  expect(WF).toContain('for attempt in 1 2 3; do')
  expect(WF).toContain('DATE=$(TZ=Australia/Sydney date +%F)')
  expect(WF).toContain('git push -f origin course-readiness-snapshot')
  expect(WF).not.toMatch(/apply-migration|svc_|security\.\w+\(/)
})

test('the sheet tabs: counts are data, every percentage and the row check are formulas over them', () => {
  const rows = [{ course_id: 'c1', country_code: 'AU', provider_id: 'p1', provider_name: 'A', course_title: 'T',
    cells: Object.fromEntries(FIELDS.map((f) => [f, 'TRYING'])) }]
  const t = build(rows, '2026-11-19').summary.sheet_tabs
  expect(t.Executive_Summary[1].slice(0, 2)).toEqual(['Active courses', 1])
  expect(t.Executive_Summary[3][0]).toBe('Field')
  expect(t.Executive_Summary[4]).toEqual(['official_url', 0, '=IF($B$2=0,0,B5/$B$2)', 1, '=IF($B$2=0,0,D5/$B$2)', 0, '=IF($B$2=0,0,F5/$B$2)', 0,
    '=IF($B$2=0,0,H5/$B$2)', 0, '=IF($B$2=0,0,J5/$B$2)', '=B5+D5+F5+H5+J5'])
  expect(t.Executive_Summary).toHaveLength(4 + FIELDS.length)
  expect(t.Dev_Display_Rules).toBe(DISPLAY_RULES)
})
