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

  test('Platform Admin can select OpenRouter and sees write-only Vault credential boundary',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      const launcher=page.getByRole('button',{name:/Layer 3 Provider/i})
      await expect(launcher).toBeVisible({timeout:45_000})
      await launcher.click()
      const dialog=page.getByRole('dialog',{name:'Layer 3 provider credential'})
      await expect(dialog).toBeVisible()
      await expect(dialog.getByRole('option',{name:/Openrouter · openrouter-free-router-v1 · openrouter\/free/i})).toHaveCount(1)
      await expect(dialog.getByLabel('API key')).toHaveAttribute('type','password')
      await expect(dialog).toContainText(/Key value is write-only/i)
      await expect(dialog).toContainText(/never unpauses the profile/i)
      await expect(dialog.getByRole('button',{name:'Save credential'})).toBeDisabled()
      await milestoneScreenshot(page,testInfo,'layer3-provider-credential-write-only')
    }finally{await finish(testInfo,runtime)}
  })
})
