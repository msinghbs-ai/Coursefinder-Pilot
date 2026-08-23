import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder deployed Layer 2 platform acceptance @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'deployed-layer2-platform',change_control:'CF-CHG-20260823-029'})})

  test('Layer 2 console exposes materially different governed acquisition profiles and filters',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      const launcher=page.getByRole('button',{name:/Layer 2 Config/i})
      await expect(launcher).toBeVisible({timeout:45000})
      await launcher.click()
      await expect(page.getByRole('heading',{name:'Enrichment Source Configuration'})).toBeVisible()
      await expect(page.getByText('Configuration is separate from execution.')).toBeVisible()
      await expect(page.getByText(/Course Detail/i).first()).toBeVisible()
      await expect(page.getByText(/Xlsx Feed/i).first()).toBeVisible()
      await expect(page.getByText(/Search Endpoint/i).first()).toBeVisible()
      await expect(page.getByText(/Document/i).first()).toBeVisible()
      await page.getByLabel('Acquisition method filter').selectOption('xlsx_feed')
      expect(await page.locator('.l2-table tbody tr').count()).toBeGreaterThanOrEqual(1)
      await expect(page.getByText(/Prisms/i).first()).toBeVisible()
      await page.getByLabel('Acquisition method filter').selectOption('')
      await milestoneScreenshot(page,testInfo,'layer2-profile-list')
    }finally{await finish(testInfo,runtime)}
  })

  test('profile detail shows safe versioned configuration, diff, traceability and governed editor',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await page.getByRole('button',{name:/Layer 2 Config/i}).click()
      const row=page.locator('.l2-table tbody tr').first()
      await expect(row).toBeVisible({timeout:45000})
      await row.click()
      const drawer=page.locator('aside.l2-drawer')
      await expect(drawer).toBeVisible()
      await expect(drawer.getByText('Governed non-secret configuration')).toBeVisible()
      await expect(drawer.getByText('Changes from previous version')).toBeVisible()
      await expect(drawer.getByText('Configuration history')).toBeVisible()
      await expect(drawer.getByText('Traceability')).toBeVisible()
      await expect(drawer.getByText(/Evidence Required/i)).toBeVisible()
      await expect(drawer.getByText(/Content Change Policy/i)).toBeVisible()
      const configText=await drawer.locator('.l2-config').first().innerText()
      expect(configText).not.toMatch(/(^|\n)(password|token|api key|client secret|authorization|cookie)(\n|$)/i)
      const createVersion=drawer.getByRole('button',{name:'Create new version'})
      if(await createVersion.count()){
        await createVersion.click()
        await expect(drawer.getByLabel('Layer 2 configuration JSON')).toBeVisible()
        await expect(drawer.getByRole('button',{name:'Validate & create version'})).toBeVisible()
        await drawer.getByRole('button',{name:'Cancel'}).click()
      }
      await milestoneScreenshot(page,testInfo,'layer2-profile-detail')
    }finally{await finish(testInfo,runtime)}
  })
})
