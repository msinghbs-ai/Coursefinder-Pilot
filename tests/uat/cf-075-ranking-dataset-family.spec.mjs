import fs from'node:fs/promises'
import{test,expect}from'@playwright/test'

test.describe('CF-075 compact multi-year ranking datasets',()=>{
 test('collapses ranking cards and preserves edition-aware imports/comparison',async()=>{
  const[layer1,shell,compare,etl,migration]=await Promise.all([
   fs.readFile('src/layer1-operations-entry.jsx','utf8'),
   fs.readFile('src/mature-main.jsx','utf8'),
   fs.readFile('src/ComparisonWorkspace.jsx','utf8'),
   fs.readFile('supabase/functions/ranking-layer1-etl/index.ts','utf8'),
   fs.readFile('supabase/migrations-archive/20260902064800_cf_075_ranking_dataset_family_metadata.sql','utf8'),
  ])
  expect(layer1).toContain('collapseRankingFamilies')
  expect(layer1).toContain('ranking_supported_years')
  expect(layer1).toContain('Upload selected edition')
  expect(layer1).toContain('One dataset family · historical editions retained')
  expect(shell).toContain('rankingYearOptions')
  // 8 Oct 2026: any edition from two years ahead back to 2010 can be uploaded (Platform Admin: upcoming years must not be limited)
  expect(shell).toContain("const top=new Date().getFullYear()+2;return Array.from({length:top-2009},(_,i)=>top-i)")
  expect(shell).toContain("system==='qs_wur'?new Date().getFullYear()+1:new Date().getFullYear()")
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
