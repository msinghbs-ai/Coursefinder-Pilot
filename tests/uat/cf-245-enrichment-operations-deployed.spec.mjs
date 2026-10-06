import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-245 Enrichment Operations deployed acceptance @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required')
    await writeRunEnvironment({suite:'cf-245-enrichment-operations-deployed',change_control:'CF-CHG-20260915-245'})
  })

  // Skipped in v2.15.203: this drives a Layer 2 screen retired in v2.15.200 (Decision 254). Its facts now live on Layer 2 > Adapters and Scheduled jobs > Jobs.
  test.skip('operator can see outcome-focused enrichment reporting and current governed coverage',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
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
    // v2.15.128: compact Overview; the execution trace is on History.
    for(const heading of ['Coverage and what is left','Where work stops','Fetchers','By hour','Not ready to fetch','Recently accepted facts'])await expect(ops.getByRole('heading',{name:heading,exact:true})).toBeVisible()
    await expect(ops).toContainText(/Course page link|Intakes|English requirements|Tuition/i)
    await expect(ops).toContainText(/Layer 3/i)
    await milestoneScreenshot(page,testInfo,'cf-245-enrichment-operations')
  }finally{await finish(testInfo,runtime)}})
})
