import{test,expect}from'@playwright/test'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-095 / CF-228 ranking release currentness @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-095-ranking-release-currentness',change_control:'CF-CHG-20260903-095 / CF-228'})})

 test('deployed Admin reports v2.15.71 and defaults ranking acquisition to governed file upload',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await expect(page.locator('.m-release-pill')).toContainText('v2.15.71',{timeout:DETERMINISTIC_UI_TIMEOUT})
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  await expect(page.getByRole('heading',{name:'Register ranking publisher file'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(page.locator('.m-ranking-import-head')).toContainText(/File upload is the preferred ranking acquisition route/i)
  const selects=page.locator('.m-ranking-essentials select')
  await expect(selects.nth(0)).toHaveValue('qs_wur')
  await expect(selects.nth(1)).toHaveValue('2026')
  await expect(selects.nth(2)).toHaveValue('file')
  await expect(page.locator('input[type="file"]')).toBeVisible()
  await expect(page.locator('input[type="file"]')).toHaveAttribute('multiple','')
 }finally{await finish(testInfo,runtime)}})

 test('QS 2027 remains file-first and exposes the URL warning only when optional URL fallback is selected',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  const selects=page.locator('.m-ranking-essentials select')
  await selects.nth(1).selectOption('2027')
  await expect(selects.nth(2)).toHaveValue('file')
  await expect(page.locator('input[type="file"]')).toBeVisible()
  await expect(page.locator('.m-ranking-detected.warning')).toHaveCount(0)
  await selects.nth(2).selectOption('url')
  await expect(page.locator('.m-ranking-detected.warning')).toContainText('QS 2027 Parse.bot source currently unavailable')
  await expect(page.locator('.m-ranking-detected.warning')).toContainText(/select 2026|File upload/i)
 }finally{await finish(testInfo,runtime)}})
})
