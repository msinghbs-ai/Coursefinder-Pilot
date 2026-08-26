import { test, expect } from '@playwright/test'
import {
  attachRuntimeEvidence,
  assertNoServerErrors,
  loginAsUatUser,
  milestoneScreenshot,
  observeRuntime,
  writeRunEnvironment,
} from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder Layer 3 provider credential control @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required for deployed acceptance.')
    await writeRunEnvironment({suite:'deployed-layer3-provider-credential',change_control:'CF-CHG-20260825-038'})
  })

  test('credential UI obeys the Platform Admin boundary and remains write-only when authorised',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await expect(page.locator('#governed-runtime-marker')).toContainText('PIM Admin v2.15.6')
      const launcher=page.getByRole('button',{name:/OpenRouter API Key|Configure OpenRouter API key/i})
      const count=await launcher.count()
      if(count===0){
        await expect(page.getByLabel('API key')).toHaveCount(0)
        const layer3Nav=page.getByRole('button',{name:'Layer 3 — AI Interpretation',exact:true})
        await expect(layer3Nav).toBeVisible({timeout:45_000})
        await layer3Nav.click()
        const dialog=page.getByRole('dialog',{name:'M2.3 Intelligence'})
        const profileCard=dialog.getByRole('article').filter({hasText:'openrouter-free-router-v1'})
        await expect(profileCard.getByText('openrouter-free-router-v1',{exact:true})).toBeVisible()
        await expect(profileCard.getByText('Enabled',{exact:true})).toBeVisible()
        await expect(profileCard).toContainText(/Benchmark Passed/i)
        await milestoneScreenshot(page,testInfo,'layer3-provider-credential-lower-rank-denied')
        return
      }
      await expect(launcher).toBeVisible({timeout:45_000})
      await launcher.click()
      const dialog=page.getByRole('dialog',{name:'Layer 3 provider credential'})
      await expect(dialog).toBeVisible()
      await expect(dialog.getByRole('option',{name:/Openrouter · openrouter-free-router-v1 · nvidia\/nemotron-3-nano-omni-30b-a3b-reasoning:free/i})).toHaveCount(1)
      await expect(dialog.getByLabel('API key')).toHaveAttribute('type','password')
      await expect(dialog).toContainText(/Key value is write-only/i)
      await expect(dialog).toContainText(/Saving or verifying never unpauses the profile/i)
      await expect(dialog).toContainText(/Benchmark Passed/i)
      await expect(dialog.getByRole('button',{name:'Save credential'})).toBeDisabled()
      await milestoneScreenshot(page,testInfo,'layer3-provider-credential-write-only')
    }finally{await finish(testInfo,runtime)}
  })
})
