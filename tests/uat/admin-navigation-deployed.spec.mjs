import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder acquisition-centred navigation @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'admin-acquisition-navigation',change_control:'CF-CHG-20260823-030'})})

  test('primary sidebar exposes the acquisition lifecycle without floating launchers',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      const nav=page.locator('.m-nav')
      await expect(nav.getByText('Data Acquisition',{exact:true})).toBeVisible({timeout:45000})
      for(const label of ['Pipeline Control','Source Registry','Layer 2 Source Config','Acquisition Providers','Jobs','Evidence'])await expect(nav.getByRole('button',{name:label,exact:true})).toBeVisible()
      await expect(nav.getByText('Quality & Review',{exact:true})).toBeVisible()
      await expect(nav.getByText('Governance & Platform',{exact:true})).toBeVisible()
      await expect(page.locator('.ops-launcher')).toBeHidden()
      await expect(page.locator('.l2-launcher')).toBeHidden()
      await expect(page.locator('.l2p-launcher')).toBeHidden()
      await milestoneScreenshot(page,testInfo,'admin-data-acquisition-navigation')
    }finally{await finish(testInfo,runtime)}
  })

  test('main menu opens governed Pipeline, Layer 2 and Evidence workspaces',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      const nav=page.locator('.m-nav')
      await nav.getByRole('button',{name:'Pipeline Control',exact:true}).click()
      await expect(page.getByRole('heading',{name:'Pipeline Operations'})).toBeVisible()
      await page.getByRole('button',{name:/Close operations console/i}).click()
      await nav.getByRole('button',{name:'Layer 2 Source Config',exact:true}).click()
      await expect(page.getByRole('heading',{name:'Enrichment Source Configuration'})).toBeVisible()
      await page.getByRole('button',{name:'Close',exact:true}).click()
      await nav.getByRole('button',{name:'Acquisition Providers',exact:true}).click()
      await expect(page.getByRole('heading',{name:'Layer 2 Acquisition Providers'})).toBeVisible()
      await page.locator('.l2p-top button').last().click()
      await nav.getByRole('button',{name:'Evidence',exact:true}).click()
      await expect(page.getByRole('heading',{name:/Evidence/i}).first()).toBeVisible({timeout:45000})
      await milestoneScreenshot(page,testInfo,'admin-acquisition-navigation-workspaces')
    }finally{await finish(testInfo,runtime)}
  })
})
