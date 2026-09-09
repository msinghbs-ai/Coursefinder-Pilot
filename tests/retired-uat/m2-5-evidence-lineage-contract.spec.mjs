import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { writeRunEnvironment } from './support/runtime-evidence.mjs'

// CF-055 deployed Edge revisions compiled before this source-contract trigger.
test.describe('M2.5 Evidence lineage classification and duplicate prevention contract',()=>{
  test.beforeAll(async()=>{
    await writeRunEnvironment({
      suite:'m2-5-evidence-lineage-contract',
      change_control:'CF-CHG-20260901-055',
    })
  })

  test('classifies raw lineage separately and removes only just-uploaded duplicates',async()=>{
    const [migration,discovery,backfill,contacts,scholarships,acquire]=await Promise.all([
      fs.readFile('supabase/migrations/20260901195000_m2_5_evidence_lineage_classification.sql','utf8'),
      fs.readFile('supabase/functions/layer2-scope-discover-scheduled/index.ts','utf8'),
      fs.readFile('supabase/functions/layer2-screenshot-backfill-scheduled/index.ts','utf8'),
      fs.readFile('supabase/functions/provider-contact-discover-scheduled/index.ts','utf8'),
      fs.readFile('supabase/functions/scholarships-au-etl/index.ts','utf8'),
      fs.readFile('supabase/functions/layer2-acquire-v2/index.ts','utf8'),
    ])

    expect(migration).toContain("'unlinked_storage_object_count_raw',v_unlinked_raw")
    expect(migration).toContain("'duplicate_unlinked_storage_object_count',v_duplicate_unlinked")
    expect(migration).toContain("'virtual_evidence_reference_count',v_virtual_refs")
    expect(migration).toContain("'missing_storage_object_count',v_failed")
    expect(migration).toContain("retained.metadata->>'eTag'=o.metadata->>'eTag'")
    expect(migration).toContain("retained.metadata->>'size'=o.metadata->>'size'")
    expect(migration).toContain("e.storage_path !~ '^[A-Za-z][A-Za-z0-9+.-]*://'")
    expect(migration).not.toMatch(/delete\s+from\s+(pipeline\.evidence_artifacts|storage\.objects)/i)

    for(const source of [discovery,backfill,contacts]){
      expect(source).toContain('duplicate_upload_path')
      expect(source).toContain('.storage.from(BUCKET).remove([path])')
      expect(source).toMatch(/retained===path\)return/)
      expect(source).toContain('console.warn("CF-055 duplicate')
    }

    expect(discovery).toContain('layer2-scope-discover-scheduled-v1.3.3')
    expect(backfill).toContain('layer2-screenshot-backfill-scheduled-v1.0.1')
    expect(contacts).toContain('provider-contact-discover-scheduled-v1.3.3')

    expect(scholarships).toContain('scholarships-au-etl-v0.1.2')
    expect(scholarships).toContain('cleanupDuplicateRegisteredObject')
    expect(scholarships).toContain('.select("storage_path").eq("id",evidenceId).single()')
    expect(scholarships).toContain('if(error||!data?.storage_path||data.storage_path===path)return')
    expect(scholarships).toContain('.storage.from("evidence").remove([path])')
    expect(scholarships).toContain('console.warn("CF-055 duplicate Scholarship cleanup failed"')

    // Existing acquisition worker remains the accepted reference implementation.
    expect(acquire).toContain('ev.content_changed===false&&path!==evidencePath')
    expect(acquire).toContain('storage.from(BUCKET).remove([path])')
  })
})
