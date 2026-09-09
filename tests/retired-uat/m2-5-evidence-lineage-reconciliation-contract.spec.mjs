import fs from'node:fs/promises'
import{execFileSync}from'node:child_process'
import{test,expect}from'@playwright/test'
import{writeRunEnvironment}from'./support/runtime-evidence.mjs'

test.describe('M2.5 Evidence lineage reconciliation and contact claim contract',()=>{
  test.beforeAll(async()=>{
    await writeRunEnvironment({
      suite:'m2-5-evidence-lineage-reconciliation-contract',
      change_control:'CF-CHG-20260901-059',
    })
  })

  test('preserves raw lineage, reconciles 5+2 history and hardens contact concurrency',async()=>{
    const[migration,worker,platform,shell,versionEntry,index,releaseTest]=await Promise.all([
      fs.readFile('supabase/migrations/20260901224000_m2_5_evidence_lineage_reconciliation_contact_claim.sql','utf8'),
      fs.readFile('supabase/functions/provider-contact-discover-scheduled/index.ts','utf8'),
      fs.readFile('src/platform-maturity-entry.jsx','utf8'),
      fs.readFile('src/mature-main.jsx','utf8'),
      fs.readFile('src/pim-version-entry.js','utf8'),
      fs.readFile('index.html','utf8'),
      fs.readFile('tests/uat/release-notes-deployed.spec.mjs','utf8'),
    ])

    expect(migration).toContain('create table if not exists pipeline.evidence_lineage_reconciliations')
    expect(migration).toContain("target_kind in('storage_object','evidence_artifact')")
    expect(migration).toContain("reconciliation_class in('historical_orphan_explained','legacy_virtual_reference')")
    expect((migration.match(/'historical_orphan_explained'/g)||[]).length).toBeGreaterThanOrEqual(6)
    expect((migration.match(/'legacy_virtual_reference'/g)||[]).length).toBeGreaterThanOrEqual(5)

    for(const path of[
      'layer2/v2/discovery/726918ee-10e9-41e3-9a2a-5dace20af754/e7b0e849-d07e-4ea4-a1ec-62dad6ce55e3/09431698-3cfd-4c2b-8669-e924bc65c329/extraction-input.json',
      'layer2/v2/provider-contacts/e47a940d-186f-4a17-bb22-2b794b73248c/1787961417749-2ea05b0cef63.html',
      'layer2/v2/provider-contacts/11e427cd-da7a-4f6f-b18a-99426b4d3b25/1787961433006-727538956bab.html',
      'layer2/v2/provider-contacts/fd815678-46ec-49f1-bcc4-ac9b5880d76c/1787961483811-85ba4c1c12e1.html',
      'layer2/v2/provider-contacts/739948f6-6338-4ee9-8d0c-a8c8e953c29d/1787961520922-4cfa1ed91b78.html',
    ]) expect(migration).toContain(path)

    expect(migration).toContain("'97370ab7-d949-4e54-8785-9ee176703fb3'")
    expect(migration).toContain("'de6710b1-de72-43e6-a96b-4f9ecac07d51'")
    expect(migration).toContain("'reconciled_historical_orphan_count',v_reconciled_orphans")
    expect(migration).toContain("'reconciled_legacy_reference_count',v_reconciled_legacy_refs")
    expect(migration).toContain("'missing_storage_object_count_raw',v_failed_raw")
    expect(migration).toContain("v_orphans:=greatest(v_unlinked_raw-v_duplicate_unlinked-v_reconciled_orphans,0)")
    expect(migration).toContain("v_integrity_count:=greatest(v_orphans,v_failed)")
    expect(migration).not.toMatch(/delete\s+from\s+(?:pipeline\.evidence_artifacts|storage\.objects)/i)
    expect(migration).not.toMatch(/update\s+pipeline\.evidence_artifacts/i)

    expect(migration).toContain('add column if not exists claim_token uuid')
    expect(migration).toContain('add column if not exists claim_until timestamptz')
    expect(migration).toContain('create or replace function public.provider_contact_profiles_claim_service')
    expect(migration).toContain('for update of pcp skip locked')
    expect(migration).toContain('(pcp.claim_until is null or pcp.claim_until<=now())')
    expect(migration).toContain('create or replace function public.provider_contact_profile_finish_claim_service')
    expect(migration).toContain('stale or invalid Provider-contact claim token')
    expect(migration).toContain('claim_token=null')
    expect(migration).toContain('claim_until=null')

    expect(worker).toContain('provider-contact-discover-scheduled-v1.3.4')
    expect(worker).toContain('"provider_contact_profiles_claim_service"')
    expect(worker).toContain('"provider_contact_profile_finish_claim_service"')
    expect(worker).toContain('p_lease_seconds:1800')
    expect(worker).toContain('captureContactEvidence')
    expect(worker).toContain('CF-059 failed-registration object cleanup failed')
    expect(worker).toContain('.storage.from(BUCKET).remove([path])')
    expect(worker).not.toContain('profiles=await rpc(svc,"provider_contact_profiles_service"')

    expect(platform).toContain('Reconciled historical orphans')
    expect(platform).toContain('Raw missing Storage refs')
    expect(platform).toContain('Reconciled legacy refs')
    expect(platform).toContain('Unresolved missing Storage objects')
    expect(platform).toContain('CF-055/059 preserve raw lineage counts')

    const shellVersion=shell.match(/const UI_VERSION='([^']+)'/)?.[1]
    const releaseVersion=versionEntry.match(/const VERSION='([^']+)'/)?.[1]
    expect(shellVersion).toBeTruthy()
    expect(releaseVersion).toBe(shellVersion)
    expect(index).toContain('Coursefinder PIM Admin v'+shellVersion)
    expect(versionEntry).toContain("version:'2.15.19'")
    expect(versionEntry).toContain('Evidence lineage reconciliation and contact claim hardening')
    expect(releaseTest).toContain('v'+shellVersion)

    const output=execFileSync('npm',['run','build'],{
      cwd:process.cwd(),
      env:process.env,
      encoding:'utf8',
      timeout:60000,
      stdio:['ignore','pipe','pipe'],
    })
    expect(output).toContain('built in')
  })
})
