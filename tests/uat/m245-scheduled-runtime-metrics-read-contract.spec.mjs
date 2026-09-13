import {test,expect} from '@playwright/test'
import fs from 'node:fs'

const migration='supabase/migrations/20260913102500_cf_093_scheduled_runtime_metrics_read.sql'
const ui='src/ScheduledRuntimeHealth.jsx'

test('Scheduled Tasks runtime metrics read is rank-4, derived and secret-free',()=>{
  const sql=fs.readFileSync(migration,'utf8')
  expect(sql).toContain("if v_rank<4 then raise exception 'pipeline_operator role required'")
  expect(sql).toContain("if p_operation='jobs_runtime' then return security.admin_jobs_runtime_read_v1(p_args)")
  expect(sql).toContain("'processed_count'")
  expect(sql).toContain("'throughput_records_per_min'")
  expect(sql).toContain("'evidence_count'")
  expect(sql).toContain("'verified_evidence_count'")
  expect(sql).toContain("'retry_exhausted_count'")
  expect(sql).toContain("'failure_class'")
  expect(sql).not.toMatch(/'payload'\s*,\s*j\.payload|'result'\s*,\s*j\.result|'error_text'\s*,\s*j\.error_text|'source_url'|'storage_path'/)
})

test('Runtime Health distinguishes unavailable metrics and Evidence states',()=>{
  const source=fs.readFileSync(ui,'utf8')
  expect(source).toContain("p_operation:'jobs_runtime'")
  expect(source).toContain("const UNKNOWN='Unavailable'")
  expect(source).toContain('Evidence produced')
  expect(source).toContain('verified Evidence')
  expect(source).toContain('no acceptance/yield percentage is manufactured')
  expect(source).toContain('attempt_count')
})
