import { readFileSync } from 'node:fs'
import { test, expect } from '@playwright/test'

const freshness = readFileSync('supabase/migrations/20260912031356_cf_093_scheduler_terminal_negative_freshness_dedupe.sql','utf8')
const sameAttempt = readFileSync('supabase/migrations/20260912031504_cf_093_scheduler_terminal_negative_same_attempt_fix.sql','utf8')
const bindingIsolation = readFileSync('supabase/migrations/20260912031648_cf_093_scheduler_preview_context_binding_isolation.sql','utf8')
const exactScope = readFileSync('supabase/migrations/20260912031736_cf_093_scheduler_terminal_negative_exact_scope_accounting.sql','utf8')
const completionDedupe = readFileSync('supabase/migrations/20260912035500_cf_093_scheduler_completion_anchored_dedupe.sql','utf8')

test('CF-093 fresh terminal negatives remain governed and non-queueable', () => {
  expect(freshness).toContain("freshness_sla_hours")
  expect(freshness).toContain("current_page_not_found")
  expect(freshness).toContain("identity_mismatch")
  expect(freshness).toContain("terminal_negative_count")
  expect(sameAttempt).toContain("max(d.created_at) filter")
  expect(sameAttempt).toContain("selected_at<x.terminal_at")
})

test('CF-093 fresh preview does not inherit a historical async binding', () => {
  expect(bindingIsolation).toContain("coursefinder.scheduler_preview_token")
  expect(bindingIsolation).toContain("b.preview_token=v_expected_preview")
})

test('CF-093 exact scope counts terminal negatives without fabricating URLs', () => {
  expect(exactScope).toContain("fresh_terminal_negative_count")
  expect(exactScope).toContain("requested_count")
  expect(exactScope).not.toContain("insert into catalogue.courses")
})

test('CF-093 recent dispatch dedupe uses completed non-cancelled batch state', () => {
  expect(completionDedupe).toContain("b.status in ('completed','partial')")
  expect(completionDedupe).toContain("latest_completed_at")
  expect(completionDedupe).toContain("scheduler_workflow_dispatch_dedupe_anchor_v1")
  expect(completionDedupe).not.toContain("b.status='cancelled'")
})
