// CF-247 v2.15.244 (S10): on-demand scholarship tasks and Task manager › Running now (Platform Admin, 11 Oct 2026: "fire
// manually ... gather uni based scholarships or check from provider or course ... registered as job and visible under task
// manager. All background jobs using resources at any given time should be visible under task manager, with the controls").
// Migration 20261011009000; the fixed task-kind CHECK was removed by a Platform Admin paste first.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261011009000_cf247_on_demand_scholarship_tasks.sql'

test('task kinds are a registry; three scholarship task kinds; nothing dropped; md5-guarded', () => {
  const sql = fs.readFileSync(MIG, 'utf8')
  expect(sql).toContain('create table if not exists pipeline.admin_job_kinds')
  expect(sql).toContain('admin_jobs_kind_fk')
  for (const k of ['scholarship_provider_scan', 'scholarship_course_check', 'scholarship_reread']) expect(sql).toContain(`'${k}'`)
  expect(sql).toContain('security.scholarship_task_prepare_v1')
  expect(sql).toContain('security.scholarship_task_fire_v1')
  expect(sql).toContain('security.admin_running_now_v1')
  expect(sql).toContain('paste-cf247-task-kinds.sql')
  for (const md5 of ['577823ad', 'f166a3fb', 'b259a26f', 'bd0b48fc', '8bd3588a', '0080ad82']) expect(sql).toContain(md5)
  expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect(sql).not.toMatch(/^alter table .* drop /im)
})

test('buttons on provider, course and scholarship records and bulk on Coverage start tasks', () => {
  const a = fs.readFileSync('src/ScholarshipActions.jsx', 'utf8')
  expect(a).toContain('kind="scholarship_provider_scan"')
  expect(a).toContain('kind="scholarship_course_check"')
  expect(a).toContain('kind="scholarship_reread"')
  expect(a).toContain("p_action:'start',p_args:{kind:'scholarship_provider_scan'")
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toContain('<ProviderScholarshipAction providerId={data.id}')
  expect(main).toContain('<CourseScholarshipAction courseId={data.id}')
  expect(fs.readFileSync('src/ScholarshipRecord.jsx', 'utf8')).toContain('<ScholarshipReadAction scholarshipId={id}')
  const cov = fs.readFileSync('src/ScholarshipCoverage.jsx', 'utf8')
  expect(cov).toContain('data-cov-bulk')
  expect(cov).toContain('picked.size>50')
  expect(cov).toContain('Read listing page again')
})

test('Task manager shows running now with safe controls and registry-driven pause', () => {
  const t = fs.readFileSync('src/AdminTasks.jsx', 'utf8')
  expect(t).toContain('function RunningNow(')
  expect(t).toContain("{running:true}")
  expect(t).toContain("supabase.rpc('admin_automation_control'")
  expect(t).toContain('kinds[j.kind].can_pause')
  expect(t).toContain('SchResult')
})

test('guide describes the buttons and Running now', () => {
  const g = fs.readFileSync('src/guide/platformGuide.js', 'utf8')
  expect(g).toContain('Task manager › Running now')
  expect(g).toContain('Find scholarships now')
  expect(g).toContain('Check scholarships for this course')
})

test('empty tasks are refused and the credits note is honest (9100)', () => {
  const sql = fs.readFileSync('supabase/migrations/20261011009100_cf247_scholarship_task_checks.sql', 'utf8')
  expect(sql).toContain("this scholarship is not active, so there is no page to read; restore it first")
  expect(sql).toContain("use Find scholarships now on the provider")
  expect(sql).toContain("' while the task ran'")
  for (const md5 of ['814855b565bee893d71854243ec39b6d', 'f166a3fba3b7cdaf9b4a00eb75e3cdc6', '747d4df851a35ef6c80184036ee6fee0', '10dd1edb4da67f91480afa4d0adaccde']) expect(sql).toContain(md5)
  expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im)
})

test('every scheduled job has a Task manager label (9200)', () => {
  const sql = fs.readFileSync('supabase/migrations/20261011009200_cf247_label_every_scheduled_job.sql', 'utf8')
  expect(sql).toContain("('admin-jobs',")
  expect(sql).toContain('on conflict (jobname) do nothing')
  expect(sql).toContain('scheduled jobs still without a label')
  expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im)
})
