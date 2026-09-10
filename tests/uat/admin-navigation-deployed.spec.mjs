import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
import { openLayer1, openLayer2, openLayer3, openLayer4, openLayer2Advanced } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder canonical Administration and Operations navigation @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'admin-canonical-navigation-a20-a28-cf092',change_control:'CF-CHG-20260830-048 / CF-CHG-20260910-092'})})

  test('primary sidebar exposes the governed non-floating information architecture',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const nav=page.locator('.m-nav')
    for(const group of ['Overview','Catalogue','Statistics & Insights','Data Operations','Quality & Review','Administration']){
      await expect(nav.locator('.m-nav-label').filter({hasText:group})).toHaveText(group,{timeout:DETERMINISTIC_UI_TIMEOUT})
    }
    for(const label of ['Dashboard','Providers','Courses','Campuses','Scholarships','Provider Contacts','Statistics & Rankings','Compare','Layer 1 — Operations','Layer 2 — Enrichment','Layer 3 — AI Interpretation','Layer 4 — Human Resolution','Scheduled Tasks','Evidence','Jobs','Completeness','Review Queue','Administration']){
      await expect(nav.getByRole('button',{name:label,exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    }
    for(const obsolete of ['Layer 1 — Regulatory','Layer 1 — Authority','Evidence & Provenance','Jobs & Runs','Scholarship Selection','Guides & Runbooks','Settings','Layer 2 Operations','Refresh & Scheduling']){
      await expect(nav.getByRole('button',{name:obsolete,exact:true})).toHaveCount(0)
    }
    const order=await nav.locator('button').evaluateAll(nodes=>nodes.map(n=>n.textContent?.trim()))
    expect(order.indexOf('Scheduled Tasks')).toBeGreaterThan(-1)
    expect(order.indexOf('Scheduled Tasks')).toBeLessThan(order.indexOf('Evidence'))
    await milestoneScreenshot(page,testInfo,'admin-canonical-navigation')
  }finally{await finish(testInfo,runtime)}})

  test('Layer 1 and Layer 2 open as embedded canonical workspaces',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const l1=await openLayer1(page);await expect(l1.locator('.l1o-backdrop')).toHaveCount(0)
    const l2=await openLayer2(page)
    await expect(l2.getByRole('heading',{name:'Background Course enrichment',exact:true})).toBeVisible()
    await expect(l2.getByRole('button',{name:'Start production enrichment',exact:true})).toBeVisible()
    await expect(l2.getByRole('button',{name:/Advanced configuration/i})).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'layers1-2-canonical')
  }finally{await finish(testInfo,runtime)}})

  test('Layer 3 and Layer 4 are separate permanent routes',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    let ws=await openLayer3(page)
    await expect(ws.getByRole('heading',{name:'Layer 3 status',exact:true})).toBeVisible()
    await expect(ws.getByRole('heading',{name:'Layer 4 status',exact:true})).toHaveCount(0)
    ws=await openLayer4(page)
    await expect(ws.getByRole('heading',{name:'Layer 4 status',exact:true})).toBeVisible()
    await expect(ws.getByRole('heading',{name:'Layer 3 status',exact:true})).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'layers3-4-separate-routes')
  }finally{await finish(testInfo,runtime)}})

  test('Administration is configuration-only and Layer 2 source configuration is centralised',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await clickPrimaryNav(page,'Administration')
    await expect(page.getByRole('heading',{name:'Administration overview',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByRole('tab',{name:'Scheduling',exact:true})).toHaveCount(0)
    await expect(page.getByRole('tab',{name:'Extraction Profiles',exact:true})).toBeVisible()
    await openLayer2Advanced(page)
    await expect(page.getByRole('heading',{name:'Enrichment Source Configuration',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByText('Configuration is separate from execution.')).toBeVisible()
    await milestoneScreenshot(page,testInfo,'layer2-config-central-administration')
  }finally{await finish(testInfo,runtime)}})

  test('Administration subcontext and Scheduled Tasks survive deep-link browser history',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await page.evaluate(()=>{location.hash='#administration?section=layer2-providers'})
    await expect(page).toHaveURL(/#administration\?section=layer2-providers/)
    await expect(page.getByRole('tab',{name:'Scraper Config',exact:true})).toHaveAttribute('aria-selected','true',{timeout:DETERMINISTIC_UI_TIMEOUT})
    await page.reload()
    await expect(page.getByRole('tab',{name:'Scraper Config',exact:true})).toHaveAttribute('aria-selected','true',{timeout:DETERMINISTIC_UI_TIMEOUT})
    await clickPrimaryNav(page,'Scheduled Tasks')
    await expect(page).toHaveURL(/#scheduled-tasks/)
    await expect(page.getByRole('heading',{name:'Scheduled Jobs & Run Control',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await page.goBack()
    await expect(page).toHaveURL(/#administration\?section=layer2-providers/)
    await expect(page.getByRole('tab',{name:'Scraper Config',exact:true})).toHaveAttribute('aria-selected','true')
    await page.goForward()
    await expect(page).toHaveURL(/#scheduled-tasks/)
    await expect(page.getByRole('heading',{name:'Scheduled Jobs & Run Control',exact:true})).toBeVisible()
  }finally{await finish(testInfo,runtime)}})
})
