import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, clickPrimaryNav, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder streamlined Data Operations navigation @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'admin-data-operations-navigation-v2',change_control:'CF-CHG-20260826-040'})})

  test('primary sidebar presents one logical operating model',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    const nav=page.locator('.m-nav')
    for(const group of ['Overview','Catalogue','Data Operations','Insights','Quality & Review','Decision Tools','Governance & Platform','Help & Guides'])await expect(nav.getByText(group,{exact:true})).toBeVisible({timeout:45000})
    for(const label of ['Layer 2 — Enrichment','Layer 3 — AI Interpretation','Layer 4 — Human Resolution','Evidence & Provenance','Onboarding'])await expect(nav.getByRole('button',{name:label,exact:true})).toBeVisible()
    await expect(nav.getByRole('button',{name:'Scholarship Selection',exact:true})).toBeVisible()
    await expect(nav.getByRole('button',{name:'Guides & Runbooks',exact:true})).toBeVisible()
    await expect(nav.getByRole('button',{name:'Settings',exact:true})).toHaveCount(0)
    await expect(nav.getByRole('button',{name:'Review Queue',exact:true})).toHaveCount(0)
    await expect(nav.getByText('Data Enrichment',{exact:true})).toHaveCount(0)
    await expect(nav.getByRole('button',{name:'Outcomes (QILT)',exact:true})).toBeVisible()
    await expect(nav.getByRole('button',{name:'Student Flow (PRISMS)',exact:true})).toBeVisible()
    for(const sel of ['.ops-launcher','.l2-launcher','.l2p-launcher','.l2t-launcher','.l2o-launcher','.m23-launcher','.ss-launcher','.l3cred-launcher'])await expect(page.locator(sel)).toBeHidden()
    await milestoneScreenshot(page,testInfo,'admin-data-operations-navigation-v2')
  }finally{await finish(testInfo,runtime)}})

  test('Layer 2 Enrichment opens the governed operations workspace',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await clickPrimaryNav(page,'Layer 2 — Enrichment')
    const ops=page.getByRole('dialog',{name:'Layer 2 Operations'})
    await expect(ops).toBeVisible({timeout:45000})
    await expect(ops.getByRole('heading',{name:'Layer 2 Operations'})).toBeVisible()
    await expect(ops.getByText('Enrichment plan',{exact:true})).toBeVisible()
    await expect(ops.getByText('Provider health',{exact:true})).toBeVisible()
    await expect(ops.getByText('Evidence',{exact:true}).first()).toBeVisible()
    await expect(ops.getByText(/Courses and Scholarships only/i)).toBeVisible()
    await expect(ops.getByText(/QILT|PRISMS/i)).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'layer2-enrichment-primary-navigation')
  }finally{await finish(testInfo,runtime)}})

  test('Layer 3 and Layer 4 open from Data Operations instead of floating launchers',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await clickPrimaryNav(page,'Layer 3 — AI Interpretation')
    let dialog=page.getByRole('dialog',{name:'M2.3 Intelligence'})
    await expect(dialog).toBeVisible({timeout:45000})
    await expect(dialog.getByRole('button',{name:'Layer 3',exact:true})).toHaveClass(/active/)
    await dialog.getByRole('button',{name:'Layer 4',exact:true}).click()
    await expect(dialog.getByText('Terminal human resolution',{exact:true})).toBeVisible()
    await dialog.locator('header button').click()
    await clickPrimaryNav(page,'Layer 4 — Human Resolution')
    dialog=page.getByRole('dialog',{name:'M2.3 Intelligence'})
    await expect(dialog.getByRole('button',{name:'Layer 4',exact:true})).toHaveClass(/active/)
    await milestoneScreenshot(page,testInfo,'layer3-layer4-primary-navigation')
  }finally{await finish(testInfo,runtime)}})

  test('Guides and Runbooks is visible in-product and role oriented',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await clickPrimaryNav(page,'Guides & Runbooks')
    const guide=page.getByRole('dialog',{name:'Guides & Runbooks'})
    await expect(guide).toBeVisible({timeout:45000})
    await expect(guide).toContainText('Layer 1 authoritative/regulatory')
    await expect(guide).toContainText('Platform Admin')
    await expect(guide).toContainText('Pipeline Operator')
    await expect(guide).toContainText('Curator / Reviewer')
    await expect(guide).toContainText('Data Operations Admin Guide v1.1')
    await milestoneScreenshot(page,testInfo,'guides-runbooks-visible')
  }finally{await finish(testInfo,runtime)}})
})
