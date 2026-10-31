// Guards: StudySearch decision D14 (Platform Admin mandate 31 Oct 2026 21:54; admin 2026-10-31-studysearch-transformation.md §32): a person switching a job on (Automations resume, one job or an area) releases that job's automatic idle-pause flag as a person release with an audit row, so the flag unit's idle guard applies again; the one-off reconciliation releases only flags on active jobs a person switched on after the flag was raised; and job platform-alerts runs every 10 minutes.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261031100000_cf247_ss014_d14_idle_flag_recovery.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('one md5-guarded edit of the Automations control; nothing dropped; consumer API untouched', () => {
  expect(m).toContain("select pg_temp.edit_once('security.admin_automation_control_v1(text,text,jsonb)', '8d5a6f103e1ad22a6f4bbd2f15d6a5c5', 'd90af04ccda6b74a88a506c58c0299fb', array[")
  expect(m).toMatch(/^-- Replaces: security\.admin_automation_control_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(code(m)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|function\s+api\./)
})

test('resume and resume_area release only the named job’s idle-pause flag, as a person, through the audited release', () => {
  expect(m).toContain("if p_action='resume' then perform security.job_idle_flag_person_release_v1(p_job, coalesce(nullif(p_args->>'reason',''),'switched on')); end if;")
  expect(m).toContain("if p_action='resume_area' then perform security.job_idle_flag_person_release_v1(r.jobname,")
  expect(m).toContain("where x.entity = 'job' and x.entity_key = p_job and x.field = '' and x.reason_code = 'idle_paused' and x.cleared_at is null")
  expect(m).toContain("perform security.flag_release_v1(f.id, coalesce(auth.uid()::text, 'person'), 'person',")
  expect(m).toContain('revoke all on function security.job_idle_flag_person_release_v1(text, text) from public, anon, authenticated;')
})

test('reconciliation: only active jobs with a logged person restart after the flag; post-check; platform-alerts every 10 minutes', () => {
  expect(m).toContain("from pipeline.enrichment_flags x join cron.job j on j.jobname = x.entity_key and j.active")
  expect(m).toContain("where e.area = 'automations' and e.action in ('resume', 'resume_area') and e.created_at > f.flagged_at")
  expect(m).toContain('continue when v_at is null;')
  expect(m).toContain("raise exception 'D14 post-check: a flag is still raised on a job a person switched on'")
  expect(m).toContain("select cron.alter_job((select j.jobid from cron.job j where j.jobname = 'platform-alerts'), schedule => '*/10 * * * *');")
})
