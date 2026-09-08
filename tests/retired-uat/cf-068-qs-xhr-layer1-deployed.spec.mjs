import{test,expect}from'@playwright/test'
import{attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment}from'./support/runtime-evidence.mjs'
import{openLayer1}from'./support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
async function layer1Read(page,dialog){
 const responsePromise=page.waitForResponse(r=>{if(!r.url().includes('/rest/v1/rpc/admin_read'))return false;try{return r.request().postDataJSON()?.p_operation==='layer1_operations'}catch{return false}},{timeout:DETERMINISTIC_UI_TIMEOUT})
 await dialog.getByRole('button',{name:'Refresh'}).click();const response=await responsePromise;return{data:await response.json(),headers:await response.request().allHeaders(),origin:new URL(response.url()).origin}
}
async function validate(page,read,source){
 return page.evaluate(async({origin,authorization,apikey,sourceId})=>{
  const response=await fetch(`${origin}/functions/v1/layer1-operations-control`,{method:'POST',headers:{authorization,apikey,'content-type':'application/json'},body:JSON.stringify({action:'validate',source_id:sourceId})})
  return{status:response.status,body:await response.json().catch(()=>({}))}
 },{origin:read.origin,authorization:read.headers.authorization,apikey:read.headers.apikey,sourceId:source.source_id})
}

test.describe('CF-068 QS direct XHR Layer 1 acquisition @deployed',()=>{
 test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('deployed UAT environment required');await writeRunEnvironment({suite:'cf-068-qs-xhr-layer1',change_control:'CF-CHG-20260902-068'})})

 test('QS 2026 validates 1501 publisher rows from retained direct XHR JSON',async({page},testInfo)=>{test.setTimeout(180000);const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);const dialog=await openLayer1(page)
  const country=dialog.locator('.l1v2-filter').filter({hasText:'Country'}).locator('select');await country.selectOption('GLOBAL')
  const dataset=dialog.locator('.l1v2-filter').filter({hasText:'Dataset'}).locator('select');await dataset.selectOption('statistics')
  await expect(dialog.getByText('QS World University Rankings 2026',{exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const read=await layer1Read(page,dialog),source=(read.data?.sources||[]).find(s=>s.source_system==='QS'&&Number(s.edition_year)===2026)
  expect(source?.acquisition_mode).toBe('publisher_static_xhr_json_with_manual_fallback')
  const result=await validate(page,read,source)
  expect(result.status).toBe(200);expect(result.body?.ok).toBe(true)
  expect(result.body?.validation?.source_system).toBe('QS')
  expect(result.body?.validation?.discovered?.candidate_observations).toBe(1501)
  expect(result.body?.validation?.source_hash).toMatch(/^[a-f0-9]{64}$/)
  expect(result.body?.validation?.discovered?.evidence_artifact_id).toBeTruthy()
  const preview=result.body?.validation?.discovered?.reconciliation_preview;console.log('CF071_RECONCILIATION_PREVIEW',JSON.stringify(preview));expect(preview?.country_code).toBe('AU');expect(preview?.country_rows).toBe(36);expect(preview?.mapped_unique).toBe(35);expect(preview?.alias_unique).toBe(14);expect(preview?.exact_unique).toBe(21);expect(preview?.exact_ambiguous).toBe(1);expect(preview?.unmatched).toBe(0)
  await dialog.getByRole('button',{name:'Refresh'}).click();await country.selectOption('GLOBAL');await dataset.selectOption('statistics')
  await expect(dialog.locator('article.l1v2-card').filter({hasText:'QS World University Rankings 2026'})).toContainText('1,501')
  await milestoneScreenshot(page,testInfo,'cf-068-qs-2026-xhr-validated')
 }finally{await finish(testInfo,runtime)}})

 test('QS 2027 reports publisher endpoint challenge without bypassing it',async({page},testInfo)=>{test.setTimeout(120000);const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);const dialog=await openLayer1(page);const read=await layer1Read(page,dialog),source=(read.data?.sources||[]).find(s=>s.source_system==='QS'&&Number(s.edition_year)===2027)
  expect(source?.source_id).toBeTruthy();expect(source?.acquisition_mode).toBe('publisher_rest_json_qualification_with_manual_fallback')
  const result=await validate(page,read,source)
  expect(result.status).toBeGreaterThanOrEqual(400)
  expect(String(result.body?.error||'')).toMatch(/Cloudflare|challenge/i)
 }finally{await finish(testInfo,runtime)}})
})
