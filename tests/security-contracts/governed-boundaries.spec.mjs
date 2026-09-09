import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

const read = path => fs.readFile(path, 'utf8')

async function readAllMigrations() {
  const dir = 'supabase/migrations'
  const names = (await fs.readdir(dir)).filter(name => name.endsWith('.sql')).sort()
  const contents = await Promise.all(names.map(async name => `\n-- ${name}\n${await read(`${dir}/${name}`)}`))
  return contents.join('\n')
}

test('QS and THE acquisition remain publisher-allowlisted and Evidence-first', async () => {
  const [qs, the] = await Promise.all([
    read('supabase/functions/ranking-qs-url-import/index.ts'),
    read('supabase/functions/ranking-the-url-import/index.ts'),
  ])

  expect(qs).toMatch(/u\.protocol\s*!==\s*["']https:["']/)
  expect(qs).toMatch(/u\.hostname\s*!==\s*["']www\.topuniversities\.com["']/)
  expect(qs).toMatch(/world-university-rankings/)
  expect(qs).toContain('complete_qs_source_unavailable')
  expect(qs).toContain('global_completeness_gate_failed_')
  expect(qs).toMatch(/storage\.from\(["']evidence["']\)\.upload/)
  expect(qs).toContain('svc_ranking_raw_evidence_register')

  expect(the).toMatch(/u\.protocol\s*!==\s*["']https:["']/)
  expect(the).toMatch(/u\.hostname\s*!==\s*["']www\.timeshighereducation\.com["']/)
  expect(the).toMatch(/world-university-rankings/)
  expect(the).toContain('the_completeness_gate_failed_')
  expect(the).toContain('publisher_total')
  expect(the).toMatch(/storage\.from\(["']evidence["']\)\.upload/)
  expect(the).toContain('svc_ranking_raw_evidence_register')
})

test('ranking ingest remains service-role-only and evidence export stays short-lived', async () => {
  const [migration, allMigrations, exportWorker] = await Promise.all([
    read('supabase/migrations/20260905085600_cf_213_ranking_indicator_rank_semantics.sql'),
    readAllMigrations(),
    read('supabase/functions/ranking-evidence-export/index.ts'),
  ])

  expect(migration).toContain('revoke all on function public.svc_ranking_ingest_apply')
  expect(migration).toContain('grant execute on function public.svc_ranking_ingest_apply')
  expect(migration).toContain('to service_role')
  expect(allMigrations).not.toMatch(/grant\s+execute\s+on\s+function\s+public\.svc_ranking_ingest_apply\b[\s\S]{0,500}?\bto\s+(?:anon|authenticated)\b/i)
  expect(exportWorker).toMatch(/createSignedUrl\([^,]+,\s*300/)
  expect(exportWorker).toContain('authorised_role_required')
})

test('evidence lineage remains non-destructive and excludes logical URI schemes from storage checks', async () => {
  const migration = await read('supabase/migrations/20260901195000_m2_5_evidence_lineage_classification.sql')

  expect(migration).toContain("e.storage_path !~ '^[A-Za-z][A-Za-z0-9+.-]*://'")
  expect(migration).toContain("'unlinked_storage_object_count_raw'")
  expect(migration).toContain("'virtual_evidence_reference_count'")
  expect(migration).not.toMatch(/delete\s+from\s+(pipeline\.evidence_artifacts|storage\.objects)/i)
})

test('historical lineage reconciliation and provider-contact claiming remain concurrency-safe', async () => {
  const migration = await read('supabase/migrations/20260901224000_m2_5_evidence_lineage_reconciliation_contact_claim.sql')

  expect(migration).toContain('create table if not exists pipeline.evidence_lineage_reconciliations')
  expect(migration).toContain('add column if not exists claim_token uuid')
  expect(migration).toContain('add column if not exists claim_until timestamptz')
  expect(migration).toContain('for update of pcp skip locked')
  expect(migration).toContain('stale or invalid Provider-contact claim token')
  expect(migration).not.toMatch(/delete\s+from\s+(?:pipeline\.evidence_artifacts|storage\.objects)/i)
  expect(migration).not.toMatch(/update\s+pipeline\.evidence_artifacts/i)
})

test('platform administration contract remains non-destructive and secret references stay server-side', async () => {
  const migration = await read('supabase/migrations/20260901220500_m2_5_platform_maturity_admin_read_surface.sql')

  expect(migration).toContain('create or replace function security.admin_platform_maturity_read')
  expect(migration).not.toContain('vault_secret_id')
  expect(migration).not.toContain('secret_env_key')
  expect(migration).not.toMatch(/\b(delete|truncate)\s+from\b/i)
  expect(migration).not.toMatch(/\bupdate\s+pipeline\.(?:environment_source_gates|layer2_provider_environment_gates|layer3_profile_environment_gates)\b/i)
})

test('browser Supabase boundary remains publishable-key plus public.admin_read only', async () => {
  const client = await read('src/lib/supabase.ts')

  expect(client).toContain('VITE_SUPABASE_URL')
  expect(client).toContain('VITE_SUPABASE_PUBLISHABLE_KEY')
  expect(client).toContain("supabase.rpc('admin_read'")
  expect(client).not.toMatch(/service[_-]?role/i)
  expect(client).not.toMatch(/SUPABASE_SERVICE/i)
})
