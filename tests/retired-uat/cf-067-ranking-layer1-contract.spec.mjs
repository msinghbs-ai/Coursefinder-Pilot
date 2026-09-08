import fs from'node:fs/promises'
import{test,expect}from'@playwright/test'
import{writeRunEnvironment}from'./support/runtime-evidence.mjs'

test.describe('CF-067 QS THE Layer 1 ranking ingestion contract',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-067-ranking-layer1-contract',change_control:'CF-CHG-20260902-067'})})

 test('keeps ranking ingestion governed and reachable from Layer 1',async()=>{
  const[ui,shell,version,ctl,etl,m1,m2,m3,m4,m5]=await Promise.all([
   fs.readFile('src/layer1-operations-entry.jsx','utf8'),
   fs.readFile('src/mature-main.jsx','utf8'),
   fs.readFile('src/pim-version-entry.js','utf8'),
   fs.readFile('supabase/functions/layer1-operations-control/index.ts','utf8'),
   fs.readFile('supabase/functions/ranking-layer1-etl/index.ts','utf8'),
   fs.readFile('supabase/migrations/20260902004533_cf_067_ranking_layer1_ingest_service_contract.sql','utf8'),
   fs.readFile('supabase/migrations/20260902004608_cf_067_register_qs_the_layer1_sources.sql','utf8'),
   fs.readFile('supabase/migrations/20260902004626_cf_067_layer1_global_source_projection.sql','utf8'),
   fs.readFile('supabase/migrations/20260902004804_cf_067_layer1_ranking_source_metadata_projection.sql','utf8'),
   fs.readFile('supabase/migrations/20260902011100_cf_068_qs_xhr_layer1_adapter_support.sql','utf8'),
  ])

  expect(ui).toContain('Upload publisher file')
  expect(ui).toContain("['QS','THE']")
  expect(ui).toContain('source.edition_year')
  expect(ui).toContain('sources-imports')
  expect(ui).toContain('GLOBAL')
  expect(shell).toContain("const UI_VERSION='2.15.27'")
  expect(shell).toContain('RankingImportPanel')
  expect(shell).toContain("routeParams?.get?.('system')")
  expect(version).toContain("const VERSION='2.15.27'")
  expect(version).toContain('QS & THE Layer 1 ranking ingestion')

  expect(ctl).toContain('ranking-layer1-etl')
  expect(ctl).toContain('ranking_observations_reconciled')
  expect(ctl).toContain('ranking_validation_completed')
  expect(etl).toContain('publisher_static_xhr_json')
  expect(etl).toContain('4061771_indicators.txt')
  expect(etl).toContain('Direct QS JSON APPLY is intentionally disabled')
  expect(etl).toContain('authorised publisher file required')
  expect(etl).toContain('ranked_band')
  expect(etl).toContain('reporter')
  expect(etl).toContain('svc_ranking_ingest_apply')
  expect(etl).toContain('x-cf-layer1-service-key')

  const migration=m1+m2+m3+m4+m5
  expect(migration).toContain('QS World University Rankings 2026')
  expect(migration).toContain('QS World University Rankings 2027')
  expect(migration).toContain('Times Higher Education World University Rankings 2026')
  expect(migration).toContain("'global'")
  expect(migration).toContain('exact_canonical_name_country')
  expect(migration).toContain('service role required')
  expect(migration).not.toMatch(/grant\s+(select|insert|update|delete)\s+on\s+ranking\..*\s+to\s+(anon|authenticated)/i)
 })
})
