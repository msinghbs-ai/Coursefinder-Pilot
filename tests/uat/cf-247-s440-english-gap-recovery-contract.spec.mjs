// Guards: Platform Admin directive 8 Nov 2026 14:06 (English gap recovery: classify every course without English, recover only what needs no spend and no decision, the English requeue stays a recorded decision) and IQ-00072 (no repeated spend on a stuck onboarding).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const A = fs.readFileSync('supabase/migrations/20261108120000_cf247_eng_gap_funnel.sql', 'utf8')
const B = fs.readFileSync('supabase/migrations/20261108121000_cf247_eng_default_after_withdrawn_reading.sql', 'utf8')
const C = fs.readFileSync('supabase/migrations/20261108122000_cf247_plan_stalled_onboarding_hold.sql', 'utf8')
const run = fs.readFileSync('tests/fixtures/eng-gap-recovery/run.sh', 'utf8')
const funnelTests = fs.readFileSync('tests/fixtures/eng-gap-recovery/funnel-tests.sql', 'utf8')
const planTests = fs.readFileSync('tests/fixtures/eng-gap-recovery/plan-tests.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('the funnel only reads: one cause per course, no row written, no job, no setting, the requeue is reported and not run', () => {
  const c = code(A)
  expect(c).not.toMatch(/\b(insert\s+into|update\s+\w+[\w.]*\s+set|delete\s+from|drop\s+|truncate)\b/i)
  expect(c).toContain("'primary'::text layer")
  expect(c).toContain("'central_page_refused_not_retried'")
  expect(c).toContain("'english_read_failed_not_retried'")
  expect(c).toContain("'withdrawn_reading_differs_from_default'")
  // the status read is cut per stage at its own display limit, so no provider is dropped from the count
  expect(c).toMatch(/english_policy_status_v1\(null, s\.stage, 1000\)\)?.*-- fixed: /)
  expect(c).toContain("security.current_role_rank(), 0) < 3")
  expect(c).toContain('revoke all on function public.admin_english_gap_funnel() from public, anon;')
  expect(c).toContain('grant execute on function public.admin_english_gap_funnel() to authenticated;')
  expect(A).toMatch(/^-- Replaces: nothing\./m)
  expect(A).toMatch(/^-- Retires: nothing\./m)
  expect(funnelTests).toContain('the primary layer adds up to the active courses without English (one cause per course)')
  expect(funnelTests).toContain('a user with no role cannot read the funnel')
})

test('the default after a withdrawn reading ships off, is md5-guarded, and leaves policy-written rows, locks and held levels alone', () => {
  const c = code(B)
  expect(B).toMatch(/--   security\.provider_english_plan_v1\(uuid\)   b5b449dd54d885fe68b5085626531bd3 -> 6fec9e6515a347438b7ed07215cbd748/)
  expect(c).toContain("pg_temp.edit_once('security.provider_english_plan_v1(uuid)', 'b5b449dd54d885fe68b5085626531bd3', '6fec9e6515a347438b7ed07215cbd748'")
  expect(c).toContain("'english.default_after_withdrawn_reading'")
  expect(c).toMatch(/'on \(1\) or off \(0\)', 1030, 'English policies'/)
  expect(c).toMatch(/'number', '0'::jsonb, 0, 1,/)  // ships off: it writes English values
  expect(c).toContain("coalesce(r.source_requirement_key, '') like 'policy:%'")
  expect(c).toContain("then 'differs'")
  expect(c).not.toMatch(/insert into catalogue\.course_english_requirements|update catalogue\.course_english_requirements/)
  expect(B).toMatch(/^-- Replaces: security\.provider_english_plan_v1\(uuid\)/m)
  expect(B).toMatch(/^-- Retires: nothing\./m)
  for (const t of ['off: a withdrawn page reading still blocks the default (as live)',
    'on: a withdrawn page reading with the same score as the default no longer blocks it',
    'on: a withdrawn page reading at another score is held and shown as differing, not written',
    'on: a withdrawn row the policy itself wrote keeps blocking (no rewrite of a withdrawal)',
    'on: a locked course is still left alone', 'planning wrote nothing']) expect(funnelTests).toContain(t)
})

test('the stalled-onboarding hold stops repeated spend only: settings not numbers, md5-guarded, automatic planner only, comes back on any change', () => {
  const c = code(C)
  expect(C).toMatch(/--   security\.enrich_plan_v1\(uuid\)   774c061974916b878f7762e55de07bb6 -> [0-9a-f]{32}/)
  expect(C).not.toContain('__AFTER_PLAN__')
  expect(c).toContain("pg_temp.edit_once('security.enrich_plan_v1(uuid)', '774c061974916b878f7762e55de07bb6'")
  expect(c).toContain("security.pipeline_num_v1('plans.stalled_onboarding_hold', 1) < 1")
  expect(c).toContain("security.pipeline_num_v1('plans.stalled_onboarding_quiet_days', 30)")
  expect(c).toContain("'plans.retry_waits_for_change'")  // the one list of causes time does not clear
  expect(c).toContain('v_stalled is not null and auth.uid() is null')  // a person's Run now is not held
  expect(c).toContain("'code', 'onboarding_stalled'")
  expect(c).toContain("x->>'step' in ('pages', 'adapter')")  // only the two steps that repeat the spend
  expect(c).toContain('c.created_at > o.at')
  expect(c).toContain("g.read_at > o.at")
  expect(c).toContain("s.searched_at > o.at")
  expect(c).not.toMatch(/interval '\d+ day/)
  expect(c).not.toMatch(/\b(insert\s+into|update|delete\s+from)\s+(pipeline\.(enrich_plan_runs|admin_jobs|provider_onboarding)|catalogue\.)/i)
  expect(C).toMatch(/^-- Replaces: security\.enrich_plan_v1\(uuid\)/m)
  expect(C).toMatch(/^-- Retires: nothing\./m)
  for (const t of ['the automatic planner is not offered Find course pages or Build the adapter',
    'a person behind the call sees every step', 'a course added since the stop brings the steps back',
    'a course page read and stored since the stop brings the steps back', 'a central search finished since the stop brings the steps back',
    'after the quiet days the steps come back by themselves', 'with the setting off the plan is as before',
    'a stop for another cause (a crash) is not held: only a cause time does not clear is']) expect(planTests).toContain(t)
})

test('nothing is dropped, requeued or switched on by the three migrations; the consumer API is untouched', () => {
  for (const m of [A, B, C]) {
    const c = code(m)
    expect(c).not.toMatch(/\b(drop\s+(table|function|view|schema|column)|delete\s+from|truncate)\b/i)
    expect(c).not.toMatch(/cron\.(schedule|alter_job|unschedule)/)
    expect(c).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
    expect(c).not.toMatch(/provider_facts_requeue|requeue/i)
  }
  expect(code(B)).not.toMatch(/provider_english_apply_all_v1\(/)  // the default is applied by the existing job, not by this migration
  expect(run).toContain('a second run adds nothing')
  expect(run).toContain('the loaded security.enrich_plan_v1 carries its live md5')
})
