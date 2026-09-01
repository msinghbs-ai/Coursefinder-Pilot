import { test, expect } from '@playwright/test'
import {
  attachRuntimeEvidence,
  assertNoServerErrors,
  DETERMINISTIC_UI_TIMEOUT,
  loginAsUatUser,
  milestoneScreenshot,
  observeRuntime,
  writeRunEnvironment,
} from './support/runtime-evidence.mjs'
import { openLayer2, openLayer3 } from './support/navigation.mjs'

async function finish(testInfo,runtime){
  await attachRuntimeEvidence(testInfo,runtime)
  assertNoServerErrors(runtime)
}

test.describe('M2.5 Pilot deployment currentness @deployed',()=>{
  test.beforeAll(async()=>{
    await writeRunEnvironment({
      suite:'m2-5-pilot-deployment-currentness',
      change_control:'CF-CHG-20260901-053 / CF-CHG-20260901-054',
    })
  })

  test('deployed Worker contains CF-053 and CF-054 operator surfaces without executing AI',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)

      const layer2=await openLayer2(page)
      const terminal=layer2.locator('[data-l2-latest-terminal="true"]')
      await expect(terminal).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      const classification=terminal.locator('[data-l2-wave-classification]')
      await expect(classification).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(classification).toContainText(/acceptance-isolation\/rescheduled/i)
      await expect(classification).toContainText(/operational failures/i)

      const layer3=await openLayer3(page)
      const queue=layer3.locator('[data-layer3-source-pattern-queue]')
      await expect(queue).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(queue.getByRole('heading',{name:'Governed Provider source-pattern queue',exact:true})).toBeVisible()
      await expect(queue).toContainText(/manual-governed/i)
      await expect(queue.getByRole('button',{name:'Run source-pattern interpretation',exact:true}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(page.getByRole('button',{name:/Run all source-pattern/i})).toHaveCount(0)

      await milestoneScreenshot(page,testInfo,'m2-5-pilot-deployment-currentness')
    }finally{
      await finish(testInfo,runtime)
    }
  })
})
