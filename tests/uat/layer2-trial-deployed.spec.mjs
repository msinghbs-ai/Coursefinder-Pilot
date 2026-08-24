import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
async function openTrials(page){
  const nav=page.locator('.m-nav')
  await expect(nav.getByText('Data Enrichment',{exact:true})).toBeVisible({timeout:45000})
  await nav.getByRole('button',{name:'Layer 2 Operations',exact:true}).click()
  const ops=page.getByRole('dialog',{name:'Layer 2 Operations'})
  await expect(ops).toBeVisible({timeout:45000})
  await ops.getByRole('button',{name:/Run bounded trial/i}).click()
  await expect(page.getByRole('heading',{name:'Acquisition & Course Completeness Trials'})).toBeVisible({timeout:45000})
}

test.describe('CourseFinder deployed Layer 2 completeness trial acceptance @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'deployed-layer2-trials-v1.4',change_control:'CF-CHG-20260823-029'})})

  test('AU RMIT and UQ learning cohorts expose 10 Courses with controls and gaps',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await openTrials(page)
      await expect(page.getByText('RMIT University (RMIT)',{exact:true}).first()).toBeVisible()
      await expect(page.getByText('The University of Queensland',{exact:true}).first()).toBeVisible()
      const cohort=page.locator('.l2t-trials button').filter({hasText:'RMIT University (RMIT)'}).first()
      await cohort.click()
      await expect(page.locator('.l2t-summary')).toContainText('10')
      await expect(page.locator('.l2t-summary')).toContainText('2 / 8')
      await expect(page.locator('.l2t-table-wrap tbody tr')).toHaveCount(10)
      await expect(page.getByText(/control known coverage/i).first()).toBeVisible()
      await expect(page.getByText(/gap learning sample/i).first()).toBeVisible()
      await milestoneScreenshot(page,testInfo,'layer2-au-completeness-cohort-v1-4')
    }finally{await finish(testInfo,runtime)}
  })

  test('trial view preserves factual versus contextual completeness semantics',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await openTrials(page)
      const first=page.locator('.l2t-table-wrap tbody tr').first()
      await expect(first).toContainText(/QILT/i)
      await expect(first).toContainText(/PRISMS provider/i)
      await expect(first).toContainText(/state/i)
      await expect(page.getByText(/Trial results are candidates and measurements, not canonical writes/i)).toBeVisible()
      await expect(page.getByText(/Layer 3 only when needed.*Layer 4 only when automation is exhausted/i)).toBeVisible()
      await milestoneScreenshot(page,testInfo,'layer2-context-completeness-boundary-v1-4')
    }finally{await finish(testInfo,runtime)}
  })

  test('enrichment source selector contains only Course Layer 2 targets while QILT/PRISMS remain context',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await openTrials(page)
      await expect(page.getByText('Enrichment source',{exact:true}).first()).toBeVisible({timeout:15000})
      const sourceSelector=page.locator('.l2t-controls select').first()
      const sourceOptions=(await sourceSelector.locator('option').allTextContents()).join(' ')
      expect(sourceOptions).toMatch(/Australia · Courses · RMIT University/)
      expect(sourceOptions).toMatch(/Australia · Courses · The University of Queensland/)
      expect(sourceOptions).toMatch(/Federation/i)
      expect(sourceOptions).not.toMatch(/QILT|PRISMS/i)
      await milestoneScreenshot(page,testInfo,'layer2-enrichment-source-selector-v1-4')
    }finally{await finish(testInfo,runtime)}
  })

  test('provider selector shows configured acquisition catalogue without exposing secrets',async({page},testInfo)=>{
    const runtime=observeRuntime(page)
    try{
      await loginAsUatUser(page)
      await openTrials(page)
      const selector=page.locator('.l2t-controls select').nth(1)
      await expect(selector).toBeVisible()
      const options=await selector.locator('option').allTextContents()
      expect(options.join(' ')).toMatch(/Direct HTTP/)
      expect(options.join(' ')).toMatch(/Scrape\.do/)
      expect(options.join(' ')).toMatch(/Firecrawl/)
      expect(options.join(' ')).toMatch(/ZenRows/)
      expect((await page.locator('body').innerText())).not.toMatch(/sb_secret_|service_role|SUPABASE_SERVICE_ROLE_KEY/i)
      await milestoneScreenshot(page,testInfo,'layer2-trial-provider-selector-v1-4')
    }finally{await finish(testInfo,runtime)}
  })
})
