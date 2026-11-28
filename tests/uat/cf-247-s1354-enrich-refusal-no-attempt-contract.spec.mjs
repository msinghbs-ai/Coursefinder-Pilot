// Guards: DR-19 qualified remedy (Platform Admin 28 Nov 2026 18:10; PC-20261128-ONE-COMMAND-RUNTIME-CLOSURE): an AI account refusal does not use an enrichment attempt when the recovery policy ai_account_refusal says counts_attempt false; every other error keeps the attempt cap
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261201120000_cf247_s1354_enrich_refusal_no_attempt.sql', 'utf8')

test('s1354: refusals read the recovery policy and the classifier, both branches', () => {
  for (const k of ["'reason'", "'error'"]) {
    expect(sql).toContain(`security.pim_failure_cause_v1(r->>${k}) = 'account_refusal'`)
  }
  expect(sql.split("p.failure_class = 'ai_account_refusal'").length - 1).toBe(2)
  expect(sql.split('attempts = greatest(attempts - 1, 0)').length - 1).toBe(2)
  expect(sql.split("else 'ai' end").length - 1).toBe(4)
})

test('s1354: the wait is a G2 setting, not a number in code', () => {
  expect(sql).toContain("'pim.refusal_defer_minutes'")
  expect(sql).toContain("security.pipeline_num_v1('pim.refusal_defer_minutes', 60)")
  expect(sql).toMatch(/used_by[\s\S]*'public\.svc_enrich_ai_record \(s1354\)'/)
})

test('s1354: anchored, guarded, adds no job and drops nothing', () => {
  expect(sql).toContain('if v_n <> 1 then raise exception')
  expect(sql).toContain('security.consumer_api_check_v1()')
  expect(sql).toContain('manual locks changed')
  expect(sql).toContain('active job count changed')
  expect(sql).not.toMatch(/cron\.schedule/)
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(sql).toMatch(/^-- Replaces: /m)
  expect(sql).toMatch(/^-- Retires: nothing/m)
})
