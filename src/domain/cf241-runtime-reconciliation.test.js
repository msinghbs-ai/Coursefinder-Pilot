import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const migrationUrl = new URL('../../supabase/migrations/20260908103500_cf_241_forward_runtime_reconciliation.sql', import.meta.url)
const sql = readFileSync(fileURLToPath(migrationUrl), 'utf8')

describe('CF-241 forward runtime reconciliation contract', () => {
  it('restores the two superseded CF-239 admin_read routes', () => {
    expect(sql).toContain("security.admin_evidence_page(p_args)")
    expect(sql).toContain("security.admin_layer2_ops_read(''layer2_ops_overview'',p_args)")
    expect(sql).toContain('admin_evidence_page_default_fast')
    expect(sql).toContain('admin_layer2_ops_overview_fast')
  })

  it('fails closed on unknown dispatcher shapes and is replay-safe', () => {
    expect(sql).toContain('dispatcher shape is neither superseded nor reconciled')
    expect(sql).toContain('position(v_evidence_new in v_definition)')
    expect(sql).toContain('position(v_layer2_new in v_definition)')
  })

  it('does not remove helpers, indexes, canonical data, or rewrite unrelated routes', () => {
    expect(sql).not.toMatch(/drop\s+index/i)
    expect(sql).not.toMatch(/drop\s+function/i)
    expect(sql).not.toMatch(/delete\s+from/i)
    expect(sql).not.toMatch(/truncate\s+/i)
    expect(sql).not.toMatch(/update\s+(catalogue|pim|scholarship|pipeline)\./i)
    expect(sql).toContain('preserve all other current admin_read routes')
  })
})
