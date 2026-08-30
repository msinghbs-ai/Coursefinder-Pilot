import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('A21 permanent Layer navigation @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-a21-permanent-layer-navigation',change_control:'CF-CHG-20260830-048'})})

  test('canonical Operations navigation owns all four Layer workspaces',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const nav=page.locator('.m-nav')
    for(const label of ['Layer 1 — Authority','Layer 2 — Enrichment','Layer 3 — AI Interpretation','Layer 4 — Human Resolution'])
      await expect(nav.getByRole('button',{name:label,exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.locator('.l1o-backdrop')).toHaveCount(0)
    await expect(page.locator('.l2o-launcher')).toHaveCount(0)
    await expect(page.locator('.m23-launcher')).toHaveCount(0)
    await expect(page.locator('.l3cred-launcher')).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'a21-canonical-layer-navigation')
  }finally{await finish(testInfo,runtime)}})

  test('Layer 1 is embedded and actionable, not a floating dialog',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await page.locator('.m-nav').getByRole('button',{name:'Layer 1 — Authority',exact:true}).click()
    await expect(page.getByRole('heading',{name:'Layer 1 — Regulatory'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.locator('.l1o-page')).toBeVisible()
    await expect(page.locator('.l1o-backdrop')).toHaveCount(0)
    await expect(page.getByRole('button',{name:/Refresh/i}).first()).toBeVisible()
    await milestoneScreenshot(page,testInfo,'a21-layer1-embedded')
  }finally{await finish(testInfo,runtime)}})

  test('Layer 2 is embedded with Wave 1 action and no close/config launcher',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await page.locator('.m-nav').getByRole('button',{name:'Layer 2 — Enrichment',exact:true}).click()
    await expect(page.getByRole('heading',{name:'Layer 2 — Enrichment'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByLabel('Layer 2 Wave 1 Courses')).toHaveValue('500')
    await expect(page.getByRole('button',{name:/Run Wave 1|Qualify next wave/})).toBeVisible()
    await expect(page.getByRole('button',{name:'Close Layer 2'})).toHaveCount(0)
    await expect(page.getByRole('button',{name:/Advanced configuration/i})).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'a21-layer2-embedded')
  }finally{await finish(testInfo,runtime)}})

  test('Layer 3 and Layer 4 are separate permanent routes',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const nav=page.locator('.m-nav')
    await nav.getByRole('button',{name:'Layer 3 — AI Interpretation',exact:true}).click()
    await expect(page.getByRole('heading',{name:'Layer 3 status'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByRole('heading',{name:'Layer 4 status'})).toHaveCount(0)
    await nav.getByRole('button',{name:'Layer 4 — Human Resolution',exact:true}).click()
    await expect(page.getByRole('heading',{name:'Layer 4 status'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByRole('heading',{name:'Layer 3 status'})).toHaveCount(0)
    await expect(page.locator('.m23-shell[role="dialog"]')).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'a21-layer3-layer4-separated')
  }finally{await finish(testInfo,runtime)}})
})
