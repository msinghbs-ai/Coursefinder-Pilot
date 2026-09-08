import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const migrationUrl = new URL('../../supabase/migrations/20260908103500_cf_241_forward_runtime_reconciliation.sql', import.meta.url)
const sql = readFileSync(fileURLToPath(migrationUrl), 'utf8')

describe('CF-241 forward runtime reconciliation contract', () => {
  it('restores the governed evidence page implementation before routing to it', () => {
    const definition = sql.indexOf('create or replace function security.admin_evidence_page')
    const dispatcher = sql.indexOf("v_evidence_new constant text := 'if p_operation=''evidence_page'' then return security.admin_evidence_page(p_args); end if;'")
    expect(definition).toBeGreaterThanOrEqual(0)
    expect(dispatcher).toBeGreaterThan(definition)
    expect(sql).toContain("security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type)")
    expect(sql).toContain("if v_rank<3 then raise exception 'curator role required'")
    expect(sql).toContain("set search_path to 'pg_catalog','security','pipeline','ref','auth','storage'")
  })

  it('restores the two superseded CF-239 admin_read routes', () => {
    expect(sql).toContain("security.admin_evidence_page(p_args)")
    expect(sql).toContain("security.admin_layer2_ops_read(''layer2_ops_overview'',p_args)")
    expect(sql).toContain('admin_evidence_page_default_fast')
    expect(sql).toContain('admin_layer2_ops_overview_fast')
  })

  it('accepts the checked-in pre-CF-239 dispatcher shape for clean migration replay', () => {
    expect(sql).toContain('v_evidence_checked_in')
    expect(sql).toContain("'evidence_page'',''evidence_filters'',''evidence_detail'',''evidence_observations'',''evidence_entities''")
    expect(sql).toContain('v_layer2_checked_in')
    expect(sql).toContain("'layer2_ops_overview'',''layer2_ops_run_detail''")
    expect(sql).toContain('v_evidence_checked_in_reconciled')
    expect(sql).toContain('v_layer2_checked_in_reconciled')
  })

  it('fails closed on unknown dispatcher shapes and remains replay-safe', () => {
    expect(sql).toContain('dispatcher shape is neither checked-in, superseded nor reconciled')
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
