import{test,expect}from'@playwright/test'
import fs from'node:fs'
import{attachRuntimeEvidence,assertNoServerErrors,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment,DETERMINISTIC_UI_TIMEOUT}from'./support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-104 Statistics dataset registry @targeted',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-104-statistics-dataset-registry',change_control:'CF-CHG-20260904-104'})})
 test('source keeps operational imports out and registry is extensible',async()=>{
  const x=fs.readFileSync('src/StatisticsDatasetEnhancer.js','utf8'),m=fs.readFileSync('supabase/migrations/20260904104000_cf_104_statistics_dataset_registry.sql','utf8')
  expect(x).toContain('statistics_dataset_registry_read');expect(x).toContain('Statistics dataset registry');expect(x).toContain('Manage imports');
  expect(x).toContain("filter(x=>/manage imports/i.test(x.textContent)).forEach(x=>x.remove())")
  expect(m).toContain("'arwu','Academic Ranking of World Universities'");expect(m).toContain("'diversity_index','University Diversity Index'")
  expect(m).toContain('display_enabled boolean not null default true')
 })
 test('deployed operational page uses scalable cards and no Manage imports action',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
  await loginAsUatUser(page);await page.goto(new URL('/#statistics-rankings',process.env.UAT_BASE_URL).toString());await expect(page.getByRole('heading',{name:'Statistics & Rankings',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(page.locator('.m-stats-grid')).toBeVisible();await expect(page.getByText('Manage imports',{exact:true})).toHaveCount(0)
  const cards=page.locator('.m-stats-card');await expect(cards.first().locator('.cf-stat-desc')).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});expect(await cards.count()).toBeGreaterThanOrEqual(4)
  await milestoneScreenshot(page,testInfo,'cf-104-statistics-dataset-cards')
 }finally{await finish(testInfo,runtime)}})
 test('Admin exposes dataset display controls',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
  await loginAsUatUser(page);await page.goto(new URL('/#administration?section=statistics-datasets',process.env.UAT_BASE_URL).toString());await expect(page.getByText('Statistics dataset registry',{exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(page.getByText('Academic Ranking of World Universities',{exact:true})).toBeVisible();await expect(page.getByText('University Diversity Index',{exact:true})).toBeVisible();await expect(page.getByPlaceholder('Dataset name')).toBeVisible()
  await milestoneScreenshot(page,testInfo,'cf-104-statistics-dataset-admin')
 }finally{await finish(testInfo,runtime)}})
})
