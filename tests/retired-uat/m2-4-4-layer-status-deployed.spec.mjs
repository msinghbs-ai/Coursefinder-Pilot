import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){
  await attachRuntimeEvidence(testInfo,runtime)
  assertNoServerErrors(runtime)
}

test.describe('M2.4.4 Dashboard Layer status @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-layer-status',change_control:'CF-CHG-20260830-048'})})

  test('Dashboard loads bounded Layer 1-4 operational status without RPC errors',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await expect(page.getByRole('heading',{name:'Operational command view',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      const panel=page.locator('.m-panel').filter({has:page.getByText('Layer status',{exact:true})}).first()
      await expect(panel).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      for(const label of ['Layer 1 · Authority','Layer 2 · Enrichment','Layer 3 · AI interpretation','Layer 4 · Human resolution']){
        await expect(panel.getByText(label,{exact:true})).toBeVisible()
      }
      await expect(page.getByText(/unsupported admin read operation: layer_status_summary/i)).toHaveCount(0)
    }finally{
      await finish(testInfo,runtime)
    }
  })
})
