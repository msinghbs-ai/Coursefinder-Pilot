// Guards: Platform Admin 19 Nov 2026 15:36 AEDT (chat S1-Build, s776): the Google Sheet Stakeholder_Course_Readiness_Summary (Drive › Monitoring) has its summary tabs Executive_Summary, Field_ETA_Forecast (columns Admitted, Trying, Possible / Needs Source, Not Possible, Empty / Wave 2, Observed Daily Velocity, Primary Bottleneck, Expected 100% Achievable ETA) and By_Provider_Action_List refreshed every hour from security.course_field_readiness_tabs_v1, read by the hourly telemetry sync; the per-country CSV export stays daily (07:30 AEDT). The readiness snapshot uses the export's rules verbatim.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const m = fs.readFileSync(migrationPath('20261119174000_cf247_s777_pipeline_field_eta.sql'), 'utf8')
const exportSql = fs.readFileSync(new URL('../../scripts/telemetry/course-field-readiness.sql', import.meta.url), 'utf8')
const wf = fs.readFileSync(new URL('../../.github/workflows/course-field-readiness.yml', import.meta.url), 'utf8')
const tabs = m.slice(m.indexOf('create or replace function security.course_field_readiness_tabs_v1('), m.indexOf('$function$;', m.indexOf('create or replace function security.course_field_readiness_tabs_v1(')))

test('the snapshot builder uses the readiness rules of the daily export, verbatim', () => {
  const a = m.indexOf('  -- readiness rules: begin'); const b = m.indexOf('  -- readiness rules: end')
  expect(a).toBeGreaterThan(-1); expect(b).toBeGreaterThan(a)
  const norm = (s) => s.replace(/\s+/g, ' ').trim()
  const rules = m.slice(m.indexOf('with c as (', a), b)
  const exp = exportSql.slice(exportSql.indexOf('with c as ('), exportSql.lastIndexOf('order by x.cc, x.provider_name, x.title;'))
    .replace('mod(abs(hashtext(co.id::text)), __PARTS__) = __PART__', 'mod(abs(hashtext(co.id::text)), v_parts) = v_part')
  // the export's final select becomes CTE r in the builder; everything else is the same text
  const builderNoR = norm(rules).replace(/, r as \( (select x\.course_id, x\.cc country_code.*)\),$/, ' $1')
  expect(builderNoR).toBe(norm(exp))
})

test('the three summary tabs keep their names, the export layout and the ETA columns', () => {
  for (const t of ["'Executive_Summary', v_exec", "'Field_ETA_Forecast', v_eta", "'By_Provider_Action_List', v_prov"]) expect(tabs).toContain(t)
  expect(tabs).toContain("jsonb_build_array('Field', 'Admitted', 'Admitted %', 'Trying', 'Trying %', 'Possible, needs a source', 'Possible, needs a source %', 'Not possible', 'Not possible %',")
  expect(tabs).toContain("format('=IF($B$2=0,0,B%s/$B$2)', x.r)")
  expect(tabs).toContain("format('=B%1$s+D%1$s+F%1$s+H%1$s+J%1$s', x.r)")
  expect(tabs).toContain("jsonb_build_array('Canonical API v3 Field', 'Admitted Now', 'Trying / In Pipeline', 'Possible / Needs Source', 'Not Possible / Not Published', 'Empty / Wave 2',")
  expect(tabs).toContain("'Current Observed Velocity', 'Primary Bottleneck / Dependency', 'Expected 100% Achievable Target ETA'))")
  expect(tabs).toContain("jsonb_build_array('rank', 'provider_name', 'country_code', 'active_courses', 'cells_possible_needs_source', 'cells_trying', 'top_fields_needing_a_source', 'provider_id')")
  expect(tabs).toContain(' stable security definer')
  expect(m).toContain("revoke all on function security.course_field_readiness_tabs_v1() from public, anon, authenticated;")
})

test('the per-course CSV export stays daily', () => {
  expect(wf).toContain('- cron: "30 20 * * *"')
})
