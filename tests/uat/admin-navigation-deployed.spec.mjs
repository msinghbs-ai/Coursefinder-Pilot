import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
import { openGuides, openLayer1, openLayer2, openLayer3, openLayer4 } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder streamlined Data Operations navigation @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'admin-data-operations-navigation-v4',change_control:'CF-CHG-20260826-040'})})

  test('primary sidebar presents one logical operating model',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const nav=page.locator('.m-nav')
    for(const group of ['Overview','Catalogue','Data Operations','Insights','Quality & Review','Decision Tools','Governance & Platform','Help & Guides'])await expect(nav.getByText(group,{exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    for(const label of ['Layer 1 — Regulatory','Layer 2 — Enrichment','Layer 3 — AI Interpretation','Layer 4 — Human Resolution','Evidence & Provenance','Jobs & Runs','Onboarding'])await expect(nav.getByRole('button',{name:label,exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(nav.getByRole('button',{name:'Scholarship Selection',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(nav.getByRole('button',{name:'Guides & Runbooks',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(nav.getByRole('button',{name:'Settings',exact:true})).toHaveCount(0)
    await expect(nav.getByRole('button',{name:'Review Queue',exact:true})).toHaveCount(0)
    await expect(nav.getByRole('button',{name:'Layer 2 Operations',exact:true})).toHaveCount(0)
    await expect(nav.getByText('Data Enrichment',{exact:true})).toHaveCount(0)
    await expect(nav.getByRole('button',{name:'Outcomes (QILT)',exact:true})).toBeVisible()
    await expect(nav.getByRole('button',{name:'Student Flow (PRISMS)',exact:true})).toBeVisible()
    await milestoneScreenshot(page,testInfo,'admin-data-operations-navigation-v4')
  }finally{await finish(testInfo,runtime)}})

  test('Layer 1 Regulatory opens as the normal operator journey without Settings',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await openLayer1(page)
    await expect(page.getByRole('button',{name:'Settings',exact:true})).toHaveCount(0)
    await expect(page.getByRole('heading',{name:'Layer 1 — Regulatory'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await milestoneScreenshot(page,testInfo,'layer1-regulatory-primary-navigation')
  }finally{await finish(testInfo,runtime)}})

  test('Layer 2 Enrichment opens the governed operations workspace',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const ops=await openLayer2(page)
    await expect(ops.getByRole('heading',{name:'Layer 2 — Enrichment'})).toBeVisible()
    await expect(ops.getByRole('heading',{name:'Sync Course enrichment'})).toBeVisible()
    await expect(ops.getByRole('heading',{name:'How the single Sync button works'})).toBeVisible()
    await expect(ops.getByText('Evidence',{exact:true}).first()).toBeVisible()
    await expect(ops.getByText(/Layer 1 defines the full catalogue scope/i)).toBeVisible()
    await expect(ops.getByText(/QILT|PRISMS/i)).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'layer2-enrichment-primary-navigation')
  }finally{await finish(testInfo,runtime)}})

  test('Layer 3 and Layer 4 open from accepted Data Operations navigation',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    let dialog=await openLayer3(page)
    await dialog.getByRole('button',{name:'Layer 4',exact:true}).click()
    await expect(dialog.getByText('Terminal human resolution',{exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await dialog.locator('header button').click()
    dialog=await openLayer4(page)
    await expect(dialog.getByRole('button',{name:'Layer 4',exact:true})).toHaveClass(/active/)
    await milestoneScreenshot(page,testInfo,'layer3-layer4-primary-navigation')
  }finally{await finish(testInfo,runtime)}})

  test('Guides and Runbooks is visible in-product and role oriented',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const guide=await openGuides(page)
    await expect(guide).toContainText('Layer 1 authoritative/regulatory')
    await expect(guide).toContainText('Platform Admin')
    await expect(guide).toContainText('Pipeline Operator')
    await expect(guide).toContainText('Curator / Reviewer')
    await expect(guide).toContainText('Data Operations Admin Guide v1.1')
    await milestoneScreenshot(page,testInfo,'guides-runbooks-visible')
  }finally{await finish(testInfo,runtime)}})
})
