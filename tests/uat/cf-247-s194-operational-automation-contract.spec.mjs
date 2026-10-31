// Guards: StudySearch SS-014A to SS-014D (Platform Admin mandate 31 Oct 2026 19:22, decisions D7 and D11; admin 2026-10-31-studysearch-transformation.md §31): the health check works out each provider's scholarship hold once (same counts), a job paused by the flag unit's idle rule is not critical until the critical age, search refresh requests have a slow/stalled check with a cause and next step, platform alerts are recorded with deduplication, escalation, reminders, recovery, retries and a test mode while external delivery stays off, issues can be acknowledged with a reason, and a weekly scorecard measures T1 to T8 from existing measurements, saying when a window is incomplete.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const m = fs.readFileSync('supabase/migrations/20261031091000_cf247_ss014_operational_automation.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('two md5-guarded edits of existing health functions; nothing dropped; consumer API untouched', () => {
  expect(m).toContain("select pg_temp.edit_v2('security.platform_health_stall_v1(text,text,text,text,timestamp with time zone,text,integer)', 'e1c74fa638bd1a52832102122cdfa50c', 'fe27fdb050f8a7385fd7885199da4bc4',")
  expect(m).toContain("select pg_temp.edit_v2('security.platform_health_check_v1(boolean)', 'd245c53574b1de0251711b0cb41c47cf', 'b648e6494ccf39dbbe7eea6cec18f993',")
  expect(code(m).match(/select pg_temp\.edit_v2\(/g)).toHaveLength(2)
  expect(m).toMatch(/^-- Replaces: security\.platform_health_check_v1, security\.platform_health_stall_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(code(m)).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|function\s+api\./)
})

test('SS-014A: the scholarship hold is worked out once per provider and shared by the three counts', () => {
  expect(m).toContain("hp as materialized (select x.provider_id, security.fc_sch_held_v1(x.provider_id, true) held from (select dp.provider_id from dp union select cand.provider_id from cand) x)")
  expect(m).toContain("v_q:=v_q||security.platform_health_stall_v1('scholarship_queues:discover','scholarships','Scholarship provider discovery','scholarship-discover',v_ts,'select '||v_n2);")
  expect(m).toContain("'providers_not_searched',v_n3,")
})

test('A2: a job paused by the flag unit is information until the critical age; a missing or person-paused job stays critical', () => {
  expect(m).toContain("$n$case when v_age>v_crit or (coalesce(v_active,false)=false and not v_unit) then 'critical' when v_unit then 'info' else 'warning' end$n$")
  expect(m).toContain("f.reason_code='idle_paused' and f.cleared_at is null and coalesce(f.state,'raised')='raised'")
})

test('SS-014B: search refresh slow vs stalled from settings, with cause, writer and next step', () => {
  for (const k of ['health.search_refresh_slow_minutes', 'health.search_refresh_stalled_minutes']) expect(m).toContain(`('pipeline', '${k}', `)
  expect(m).toContain("v_bool:=v_num>security.pipeline_num_v1('health.search_refresh_stalled_minutes', 90) or v_txt in ('job_missing','job_paused','job_failing','job_not_running');")
  expect(m).toContain("security.platform_health_issue_v1('search_refresh:waiting', case when v_bool then 'critical' else 'warning' end, 'search/API',")
  for (const c of ['job_missing', 'job_paused', 'job_failing', 'job_not_running', 'writer_busy', 'refresh_gap']) expect(m).toContain(`when '${c}' then '`)
  expect(m).toContain("('search_refresh', 'search/API', 'Search refresh requests', 'skipped', '{}'::jsonb, 10, false, 125)")
})

test('SS-014C: alerts recorded as held while external delivery is off (D7); dedupe, escalation, reminder, recovery, retries, webhook off', () => {
  expect(m).toMatch(/\('pipeline', 'alerts\.delivery_enabled', [^\n]*\n[^\n]*\n\s*to_jsonb\(false\)/)
  expect(m).toMatch(/\('pipeline', 'alerts\.webhook_enabled', [^\n]*\n[^\n]*\n\s*to_jsonb\(false\)/)
  expect(m).toContain("raise exception 'SS-014 post-check: external alert delivery must be off (D7)'")
  expect(m).toContain("case when v_on then 'pending' else 'held' end, p_dedupe)")
  expect(m).toContain("on conflict (dedupe_key) do nothing returning id into v_id;")
  for (const k of ["'raised'", "'escalated'", "'reminder'", "'recovered'"]) expect(m).toContain(`i.id::text || ':${k.slice(1, -1)}`)
  expect(m).toContain("and a.created_at > now() - make_interval(mins => v_cool)) then")
  expect(m).toContain("next_attempt_at = now() + make_interval(mins => (v_retry * power(2, greatest(a.attempts - 1, 0)))::int)")
  expect(m).toContain("select s.decrypted_secret into v_url from vault.decrypted_secrets s where s.name = 'studysearch_alert_webhook_url';")
  expect(m).toContain("if v_on and v_hook then v_hook_out := security.platform_alerts_webhook_v1(); end if;")
  expect(m).toContain("return jsonb_build_object('count', 0, 'alerts', '[]'::jsonb, 'delivery', 'off: alerts are recorded on Platform health only');")
  expect(m).toContain("security.platform_health_issue_v1('alerts:not_collected','critical','scheduled jobs',")
  expect(m).toContain("comment on table pipeline.platform_alerts is 'StudySearch SS-014C")
})

test('SS-014D: scorecard targets are settings; T1 kept day by day because the scheduler forgets after about three days', () => {
  for (const k of ['targets.job_failures_per_day', 'targets.ai_credit_min_usd', 'targets.futile_items_per_day', 'targets.review_oldest_days', 'targets.api_search_p95_ms', 'targets.api_search_page_size', 'targets.reference_bundle_hours'])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace(/\./g, '\\.')}', '[^']+',\\s*\\n\\s*'[^']+', 'number',\\s*\\n\\s*to_jsonb\\(\\d+\\), \\d+, \\d+, '[^']+', \\d+, 'Operating targets', 'security\\.ops_scorecard_v1`))
  expect(m).toContain("v_x := coalesce(p_prior -> 'targets' -> 'T1' -> 'by_day', '{}'::jsonb) || v_x;")
  expect(m).toContain("continue when w < v_cur and coalesce((v_old ->> 'complete')::boolean, false);")
  expect(m).toContain("'status', 'see the release record'")
  expect(m).toContain("when v_n3 = 0 then 'no search traffic: latency not measurable'")
})

test('G1: both jobs catalogued and scheduled with no number in their commands; functions not callable from the browser', () => {
  expect(m).toContain("select cron.schedule('platform-alerts', '10-59/10 * * * *', $$select security.platform_alerts_evaluate_v1()$$);")
  expect(m).toContain("select cron.schedule('ops-scorecard', '29 19 * * *', $$select security.ops_scorecard_record_v1()$$);")
  for (const j of ['platform-alerts', 'ops-scorecard']) expect(m).toMatch(new RegExp(`\\('${j}', '[^']+', \\d+, '[^']+',`))
  for (const f of ['platform_alerts_evaluate_v1()', 'platform_alerts_webhook_v1()', 'platform_alerts_take_v1(text)', 'platform_alerts_confirm_v1(bigint[], boolean, text)', 'ops_scorecard_v1(date, jsonb)', 'ops_scorecard_record_v1()'])
    expect(m).toContain(`revoke all on function security.${f} from public, anon, authenticated;`)
  expect(m).toContain("if coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;")
})

test.describe('mocked browser', () => {
  test('Platform health: alerts held while delivery is off, acknowledge with a reason, test alert, weekly scorecard', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#platform-health')
    const panel = page.locator('[data-platform-alerts]')
    await expect(panel.locator('[data-alert-delivery="off"]')).toContainText('nothing leaves the platform until the Platform Admin approves a destination')
    await expect(panel.locator('[data-alert-row="held"]')).toHaveCount(2)
    await panel.getByLabel('Reason for the test alert').fill('Check the outbox')
    await panel.getByRole('button', { name: 'Send a test alert' }).click()
    await expect.poll(() => page.l3calls.find(c => c.alerts?.p_action === 'test')?.alerts).toEqual({ p_action: 'test', p_args: { reason: 'Check the outbox' } })
    await page.locator('[data-ack-issue="i1"]').click()
    const form = page.locator('[data-ack-form="i1"]')
    await expect(form.getByRole('button', { name: 'Acknowledge' })).toBeDisabled()
    await form.getByLabel('Reason for acknowledging').fill('Known: Layer 3 retired')
    await form.getByRole('button', { name: 'Acknowledge' }).click()
    await expect.poll(() => page.l3calls.find(c => c.alerts?.p_action === 'acknowledge')?.alerts).toEqual({ p_action: 'acknowledge', p_args: { id: 'i1', reason: 'Known: Layer 3 retired' } })
    const sc = page.locator('[data-ops-scorecard="2026-10-26"]')
    await expect(sc.locator('[data-scorecard-target]')).toHaveCount(8)
    await expect(sc.locator('[data-scorecard-target="T1"]')).toContainText('incomplete: 4 of 6 days recorded')
    await expect(sc.locator('[data-scorecard-target="T6"]')).toContainText('search p95 5,203 ms')
    await sc.getByRole('button', { name: /Week of/ }).click()
    await expect(page.locator('[data-ops-scorecard="2026-10-19"] [data-scorecard-target="T1"]')).toContainText('Not fully observed')
  })

  test('a viewer sees the alerts and scorecard but cannot acknowledge or send a test alert', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    await page.goto('/#platform-health')
    await expect(page.locator('[data-platform-alerts]')).toBeVisible()
    await expect(page.locator('[data-alert-test]')).toHaveCount(0)
    await expect(page.locator('[data-ack-issue]')).toHaveCount(0)
  })
})
