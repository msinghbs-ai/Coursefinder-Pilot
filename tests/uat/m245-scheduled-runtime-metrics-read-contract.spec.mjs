import {test,expect} from '@playwright/test'
import fs from 'node:fs'

const migration='supabase/migrations/20260913102500_cf_093_scheduled_runtime_metrics_read.sql'
// CF-247 cleanup: the admin_read dispatch line for 'jobs_runtime' was moved
// out of the metrics-read migration (it carried a stale, superseded full
// copy of admin_read — see that file's own comment) and now lives only in
// the migration that already owns admin_read's live dispatch wiring.
const dispatchMigration='supabase/migrations/20260914210000_cf_093_admin_dispatcher_tuning_metrics.sql'
const ui='src/ScheduledRuntimeHealth.jsx'

test('Scheduled Tasks runtime metrics read is rank-4, derived and secret-free',()=>{
  const sql=fs.readFileSync(migration,'utf8')
  const dispatchSql=fs.readFileSync(dispatchMigration,'utf8')
  expect(sql).toContain("if v_rank<4 then raise exception 'pipeline_operator role required'")
  expect(dispatchSql).toContain("if p_operation=''jobs_runtime'' then return security.admin_jobs_runtime_read_v1(p_args); end if;")
  expect(sql).toContain('revoke all on function security.admin_jobs_runtime_read_v1(jsonb) from public,anon,authenticated')
  expect(sql).toContain('grant execute on function security.admin_jobs_runtime_read_v1(jsonb) to authenticated')
  expect(sql).toContain("coalesce(p_args->>'limit','') ~ '^\\d{1,9}$'")
  expect(sql).toContain("(j.result->>'processed')::bigint")
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
  expect(source).toContain('Evidence produced and verified are separate counters')
  expect(source).toContain('no acceptance/yield percentage is manufactured')
  expect(source).toContain('attempt_count')
})
