// Guards: CF-209 deployed Scheduler and Jobs operations acceptance
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

 // v2.15.124 (Schedules folded into Automations) and v2.15.200 (Administration's Scheduling sub-tab retired): the scheduling intelligence
 // is the "Refresh schedules and one-off runs" section of Scheduled jobs › Automations.
 test('shows governed Scheduling intelligence without generic execution controls',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await clickPrimaryNav(page,'Scheduled Tasks')
  await expect(page.locator('.m-title-wrap h1')).toContainText('Scheduled jobs',ui)
  const tab=page.locator('.cf-page-tabs [role="tab"]').filter({hasText:'Automations'}).first()
  await expect(tab).toHaveAttribute('aria-selected','true',ui)
  const scheduling=page.locator('.cf-scheduler-v2-native')
  await expect(scheduling).toBeVisible({timeout:20_000})
  await expect(scheduling.getByRole('heading',{name:'Schedule Configuration',exact:true})).toBeVisible({timeout:20_000})
  await expect(scheduling.getByRole('heading',{name:'Latest Refresh Queue',exact:true})).toBeVisible(ui)
  await expect(scheduling.getByRole('heading',{name:/^Downstream Search refresh signals$/i})).toBeVisible(ui)
  await expect(scheduling).toContainText('Historical Jobs are never reset or replayed')
  await expect(page.getByRole('button',{name:/Retry scheduled refresh/i})).toHaveCount(0)
  await expect(page.getByRole('button',{name:/Replay scheduled refresh/i})).toHaveCount(0)
  await expect(page.getByRole('button',{name:/Reset scheduled refresh/i})).toHaveCount(0)
  await milestoneScreenshot(page,testInfo,'cf-209-scheduling')
 }finally{await finish(testInfo,runtime)}})

 // v2.15.200: Jobs is a tab of Scheduled jobs; v2.15.229 removed the console's descriptive banner. The rule is unchanged: server-paged
 // history with completion and failure classes, and no generic retry, replay or reset of past runs.
 test('keeps Jobs as the server-paged execution and telemetry workspace',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  const jobsPage=page.waitForResponse(r=>{if(!r.url().includes('/rest/v1/rpc/admin_read'))return false;try{return r.request().postDataJSON()?.p_operation==='pipeline_jobs_page'}catch{return false}},{timeout:45_000})
  await clickPrimaryNav(page,'Jobs')
  await expect(page.locator('.m-title-wrap h1')).toContainText(/Scheduled jobs/i,ui)
  const body=await(await jobsPage).json()
  expect(Number(body?.total||0)).toBeGreaterThan(Number(body?.limit||50))
  expect((body?.items||body?.rows||[]).length).toBeLessThanOrEqual(50)
  await expect(page.locator('section.ops-workspace-head[aria-label="Jobs"]')).toBeVisible(ui)
  await expect(page.locator('.ops-pager').first()).toBeVisible(ui)
  await expect(page.locator('.ops-select').filter({hasText:'Completion'}).first()).toBeVisible(ui)
  await expect(page.locator('.ops-select').filter({hasText:'Failure class'}).first()).toBeVisible(ui)
  await expect(page.getByRole('button',{name:/^(Retry|Replay|Reset)( job| run)?$/i})).toHaveCount(0)
  await milestoneScreenshot(page,testInfo,'cf-209-jobs')
 }finally{await finish(testInfo,runtime)}})
})
