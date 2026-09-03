import{test,expect}from'@playwright/test'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-096 ranking Parse.bot Evidence hand-off @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-096-ranking-parsebot-handoff',change_control:'CF-CHG-20260903-096'})})

 test('QS 2026 registered Parse.bot Evidence parses through the exact selected import',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  await expect(page.locator('.m-release-pill')).toContainText('v2.15.52',{timeout:DETERMINISTIC_UI_TIMEOUT})
  const row=page.locator('.m-ranking-import-row').filter({hasText:'QS_WUR 2026'}).first()
  await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const action=row.getByRole('button',{name:'Parse & validate'})
  if(await action.count()){
    await action.click()
    await expect(row).toContainText(/Validated|Needs review/i,{timeout:60000})
    await expect(row).toContainText(/parsed observations/i)
  }else{
    await expect(row).toContainText(/Validated|Needs review|Applied/i)
  }
  await expect(page.locator('.m-alert')).not.toContainText(/ranking Evidence required/i)
 }finally{await finish(testInfo,runtime)}})
})
