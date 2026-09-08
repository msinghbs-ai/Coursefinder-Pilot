import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const migrationUrl = new URL('../../supabase/migrations/20260908113300_cf_241_lineage_privilege_hardening.sql', import.meta.url)
const sql = readFileSync(fileURLToPath(migrationUrl), 'utf8')

describe('CF-241 Evidence lineage privilege hardening', () => {
  it('revokes direct browser execution of the SECURITY DEFINER lineage mutator', () => {
    const signature = 'security.adjust_evidence_lineage_stats(uuid,bigint,bigint,bigint)'
    expect(sql).toContain(`revoke all on function ${signature} from public`)
    expect(sql).toContain(`revoke all on function ${signature} from anon`)
    expect(sql).toContain(`revoke all on function ${signature} from authenticated`)
  })

  it('keeps the trigger function internal-only as defence in depth', () => {
    expect(sql).toContain('revoke all on function security.sync_evidence_lineage_stats() from public')
    expect(sql).toContain('revoke all on function security.sync_evidence_lineage_stats() from anon')
    expect(sql).toContain('revoke all on function security.sync_evidence_lineage_stats() from authenticated')
  })
})
