// Guards: Platform Admin via SS-Programme-Control 26 Nov 2026 19:06 and 19:13 AEDT (complete the planner correction, admin #1201: an automatic plan queues academic entry reads through the existing reader; no new queue, planner or scheduler)
// s1274: one eligibility rule per provider, the planner's academic_entry step queues the due entry reads under the scheduled reader's capacity rules, and the tick closes it when they leave the queue.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129220000_cf247_s1274_academic_entry_planner_handoff.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1274: one eligibility rule, per provider; skipped refusals are read again; guarded on the definitions it replaces', () => {
  expect(MIG).toContain('create function security.aer_schedule_courses_v1(p_limit integer, p_all boolean, p_provider uuid)')
  expect(MIG).toContain('security.aer_course_population_v1(p_provider) p')
  expect(MIG).toContain('select * from security.aer_schedule_courses_v1(p_limit, p_all, null::uuid)')
  expect(MIG).toContain("not (f.state in ('failed', 'skipped') and s.refused <> '' and coalesce(f.reason, '') ~* s.refused)")
  expect(MIG).toContain("v_new := v_old || '|AI route is switched off';")
  for (const h of ['0e42dd3e90291ad35e7d9f3665163a95', '04f1ec1f5f7803637071df71b6764efd', '87e3d7c5899fde5a2714c6020cb7ef44', '26b0ae9c387b904439a085e95b47c4ab', 'df0f2a2826e61b92b168847f1557435b']) expect(MIG).toContain(h)
})

test('s1274: the planner proposes and starts the entry reads through the existing enqueue and capacity rules, and closes the step when they leave the queue', () => {
  expect(MIG).toContain("security.aer_schedule_courses_v1(security.pipeline_num_v1('aer.schedule_daily_max', 200)::int, true, p_provider)")
  expect(MIG).toContain("v_fields := security.aer_entry_reads_plan_v1(r.provider_id,")
  expect(MIG).toContain('v_job := security.course_entry_read_enqueue_v1(r.course_id, v_owner, p_reason);')
  expect(MIG).toContain("security.aer_schedule_courses_v1(v_room, false, p_provider)")
  expect(MIG).toContain("security.enrich_item_held_v1(r.course_id, 'entry_requirements')")
  expect(MIG).toContain('insert into pipeline.aer_schedule_runs(')
  expect(MIG).toContain("coalesce(s->'ref'->'entry_courses', '[]'::jsonb)")
})

test('s1274: no route, job, queue or consumer change; nothing dropped; locks and cron checked', () => {
  expect(code).not.toMatch(/ai_service_routes|cron\.schedule|cron\.alter_job|create table|\bdelete from\b|truncate |website_v2_/i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l))).toEqual([])
  for (const s of ['post-check: a cron job was created', 'post-check: more than 140 active cron jobs', 'post-check: manual locks changed', 'post-check: consumer API moved']) expect(MIG).toContain(s)
})
