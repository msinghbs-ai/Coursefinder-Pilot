// Guards: Platform Admin direction 2 Nov 2026 23:24 §3 (continuous validation: invocation is not work done; zero yield, hidden errors, incomplete pagination, repeated failures)
// Pipeline yield checks: hidden worker errors under a succeeded job (edge responses read incrementally from net._http_response and
// pipeline.edge_request_log), persistent zero yield (pipeline.mode_outcome_ledger), incomplete pagination and whole reads, repeated failed attempts
// per provider; each feeds the integration queue (20261102120000) by fingerprint. Per-stage yield for four lanes on Platform health › Integration
// queue. The behaviour runs on isolated fixtures by tests/fixtures/pipeline-yield/run.sh (scratch PostgreSQL on the integration-queue fixture
// database; the migration applied twice). This spec holds the contract, the fixture coverage and the screen. G1, G2, G3 and housekeeping are
// guarded centrally (s32, s42, s57).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = 'supabase/migrations/20261103040000_cf247_pipeline_yield_checks.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/pipeline-yield'
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); return m.slice(a, m.indexOf('$function$;', m.indexOf('$function$', a) + 10)) }
const checks = fn('security.integration_yield_checks_v1'), yieldFn = fn('security.pipeline_yield_v1'), screen = fn('public.admin_pipeline_yield')

test('reuses the integration queue: no existing function edited, nothing dropped; the job runs the checks after the integration checks', () => {
  expect(code).not.toMatch(/create or replace function security\.(integration_validate_v1|integration_issue_upsert_v1|platform_health_check_v1|queue_watch_run_v1)\(/)
  expect(code).not.toMatch(/pg_temp\.edit|edit_once/)
  expect(m).toMatch(/^-- Replaces: nothing/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(m).toContain("command := $j$select security.integration_validate_v1(), security.integration_yield_checks_v1()$j$);")
  expect(code).not.toMatch(/alter_job\([^;]*active\s*:=/)  // the job keeps its state
  expect(run).toContain('the migration changed security.integration_validate_v1')
  expect(checks.match(/security\.integration_issue_upsert_v1\(/g).length).toBe(7)  // seven call sites, one per finding kind
})

test('hidden worker errors: the newest edge responses only, by ring slot, counted per mode with "ok": false under HTTP 200 as failed', () => {
  expect(checks).toContain("x.id > coalesce(s.watermark_id, 0)")
  expect(checks).toContain("l.slot = (h.id % 50000)::int and l.request_id = h.id)  -- fixed: the request log is a ring of 50,000 slots")
  expect(checks).toContain(`(coalesce(h.status_code, 0) < 300 and h.content ~ '"ok"\\s*:\\s*false')`)
  expect(checks).toContain("if r.failures >= v_minf and r.failures * 100 >= v_share * r.calls then")
  expect(checks).toContain("v_fp := 'hidden_worker_error:' || r.key;")
  expect(m).toContain('create table if not exists pipeline.integration_yield_buckets')
})

test('zero yield, incomplete pagination and reads, repeated failures per provider: one fingerprint each, settings for every threshold', () => {
  expect(checks).toContain("if r.calls >= v_zmin and r.ok = 0 then")
  expect(checks).toContain("v_wait := coalesce(security.worker_mode_waiting_v1(r.key), false);")
  expect(checks).toContain("where l.id > coalesce(s.watermark_id, 0)")
  for (const f of ["'zero_yield:' || r.key", "'incomplete_pagination:course_lists'", "'incomplete_read:entry_matrix'", "'provider_failed_attempts:course_pages'",
    "'provider_failed_attempts:scholarship_discovery'", "'provider_failed_attempts:flag:' || r.reason_code"]) expect(checks).toContain(f)
  expect(checks).toContain("substring(c.reason from '\\((\\d+) course addresses\\)')::int > coalesce(c.links_found, 0)")
  for (const k of ['hidden_error_window_minutes', 'hidden_error_min_failures', 'hidden_error_min_share', 'zero_yield_hours', 'zero_yield_min_calls',
    'provider_failed_attempts_min', 'provider_failed_pages_min', 'bucket_keep_hours', 'yield_window_hours']) expect(m).toContain(`'integration.${k}'`)
  // a check that ran and no longer sees its condition marks the issue cleared; it never closes it
  expect(checks).toContain("values (r.id, 'not_observed', r.status, r.status, 'integration-validate', 'condition no longer observed; close after production verification');")
  expect(checks).not.toContain("status = 'closed'")
})

test('the yield view: four lanes, eight stages each, existing tables only; PIM Admin and above', () => {
  for (const l of ["'scholarships'", "'course_pages'", "'aer'", "'descriptions'"]) expect(yieldFn).toContain(`'lane', ${l}`)
  for (const s of ['invoked', 'source_accessed', 'pages_discovered', 'read_completely', 'extracted', 'accepted_or_held', 'published', 'consumer_read_back'])
    expect(yieldFn.match(new RegExp(`'${s}', \\(`, 'g')).length).toBe(4)
  expect(code).not.toMatch(/create table[^;]*(yield_view|stage)/i)
  expect(yieldFn).not.toMatch(/\b(insert|update|delete)\b/i)
  expect(screen).toContain("if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'PIM Admin role or above required'")
  expect(m).toContain('revoke all on function public.admin_pipeline_yield(jsonb) from public, anon;')
})

test('the fixtures cover each invariant firing and staying silent, no duplicates, clearing and regression, and every lane', () => {
  for (const c of ['clean: no issue', 'incremental: rows past the watermark only, nothing counted twice', 'each invariant fires once: ', '"ok": false under HTTP 200 counts as failed',
    'zero yield with failures is P1; with work waiting P2', 'repeated runs (and the integration checks between them): no duplicate issues', 'cleared, still open until verified',
    'back after closure: the same issue reopens as a regression', 'failures older than the window do not open an issue', 'four lanes',
    'scholarships: invoked 2, one failed (the 500 is not success)', 'course pages: published link read back from the search projection', 'Pipeline Operator refused']) expect(fixtures).toContain(`'${c}`)
  for (const fp of ['hidden_worker_error:coverage-sweep:link_search', 'hidden_worker_error:coverage-sweep:scholarship_discover', 'incomplete_pagination:course_lists',
    'incomplete_read:entry_matrix', 'provider_failed_attempts:course_pages', 'provider_failed_attempts:flag:pages_refuse_reading', 'provider_failed_attempts:scholarship_discovery',
    'zero_yield:fc_run', 'zero_yield:find_site']) expect(fixtures).toContain(`'${fp}'`)
})

test('Platform health › Integration queue shows the pipeline yield stage by stage for each lane', async ({ page }) => {
  await mockAdmin(page, { rank: 5 })
  await page.route('**/rest/v1/rpc/admin_integration_queue', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify({ mode: { mode: 1, set_by: 'x', set_at: '2026-11-02T06:00:00Z', reason: 'r' }, by_status: {}, by_severity: {}, by_workstream: {}, issues: [] }) }))
  const st = (o) => ({ invoked: { calls: 36, failed_calls: 22 }, source_accessed: 4, pages_discovered: 0, read_completely: 0, extracted: 0, accepted_or_held: { accepted: 0, held: 0 }, published: 0, consumer_read_back: 0, ...o })
  await page.route('**/rest/v1/rpc/admin_pipeline_yield', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify({ window_hours: 24, lanes: [
    { lane: 'scholarships', label: 'Scholarships', stages: st({}) }, { lane: 'course_pages', label: 'Course pages and official links', stages: st({ published: 12 }) },
    { lane: 'aer', label: 'Academic entry requirements', stages: st({}) }, { lane: 'descriptions', label: 'University descriptions', stages: st({}) }] }) }))
  await page.goto('/#platform-health?tab=integration')
  const y = page.locator('[data-pipeline-yield]')
  await expect(y).toContainText('Each lane over the last 24 hours')
  await expect(y.locator('[data-yield-stage="invoked"] [data-yield-lane="scholarships"]')).toHaveText('36 calls · 22 failed calls')
  await expect(y.locator('[data-yield-stage="published"] [data-yield-lane="course_pages"]')).toHaveText('12')
  await expect(y.locator('[data-yield-stage]')).toHaveCount(8)
})
