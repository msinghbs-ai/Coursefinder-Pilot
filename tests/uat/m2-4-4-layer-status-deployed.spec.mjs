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
      // v2.15.107+: the Dashboard page title is 'Dashboard' and the four Layers sit in one 'Layers' panel.
      await expect(page.getByRole('heading',{name:'Dashboard',exact:true}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      const panel=page.locator('.m-panel').filter({has:page.getByRole('heading',{name:'Layers',exact:true})}).first()
      await expect(panel).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      for(const label of ['Layer 1 · Registers','Layer 2 · Pages','Layer 3 · AI','Layer 4 · Review']){
        await expect(panel.getByText(label,{exact:true})).toBeVisible()
      }
      await expect(page.getByText(/unsupported admin read operation: layer_status_summary/i)).toHaveCount(0)
    }finally{
      await finish(testInfo,runtime)
    }
  })
})
