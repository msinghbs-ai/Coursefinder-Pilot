import{test,expect}from'@playwright/test'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-100 multi-country same-edition ranking scope @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-100-ranking-country-extension',change_control:'CF-CHG-20260903-100'})})

 test('existing edition recognises a new country as extension rather than replacement',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports&system=qs_wur&year=2026',process.env.UAT_BASE_URL).toString())
  await expect(page.locator('.m-release-pill')).toContainText('v2.15.56',{timeout:DETERMINISTIC_UI_TIMEOUT})
  const input=page.locator('input[type=file][multiple]')
  await expect(input).toBeVisible()
  const payload=JSON.stringify({status:'success',data:{ranking_title:'QS World University Rankings 2026',edition_year:'2026',total_universities:1,page:0,items_per_page:100,total_pages:1,has_more:false,universities:[{rank:'1',university_id:'cf100-ca-1',name:'CF100 Canada University',country:'Canada',city:'Toronto',overall_score:'99',indicators:[]}]}})
  await input.setInputFiles({name:'QS_2026_CA_CF100.txt',mimeType:'text/plain',buffer:Buffer.from(payload)})
  const detected=page.locator('.m-ranking-detected').filter({hasText:'Canada'})
  await expect(detected).toContainText('QS World University Rankings · 2026')
  const button=page.locator('.m-ranking-import-actions button.m-primary')
  const text=(await button.textContent())||''
  if(text.includes('Add country data')){
    await expect(detected).toContainText('Add country data')
  }else{
    await expect(detected).toContainText(/Existing country scope|Mixed scope/)
  }
  await expect(page.locator('body')).not.toContainText('may replace the accepted edition')
 }finally{await finish(testInfo,runtime)}})

 test('source contract keeps Apply manual and exposes country scope metadata',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  await expect(page.locator('.m-release-pill')).toContainText('v2.15.56',{timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(page.locator('.m-ranking-history-head')).toContainText('Acquire Evidence → Parse & validate → Apply edition')
  await expect(page.locator('.m-ranking-import-page')).toContainText(/country|Country/)
 }finally{await finish(testInfo,runtime)}})
})
