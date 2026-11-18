// Guards: student-facing correlated read (S1-RM-Design hand-off, Platform Admin 18 Nov 2026 21:23): Viewer and Counsellor read approved, published destination figures with student-facing fields only; Curator and above keep the full review read; provider detail carries accreditations (all statuses for Curator and above, the API v3 set for lower roles); no new table or function.
// CF-247 S712. supabase/migrations/20261119045000_cf247_student_facing_destination_read.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119045000_cf247_student_facing_destination_read.sql', 'utf8')
const code = M.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n')
const student = code.slice(code.indexOf("if coalesce(security.current_role_rank(), 0) < 3 then"), code.indexOf("'20261119045000 (s712)');"))

test('two md5-guarded edits of existing functions; nothing new, dropped or deleted', () => {
  expect(code).toContain("select pg_temp.cf_edit('public.admin_destination_review(text,text)'::regprocedure, '228efaa4e251a9e0bfab8e1081dd0618',")
  expect(code).toContain("select pg_temp.cf_edit('public.admin_read(text,jsonb)'::regprocedure, 'b6570ab86cecb6c4d2f843538c56bd1f',")
  expect(code).not.toMatch(/create table|create or replace function (public|security|pipeline|destination|catalogue)\./i)
  expect(code).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: /m)
})

test('Viewer and Counsellor get approved rows of published editions, three kinds only', () => {
  expect(code).toContain("if coalesce(security.current_role_rank(), 0) < 1 then raise exception 'assigned StudySearch role required'")
  expect(student).toContain("where m.status = 'approved' and l.status = 'approved'")
  expect(student).toContain("where o.status = 'approved' and e.status = 'published'")
  expect(student).toContain("where r.approval_status = 'approved' and e.status = 'published'")
  expect(student).toMatch(/else\s+raise exception 'Curator role or above required'/)
  expect(student).toContain("'audience', 'student'")
})

test('the student-facing rows carry no diagnostics, evidence or audit columns', () => {
  for (const internal of ['evidence_id', 'quote_on_page', 'status_reason', 'status_changed_by', 'approved_by', 'dataset_edition', 'terms_status', 'applicability', 'to_jsonb(r)', 'to_jsonb(o)', 'o.*', 'm.*']) {
    expect(student, internal).not.toContain(internal)
  }
  for (const shown of ['m.numeric_value', 'm.attribution_text', 'o.employment_count', 'o.source_url', 'r.application_fee_amount', 'r.post_study_work_years_max', 'e.attribution_text']) {
    expect(student, shown).toContain(shown)
  }
})

test('provider detail carries accreditations; lower roles get the API v3 set', () => {
  expect(code).toContain("jsonb_build_object('accreditations',case when coalesce(security.current_role_rank(),0)>=3 then")
  expect(code).toContain("'status',a.status")
  expect(code).toContain('else security.provider_accreditations_v3_v1(v_id) end)')
})

test('the frozen consumer API is not touched; drift is checked', () => {
  expect(code).not.toMatch(/website_v2_|website_edge_|zoho_edge_|website_api_v2_|svc_website_settings_v1/)
  expect(code).toContain('v_drift := security.consumer_api_check_v1();')
})
