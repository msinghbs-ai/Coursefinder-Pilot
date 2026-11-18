// Guards: Operations backend alignment (Platform Admin 18 Nov 2026 12:49): Task manager reads within the statement time-out, tasks stranded on a held AI route are closed with their reason, health checks follow the dispatchers and recorded pauses (no false alarms), Platform health checks Dispatchers, Boost, Layer 4 backlog and Guardrails, Storage & retention shows staging figures and Evidence shows an audit trail.
// CF-247 S636. supabase/migrations/20261118160000_cf247_operations_backend_alignment.sql, src/RetentionScreen.jsx, src/EvidenceAuditTrail.jsx.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118160000_cf247_operations_backend_alignment.sql', 'utf8')

test('Task manager: the task runner last run is read newest-first by run id, not max() over every run', () => {
  expect(M).toContain("'(select max(d.start_time) from cron.job_run_details d where d.jobid = c.jobid) last_run'")
  expect(M).toContain("'(select d.start_time from cron.job_run_details d where d.jobid = c.jobid order by d.runid desc limit 1) last_run'")
  expect(M).toContain("raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src)")
})

test('stranded entry requirement tasks are closed only while their AI route is held, with the reason, and nothing is deleted', () => {
  expect(M).toContain("if not ((security.ai_enrich_routes_v1()->'held') ? 'course_entry_requirements') then")
  expect(M).toContain("update pipeline.field_enrich_items i set state = 'skipped', reason = v_why")
  expect(M).toContain("perform security.aer_read_supersession_close_v1(r.id, 'refused',")
  expect(M).toContain("perform security.admin_job_close_v1(x) from unnest(v_jobs) x;")
  expect(M).toContain("'the entry requirements AI route is held: '")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
})

test('a job a dispatcher runs is running, and a recorded pause by a person reads paused, not stuck or critical', () => {
  expect(M).toContain('create or replace function security.job_dispatched_v1(p_job text)')
  expect(M).toContain('create or replace function security.job_paused_by_person_v1(p_job text)')
  expect(M).toContain("'where not j.active and security.job_dispatched_v1(j.jobname) is null and not exists'")
  expect(M).toContain("Waiting on a job switched off by a person: ")
  expect(M).toContain("return jsonb_build_object('queue',p_key,'status','paused','pending',v_pending")
  expect(M).toContain("security.job_dispatched_v1(''course-link-search-worker'') is null")
})

test('Platform health records Dispatchers, Boost, Layer 4 backlog and Guardrails from settings, on rollup-scheduler', () => {
  expect(M).toContain("v_keys constant text[] := array['dispatchers', 'boost', 'layer4_backlog', 'guardrails'];")
  expect(M).toContain("security.pipeline_num_v1('health.dispatcher_stale_minutes', 5)")
  expect(M).toContain("security.pipeline_num_v1('health.layer4_pending_warn', 6000)")
  expect(M).toContain("values ('platform-health-consolidated', null, 'select security.platform_health_consolidated_v1()'")
  expect(M).toContain("raise exception 'G3: the consumer API surface changed';")
})

test('Storage & retention shows staging tables and Evidence shows the audit trail', () => {
  expect(M).toContain("''storage'', security.retention_storage_v1(),")
  expect(M).toContain('create or replace function public.admin_ops_audit_v1(p_args jsonb default')
  const R = fs.readFileSync('src/RetentionScreen.jsx', 'utf8')
  expect(R).toContain('<Staging s={r.storage}/>')
  expect(R).toContain('data-retention-staging-tables')
  const A = fs.readFileSync('src/EvidenceAuditTrail.jsx', 'utf8')
  expect(A).toContain("supabase.rpc('admin_ops_audit_v1',{p_args:{failed_only:failed}})")
  expect(fs.readFileSync('src/EvidenceWorkspace.jsx', 'utf8')).toContain('{audit&&<EvidenceAuditTrail onError={onError}/>}')
})
