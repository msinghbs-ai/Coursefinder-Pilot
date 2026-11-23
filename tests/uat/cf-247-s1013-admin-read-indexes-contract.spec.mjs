// Guards: Platform Admin 23 Nov 2026 22:10 AEDT (S1-Build Deployed UAT recovery: admin_toolsets_read and admin_course_audit stop timing out at the signed-in statement limit through covering indexes; no function changed; G3 frozen; nothing dropped)
// s1013: four indexes, each under a short lock retry, serve the reads that timed out (production logs, timed live in rolled-back runs);
// the Data Quality acceptance pages the exceptions list's own pager; CF-073 checks the direct route on today's Services & limits screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261123233000_cf247_s1013_admin_read_indexes.sql', 'utf8')

test('s1013: the four covering indexes for admin_toolsets_read and admin_course_audit, each under a lock retry', () => {
  expect(MIG).toContain("create index if not exists scholarship_ai_extractions_at_cost_idx on pipeline.scholarship_ai_extractions (at) include (cost_usd)")
  expect(MIG).toContain("create index if not exists coverage_ai_match_created_cost_idx on pipeline.coverage_ai_match (created_at) include (cost_usd, decided_at) where coalesce(cost_usd, 0) > 0")
  expect(MIG).toContain("create index if not exists coverage_vendor_usage_acq_provider_at_idx on pipeline.coverage_vendor_usage (acquisition_provider_id, at) include (units)")
  expect(MIG).toContain("create index if not exists evidence_artifacts_course_captured_idx on pipeline.evidence_artifacts ((metadata->>''course_id''), captured_at desc) where (metadata->>''course_id'') is not null")
  expect(MIG).toContain('exception when lock_not_available then')
  expect(MIG).toContain('post-check: an index is missing')
})

test('s1013: no function, drop or delete; G3, manual locks and active cron checked before and after', () => {
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/create or replace function|drop |delete from|truncate /i)
  expect(MIG).toContain('guard: the consumer API is not at its baseline before this change')
  expect(MIG).toContain('post-check: the consumer API moved')
  expect(MIG).toContain('post-check: manual locks changed')
  expect(MIG).toContain('post-check: the number of active cron jobs changed')
})

test('s1013: the deployed Data Quality and CF-073 checks follow the current screens without weakening them', () => {
  const dq = fs.readFileSync('tests/uat/data-quality-deployed.spec.mjs', 'utf8')
  expect(dq).toContain("page.locator('.dq-exceptions .dq-pager').getByRole('button', { name: /Next/i })")
  expect(dq).toMatch(/51–\\d\+ of \\d\+/)
  const r = fs.readFileSync('tests/uat/cf-073-administration-acquisition-route-deployed.spec.mjs', 'utf8')
  expect(r).toContain("page.locator('[data-services-limits]')")
  expect(r).toContain("page.locator('.m-workspace-error')).toHaveCount(0)")
  expect(r).toContain('await page.goBack()')
  expect(r).toContain('expect(pageErrors).toEqual([])')
})
