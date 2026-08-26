import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
import { openLayer1 } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('M2.4.1 Layer 1 regulatory operations @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'m2-4-1-layer1-operations',change_control:'CF-CHG-20260826-043'})})

  test('AU and NZ expose the production-shaped operator journey',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const dialog=await openLayer1(page)
    await expect(dialog.getByRole('heading',{name:'Layer 1 — Regulatory'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    for(const country of ['AU','NZ']){const card=dialog.locator(`article.l1o-source[data-country="${country}"]`);await expect(card).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});for(const heading of ['1. Source Health','2. Current / Next Job','3. Progress','4. Reconciliation','5. Evidence / Provenance','6. Schedule / Recheck','7. Blockers / Required Actions'])await expect(card.getByRole('heading',{name:heading})).toBeVisible();await expect(card).toContainText('Approved authority domains');await expect(card).toContainText('Expected / previous');await expect(card).toContainText('Current source hash')}
    await expect(dialog).toContainText(/26,648/);await expect(dialog).toContainText(/409/);await expect(dialog).toContainText('Transient queue only; Evidence retained')
    await expect(dialog.getByText(/reset database/i)).toHaveCount(0);await expect(dialog.getByText(/parser qualification/i)).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'m2-4-1-layer1-operations')
  }finally{await finish(testInfo,runtime)}})

  test('authorised Layer 1 operator performs a real NZQA authority and count validation',async({page},testInfo)=>{test.setTimeout(120000);const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const readResponsePromise=page.waitForResponse(response=>{
      if(!response.url().includes('/rest/v1/rpc/admin_read'))return false
      try{return response.request().postDataJSON()?.p_operation==='layer1_operations'}catch{return false}
    },{timeout:DETERMINISTIC_UI_TIMEOUT})
    const dialog=await openLayer1(page),nz=dialog.locator('article.l1o-source[data-country="NZ"]')
    const readResponse=await readResponsePromise,readData=await readResponse.json(),source=(readData?.sources||[]).find(s=>s.country_code==='NZ')
    expect(source?.source_id,'NZ Layer 1 source must be present in governed read contract').toBeTruthy()
    const requestHeaders=await readResponse.request().allHeaders(),supabaseOrigin=new URL(readResponse.url()).origin
    expect(requestHeaders.authorization,'authenticated Layer 1 read must carry bearer authority').toMatch(/^Bearer /i)
    expect(requestHeaders.apikey,'authenticated Layer 1 read must carry publishable API key').toBeTruthy()
    const result=await page.evaluate(async({origin,authorization,apikey,sourceId})=>{
      const response=await fetch(`${origin}/functions/v1/layer1-operations-control`,{method:'POST',headers:{authorization,apikey,'content-type':'application/json'},body:JSON.stringify({action:'validate',source_id:sourceId})})
      const data=await response.json().catch(()=>({}));if(!response.ok||data?.error)throw new Error(data?.error||`Layer 1 validation HTTP ${response.status}`);return data
    },{origin:supabaseOrigin,authorization:requestHeaders.authorization,apikey:requestHeaders.apikey,sourceId:source.source_id})
    expect(result?.ok).toBe(true);expect(result?.validation?.country_code).toBe('NZ');expect(result?.validation?.discovered?.providers).toBeGreaterThan(300);expect(result?.validation?.discovered?.pages).toBe(5);expect(result?.validation?.worker_version).toContain('v1.0.1')
    await page.getByRole('button',{name:'Refresh'}).click();await expect(nz).toContainText('passed',{timeout:DETERMINISTIC_UI_TIMEOUT});await expect(nz).toContainText(/409/);await milestoneScreenshot(page,testInfo,'m2-4-1-nz-source-validated')
  }finally{await finish(testInfo,runtime)}})

  test('anonymous browser cannot execute Layer 1 read or command contracts',async({request})=>{
    const base=process.env.UAT_BASE_URL;const home=await request.get(base);expect(home.ok()).toBeTruthy();const html=await home.text();expect(html).not.toContain('SUPABASE_SERVICE_ROLE_KEY')
  })
})
