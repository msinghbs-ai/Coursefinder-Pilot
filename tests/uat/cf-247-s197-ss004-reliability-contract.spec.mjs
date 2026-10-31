// Guards: StudySearch SS-004 reliability closure (Platform Admin mandate 1 Nov 2026 08:57; admin 2026-10-31-studysearch-transformation.md §33): a scheduled run that pg_cron reports as "job canceled" within seconds of the flag unit's idle pause of that job is classified paused, not failed, in the health check and target T1, while every other failure still counts; the coverage page reading and provider discovery stall age runs from the later of the last progress and when the oldest waiting item became due (same waiting filter as the count); and the three admission writers start at different minutes (:00, :03, :08) with unchanged commands, frequency, batches and time-outs.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261101010000_cf247_ss004_reliability.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('md5-guarded edits of the health check and the scorecard; nothing dropped; consumer API untouched', () => {
  expect(m).toContain("select pg_temp.edit_once('security.platform_health_check_v1(boolean)', 'b648e6494ccf39dbbe7eea6cec18f993', '43f5ba0f68140ccafe4a2d46fe0cf4ad', array[")
  expect(m).toContain("select pg_temp.edit_once('security.ops_scorecard_v1(date,jsonb)', '9e21229945de3b96ce3f738de2d1fbae', '18dcf612e1572f51797fb80853f0dbe3', array[")
  expect(m).toMatch(/^-- Replaces: security\.platform_health_check_v1, security\.ops_scorecard_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(code(m)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|function\s+api\./)
})

test('only a cancellation within seconds of an idle-pause event of the same job is "paused"; the post-check proves no real failure is reclassified', () => {
  expect(m).toContain("select case when p_status = 'failed' and p_message = 'job canceled'")
  expect(m).toContain("where f.entity = 'job' and f.entity_key = p_jobname and e.action in ('raised', 're_raised')")
  expect(m).toContain("and e.at between p_start - interval '30 seconds' and p_start + interval '5 seconds')")
  expect(m).toContain("then 'paused' else p_status end")
  expect(m).toContain("raise exception 'SS-004 post-check: a real failure was reclassified'")
  expect(m).toContain('security.cron_run_outcome_v1(r.jobname, d.status, d.return_message, d.start_time) status from cron.job_run_details d where d.jobid=r.jobid')
})

test('admission writers staggered; commands unchanged; coverage-admit and search refresh keep their minutes', () => {
  expect(m).toContain("select cron.alter_job((select j.jobid from cron.job j where j.jobname = 'adapter-overwrite'), schedule => '3-59/10 * * * *');")
  expect(m).toContain("select cron.alter_job((select j.jobid from cron.job j where j.jobname = 'coverage-admit-intakes'), schedule => '8-59/10 * * * *');")
  expect(code(m)).not.toMatch(/command\s*=>/)
  expect(m).toContain("(select schedule from cron.job where jobname = 'coverage-admit') <> '*/10 * * * *'")
})

test('stall age: later of last progress and when the oldest waiting item became due, with the same filter as the waiting count', () => {
  expect(m).toContain("select greatest(max(read_at), (select min(coalesce(q.next_read_at, q.bound_at)) from pipeline.coverage_course_pages q")
  expect(m).toContain("where q.status in ('bound','ambiguous') and coalesce(q.next_read_at,now())<=now() and q.read_attempts<3)) into v_ts from pipeline.coverage_course_pages;")
  expect(m).toContain("select greatest(max(updated_at), (select min(coalesce(q.next_due_at, q.updated_at)) from pipeline.coverage_provider_discovery q")
  expect(m).toContain("and security.enrich_focus_v1(q.provider_id) and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id=q.provider_id))) into v_ts from pipeline.coverage_provider_discovery;")
  expect(m).toMatch(/array\[1, 1, 1, 1\]\);/)
})
