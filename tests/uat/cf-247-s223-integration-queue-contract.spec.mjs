// Guards: CF-247 continuous validation and integration feedback mandate (Platform Admin 2 Nov 2026 16:58) §3 queue, §4 V3/V4, §5 loop, §13 modes
// The persistent integration feedback queue (pipeline.integration_issues, by deterministic fingerprint: no duplicate for an unchanged problem,
// a recurrence after Closed reopens as a regression, Closed only with production verification evidence), the operating mode (changed only by
// the Integration Controller, audited), the V4 job integration-validate (created inactive) and the V3 deploy check. Reuses Platform health,
// queue-watch and the deduplicated platform-alerts path; edits no existing function. The behaviour runs on isolated fixtures by
// tests/fixtures/integration-queue/run.sh (scratch PostgreSQL with the live table definitions; the alert functions loaded from the repository
// and checked against the live md5s; the migration applied twice). This spec holds the contract, the fixture coverage and the screen.
// G1, G2, G3 and housekeeping are guarded centrally (s32, s42, s57).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = 'supabase/migrations/20261102120000_cf247_integration_queue.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/integration-queue'
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const stubs = fs.readFileSync(`${FX}/stubs.sql`, 'utf8')
const ui = fs.readFileSync('src/IntegrationQueue.jsx', 'utf8')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); return m.slice(a, m.indexOf('$function$;', m.indexOf('$function$', a) + 10)) }
const upsert = fn('security.integration_issue_upsert_v1'), close = fn('security.integration_issue_close_v1'), modeSet = fn('security.integration_mode_set_v1')
const validate = fn('security.integration_validate_v1'), deploy = fn('security.integration_deploy_check_v1'), screen = fn('public.admin_integration_queue')

test('the queue holds every §3 field, a stable id and a unique fingerprint; history beside it; nothing dropped; no existing function edited', () => {
  for (const c of ["issue_ref text generated always as ('IQ-' || lpad(id::text, 5, '0')) stored", 'fingerprint text not null unique', 'layer text not null', 'subsystem text',
    'provider_ids uuid[]', 'course_ids uuid[]', 'country_codes text[]', 'detected_at timestamptz', 'failure text not null', 'expected text not null', 'detection_source text not null',
    'evidence jsonb', 'evidence_refs text[]', 'root_cause_class text', "severity text not null check (severity in ('P0', 'P1', 'P2'))",
    "workstream text not null check (workstream in ('A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'A9', 'A10'))", 'impact text', 'blocked_by bigint[]', 'depends_on text[]',
    'fix_commit text', 'fix_migration text', 'deployed_version text', 'verification_outcome text', 'retry_count int', 'last_observed_at timestamptz', 'aer_root_cause_ref text']) expect(m).toContain(c)
  expect(m).toContain("status text not null default 'detected' check (status in ('detected', 'triaged', 'assigned', 'in_progress', 'code_ready', 'integration_testing',\n    'deployed', 'production_verification', 'closed', 'reopened'))")
  expect(m).toContain('create table if not exists pipeline.integration_issue_events')
  // AER Phase B is linked by reference only: one root cause to at most one issue; none of its objects is created or touched
  expect(m).toContain('create unique index if not exists integration_issues_aer_ref_uq on pipeline.integration_issues (aer_root_cause_ref) where aer_root_cause_ref is not null;')
  expect(code).not.toMatch(/(create|alter)\s+table[^;]*aer_gap_/i)
  expect(code).not.toMatch(/pg_temp\.edit|edit_once|edit_v2/)
  for (const f of ['platform_health_check_v1', 'queue_watch_run_v1', 'flag_jobs_v1', 'platform_alerts_evaluate_v1', 'platform_alerts_add_v1', 'controls_check_v1'])
    expect(code).not.toContain(`create or replace function security.${f}(`)
  expect(m).toMatch(/^-- Replaces: nothing/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})

test('upsert by fingerprint: unchanged problems are not duplicated; new entities are added; a recurrence after Closed reopens as a regression', () => {
  expect(upsert).toContain("perform pg_advisory_xact_lock(hashtext('cf247:integration_issue:' || v_fp));  -- fixed: one writer per fingerprint")
  expect(upsert).toContain("if r.status = 'closed' then")
  expect(upsert).toContain("update pipeline.integration_issues i set status = 'reopened', regression_count = i.regression_count + 1, reopened_at = now(), retry_count = i.retry_count + 1,")
  expect(upsert).toContain("values (r.id, 'reopened_regression', 'closed', 'reopened', p_actor,")
  expect(upsert).toContain("update pipeline.integration_issues i set retry_count = i.retry_count + 1, last_observed_at = now(), condition_cleared_at = null,")
  expect(upsert).toContain("if v_action <> 'unchanged' then")  // an unchanged repeat writes no history line
  expect(upsert).toContain("severity = case when v_sev < i.severity then v_sev else i.severity end")  // never lowered automatically
  expect(upsert).toContain("security.pipeline_num_v1('integration.entity_ids_max', 500)")
})

test('closing needs production verification evidence; the lifecycle never closes; failed validation returns with its evidence', () => {
  expect(close).toContain("coalesce(p_verification->>'outcome', '') <> 'passed'")
  expect(close).toContain("length(btrim(coalesce(p_verification->>'evidence', ''))) < 20")
  expect(close).toContain("raise exception 'closing needs production verification evidence")
  expect(fn('security.integration_issue_transition_v1')).toContain("if p_to = 'closed' then raise exception 'an issue is closed only with verification evidence")
  expect(fn('security.integration_issue_transition_v1')).toContain("raise exception 'failed validation returns the issue with its new evidence")
})

test('operating mode: one row, written only through the Integration Controller path, audited in admin_control_events; Mode 2 only with no open P0/P1', () => {
  expect(m).toContain("id int primary key default 1 check (id = 1)")
  expect(m).toContain("create trigger integration_mode_guard before update or delete on pipeline.integration_operating_mode")
  expect(fn('security.integration_mode_guard_v1')).toContain("current_setting('cf247.integration_mode_path', true)")
  expect(modeSet).toContain("perform set_config('cf247.integration_mode_path', 'on', true);")
  expect(modeSet).toContain("insert into pipeline.admin_control_events(area, action, target, detail, actor)")
  expect(modeSet).toContain("raise exception 'Mode 2 needs programme acceptance: % P0/P1 integration issue(s) are still open'")
  expect(m).toContain("values (1, 1, 'Platform Admin (AGENT-OPERATING-MODEL.md, 2 Nov 2026 17:00)'")
  for (const f of ['integration_issue_upsert_v1(jsonb, text)', 'integration_issue_transition_v1(bigint, text, text, text, jsonb)', 'integration_issue_close_v1(bigint, text, jsonb)',
    'integration_mode_set_v1(int, text, text)', 'integration_validate_v1()', 'integration_deploy_check_v1(text, jsonb, jsonb, timestamptz, text[])'])
    expect(m).toContain(`revoke all on function security.${f} from public, anon, authenticated;`)
})

test('V4: one job, inactive, at minutes clear of :x3/:x5/:x9, :35-:42, :47-:48 and the :x6-:x8 read windows; keyed checks; reuses health, queue-watch and platform-alerts', () => {
  expect(m).toContain("perform cron.schedule('integration-validate', '21,51 * * * *', $j$select security.integration_validate_v1()$j$);")
  expect(m).toContain("perform cron.alter_job((select jobid from cron.job where jobname = 'integration-validate'), active := false);")
  for (const min of [21, 51]) {
    expect([3, 5, 6, 7, 8, 9]).not.toContain(min % 10)
    expect(min >= 35 && min <= 42).toBe(false)
    expect(min >= 47 && min <= 48).toBe(false)
  }
  expect(m.indexOf("('integration-validate', 'Platform upkeep'")).toBeLessThan(m.indexOf("cron.schedule('integration-validate'"))
  // the health and queue-watch output is read, not re-run; the queue's own alert rows are not fed back
  expect(validate).toContain("where p.resolved_at is null and p.severity in ('critical', 'warning') and p.check_key not like 'integration:%'")
  expect(validate).not.toMatch(/platform_health_check_v1\(|queue_watch_run_v1\(/)
  // every invariant has its own fingerprint
  for (const f of ["'job_failed:' || r.jobname", "'stale_lease:' || r.table_name", "'draft_stuck:' || r.status", "'l4_duplicate:' || r.field_code", "'l4_orphan:' || r.field_code",
    "'l4_regenerated:' || r.field_code", "'course_url_fill:pending_official_course_url'", "'archived_provider_work:firecrawl'", "'search_leak:archived_provider'",
    "'search_leak:inactive_course'", "'spend:firecrawl_day'", "'spend:ai_day'"]) expect(validate).toContain(f)
  // incremental and keyed: newest scheduler runs past the watermark, bounded pending items, ledger rows past the watermark, bounded inactive courses
  expect(validate).toContain('from cron.job_run_details x order by x.runid desc limit v_scan')
  expect(validate).toContain("d.runid > coalesce(s.watermark_id, 0)")
  expect(validate).toContain("u.id > coalesce(s.watermark_id, 0)")
  expect(validate).toContain("limit v_inmax")
  expect(m).toContain("where i.status = 'pending' order by i.created_at desc limit p_max")
  expect(m).toContain('create index if not exists layer4_review_items_entity_field_iq_idx on pipeline.layer4_review_items (entity_id, field_code, status);')
  // P0 goes through the existing outbox: one Platform health issue per fingerprint, resolved when it clears (platform-alerts raises and recovers)
  const sync = fn('security.integration_alert_sync_v1')
  expect(sync).toContain("v_key := 'integration:' || left(r.fingerprint, 200);")
  expect(sync).toContain("on conflict (check_key) where resolved_at is null do update set last_seen = now(), occurrences = i.occurrences + 1;")
  expect(sync).toContain("update pipeline.platform_issues set resolved_at = now() where check_key = r.alert_check_key and resolved_at is null;")
  expect(code).not.toMatch(/create table (if not exists )?[a-z_]+\.[a-z0-9_]*alert/i)  // no second alert outbox
  expect(code).not.toContain('platform_alerts_add_v1(')
})

test('V3: migration md5 against the file, function md5s, job compatibility and errors since the deploy, each mismatch an issue', () => {
  expect(deploy).toContain("select md5(array_to_string(s.statements, '')), md5(rtrim(replace(array_to_string(s.statements, ''), E'\\r', ''), E'\\n')) into v_live, v_norm")
  expect(deploy).toContain("'ok', v_live is not null and m.md5 in (v_live, v_norm)")
  expect(deploy).toContain("v_live := md5(pg_get_functiondef(f.sig::regprocedure));")
  expect(deploy).toContain("regexp_matches(j.command, '([a-z_][a-z0-9_]*)\\.([a-z_][a-z0-9_]*)\\s*\\(', 'g')")
  for (const f of ["'v3_migration:' || m.version", "'v3_function:' || f.sig", "'v3_job:' || j.jobname", "'v3_errors:' || p_release"]) expect(deploy).toContain(f)
  expect(deploy).toContain('insert into pipeline.integration_deploy_checks(release, since, ok, result, issues)')
})

test('the fixtures: live table definitions, the alert path checked against live, the migration twice, and every case', () => {
  expect(run).toContain('LIVE="6880db9e624650116a722853bdea974b c44b2ba7626e74fa46cf19a2561b3499"')
  expect(run).toContain('applied twice: one job, one mode row, alert path unchanged')
  expect(stubs).toContain('read from information_schema on production, read-only, 2 Nov 2026 17:06-17:08 AEDT')
  for (const c of ['dedupe: the same problem twice is one issue', 'dedupe: an unchanged repeat adds no history line', 'close refused: no verification', 'close refused: verification failed',
    'close refused: evidence too thin', 'closes with verification evidence', 'a recurrence after Closed reopens the same issue', 'recorded as a regression',
    'failed validation returns to In progress', 'a direct write is refused', 'Mode 2 refused while a P1 is open', 'the change is in admin_control_events', 'every change audited',
    'clean platform: no issue', 'each invariant fires once: ', 'second run: no duplicate issues', 'platform-alerts raises one alert per P0 issue',
    'repeated checks and alert runs: still two alerts', 'one recovery notice', 'back within the quiet period: no second raised alert',
    'the same job failing after closure reopens the original issue', 'V3 issues: ', 'V3: line endings and a trailing newline are not a mismatch', 'Pipeline Operator refused', 'PIM Admin: counts and mode']) expect(fixtures).toContain(`'${c}`)
  for (const fp of ['archived_provider_work:firecrawl', 'course_url_fill:pending_official_course_url', 'draft_stuck:proposing', 'health:queue_watch:fee_reader',
    'health:scholarship_queues:candidates', 'job_failed:coverage-admit', 'l4_duplicate:course_intake', 'l4_orphan:course_english', 'l4_regenerated:course_duration',
    'search_leak:archived_provider', 'search_leak:inactive_course', 'spend:ai_day', 'spend:firecrawl_day', 'stale_lease:pipeline.coverage_ai_match']) expect(fixtures).toContain(`'${fp}'`)
})

test('the screen is read only, PIM Admin and above; consumers never reach it', () => {
  expect(screen).toContain("if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'PIM Admin role or above required'")
  expect(m).toContain('revoke all on function public.admin_integration_queue(text, jsonb) from public, anon;')
  expect(screen).not.toMatch(/\b(insert|update|delete)\b/i)
  expect(fs.readFileSync('src/nav-map.js', 'utf8')).toContain("{ key: 'integration', label: 'Integration queue', min: 5 },")
  expect(ui).not.toMatch(/integration_issue_(upsert|transition|close)|integration_mode_set/)
})

test('Platform health › Integration queue: counts by status, severity, workstream and reopened, the operating mode, and an issue with its history', async ({ page }) => {
  await mockAdmin(page, { rank: 5 })
  const summary = { mode: { mode: 1, set_by: 'Platform Admin (AGENT-OPERATING-MODEL.md, 2 Nov 2026 17:00)', set_at: '2026-11-02T06:00:00Z', reason: 'CF-247 programme not yet accepted' },
    by_status: { detected: 2, reopened: 1, closed: 4 }, by_severity: { P0: 1, P1: 2 }, by_workstream: { A4: 2, A5: 1 }, reopened: 1, regressions_total: 1, job_active: false,
    last_check: { at: '2026-11-02T06:21:00Z', found: 3 },
    issues: [{ id: 7, ref: 'IQ-00007', title: 'course-url-fill wrote course_url while an official_course_url Layer 4 item was pending', layer: 'Catalogue', severity: 'P1', status: 'reopened',
      workstream: 'A4', source: 'integration-validate', validation_layer: 'V4', root_cause: 'code_defect', retry_count: 4, regressions: 1, providers: 0, courses: 48, last_observed_at: '2026-11-02T06:21:00Z' }] }
  await page.route('**/rest/v1/rpc/admin_integration_queue', async (route) => {
    const body = route.request().postDataJSON()
    if (body.p_action === 'issue') return route.fulfill({ contentType: 'application/json', body: JSON.stringify({
      issue: { issue_ref: 'IQ-00007', failure: '48 course(s) whose course_url was filled after a pending item', expected: 'course-url-fill skips a course with a pending item', detected_at: '2026-11-02T05:23:00Z', detection_source: 'integration-validate' },
      events: [{ id: 2, kind: 'reopened_regression', from_status: 'closed', to_status: 'reopened', actor: 'integration-validate', at: '2026-11-02T06:21:00Z' },
               { id: 1, kind: 'detected', to_status: 'detected', actor: 'integration-validate', at: '2026-11-02T05:51:00Z' }] }) })
    return route.fulfill({ contentType: 'application/json', body: JSON.stringify(summary) })
  })
  await page.goto('/#platform-health?tab=integration')
  await expect(page.locator('[data-iq-mode="1"]')).toContainText('Mode 1 — Active remediation')
  await expect(page.locator('[data-iq-summary]')).toContainText('P0 1 · P1 2 · P2 0')
  await expect(page.locator('[data-iq-by="status"]')).toContainText('Reopened (regression)')
  await expect(page.locator('[data-iq-by="workstream"]')).toContainText('A4 Layer 4 · 2')
  const row = page.locator('[data-iq-issue="IQ-00007"]')
  await expect(row).toContainText('48 course(s)')
  await row.click()
  await expect(page.locator('[data-iq-history="IQ-00007"] [data-iq-event="reopened_regression"]')).toContainText('Closed → Reopened (regression)')
})

test('a Pipeline Operator does not see the Integration queue', async ({ page }) => {
  await mockAdmin(page, { rank: 4 })
  await page.route('**/rest/v1/rpc/admin_integration_queue', (route) => route.fulfill({ status: 403, contentType: 'application/json', body: '{"message":"PIM Admin role or above required"}' }))
  await page.goto('/#platform-health?tab=integration')
  await expect(page.locator('[data-iq-summary]')).toHaveCount(0)
})
