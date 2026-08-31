import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
test.describe('A23 quota-aware Layer 2 background execution @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-a23-layer2-background-firecrawl',change_control:'CF-CHG-20260830-048'})})
 test('operator Layer 2 shows effective background policy, not manual qualification knobs',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await page.locator('.m-nav').getByRole('button',{name:'Layer 2 — Enrichment',exact:true}).click()
  const ws=page.getByLabel('Layer 2 Operations');await expect(ws).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(ws.getByRole('button',{name:'Start background enrichment',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(page.getByLabel('Layer 2 Wave 1 Courses')).toHaveCount(0);await expect(page.getByLabel('Layer 2 acquisition route')).toHaveCount(0)
  await expect(ws.getByText('Firecrawl direct',{exact:true})).toBeVisible()
  await expect(ws.getByText(/Qualification Providers \/ batch/i)).toBeVisible()
  await expect(ws.getByText(/Production Course wave/i)).toBeVisible()
  await expect(ws).toContainText(/identity check|identity samples/i)
  await milestoneScreenshot(page,testInfo,'a23-layer2-background-policy')
 }finally{await finish(testInfo,runtime)}})

 test('Administration owns editable Layer 2 policy and Firecrawl quota state',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await page.locator('.m-nav').getByRole('button',{name:'Administration',exact:true}).click()
  await expect(page.getByRole('heading',{name:'Layer 2 execution policy'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(page.getByLabel('Layer 2 qualification Providers per batch')).toBeVisible()
  await expect(page.getByLabel('Layer 2 qualification samples per Provider')).toBeVisible()
  await expect(page.getByLabel('Layer 2 production target wave')).toBeVisible()
  await expect(page.getByLabel('Layer 2 production maximum wave')).toBeVisible()
  await expect(page.getByLabel('Layer 2 production route mode')).toHaveValue('scraper_first')
  await expect(page.getByText('Firecrawl monthly limit')).toBeVisible()
  await expect(page.getByRole('button',{name:'Save Layer 2 policy'})).toBeVisible()
  await milestoneScreenshot(page,testInfo,'a23-admin-layer2-policy')
 }finally{await finish(testInfo,runtime)}})
})