import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
import { openLayer1, openLayer2, openLayer3, openLayer4, openLayer2Advanced } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder canonical Administration and Operations navigation @deployed',()=>{
  test.beforeAll(async()=>{await writeRunEnvironment({suite:'admin-canonical-navigation-a20-a28',change_control:'CF-CHG-20260830-048'})})

  test('primary sidebar exposes the governed non-floating information architecture',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const nav=page.locator('.m-nav')
    for(const group of ['Overview','Catalogue','Enrichment & Insights','Data Quality','Operations','Administration']){
      await expect(nav.locator('.m-nav-label').filter({hasText:group})).toHaveText(group,{timeout:DETERMINISTIC_UI_TIMEOUT})
    }
    for(const label of ['Dashboard','Providers','Courses','Campuses','Scholarships','Outcomes (QILT)','Student Flow (PRISMS)','Completeness','Evidence','Review Queue','Layer 1 — Authority','Layer 2 — Enrichment','Layer 3 — AI Interpretation','Layer 4 — Human Resolution','Important Links','Important Dates','Jobs','Administration']){
      await expect(nav.getByRole('button',{name:label,exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    }
    for(const obsolete of ['Layer 1 — Regulatory','Evidence & Provenance','Jobs & Runs','Scholarship Selection','Guides & Runbooks','Settings','Layer 2 Operations']){
      await expect(nav.getByRole('button',{name:obsolete,exact:true})).toHaveCount(0)
    }
    await expect(nav.getByText('Data Operations',{exact:true})).toHaveCount(0)
    await expect(nav.getByText('Governance & Platform',{exact:true})).toHaveCount(0)
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

  test('Administration opens non-empty and Layer 2 source configuration is centralised',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await page.getByRole('button',{name:'Administration',exact:true}).click()
    await expect(page.getByRole('heading',{name:'Administration overview',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByRole('tab',{name:'Layer 2 sources',exact:true})).toBeVisible()
    await openLayer2Advanced(page)
    await expect(page.getByRole('heading',{name:'Enrichment Source Configuration',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByText('Configuration is separate from execution.')).toBeVisible()
    await milestoneScreenshot(page,testInfo,'layer2-config-central-administration')
  }finally{await finish(testInfo,runtime)}})
})
