import{test,expect}from'@playwright/test'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-095 ranking release currentness @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-095-ranking-release-currentness',change_control:'CF-CHG-20260903-095'})})

 test('deployed Admin reports v2.15.51 and defaults QS Parse.bot to qualified 2026',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await expect(page.locator('.m-release-pill')).toContainText('v2.15.51',{timeout:DETERMINISTIC_UI_TIMEOUT})
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  await expect(page.getByRole('heading',{name:'Register ranking publisher file'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const selects=page.locator('.m-ranking-essentials select')
  await expect(selects.nth(0)).toHaveValue('qs_wur')
  await expect(selects.nth(1)).toHaveValue('2026')
  await expect(selects.nth(2)).toHaveValue('url')
  await expect(page.locator('input[placeholder="/scrapers/…"]')).toHaveValue('/scrapers/e3ecc5de-f530-478a-b464-867d43099420')
  await expect(page.getByRole('button',{name:'Parse import'})).toBeEnabled()
 }finally{await finish(testInfo,runtime)}})

 test('QS 2027 URL route is visibly blocked with readable fallback guidance',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  const selects=page.locator('.m-ranking-essentials select')
  await selects.nth(1).selectOption('2027')
  await expect(page.locator('.m-ranking-detected.warning')).toContainText('QS 2027 Parse.bot source currently unavailable')
  await expect(page.locator('.m-ranking-detected.warning')).toContainText(/select 2026|File upload/i)
  await expect(page.getByRole('button',{name:/Parse import|change year/i})).toBeDisabled()
 }finally{await finish(testInfo,runtime)}})
})
