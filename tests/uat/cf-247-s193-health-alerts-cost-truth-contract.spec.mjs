// Guards: StudySearch SS-014 (Platform Admin mandate 31 Oct 2026 14:27; admin 2026-10-31-studysearch-transformation.md §30): the existing platform health check keeps a job failure visible until the job runs cleanly, escalates repeated failures at any schedule, and measures all AI spend from the OpenRouter credit balance against a ceiling held in settings; no new job, table or check
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261031080000_cf247_ss014_health_alerts_cost_truth.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('one md5-guarded edit of the existing health check; four settings with label, range, unit and used_by', () => {
  expect(m).toContain("select pg_temp.edit_once('security.platform_health_check_v1(boolean)', '293156782123a7e66b6fd1c021e22af0', 'd245c53574b1de0251711b0cb41c47cf', array[")
  expect(code(m).match(/select pg_temp\.edit_once\(/g)).toHaveLength(1)
  for (const k of ['health.job_failure_window_hours', 'health.job_failure_repeat_count', 'health.job_failure_critical_consecutive', 'budgets.ai_daily_ceiling_usd'])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace(/\./g, '\\.')}', '[^']+',\\s*\\n\\s*'[^']+', 'number',\\s*\\n\\s*to_jsonb\\(\\d+\\), \\d+, \\d+, '[^']+', \\d+, 'Platform upkeep', 'security\\.platform_health_check_v1`))
  expect(code(m)).not.toMatch(/cron\.(schedule|alter_job|unschedule)|create table|\b(drop|delete|truncate)\b/i)
})

test('job failures: stay open while the last run failed or failures repeat; critical on consecutive failures at any frequency', () => {
  expect(m).toContain("if r.fails_1h>0 or r.last_status='failed' or r.fails_win>=security.pipeline_num_v1('health.job_failure_repeat_count', 3) then")
  expect(m).toContain("$n$case when v_bool then 'critical' else 'warning' end$n$")
  expect(m).toContain("limit security.pipeline_num_v1('health.job_failure_critical_consecutive', 3)::int) x;")
  expect(m).toContain("raise exception 'SS-014 post-check: a fixed threshold is left in the health check'")
})

test('AI spend: every route, from the credit balance, top-ups not counted; ceiling from settings; credit no longer labelled as spend', () => {
  expect(m).toContain("select coalesce((select sum(greatest(o.prev - o.remaining_usd, 0)) from (select x.remaining_usd, lag(x.remaining_usd) over (order by x.observed_at) prev")
  expect(m).toContain("if v_num>=security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) then")
  expect(m).toContain("'openrouter_credit_remaining_usd',round(v_num,4),'openrouter_spend_24h_usd',v_spend")
  expect(code(m)).not.toMatch(/website_v2_|zoho_|function\s+api\./)
})
