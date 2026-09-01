import{test,expect}from'@playwright/test'
import{attachRuntimeEvidence,assertNoServerErrors,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('M2.5 Jobs workspace deployed @deployed',()=>{
 test.beforeAll(async()=>{
  if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.')
  if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required for deployed acceptance.')
  await writeRunEnvironment({suite:'m2-5-jobs-workspace-deployed',change_control:'CF-CHG-20260901-060'})
 })
 test('Jobs route shows live governed Pipeline Jobs instead of a manufactured empty list',async({page},testInfo)=>{
  const runtime=observeRuntime(page)
  try{
   await loginAsUatUser(page)
   await expect(page.locator('.m-release-pill')).toContainText('v2.15.20')
   await page.evaluate(()=>{location.hash='#jobs'})
   await expect(page.locator('.ops-workspace-head h2')).toHaveText('Jobs')
   const total=page.locator('.ops-result-count strong')
   await expect(total).not.toHaveText('0')
   await expect(page.locator('.ops-table tbody tr').first()).toBeVisible()
   await expect(page.locator('.ops-table')).toContainText(/layer2|regulatory|completed|running|failed/i)
   await expect(page.getByText('No matching jobs',{exact:true})).toHaveCount(0)
   await milestoneScreenshot(page,testInfo,'m2-5-jobs-workspace-live')
  }finally{await finish(testInfo,runtime)}
 })
})
