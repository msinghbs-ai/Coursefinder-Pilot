// Guards: CF-104 Statistics dataset registry
import{test,expect}from'@playwright/test'
import fs from'node:fs'
import{attachRuntimeEvidence,assertNoServerErrors,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment,DETERMINISTIC_UI_TIMEOUT}from'./support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-104 Statistics dataset registry @targeted',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-104-statistics-dataset-registry',change_control:'CF-CHG-20260904-104'})})
 test('source keeps operational imports out and registry is extensible',async()=>{
  // v2.15.291: the cards are drawn from the registry by mature-main.jsx (the post-render StatisticsDatasetEnhancer.js is retired); no Manage imports action.
  const x=fs.readFileSync('src/mature-main.jsx','utf8'),m=fs.readFileSync('supabase/migrations-archive/20260904104000_cf_104_statistics_dataset_registry.sql','utf8')
  expect(x).toContain("supabase.rpc('statistics_dataset_registry_read')");expect(x).toContain('registry.filter(x=>x?.display_enabled)');expect(x).toContain('className="cf-stat-desc"')
  expect(x).not.toMatch(/manage imports/i)
  expect(m).toContain("'arwu','Academic Ranking of World Universities'");expect(m).toContain("'diversity_index','University Diversity Index'")
  expect(m).toContain('display_enabled boolean not null default true')
 })
})
