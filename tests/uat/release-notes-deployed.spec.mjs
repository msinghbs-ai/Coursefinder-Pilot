import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
test.describe('CourseFinder PIM Admin v2.15.14 release notes @deployed',()=>{
 test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required for deployed acceptance.');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required for deployed acceptance.');await writeRunEnvironment({suite:'deployed-pim-v2.15.14-release-notes',change_control:'CF-CHG-20260830-048'})})
 test('top-right version opens maintained release history and closes accessibly',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await expect(page.locator('#governed-runtime-marker')).toHaveCount(0)
  const version=page.locator('.m-release-pill')
  await expect(version).toContainText('v2.15.14')
  await expect(page.locator('body')).not.toContainText(/Pipeline Ops v1\.0 · Evidence v1\.0 · Data Quality v1\.0 · Access Admin v1\.0/)
  await expect(version).toHaveAttribute('role','button')
  await expect(version).toHaveAttribute('aria-haspopup','dialog')
  await version.click()
  const dialog=page.getByRole('dialog',{name:'Release notes'})
  await expect(dialog).toBeVisible()
  await expect(dialog.locator('[data-release-version="2.15.14"]')).toContainText('Production operations and Administration hardening')
  await expect(dialog.locator('[data-release-version="2.15.11"]')).toContainText('Layer 3 AI operations maturity')
  await expect(dialog.locator('[data-release-version="2.15.6"]')).toContainText('Streamlined Data Operations navigation')
  await expect(dialog).toContainText('Evidence')
  await milestoneScreenshot(page,testInfo,'pim-v2-15-14-release-notes')
  await page.keyboard.press('Escape')
  await expect(dialog).toBeHidden()
  await expect(version).toBeFocused()
 }finally{await finish(testInfo,runtime)}})
})
