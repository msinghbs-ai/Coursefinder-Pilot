import { test, expect } from '@playwright/test'
import { UI_VERSION } from '../../src/release-manifest.js' // pill shows the current release, not a pinned one
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-073 Administration Acquisition route regression @deployed',()=>{
  test.beforeAll(async()=>{
    if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required')
    if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required')
    await writeRunEnvironment({suite:'cf-073-administration-acquisition-route-v1',change_control:'CF-CHG-20260902-073'})
  })

  test('direct Acquisition route renders and browser Back recovers without blank Admin',async({page},testInfo)=>{
    const runtime=observeRuntime(page),pageErrors=[]
    page.on('pageerror',error=>pageErrors.push(error.message))
    try{
      await loginAsUatUser(page)
      await page.goto(new URL('/#administration?section=layer2-providers',process.env.UAT_BASE_URL).toString())

      await expect(page.locator('.m-shell')).toBeVisible({timeout:45000})
      await expect(page.locator('.l2p-shell')).toBeVisible({timeout:45000})
      await expect(page.getByRole('heading',{name:'Acquisition providers',exact:true})).toBeVisible()
      await expect(page.locator('.m-workspace-error')).toHaveCount(0)
      await expect(page.locator('.m-release-pill')).toContainText(`v${UI_VERSION}`)
      const rankLabel=(await page.locator('.m-role-pill').textContent())||''
      expect(rankLabel.trim()).not.toBe('')

      // v2.15.107 and v2.15.200: Administration is folded into Scrapers & fetchers, so the old Overview tab no longer exists.
      // The direct address still renders the Acquisition providers screen. Leaving it by the menu and going Back recovers it.
      await page.evaluate(()=>{location.hash='#dashboard'})
      await expect(page.locator('.m-shell')).toBeVisible()
      await page.goBack()
      await expect(page.locator('.m-shell')).toBeVisible({timeout:45000})
      await expect(page.locator('.l2p-shell')).toBeVisible({timeout:45000})
      await expect(page.locator('.m-workspace-error')).toHaveCount(0)
      expect(pageErrors).toEqual([])

      await milestoneScreenshot(page,testInfo,'cf-073-administration-acquisition-back-recovery')
    }finally{await finish(testInfo,runtime)}
  })
})
