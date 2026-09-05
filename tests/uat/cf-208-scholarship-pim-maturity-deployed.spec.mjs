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
  const catalogue=page.locator('.m-catalogue-panel').first()
  await expect(catalogue.getByRole('heading',{name:'Scholarship catalogue',exact:true})).toBeVisible(ui)
  const count=catalogue.locator('.m-result-count strong')
  await expect(count).toBeVisible(ui)
  await expect.poll(async()=>Number((await count.innerText()).replace(/[^0-9]/g,'')),ui).toBeGreaterThan(0)
  await expect(catalogue.getByText('Country',{exact:true}).first()).toBeVisible(ui)
  await expect(catalogue.getByText('Lifecycle',{exact:true}).first()).toBeVisible(ui)
  await expect(catalogue.getByText('Publication',{exact:true}).first()).toBeVisible(ui)
  await expect(catalogue.locator('tbody tr').first()).toBeVisible(ui)
  await milestoneScreenshot(page,testInfo,'cf-208-scholarship-pim-catalogue')
 }finally{await finish(testInfo,runtime)}})
})
