// Guards: Platform Admin decision 5 Nov 2026 16:36 §3-§5 (Automation Progress inside the existing Process results, read only, Pause/Resume through the existing job control), decision 20:03 (the generic progress observer reused, no overlapping detection) and the intake closure of 18:35 (the intake scheduler and processing are not changed). The database-backed acceptance is the isolated track tests/integration-progress.
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const MIG = fs.readFileSync('supabase/migrations/20261106400000_cf247_intake_automation_progress.sql', 'utf8')

test('the browser bridge: progress reads one role-checked function; Pause and Resume go to the existing Automations control only', async ({ page }) => {
  await page.goto('/')
  const calls = []
  await page.route('https://example.supabase.co/rest/v1/rpc/**', async route => { calls.push({ url: route.request().url(), body: route.request().postDataJSON() }); await route.fulfill({ json: {} }) })
  const refused = await page.evaluate(async () => {
    const { processResultsApi } = await import('/src/process-results-api.js')
    await processResultsApi.progress('window', { window: '7d' })
    await processResultsApi.control('intake-dates-apply', 'pause', { reason: 'r' })
    try { await processResultsApi.control('intake-dates-apply', 'run_now'); return false } catch { return true }
  })
  expect(refused).toBe(true)
  expect(calls).toEqual([
    { url: 'https://example.supabase.co/rest/v1/rpc/admin_intake_progress_v1', body: { p_view: 'window', p_args: { window: '7d' } } },
    { url: 'https://example.supabase.co/rest/v1/rpc/admin_automation_control', body: { p_job: 'intake-dates-apply', p_action: 'pause', p_args: { reason: 'r' } } },
  ])
})

test('the migration adds a read layer and folds intake into the generic progress observer: no job added or changed, the intake plan, apply job and applicability rule untouched', () => {
  expect(MIG).not.toContain('cron.schedule(')
  expect(MIG).not.toContain('pipeline.process_results(')
  // one edit of each generic function, guarded on its live md5; intake transitions in the shared contract
  expect(MIG).toContain("pg_temp.edit('security.progress_measure_v1(text,timestamp with time zone)', '40c0c972abc353be8f6eee35c79750e9'")
  expect(MIG).toContain("pg_temp.edit('security.progress_read_v1()', 'f11ed22d149eb06aa10387e67467ec6f'")
  expect(MIG).toContain("('intake_admission', 'intake', 20, 'Admission', '{intake-dates-apply}', '{}')")
  for (const frozen of ['intake_dates_plan_v3', 'intake_dates_apply_v1(', 'intake_course_applicability_v1', 'intake_date_withdraw', "cron.schedule('intake-dates-apply'", "alter_job("]) expect(MIG).not.toContain(frozen)
  expect(MIG).toMatch(/create or replace function public\.admin_intake_progress_v1[\s\S]*?security definer[\s\S]*?if auth\.uid\(\) is null or v_rank < 3 then raise exception/)
  expect(MIG).toContain('security.integration_issue_upsert_v1(jsonb_build_object(')
  expect(MIG).not.toMatch(/create table/i)
})

test('Process results mounts Automation progress only when the progress bridge is present', () => {
  const src = fs.readFileSync('src/ProcessResults.jsx', 'utf8')
  expect(src).toContain('<AutomationProgress rank={rank} client={client}/>')
  expect(fs.readFileSync('src/AutomationProgress.jsx', 'utf8')).toContain('if (!client?.progress) return null')
})
