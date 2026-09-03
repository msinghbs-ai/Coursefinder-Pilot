import{test,expect}from'@playwright/test'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-098 file-first ranking bundle @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-098-ranking-file-bundle',change_control:'CF-CHG-20260903-098'})})

 test('ranking file upload is primary and country files combine before registration',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  await expect(page.locator('.m-release-pill')).toContainText('v2.15.54',{timeout:DETERMINISTIC_UI_TIMEOUT})
  const selects=page.locator('.m-ranking-essentials select')
  await expect(selects.nth(2)).toHaveValue('file')
  const input=page.locator('input[type=file][multiple]')
  await expect(input).toBeVisible()
  const makePayload=(country,count)=>JSON.stringify({status:'success',data:{ranking_title:'QS World University Rankings 2027',edition_year:'2027',total_universities:count,page:0,items_per_page:100,total_pages:1,has_more:false,universities:Array.from({length:count},(_,i)=>({rank:String(i+1),university_id:country.slice(0,2)+i,name:country+' University '+(i+1),country,city:'Test',overall_score:'50',indicators:[]}))}})
  await input.setInputFiles([
    {name:'QS_2027_AU.txt',mimeType:'text/plain',buffer:Buffer.from(makePayload('Australia',37))},
    {name:'QS_2027_NZ.txt',mimeType:'text/plain',buffer:Buffer.from(makePayload('New Zealand',8))}
  ])
  await expect(selects.nth(0)).toHaveValue('qs_wur')
  await expect(selects.nth(1)).toHaveValue('2027')
  const detected=page.locator('.m-ranking-detected').filter({hasText:'Country/multi-page bundle'})
  await expect(detected).toContainText('45 source rows detected')
  await expect(detected).toContainText('Australia')
  await expect(detected).toContainText('New Zealand')
 }finally{await finish(testInfo,runtime)}})
})
