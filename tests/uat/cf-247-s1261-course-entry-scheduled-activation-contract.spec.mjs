// Guards: Platform Admin approval relayed by SS-Programme-Control 26 Nov 2026 18:21 AEDT (scheduled course entry on qualified gpt-4.1-mini at US$1.00 a day inside the US$5.00 platform limit, once an automatic plan queues entry reads)
// s1261: the course entry route is switched on for scheduled work with a US$1.00 daily cap on gpt-4.1-mini; nothing else changes.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129233000_cf247_s1261_course_entry_scheduled_activation.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1261: only the course entry route changes, to gpt-4.1-mini at US$1.00 a day, guarded on qualification and the platform limit', () => {
  expect(MIG).toContain("update pipeline.ai_service_routes set enabled = true, daily_usd_cap = 1.00")
  expect(MIG).toContain("where service_code = 'course_entry_requirements';")
  expect(MIG).toContain("model_code = 'gpt-4.1-mini' and status = 'qualified'")
  expect(MIG).toContain("security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 0) < 5")
  expect(code.match(/update pipeline\.ai_service_routes/g).length).toBe(1)
})

test('s1261: no setting, job, model, qualification or consumer change, and nothing dropped', () => {
  expect(code).not.toMatch(/platform_toolset_settings\s+set|insert into pipeline\.ai_route_qualifications|ai_model_catalogue|cron\.schedule|cron\.alter_job|\bdelete from\b|truncate |website_v2_/i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
  for (const s of ['post-check: a cron job was created', 'post-check: more than 140 active cron jobs', 'post-check: manual locks changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
})
