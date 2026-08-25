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

test.describe('CourseFinder PIM Admin v2.15.5 release notes @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required for deployed acceptance.')
    await writeRunEnvironment({suite:'deployed-pim-v2.15.5-release-notes'})
  })

  test('top-right version opens maintained release history and closes accessibly',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await expect(page.locator('#governed-runtime-marker')).toContainText('PIM Admin v2.15.5')
      const version=page.locator('.m-release-pill')
      await expect(version).toContainText('v2.15.5')
      await expect(version).toHaveAttribute('role','button')
      await expect(version).toHaveAttribute('aria-haspopup','dialog')
      await version.click()
      const dialog=page.getByRole('dialog',{name:'Release notes'})
      await expect(dialog).toBeVisible()
      await expect(dialog.locator('[data-release-version="2.15.5"]')).toContainText('Layer 3 provider credential control')
      await expect(dialog.locator('[data-release-version="2.15.4"]')).toContainText('Release notes in the Admin UI')
      await expect(dialog).toContainText('stored encrypted in Supabase Vault')
      await milestoneScreenshot(page,testInfo,'pim-v2-15-5-release-notes')
      await page.keyboard.press('Escape')
      await expect(dialog).toBeHidden()
      await expect(version).toBeFocused()
    }finally{await finish(testInfo,runtime)}
  })
})
