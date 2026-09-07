import{test,expect}from'@playwright/test'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('M2.4.5 v2.15.73 release currentness @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'m245-v2-15-73-release-currentness',change_control:'CF-CHG-20260907-241'})})
 test('accepted Pilot UI reports one synchronized v2.15.73 release',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await expect(page.locator('.m-release-pill')).toContainText('v2.15.73',{timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(page).toHaveTitle(/Coursefinder PIM Admin v2\.15\.73/)
  await expect.poll(()=>page.evaluate(()=>document.documentElement.dataset.cfReleaseVersion||''),{timeout:DETERMINISTIC_UI_TIMEOUT}).toBe('2.15.73')
  await page.locator('.m-release-pill').click()
  await expect(page.locator('[data-release-version="2.15.73"]')).toHaveCount(1)
  await expect(page.locator('[data-release-version="2.15.73"]')).toContainText('Fluid catalogues, ranking datasets and Provider comparison')
 }finally{await finish(testInfo,runtime)}})
})
