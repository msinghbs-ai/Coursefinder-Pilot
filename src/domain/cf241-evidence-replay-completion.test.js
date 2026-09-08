import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const migrationUrl = new URL('../../supabase/migrations/20260908111800_cf_241_evidence_replay_completion.sql', import.meta.url)
const sql = readFileSync(fileURLToPath(migrationUrl), 'utf8')

describe('CF-241 Evidence replay completion contract', () => {
  it('restores all helper dependencies used by the governed Evidence page', () => {
    expect(sql).toContain('create or replace function security.admin_evidence_layer')
    expect(sql).toContain('create or replace function security.admin_evidence_matches_entity')
    expect(sql).toContain('create or replace function security.admin_evidence_verification_at')
  })

  it('rebuilds the derived lineage cache under write-blocking relation locks', () => {
    expect(sql).toContain('lock table %s in share row exclusive mode')
    expect(sql).toContain('create temporary table cf241_lineage_rebuild')
    expect(sql).toContain('delete from pipeline.evidence_lineage_stats')
    expect(sql).toContain('insert into pipeline.evidence_lineage_stats')
  })

  it('gives rejected extraction state precedence over extracted', () => {
    expect(sql).toContain("(v_extraction_state=''extracted'' and observation_count>0 and rejected_count=0)")
    expect(sql).toContain("case when x.rejected_count>0 then ''rejected'' when x.observation_count>0 then ''extracted'' else ''missing_extraction'' end")
  })

  it('excludes explicit stale rows from expired and current freshness filters', () => {
    expect(sql).toContain("v_freshness=''expired'' and not (lower(coalesce(e.metadata->>''freshness_state'',''''))=''stale''")
    expect(sql).toContain("v_freshness=''current'' and not (lower(coalesce(e.metadata->>''freshness_state'',''''))=''stale''")
  })
})
