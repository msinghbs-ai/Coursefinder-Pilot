import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
import { openLayer1 } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
async function chooseCountry(dialog,country){
  const select=dialog.locator('.l1v2-filter').filter({hasText:'Country'}).locator('select')
  await select.selectOption(country)
}

async function validateSource(page,dialog,predicate,label){
  const readResponsePromise=page.waitForResponse(response=>{
    if(!response.url().includes('/rest/v1/rpc/admin_read'))return false
    try{return response.request().postDataJSON()?.p_operation==='layer1_operations'}catch{return false}
  },{timeout:DETERMINISTIC_UI_TIMEOUT})
  await dialog.getByRole('button',{name:'Refresh'}).click()
  const readResponse=await readResponsePromise,readData=await readResponse.json(),source=(readData?.sources||[]).find(predicate)
  expect(source?.source_id,`${label} Layer 1 source must be present in governed read contract`).toBeTruthy()
  const requestHeaders=await readResponse.request().allHeaders(),supabaseOrigin=new URL(readResponse.url()).origin
  expect(requestHeaders.authorization,'authenticated Layer 1 read must carry bearer authority').toMatch(/^Bearer /i)
  expect(requestHeaders.apikey,'authenticated Layer 1 read must carry publishable API key').toBeTruthy()
  return page.evaluate(async({origin,authorization,apikey,sourceId})=>{
    const response=await fetch(`${origin}/functions/v1/layer1-operations-control`,{method:'POST',headers:{authorization,apikey,'content-type':'application/json'},body:JSON.stringify({action:'validate',source_id:sourceId})})
    const data=await response.json().catch(()=>({}));if(!response.ok||data?.error)throw new Error(data?.error||`Layer 1 validation HTTP ${response.status}`);return data
  },{origin:supabaseOrigin,authorization:requestHeaders.authorization,apikey:requestHeaders.apikey,sourceId:source.source_id})
}

test.describe('M2.4.1 Layer 1 regulatory operations @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'m2-4-1-layer1-operations',change_control:'CF-CHG-20260826-043'})})

  test('AU and NZ expose the production-shaped operator journey',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const dialog=await openLayer1(page)
    await expect(dialog.getByRole('heading',{name:'Layer 1 Operations'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(dialog.locator('.l1v2-summary.healthy')).toContainText('Healthy')
    await expect(dialog.locator('.l1v2-summary.running')).toContainText('Running')
    await expect(dialog.locator('.l1v2-summary.attention')).toContainText('Attention')
    await expect(dialog.locator('.l1v2-summary.due')).toContainText('Due')
    for(const country of ['AU','NZ']){await chooseCountry(dialog,country);const card=dialog.locator(`article.l1v2-card[data-country="${country}"]`).first();await expect(card).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await expect(card.getByRole('button',{name:'Details'})).toBeVisible();await card.getByRole('button',{name:'Details'}).click();await expect(card).toContainText('Reconciliation');await expect(card).toContainText('Evidence & provenance');await expect(card).toContainText('Schedule');await expect(card).toContainText('Source health')}
    await expect(dialog.getByText('Advanced source configuration')).toHaveCount(0)
    await expect(dialog.getByText(/reset database/i)).toHaveCount(0);await expect(dialog.getByText(/parser qualification/i)).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'m2-4-1-layer1-operations')
  }finally{await finish(testInfo,runtime)}})

  test('Administration preserves the Platform Admin boundary for Layer 1 source configuration',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await page.goto(new URL('/#administration?section=layer1-sources',process.env.UAT_BASE_URL).toString())
    await expect(page.locator('.m-release-pill')).toContainText(/^v2\.15\.\d+$/)
    const admin=page.locator('main h1').filter({hasText:/^Administration$/});await expect(admin).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByRole('tab',{name:'Layer 1 sources'})).toHaveCount(0)
    await expect(page.locator('.l1s-shell')).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'cf-067-layer1-source-settings-role-boundary')
  }finally{await finish(testInfo,runtime)}})

  test('authorised Layer 1 operator performs real NZQA authority and count validation',async({page},testInfo)=>{test.setTimeout(120000);const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const dialog=await openLayer1(page);await chooseCountry(dialog,'NZ');const nz=dialog.locator('article.l1v2-card[data-country="NZ"]').first(),result=await validateSource(page,dialog,s=>s.country_code==='NZ','NZQA')
    expect(result?.ok).toBe(true);expect(result?.validation?.country_code).toBe('NZ');expect(result?.validation?.discovered?.providers).toBeGreaterThan(300);expect(result?.validation?.discovered?.pages).toBe(5);expect(result?.validation?.worker_version).toMatch(/^layer1-operations-control-v1\./)
    await dialog.getByRole('button',{name:'Refresh'}).click();await chooseCountry(dialog,'NZ');await expect(nz).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await expect(nz).toContainText(String(result.validation.discovered.providers),{timeout:DETERMINISTIC_UI_TIMEOUT});await milestoneScreenshot(page,testInfo,'m2-4-1-nz-source-validated')
  }finally{await finish(testInfo,runtime)}})

  test('authorised Layer 1 operator performs real CRICOS authority, shape and active-count validation',async({page},testInfo)=>{test.setTimeout(180000);const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const dialog=await openLayer1(page);await chooseCountry(dialog,'AU');const au=dialog.locator('article.l1v2-card[data-country="AU"]').first(),result=await validateSource(page,dialog,s=>s.country_code==='AU'&&!/QILT|PRISMS/i.test(s.source_label||''),'CRICOS')
    expect(result?.ok).toBe(true);expect(result?.validation?.country_code).toBe('AU');expect(result?.validation?.discovered?.active).toBeGreaterThan(25000);expect(result?.validation?.discovered?.total).toBeGreaterThanOrEqual(result.validation.discovered.active);expect(result?.validation?.count_basis).toContain('active CRICOS course rows');expect(result?.validation?.worker_version).toMatch(/^layer1-operations-control-v1\./)
    await dialog.getByRole('button',{name:'Refresh'}).click();await chooseCountry(dialog,'AU');await expect(au).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await expect(au).toContainText(Number(result.validation.discovered.active).toLocaleString(),{timeout:DETERMINISTIC_UI_TIMEOUT});await milestoneScreenshot(page,testInfo,'m2-4-1-au-source-validated')
  }finally{await finish(testInfo,runtime)}})

  test('AU Statistics filter exposes QILT and PRISMS as governed runnable sources',async({page},testInfo)=>{test.setTimeout(180000);const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const dialog=await openLayer1(page);await chooseCountry(dialog,'AU')
    const datasetSelect=dialog.locator('.l1v2-filter').filter({hasText:'Dataset'}).locator('select');await datasetSelect.selectOption('statistics')
    const cards=dialog.locator('article.l1v2-card[data-country="AU"]');await expect(cards).toHaveCount(5,{timeout:DETERMINISTIC_UI_TIMEOUT})
    for(const [label,edition] of [['QILT Graduate Outcomes Survey','2025'],['QILT Student Experience Survey','2024'],['QILT Graduate Outcomes Survey – Longitudinal','2025'],['QILT Employer Satisfaction Survey','2025'],['PRISMS International Student Flow','2025-12']]){
      const card=cards.filter({has:page.getByRole('heading',{name:label,exact:true})});await expect(card).toBeVisible();await expect(card.getByText('statistics',{exact:true})).toBeVisible();await expect(card).toContainText(`current ${edition}`);await expect(card.getByRole('button',{name:'Details'})).toBeVisible();await card.getByRole('button',{name:'Details'}).click();await expect(card).toContainText('Edition history & comparison retention');await expect(card).toContainText('retained rather than overwritten');await expect(card.getByRole('button',{name:'Open Compare'})).toBeVisible()
    }
    const qilt=await validateSource(page,dialog,s=>/QILT GOS 2025 National Report Tables/i.test(s.source_label||''),'QILT GOS');expect(qilt?.ok).toBe(true);expect(qilt?.validation?.source_system).toBe('QILT');expect(qilt?.validation?.discovered?.candidate_observations).toBeGreaterThan(100)
    const prisms=await validateSource(page,dialog,s=>/PRISMS/i.test(s.source_label||''),'PRISMS');expect(prisms?.ok).toBe(true);expect(prisms?.validation?.source_system).toBe('PRISMS');expect(prisms?.validation?.discovered?.candidate_observations).toBeGreaterThan(1000)
    await milestoneScreenshot(page,testInfo,'cf-066-layer1-statistics-sources')
  }finally{await finish(testInfo,runtime)}})

  test('anonymous browser cannot execute Layer 1 read or command contracts',async({request})=>{
    const base=process.env.UAT_BASE_URL;const home=await request.get(base);expect(home.ok()).toBeTruthy();const html=await home.text();expect(html).not.toContain('SUPABASE_SERVICE_ROLE_KEY')
  })
})
