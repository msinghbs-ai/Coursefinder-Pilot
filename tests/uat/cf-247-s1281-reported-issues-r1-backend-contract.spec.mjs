// Guards: SS-Programme-Control 26 Nov 2026 22:22 AEDT (Reported Data Issues R1 shared backend; design admin #1220 section 8, release plan admin #1223): additive on the existing in-app store, own reports only, durable per-reporter state, Fixed only after catalogue and consumer verification
// s1281: submission extension with idempotency and duplicate check; report_summary_v1, report_inbox_v1, report_detail_v1, report_ack_v1; stages; verification; no consumer change, Zoho untouched.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261130054500_cf247_s1281_reported_issues_r1_backend.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1281: submission carries field, displayed value, audience, year, origin and an idempotency key; a retry or a duplicate returns the first report', () => {
  for (const k of ['field_code', 'displayed_value', 'audience', 'study_year', 'origin', 'idempotency_key']) expect(code).toContain(`add column if not exists ${k}`)
  expect(code).toContain("check (origin in ('admin', 'portal'))")
  expect(code).toContain('create unique index if not exists counsellor_feedback_idem_idx on pipeline.counsellor_feedback (created_by, idempotency_key)')
  expect(code).toContain("'idempotent', true")
  expect(code).toContain("'duplicate', true")
  expect(code).toContain("security.pipeline_num_v1('lookups.intake_years_ahead', 2)")
  expect(code).toContain("from pipeline.field_register f where f.field = v_field and f.active")
})

test('s1281: the reporter reads only their own reports; state is per person and never deleted; acknowledge and archive only closed reports', () => {
  expect(code).toContain('where f.created_by = auth.uid()')
  for (const fn of ['report_summary_v1()', 'report_inbox_v1(jsonb)', 'report_detail_v1(jsonb)', 'report_ack_v1(jsonb)']) {
    expect(code).toContain(`create or replace function public.${fn.replace(/\(.*/, '')}(`)
    expect(code).toContain(`grant execute on function public.${fn} to authenticated, service_role;`)
    expect(code).toContain(`revoke all on function public.${fn} from public, anon;`)
  }
  expect(code).toContain('create table if not exists pipeline.counsellor_feedback_reader_state')
  expect(code).toContain("(v_action = 'seen' or f.status in ('fixed', 'not_changed'))")
  expect(code).toContain("'active', 'in_progress', 'awaiting_input', 'resolved', 'history'")
})

test('s1281: Fixed waits for verification: catalogue verified and the consumer read serving a changed value; the map is data', () => {
  expect(code).toContain("update pipeline.counsellor_feedback set stage = 'awaiting_verification'")
  expect(code).toContain("if p_choice in ('fixed', 'verify') then v := security.counsellor_feedback_verify_v1(r.id); end if;")
  expect(code).toContain("coalesce(fs->>'completeness', '') <> 'verified'")
  expect(code).toContain("public.website_v2_course(c.course_code)")
  expect(code).toContain("v_why := 'consumer_unchanged'")
  expect(code).toContain("update pipeline.counsellor_feedback set status = 'fixed', stage = 'fixed'")
  expect(code).toContain('create table if not exists pipeline.report_field_targets')
  expect((code.match(/set status = 'fixed'/g) || []).length).toBe(1)
})

test('s1281: additive only; Zoho, consumer API, jobs and locks untouched; nothing dropped', () => {
  expect(code).not.toMatch(/data_flags|zoho_v3|zoho_edge|website_v2_[a-z_]+\s*\(.*\)\s*returns|cron\.schedule|cron\.alter_job|\bdelete from\b|truncate |drop (table|function|column|constraint)/i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
  for (const s of ['post-check: consumer API moved', 'post-check: a cron job was created', 'post-check: manual locks changed', 'post-check: the Inbox kind is not registered']) expect(MIG).toContain(s)
})
