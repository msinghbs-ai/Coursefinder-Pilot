// Guards: API v3 daily admittance telemetry (Platform Admin 16 Nov 2026 20:17): every API v3 and request-register field is recorded daily in pipeline.field_coverage_daily through the existing writer (no new job, table or column), and the daily gain is today minus yesterday from that history
// CF-247 S564. Migration 20261116170000_cf247_api_v3_daily_admittance.
// G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261116170000_cf247_api_v3_daily_admittance.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the existing writer gains one union branch through an md5-guarded edit', () => {
  expect(code).toContain("select pg_temp.edit_all('security.field_coverage_record_v1()', '9e7e5bc441936a4feaa87afdd2f6e51d', 'ec8cf0c3988103a9f9fdaf6d25b924c1',")
  expect(code).toContain('from security.api_v3_field_coverage_v1() v')
})

test('every API v3 and request-register field is counted, with its REQ id in the read-out', () => {
  for (const f of ['v3_study_load', 'v3_empty_reason', 'v3_campus_primary', 'v3_accreditations', 'v3_grade_normalised', 'v3_destination', 'p_entry_matrix', 'p_registrations']) {
    expect(code).toContain(`'${f}'`)
  }
  for (const r of ["'REQ-52'", "'REQ-53'", "'REQ-75 (D-4)'", "'REQ-57 (D-3)'", "'REQ-19'", "'REQ-65, REQ-67, REQ-68'"]) expect(code).toContain(r)
  expect(code).toContain('td.filled - yd.filled')
  expect(code).toContain('f.snapshot_date = d.t - 1')
})

test('no new job, table or column; no text scans; nothing dropped', () => {
  expect(code).not.toMatch(/cron\.schedule|create table|alter table/i)
  expect(code).not.toMatch(/ ~\*? '/)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
