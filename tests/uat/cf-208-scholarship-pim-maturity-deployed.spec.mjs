// Guards: CF-208 deployed Scholarship PIM maturity
import {test,expect}from'@playwright/test'
import{attachRuntimeEvidence,assertNoServerErrors,clickPrimaryNav,DETERMINISTIC_UI_TIMEOUT,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment}from'./support/runtime-evidence.mjs'

const ui={timeout:DETERMINISTIC_UI_TIMEOUT}
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-208 deployed Scholarship PIM maturity @deployed',()=>{
 test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required.');await writeRunEnvironment({suite:'cf-208-scholarship-pim-maturity',change_control:'CF-208'})})
 test('Scholarship catalogue is populated and exposes governed operator controls',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await clickPrimaryNav(page,'Scholarships')
  await expect(page.locator('.m-title-wrap h1')).toContainText(/Scholarships/i,ui)
  // v2.15.174 (tidy Scholarships list): the list has no separate "Scholarship catalogue" heading; its count reads "<n> published"
  // (data-sch-count). Filters are Country, Provider and Audience (Lifecycle and Publication left the list with the rebuild that retired
  // the local CF-208 contracts, test register 26 Oct 2026); operators edit values in the list (Edit in list).
  const catalogue=page.locator('.m-catalogue-panel').first()
  const count=catalogue.locator('[data-sch-count] strong')
  await expect(count).toBeVisible({timeout:20_000})
  await expect.poll(async()=>Number((await count.innerText()).replace(/[^0-9]/g,'')),{timeout:20_000}).toBeGreaterThan(0)
  for(const filter of ['Country','Provider','Audience'])await expect(catalogue.locator('.m-filter-button').filter({hasText:new RegExp(filter,'i')}).first()).toBeVisible(ui)
  await expect(catalogue.locator('tbody tr').first()).toBeVisible(ui)
  await expect(catalogue.getByRole('button',{name:/Edit in list/})).toBeVisible(ui)
  await milestoneScreenshot(page,testInfo,'cf-208-scholarship-pim-catalogue')
 }finally{await finish(testInfo,runtime)}})
})
