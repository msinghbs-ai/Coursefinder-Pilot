// Guards: Platform Admin 22 Nov 2026 14:22 AEDT: ARWU is the third ranking (Layer 1 reader of the public ShanghaiRanking table, published with attribution); QS stays on the annual upload; the Platform Admin publishes and rolls back editions
// s971: the ARWU reader (ranks, ties shown as repeated numbers, bands, null band scores, indicators named by the publisher, national rank),
// the Layer 1 routes for ARWU sources, the Ranking editions panel (list for rank 4+, publish and unpublish for the Platform Admin with a
// reason), the migration (ARWU 2026 source, apply holds the ARWU revision while loading, the editions function and its log), and the guides.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PUBLIC_SOURCES, arwuRowsFromPublicJson, attribution } from '../../supabase/functions/ranking-layer1-etl/public-readers.ts'

const read = (p) => fs.readFileSync(p, 'utf8')
const ARWU = JSON.parse(read('tests/fixtures/rankings/arwu-2026-sample.json'))
const MIG = read('supabase/migrations/20261122150000_cf247_s971_rankings_arwu_editions_publish.sql')

test('ARWU rows: exact ranks, repeated ranks as ties, bands with null scores, named indicators and national rank', () => {
  const { rows, stats } = arwuRowsFromPublicJson(ARWU, 2026)
  expect(stats).toMatchObject({ rows: 6, exact: 4, bands: 2, tied: 2 })
  expect(rows[0]).toMatchObject({ publisher_institution_id: 'harvard-university', institution_name: 'Harvard University', country_text: 'United States', rank_exact: 1, overall_score: 100 })
  expect(Object.keys(rows[0].indicators).sort()).toEqual(['alumni', 'award', 'hici', 'national_rank', 'ns', 'pcp', 'pub'])
  expect(rows[0].indicators.hici).toMatchObject({ label: 'HiCi', value_numeric: 100, methodology_version: '2026' })
  const uq = rows.find((r) => r.institution_name === 'The University of Queensland')
  const mcgill = rows.find((r) => r.institution_name === 'McGill University')
  expect(uq).toMatchObject({ rank_display: '=73', rank_exact: 73, is_tied: true })
  expect(mcgill).toMatchObject({ rank_display: '=73', is_tied: true })
  const adl = rows.find((r) => r.publisher_institution_id === 'the-university-of-adelaide')
  expect(adl).toMatchObject({ rank_display: '101-150', rank_low: 101, rank_high: 150, overall_score: null, rank_status: 'ranked_band' })
  expect(adl.indicators.national_rank).toMatchObject({ value_display: '6-8', rank_low: 6, rank_high: 8 })
  expect(() => arwuRowsFromPublicJson({ ...ARWU, data: { ...ARWU.data, indicators: [{ yr: 2025, code: '1', nameEn: 'Alumni' }] } }, 2026)).toThrow(/2025, not 2026/)
  expect(() => arwuRowsFromPublicJson({ code: 500 }, 2026)).toThrow(/code 500/)
  expect(PUBLIC_SOURCES.arwu.jsonUrl(2026)).toBe('https://www.shanghairanking.com/api/pub/v1/arwu/rank?version=2026')
  expect(attribution('arwu', 2026)).toMatch(/^Academic Ranking of World Universities \(ARWU\) 2026, ShanghaiRanking\. Source: ShanghaiRanking \(shanghairanking\.com/)
})

test('the worker and the Layer 1 routes read ARWU like THE; QS is not read automatically', () => {
  const etl = read('supabase/functions/ranking-layer1-etl/index.ts')
  expect(etl).toContain('async function fetchArwuPublic(year:number)')
  expect(etl).toContain('systemCode==="arwu"?await fetchArwuPublic(editionYear)')
  for (const f of ['layer1-operations-control', 'layer1-operations-scheduled']) {
    const src = read(`supabase/functions/${f}/index.ts`)
    expect(src, f).toContain('system==="QS"||system==="THE"||system==="ARWU"')
    expect(src, f).not.toMatch(/system==="QS"\|\|system==="THE"\)/)
  }
})

test('Ranking editions panel: list for rank 4 and above, publish and unpublish with a reason for the Platform Admin', () => {
  const ui = read('src/RankingEditions.jsx')
  const main = read('src/mature-main.jsx')
  expect(main).toContain("{rank>=4&&<RankingEditions/>}")
  expect(ui).toContain("supabase.rpc('admin_ranking_editions_v1',{p_action:'list'})")
  expect(ui).toContain('p_action:action,p_edition_id:e.edition_id,p_reason:reason')
  expect(ui).toContain("disabled={busy===e.edition_id||reason.trim().length<5}")
  expect(ui).toContain('data.can_publish&&')
  expect(ui).toContain('QS comes from the annual file upload below')
})

test('migration: ARWU 2026 source, ARWU held while loading, editions function and log, first run queued; consumer API guarded', () => {
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect(MIG).toContain("'Academic Ranking of World Universities (ARWU) 2026'")
  expect(MIG).toContain("'source_system', 'ARWU', 'ranking_system_code', 'arwu'")
  expect(MIG).toContain("select pg_temp.edit_re('public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb)', 'c3f601c25e9b4cba1480d7ae04ce6b2b'")
  expect(MIG).toContain("in ('the_public_json_v1','qs_public_json_v1','arwu_public_json_v1')")
  expect(MIG).toContain('create table if not exists ranking.edition_status_changes (')
  expect(MIG).toContain("comment on table ranking.edition_status_changes is")
  expect(MIG).toContain('create or replace function public.admin_ranking_editions_v1(p_action text default')
  expect(MIG).toContain("if v_rank < 6 then raise exception 'INVALID_INPUT: only a Platform Admin publishes or unpublishes a ranking edition'")
  expect(MIG).toContain("if length(btrim(coalesce(p_reason, ''))) < 5 then raise exception")
  expect(MIG).toContain("'^\\s*the\\s+'")
  expect(MIG).toContain("'s971-initial:' || s.id::text")
  expect(MIG).toContain('security.consumer_api_check_v1()')
  expect(MIG).not.toMatch(/cron\.schedule|\bdrop (table|function|index|schema|view|trigger)|delete from |truncate /i)
})

test('guides: both SOPs carry the ranking steps; the Platform guide names the Ranking editions list', async () => {
  const { SOPS } = await import('../../src/guide/sops.js')
  const admin = SOPS.find((s) => s.id === 'admin-sop'), op = SOPS.find((s) => s.id === 'operator-sop')
  const steps = (s) => s.schedule.flatMap((b) => b.steps.map((x) => x.do)).join('\n')
  expect(steps(op)).toContain('THE and ARWU: the Layer 1 readers read the publisher')
  expect(steps(op)).toContain('keep tied ranks (=12) and bands (501-510) exactly as printed')
  expect(steps(admin)).toContain('press Unpublish, give a reason and Unpublish edition')
  const g = read('src/guide/platformGuide.js')
  expect(g).toContain('Ranking editions (22 Nov 2026, v2.16.84)')
})
