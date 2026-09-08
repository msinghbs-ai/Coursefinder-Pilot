import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const migrationUrl = new URL('../../supabase/migrations/20260908115100_cf_241_evidence_entity_links_replay.sql', import.meta.url)
const sql = readFileSync(fileURLToPath(migrationUrl), 'utf8')

describe('CF-241 Evidence entity-link replay contract', () => {
  it('restores the governed derived relation before helpers reference it', () => {
    const table = sql.indexOf('create table if not exists pipeline.evidence_entity_links')
    const helper = sql.indexOf('create or replace function security.evidence_row_entity_links')
    expect(table).toBeGreaterThanOrEqual(0)
    expect(helper).toBeGreaterThan(table)
    expect(sql).toContain("entity_type in ('provider','course','campus','scholarship')")
  })

  it('restores and protects the maintenance path', () => {
    expect(sql).toContain('create or replace function security.adjust_evidence_entity_link')
    expect(sql).toContain('create or replace function security.sync_evidence_entity_links')
    expect(sql).toContain('revoke all on function security.adjust_evidence_entity_link(uuid,text,uuid,uuid,bigint) from public,anon,authenticated')
    expect(sql).toContain('revoke all on function security.sync_evidence_entity_links() from public,anon,authenticated')
  })

  it('uses atomic relation locks, backfills clean replay, and installs the accepted trigger topology', () => {
    expect(sql).toContain('lock table %s in share row exclusive mode')
    expect(sql).toContain('if not exists(select 1 from pipeline.evidence_entity_links) then')
    expect(sql).toContain("tgname='evidence_entity_links_sync'")
    expect(sql).toContain('create trigger evidence_entity_links_sync')
  })
})
