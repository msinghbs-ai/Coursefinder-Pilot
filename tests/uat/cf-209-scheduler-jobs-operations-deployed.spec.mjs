import{test,expect}from'@playwright/test'
import{attachRuntimeEvidence,assertNoServerErrors,clickPrimaryNav,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment,DETERMINISTIC_UI_TIMEOUT}from'./support/runtime-evidence.mjs'

const ui={timeout:DETERMINISTIC_UI_TIMEOUT}
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-209 deployed Scheduler and Jobs operations acceptance @deployed',()=>{
 test.beforeAll(async()=>{
  if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.')
  if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required.')
  await writeRunEnvironment({suite:'cf-209-scheduler-jobs-operations',change_control:'CF-CHG-20260905-209'})
 })

 test('shows governed Scheduling intelligence without generic execution controls',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await clickPrimaryNav(page,'Administration')
  await expect(page.getByRole('heading',{name:'Administration overview',exact:true})).toBeVisible(ui)
  const tab=page.getByRole('tab',{name:'Scheduling',exact:true})
  await expect(tab).toBeVisible(ui);await tab.click()
  await expect(page.getByRole('heading',{name:'Source/entity freshness policies',exact:true})).toBeVisible(ui)
  await expect(page.getByRole('heading',{name:'Targeted refresh queue',exact:true})).toBeVisible(ui)
  await expect(page.getByRole('heading',{name:'Downstream Search refresh signals',exact:true})).toBeVisible(ui)
  await expect(page.getByRole('button',{name:/Retry scheduled refresh/i})).toHaveCount(0)
  await expect(page.getByRole('button',{name:/Replay scheduled refresh/i})).toHaveCount(0)
  await expect(page.getByRole('button',{name:/Reset scheduled refresh/i})).toHaveCount(0)
  await milestoneScreenshot(page,testInfo,'cf-209-scheduling')
 }finally{await finish(testInfo,runtime)}})

 test('keeps Jobs as the server-paged execution and telemetry workspace',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await clickPrimaryNav(page,'Jobs')
  await expect(page.locator('.m-title-wrap h1')).toContainText(/Jobs/i,ui)
  await expect(page.getByText(/Server-paged execution history/i)).toBeVisible(ui)
  await expect(page.getByText('Completion',{exact:true}).first()).toBeVisible(ui)
  await expect(page.getByText('Failure class',{exact:true}).first()).toBeVisible(ui)
  await expect(page.getByRole('button',{name:/Retry/i})).toHaveCount(0)
  await expect(page.getByRole('button',{name:/Replay/i})).toHaveCount(0)
  await expect(page.getByRole('button',{name:/Reset/i})).toHaveCount(0)
  await milestoneScreenshot(page,testInfo,'cf-209-jobs')
 }finally{await finish(testInfo,runtime)}})
})
