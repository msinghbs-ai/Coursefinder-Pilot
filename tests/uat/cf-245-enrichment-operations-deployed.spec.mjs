import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-245 Enrichment Operations deployed acceptance @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required')
    await writeRunEnvironment({suite:'cf-245-enrichment-operations-deployed',change_control:'CF-CHG-20260915-245'})
  })

  test('operator can see outcome-focused enrichment reporting and current governed coverage',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const readResponse=page.waitForResponse(r=>{
      if(!r.url().includes('/rest/v1/rpc/admin_read'))return false
      try{return r.request().postDataJSON()?.p_operation==='enrichment_operations'}catch{return false}
    })
    await clickPrimaryNav(page,'Layer 2 — Enrichment')
    const ws=page.getByLabel('Layer 2 Operations')
    await expect(ws).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    const ops=ws.locator('[data-cf245-enrichment-operations="true"]')
    await expect(ops).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    const response=await readResponse
    expect(response.ok()).toBeTruthy()
    const body=await response.json()
    expect(body?.change_control_ref).toBe('CF-CHG-20260915-245')
    expect(Array.isArray(body?.coverage)).toBeTruthy()
    expect(Array.isArray(body?.hourly)).toBeTruthy()
    await expect(ops.getByRole('heading',{name:'Enrichment Operations',exact:true})).toBeVisible()
    for(const heading of ['Coverage & backlog','Where work stops','Provider yield & latency','Hourly enrichment funnel','Recent field admissions','Recent execution trace'])await expect(ops.getByText(heading,{exact:true})).toBeVisible()
    await expect(ops).toContainText(/Acquisition, admission and publication remain separate stages/i)
    await expect(ops).toContainText(/Official course URL/i)
    await expect(ops).toContainText(/Layer 3/i)
    await milestoneScreenshot(page,testInfo,'cf-245-enrichment-operations')
  }finally{await finish(testInfo,runtime)}})
})
