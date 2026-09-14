import{test,expect}from'@playwright/test'
import fs from'node:fs/promises'

const read=path=>fs.readFile(path,'utf8')

test.describe('CF-245 Enrichment Operations contract',()=>{
 test('outcome reporting stays separate from scheduler configuration and mutation authority',async()=>{
  const migration=await read('supabase/migrations/20260915083500_cf_245_enrichment_operations_admin_read_v1.sql')
  const report=await read('src/EnrichmentOperations.jsx')
  const layer2=await read('src/layer2-operations-entry.jsx')
  const scheduled=await read('src/ScheduledJobsWorkspace.jsx')

  for(const text of [
   'pipeline.enrichment_coverage_snapshots',
   'svc_cf245_capture_coverage_snapshot',
   'security.admin_enrichment_operations_read',
   "p_operation='enrichment_operations'",
   "pipeline_operator role required",
   "revoke all on pipeline.enrichment_coverage_snapshots from public,anon,authenticated",
   "revoke all on function security.admin_enrichment_operations_read(jsonb) from public,anon",
   "change_control_ref','CF-CHG-20260915-245'",
   "coursefinder-cf245-enrichment-coverage-snapshot",
   "'7 * * * *'",
  ])expect(migration).toContain(text)

  expect(migration).toContain("set search_path='pg_catalog','security','pipeline','search','catalogue','ref'")
  expect(migration).toContain("set search_path='pg_catalog','pipeline','search','ref','catalogue'")
  expect(migration).not.toContain('grant select on pipeline.enrichment_coverage_snapshots to authenticated')
  expect(migration).not.toContain('grant select on pipeline.enrichment_coverage_snapshots to anon')

  for(const text of [
   'Enrichment Operations',
   'What actually enriched, where work stopped, and what reached Search/website',
   "adminRead('enrichment_operations'",
   'Coverage & backlog',
   'Hourly enrichment funnel',
   'Where work stops',
   'Provider yield & latency',
   'Recent field admissions',
   'Recent execution trace',
   'Baseline pending',
   'facts_admitted_lower_bound',
   'rejected_or_blocked',
   'layer3_escalated',
   'layer4_referred',
   'courses_improved_lower_bound',
   'vendor_units',
   'vendor_cost_usd',
   'p50_extraction_ms',
   'p95_extraction_ms',
   'openNav(\'Jobs\')',
   'openEvidence(x.evidence_id)',
  ])expect(report).toContain(text)

  expect(layer2).toContain("import EnrichmentOperations from'./EnrichmentOperations'")
  expect(layer2).toContain('<EnrichmentOperations rank={rank} openNav={openNav} openEvidence={openEvidence}/>')

  // CF-245 outcome reporting must not turn Scheduled Tasks into a second reporting/mutation surface.
  expect(scheduled).not.toContain('EnrichmentOperations')
  expect(scheduled).not.toContain("adminRead('enrichment_operations'")
  expect(report).not.toContain('scheduler_policy_edit_v1')
  expect(report).not.toContain('scheduler_policy_run_now_v1')
 })
})
