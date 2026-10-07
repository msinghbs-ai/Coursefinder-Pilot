import fs from'node:fs/promises'
import{test,expect}from'@playwright/test'

test.describe('CF-075 compact multi-year ranking datasets',()=>{
 test('collapses ranking cards and preserves edition-aware imports/comparison',async()=>{
  const[layer1,shell,compare,etl,migration]=await Promise.all([
   fs.readFile('src/layer1-operations-entry.jsx','utf8'),
   fs.readFile('src/mature-main.jsx','utf8'),
   fs.readFile('src/ComparisonWorkspace.jsx','utf8'),
   fs.readFile('supabase/functions/ranking-layer1-etl/index.ts','utf8'),
   fs.readFile('supabase/migrations/20260902064800_cf_075_ranking_dataset_family_metadata.sql','utf8'),
  ])
  expect(layer1).toContain('collapseRankingFamilies')
  expect(layer1).toContain('ranking_supported_years')
  expect(layer1).toContain('Upload selected edition')
  expect(layer1).toContain('One dataset family · historical editions retained')
  expect(shell).toContain('rankingYearOptions')
  expect(shell).toContain("Array.from({length:12},(_,i)=>2026-i)")
  // 7 Oct 2026: rewritten to the current screens (QS editions 2026 and 2027 first; Compare picks Multi-year or one edition per ranking)
  expect(shell).toContain("system==='qs_wur'?[2026,2027,")
  expect(shell).toContain('Publisher JSON/TXT')
  expect(compare).toContain("{value:'multi',label:'Multi-year'}")
  expect(compare).toContain("setYear(x=>x&&years.includes(x)?x:(years[0]||''))")
  expect(compare).toContain('RankingTrend')
  expect(etl).toContain('qs_world_rank_')
  expect(etl).toContain('the_world_rank_')
  expect(etl).toContain('the_overall_score_')
  expect(etl).toContain('Compact ranking CSV requires an explicit country/location column or a country-scoped filename such as Australia')
  expect(migration).toContain("'global_qs_wur'")
  expect(migration).toContain("'global_the_wur'")
  expect(migration).toContain("'multi_year_family',true")
 })
})
