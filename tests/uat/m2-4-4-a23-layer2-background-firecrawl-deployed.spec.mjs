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
  await expect(ws.locator('.l2o-route-chain')).toContainText(/Firecrawl direct/i)
  await expect(ws.getByText(/Qualification Providers \/ batch/i)).toBeVisible()
  await expect(ws.getByText('Production Course wave',{exact:true})).toBeVisible()
  await expect(ws).toContainText(/identity check|identity samples/i)
  await milestoneScreenshot(page,testInfo,'a23-layer2-background-policy')
 }finally{await finish(testInfo,runtime)}})

 test('Administration owns Layer 2 configuration with role-appropriate edit controls',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await page.locator('.m-nav').getByRole('button',{name:'Administration',exact:true}).click()
  await expect(page.locator('.m-title-wrap h1')).toHaveText('Administration',{timeout:DETERMINISTIC_UI_TIMEOUT})
  const sourceCard=page.locator('.m-attention').filter({hasText:'Layer 2 source profiles'}).first()
  const providerCard=page.locator('.m-attention').filter({hasText:'Layer 2 acquisition providers'}).first()
  await expect(sourceCard).toBeVisible();await expect(providerCard).toBeVisible()
  await sourceCard.getByRole('button',{name:'Open',exact:true}).click()
  await expect(page.getByRole('heading',{name:'Enrichment Source Configuration',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(page.getByText('Configuration is separate from execution.')).toBeVisible()
  const policyHeading=page.getByRole('heading',{name:'Layer 2 execution policy',exact:true})
  if(await policyHeading.count()){
    await expect(policyHeading).toBeVisible()
    await expect(page.getByLabel('Layer 2 qualification Providers per batch')).toBeVisible()
    await expect(page.getByLabel('Layer 2 production target wave')).toBeVisible()
    await expect(page.getByLabel('Layer 2 production route mode')).toHaveValue('scraper_first')
    await expect(page.getByText('Firecrawl monthly limit')).toBeVisible()
    await expect(page.getByRole('button',{name:'Save Layer 2 policy'})).toBeVisible()
  }else{
    await expect(page.getByRole('button',{name:'Save Layer 2 policy'})).toHaveCount(0)
  }
  await milestoneScreenshot(page,testInfo,'a23-admin-layer2-configuration')
 }finally{await finish(testInfo,runtime)}})
})