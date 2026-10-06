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
import { openLayer2, openLayer2Tab, openLayer3 } from './support/navigation.mjs'

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

      // v2.15.200: History is retired; Layer 2 opens on Adapters and the retired pipeline's run panel stays gone.
      const layer2=await openLayer2Tab(page,'Adapters')
      await expect(layer2.locator('[data-adapters-list]')).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(layer2.locator('[data-l2-latest-terminal]')).toHaveCount(0)

      const layer3=await openLayer3(page)
      const queue=layer3.locator('[data-layer3-source-pattern-queue]')
      await expect(queue).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(queue.getByRole('heading',{name:'Course-page pattern requests',exact:true})).toBeVisible()
      await expect(queue).toContainText(/Run by hand, one at a time/i)
      // v2.15.127: the run button appears only while a request is waiting.
      await expect(queue.getByRole('button',{name:'Run source-pattern interpretation',exact:true}).or(queue.getByText('No course-page pattern requests waiting.')).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
      await expect(page.getByRole('button',{name:/Run all source-pattern/i})).toHaveCount(0)

      await milestoneScreenshot(page,testInfo,'m2-5-pilot-deployment-currentness')
    }finally{
      await finish(testInfo,runtime)
    }
  })
})
