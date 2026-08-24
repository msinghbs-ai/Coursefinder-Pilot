import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder simplified enrichment navigation @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'admin-layer2-navigation',change_control:'CF-CHG-20260823-030'})})

  test('primary sidebar keeps Layer 2 management intentionally small',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      const nav=page.locator('.m-nav')
      await expect(nav.getByText('Data Enrichment',{exact:true})).toBeVisible({timeout:45000})
      await expect(nav.getByRole('button',{name:'Layer 2 Operations',exact:true})).toBeVisible()
      await expect(nav.getByRole('button',{name:'Evidence',exact:true})).toBeVisible()
      for(const label of ['Pipeline Control','Source Registry','Layer 2 Source Config','Acquisition Providers','Acquisition Trials','Jobs'])await expect(nav.getByRole('button',{name:label,exact:true})).toHaveCount(0)
      await expect(nav.getByText('Quality & Review',{exact:true})).toBeVisible()
      await expect(nav.getByText('Governance & Platform',{exact:true})).toBeVisible()
      for(const sel of ['.ops-launcher','.l2-launcher','.l2p-launcher','.l2t-launcher','.l2o-launcher'])await expect(page.locator(sel)).toBeHidden()
      await milestoneScreenshot(page,testInfo,'admin-layer2-simple-navigation')
    }finally{await finish(testInfo,runtime)}
  })

  test('Layer 2 Operations exposes concise policy, provider and Evidence drill-down',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      const nav=page.locator('.m-nav')
      await nav.getByRole('button',{name:'Layer 2 Operations',exact:true}).click()
      await expect(page.getByRole('heading',{name:'Layer 2 Operations'})).toBeVisible({timeout:45000})
      await expect(page.getByText('Enrichment plan',{exact:true})).toBeVisible()
      await expect(page.getByText('Provider health',{exact:true})).toBeVisible()
      await expect(page.getByText('Evidence',{exact:true}).first()).toBeVisible()
      await expect(page.getByText(/Courses and Scholarships only/i)).toBeVisible()
      await expect(page.getByText(/QILT|PRISMS/i)).toHaveCount(0)
      await expect(page.getByRole('button',{name:/Configure/i})).toBeVisible()
      await expect(page.getByRole('button',{name:/Run bounded trial/i})).toBeVisible()
      await milestoneScreenshot(page,testInfo,'layer2-operations-workspace')
    }finally{await finish(testInfo,runtime)}
  })
})
