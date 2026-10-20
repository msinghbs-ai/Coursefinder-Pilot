// v2.15.246: Layer 1 › Sources list.
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('A21 permanent Layer navigation @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-a21-permanent-layer-navigation',change_control:'CF-CHG-20260830-048'})})

  // v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 AI validation retired; three Layer workspaces remain.
  test('canonical Operations navigation owns the Layer workspaces',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const nav=page.locator('.m-nav')
    for(const label of ['Layer 1 Register','Layer 2/3 Build & enrich','Layer 4 Review'])
      await expect(nav.getByRole('button',{name:label,exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(nav.getByRole('button',{name:'Layer 3 AI validation',exact:true})).toHaveCount(0)
    await expect(page.locator('.l1o-backdrop')).toHaveCount(0)
    await expect(page.locator('.l2o-launcher')).toHaveCount(0)
    await expect(page.locator('.m23-launcher')).toHaveCount(0)
    await expect(page.locator('.l3cred-launcher')).toHaveCount(0)
    await expect(page.locator('.go7-nav-item')).toHaveCount(0)
    await expect(page.locator('html[data-go7-navigation]')).toHaveCount(0)
    await expect(nav.getByText('Data Operations',{exact:true})).toHaveCount(0)
    await expect(nav.getByText('Governance & Platform',{exact:true})).toHaveCount(0)
    await expect(page.locator('.m-alert').filter({hasText:/column "layer" does not exist/i})).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'a21-canonical-layer-navigation')
  }finally{await finish(testInfo,runtime)}})

  test('Layer 1 is embedded and actionable, not a floating dialog',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await clickPrimaryNav(page,'Layer 1 — Operations')
    await expect(page.getByRole('heading',{name:'Layer 1 Register'}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.locator('[data-l1-sources]')).toBeVisible() // v2.15.246: one Sources list
    await expect(page.locator('.l1v2-backdrop')).toHaveCount(0)
    await expect(page.getByRole('button',{name:/Refresh/i}).first()).toBeVisible()
    await milestoneScreenshot(page,testInfo,'a21-layer1-embedded')
  }finally{await finish(testInfo,runtime)}})

  test('Layer 2 opens on Adapters with no operator config knobs',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await clickPrimaryNav(page,'Layer 2 — Enrichment')
    const workspace=page.locator('[data-adapters-workspace]')
    await expect(page.getByRole('heading',{name:'Layer 2/3 Build & enrich',exact:true}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(workspace).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT}) // v2.15.200: the opening tab is Adapters
    await expect(page.locator('.m-sidebar')).toBeVisible()
    await expect(page.getByLabel('Layer 2 Wave 1 Courses')).toHaveCount(0)
    await expect(page.getByLabel('Layer 2 acquisition route')).toHaveCount(0)
    await expect(workspace.getByRole('button',{name:'Start production enrichment',exact:true})).toHaveCount(0)
    await expect(page.getByRole('button',{name:'Close Layer 2'})).toHaveCount(0)
    await expect(page.getByRole('button',{name:/Advanced configuration/i})).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'a21-layer2-embedded')
  }finally{await finish(testInfo,runtime)}})


  // v2.15.252: the old Layer 3 address opens Layer 2 › Adapters; Layer 4 stays its own route.
  test('old Layer 3 address opens Layer 2; Layer 4 is a separate permanent route',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await page.goto('/#layer-3-ai')
    await expect(page).toHaveURL(/#layer-2-discovery$/,{timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByRole('heading',{name:'Layer 2/3 Build & enrich',exact:true}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByRole('heading',{name:'Work by task'})).toHaveCount(0)
    await clickPrimaryNav(page,'Layer 4 — Human Resolution')
    await expect(page.getByRole('heading',{name:'Layer 4 status'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.locator('.m23-shell[role="dialog"]')).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'a21-layer3-retired-layer4-route')
  }finally{await finish(testInfo,runtime)}})
  test('saved Course filters restore without opening or flashing popovers',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await clickPrimaryNav(page,'Courses')
    await expect(page.getByRole('heading',{name:'Course catalogue'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    const key=await page.evaluate(async()=>{const raw=Object.keys(localStorage).find(k=>k.includes('coursefinder:pim:screen-state:v1:')&&k.endsWith(':course'));return raw||null})
    if(key)await page.evaluate(k=>localStorage.setItem(k,JSON.stringify({query:'',filters:{country:'AU'},filterLabels:{country:'Australia'},advanced:true,sort:'course',direction:'asc'})),key)
    await page.reload()
    await expect(page.getByRole('heading',{name:'Course catalogue'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await page.waitForTimeout(900)
    await expect(page.locator('.m-filter-popover')).toHaveCount(0)
    await expect(page.getByLabel('Search country…')).toHaveCount(0)
    const country=page.locator('.m-filter-button').filter({hasText:'Country'}).first()
    await expect(country).toContainText(/Australia|All/)
    await milestoneScreenshot(page,testInfo,'a21-filter-restore-no-popover')
  }finally{await finish(testInfo,runtime)}})

})
