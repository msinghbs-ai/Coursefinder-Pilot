// Guards: StudySearch decision F1c (Platform Admin 31 Oct 2026 11:24, "Keep paused, review first"; admin 2026-10-31-studysearch-transformation.md §8.9, §10): job l4-rule-low-agreement (automatic Rule 4 admission) stays paused, its catalogue entry says what it does and that it is paused, and nothing else changes; with F6 hygiene, admin_ui_error_report is not executable by anon
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261031020000_cf247_f1c_rule4_paused.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('the job is paused, not retired or rescheduled, and the post-check refuses an active job', () => {
  const c = code(m)
  expect(c).toContain("select cron.alter_job((select jobid from cron.job where jobname = 'l4-rule-low-agreement'), active := false);")
  expect(c).not.toMatch(/cron\.(schedule|unschedule)\(/)
  expect(c).not.toMatch(/schedule\s*:=/)
  expect(c).toContain("raise exception 'F1c post-check: the job is still active'")
  expect(m).toContain('-- Retires: nothing (the job is paused, not retired')
})

test('the catalogue says what the job does (it admits from the page) and that it is paused, by whom and why', () => {
  expect(m).toContain("set description = 'PAUSED (Platform Admin 31 Oct 2026, StudySearch decision F1c: keep paused until the rule is reviewed).")
  expect(m).toContain('is admitted from the page')
  expect(m).toContain('no Rule 4 admission happens while paused')
})

test('nothing else changes: the rule function, adapters, data and the consumer API are untouched', () => {
  const c = code(m)
  expect(c).not.toMatch(/create\s+or\s+replace\s+function/i)
  expect(c).not.toMatch(/uni_adapters|layer4_review_items|\b(drop|delete|truncate)\b/i)
  expect(c).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|function\s+api\.|consumer_api_rebaseline_v1/)
})

test('F6 hygiene: anon cannot execute admin_ui_error_report; authenticated keeps it', () => {
  const c = code(m)
  expect(c).toContain('revoke execute on function public.admin_ui_error_report(text, text, text, jsonb) from public, anon;')
  expect(c).toContain('grant execute on function public.admin_ui_error_report(text, text, text, jsonb) to authenticated;')
})
