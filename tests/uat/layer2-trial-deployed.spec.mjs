import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
async function openTrials(page){const nav=page.locator('.m-nav');await expect(nav.getByText('Data Acquisition',{exact:true})).toBeVisible({timeout:45000});await nav.getByRole('button',{name:'Acquisition Trials',exact:true}).click();await expect(page.getByRole('heading',{name:'Acquisition & Course Completeness Trials'})).toBeVisible({timeout:45000})}

test.describe('CourseFinder deployed Layer 2 completeness trial acceptance @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'deployed-layer2-trials',change_control:'CF-CHG-20260823-029'})})

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
      await milestoneScreenshot(page,testInfo,'layer2-au-completeness-cohort')
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
      await milestoneScreenshot(page,testInfo,'layer2-context-completeness-boundary')
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
      expect((await page.locator('body').innerText())).not.toMatch(/sb_secret_|service_role|SUPABASE_SERVICE_ROLE_KEY/i)
      await milestoneScreenshot(page,testInfo,'layer2-trial-provider-selector')
    }finally{await finish(testInfo,runtime)}
  })
})
