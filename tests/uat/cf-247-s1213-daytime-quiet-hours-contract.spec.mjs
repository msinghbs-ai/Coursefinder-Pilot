// Guards: Atlas brief 26 Nov 2026 11:59 AEDT with the Platform Admin's approval (s1213, zero-cost daytime CPU and I/O isolation): five heavy background jobs (coverage-ai-match-prepare, fee-reader, scholarship-ai-extract, course-description-machine, provider-description-read) do no work in the daytime quiet hours (08:00 to 20:00 Melbourne, settings in toolset pipeline), through security.quiet_hours_open_v1 in their own commands; no job is added, removed, activated or deactivated; the website and Zoho change feeds, Task manager and the dispatchers keep running.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261129070000_cf247_s1213_daytime_quiet_hours.sql', 'utf8')
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const jobs = ['coverage-ai-match-prepare', 'fee-reader', 'scholarship-ai-extract', 'course-description-machine', 'provider-description-read']

test('s1213: housekeeping header and guards', () => {
  expect(sql).toMatch(/^-- Replaces: the daytime runs of coverage-ai-match-prepare/m)
  expect(sql).toMatch(/^-- Retires: nothing\.$/m)
  expect(code).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(code).toContain('if (select count(*) from cron.job where active) <> (select cron_before from s1213_guard)')
  expect(code).toContain('if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1213_guard)')
  expect(code).not.toMatch(/\bdrop\s+(table|function|index|view)\b/i)
  expect(code).not.toMatch(/\bdelete\s+from\b/i)
  expect(code).not.toMatch(/cron\.(schedule|unschedule)\s*\(/)
  expect(code).not.toMatch(/active\s*=>\s*(true|false)|active\s*:=\s*(true|false)/)
})

test('s1213: the five jobs keep their own call and check the quiet hours; nothing else is held', () => {
  for (const j of jobs) expect(code).toContain(`('${j}', 'select security.`)
  expect(code).toContain("select cron.alter_job(j.jobid, command := s.command_before || ' where security.quiet_hours_open_v1(''' || s.jobname || ''')')")
  expect(code).toContain("if r.command is distinct from r.command_before or not coalesce(r.active, false) then")
  expect(code).not.toMatch(/'(website-sync-check|zoho-sync-check|admin-jobs|rollup-scheduler|admission-rule-runner[a-c-]*)', 'select/)
  expect(code).toContain("if not security.quiet_hours_open_v1('website-sync-check', v_day) or not security.quiet_hours_open_v1('admin-jobs', v_day) then")
})

test('s1213: the window is Melbourne time and every value is a setting (G2)', () => {
  expect(code).toContain("extract(hour from p_at at time zone 'Australia/Melbourne')")
  expect(code).toContain("security.pipeline_num_v1('quiet_hours.enabled', 1)")
  expect(code).toContain("security.pipeline_num_v1('quiet_hours.start_hour', 8)")
  expect(code).toContain("security.pipeline_num_v1('quiet_hours.end_hour', 20)")
  expect(code).toContain("s.key = 'quiet_hours.jobs'")
  for (const k of ['quiet_hours.enabled', 'quiet_hours.start_hour', 'quiet_hours.end_hour', 'quiet_hours.jobs']) expect(code).toContain(`('pipeline', '${k}', 'Daytime quiet hours:`)
  expect(code).toContain("revoke all on function security.quiet_hours_open_v1(text, timestamptz) from public, anon, authenticated;")
  expect(code).toContain("set description = c.description || ' Daytime quiet hours: no work from 08:00 to 20:00 Melbourne time")
})
