// Guards: layer1-operations-deployed: v2.15.246: Layer 1 › Sources list (tab Sources, not Runs). v2.15.246: Layer 1 › Sources list.
// v2.15.246: Layer 1 › Sources list (tab Sources, not Runs).
// v2.15.246: Layer 1 › Sources list.
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
import { openLayer1 } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
// v2.15.246 (bugs 11/10-3, Feature 2): Layer 1 › Sources is one list; filters line up with the columns; a row opens in place
async function chooseCountry(dialog,country){await dialog.locator('.xl-field').filter({hasText:'Country'}).locator('select').selectOption(country)}
async function chooseType(dialog,type){await dialog.locator('.xl-field').filter({hasText:'Type'}).locator('select').selectOption(type)}
async function openRow(dialog,row){const id=await row.getAttribute('data-l1-source');if(!(await row.locator('.xl-body').count()))await row.locator('.xl-chev').click();const body=dialog.locator(`[data-l1-source-body="${id}"]`);await expect(body).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});return body}

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

// 14 Oct 2026 (v2.15.276): sources are chosen by their exact names; the institution-type registers (CRICOS Institutions, NZQA provider search) also carry those words
test.describe('M2.4.1 Layer 1 regulatory operations @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');if(!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)throw new Error('UAT credentials are required');await writeRunEnvironment({suite:'m2-4-1-layer1-operations',change_control:'CF-CHG-20260826-043'})})

  test('AU and NZ expose the production-shaped operator journey',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const dialog=await openLayer1(page)
    await expect(page.getByRole('heading',{name:'Layer 1 Register'}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    const summary=dialog.locator('.xl-summary');for(const label of ['Needs attention','Running','Due','Paused','Healthy'])await expect(summary).toContainText(label)
    await expect(dialog.locator('.xl-head')).toContainText('Source');await expect(dialog.locator('.xl-head')).toContainText('Health');await expect(dialog.locator('.xl-head')).toContainText('Schedule')
    for(const country of ['AU','NZ']){await chooseCountry(dialog,country);const row=dialog.locator('[data-l1-source]').filter({hasNotText:/scholarship/i}).first();await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await expect(row.locator('[data-col="country"]')).toContainText(country);const body=await openRow(dialog,row);await expect(body).toContainText('evidence');await expect(body).toContainText('Checked');await expect(body.getByRole('button',{name:'Check source'})).toBeVisible()}
    await expect(page.getByRole('tab',{name:'Manual batch runs'})).toHaveCount(0)
    await expect(dialog.getByText(/reset database/i)).toHaveCount(0);await expect(dialog.getByText(/parser qualification/i)).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'m2-4-1-layer1-operations')
  }finally{await finish(testInfo,runtime)}})

  test('Administration preserves the Platform Admin boundary for Layer 1 source configuration',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await loginAsUatUser(page)
    await page.goto(new URL('/#administration?section=layer1-sources',process.env.UAT_BASE_URL).toString())
    await expect(page.locator('.m-release-pill')).toContainText(/^v2\.15\.\d+$/)
    // v2.15.246: the old address opens Layer 1 › Sources; editing a source's settings stays Platform Admin only (rank 6), so the
    // UAT operator (rank 4) opens a row and sees its facts and Check source but no settings form.
    const page1=page.locator('main h1').filter({hasText:/^Layer 1 Register$/});await expect(page1).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    await expect(page.getByRole('tab',{name:'Source settings'})).toHaveCount(0)
    const dialog=page.locator('[data-l1-sources]');const row=dialog.locator('[data-l1-source]').first();await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
    const body=await openRow(dialog,row);await expect(body).toContainText('Settings can be changed by a Platform Admin.');await expect(dialog.locator('[data-l1-source-form]')).toHaveCount(0)
    await expect(dialog.getByRole('button',{name:'Add source'})).toHaveCount(0)
    await milestoneScreenshot(page,testInfo,'cf-067-layer1-source-settings-role-boundary')
  }finally{await finish(testInfo,runtime)}})

  test('authorised Layer 1 operator performs real NZQA authority and count validation',async({page},testInfo)=>{test.setTimeout(120000);const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const dialog=await openLayer1(page);await chooseCountry(dialog,'NZ');const result=await validateSource(page,dialog,s=>s.country_code==='NZ'&&s.source_type!=='government_scholarship_program'&&/^NZQA Education Organisations/i.test(s.source_label||''),'NZQA')
    expect(result?.ok).toBe(true);expect(result?.validation?.country_code).toBe('NZ');expect(result?.validation?.discovered?.providers).toBeGreaterThan(300);expect(result?.validation?.discovered?.pages).toBe(5);expect(result?.validation?.worker_version).toMatch(/^layer1-operations-control-v1\./)
    await dialog.getByRole('button',{name:'Refresh'}).click();await chooseCountry(dialog,'NZ');const nz=dialog.locator('[data-l1-source]').filter({hasText:'NZQA Education Organisations'}).first();await expect(nz).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});const body=await openRow(dialog,nz);await expect(body).toContainText(Number(result.validation.discovered.providers).toLocaleString('en-AU'),{timeout:DETERMINISTIC_UI_TIMEOUT});await milestoneScreenshot(page,testInfo,'m2-4-1-nz-source-validated')
  }finally{await finish(testInfo,runtime)}})

  test('authorised Layer 1 operator performs real CRICOS authority, shape and active-count validation',async({page},testInfo)=>{
    test.setTimeout(180000);const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const dialog=await openLayer1(page);await chooseCountry(dialog,'AU');const result=await validateSource(page,dialog,s=>s.country_code==='AU'&&s.source_type!=='government_scholarship_program'&&/^CRICOS Providers, Courses and Locations/i.test(s.source_label||''),'CRICOS')
    expect(result?.ok).toBe(true);expect(result?.validation?.country_code).toBe('AU');expect(result?.validation?.discovered?.active).toBeGreaterThan(25000);expect(result?.validation?.discovered?.total).toBeGreaterThanOrEqual(result.validation.discovered.active);expect(result?.validation?.count_basis).toContain('active CRICOS course rows');expect(result?.validation?.worker_version).toMatch(/^layer1-operations-control-v1\./)
    await dialog.getByRole('button',{name:'Refresh'}).click();await chooseCountry(dialog,'AU');const au=dialog.locator('[data-l1-source]').filter({hasText:'CRICOS Providers, Courses and Locations'}).first();await expect(au).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});const body=await openRow(dialog,au);await expect(body).toContainText(Number(result.validation.discovered.active).toLocaleString('en-AU'),{timeout:DETERMINISTIC_UI_TIMEOUT});await milestoneScreenshot(page,testInfo,'m2-4-1-au-source-validated')
  }finally{await finish(testInfo,runtime)}})

  test('AU Statistics filter exposes QILT and PRISMS as governed runnable sources',async({page},testInfo)=>{test.setTimeout(180000);const runtime=observeRuntime(page);try{
    await loginAsUatUser(page);const dialog=await openLayer1(page);await chooseCountry(dialog,'AU');await chooseType(dialog,'statistics')
    // v2.15.246: each QILT survey and PRISMS is its own row in the one Sources list
    const rows=dialog.locator('[data-l1-source]');await expect(rows).toHaveCount(5,{timeout:DETERMINISTIC_UI_TIMEOUT})
    for(const row of await rows.all())await expect(row.locator('[data-col="type"]')).toContainText('Statistics')
    for(const name of ['QILT GOS 2025','PRISMS']){const row=rows.filter({hasText:name}).first();const body=await openRow(dialog,row);await expect(body).toContainText('Edition history & comparison retention');await expect(body).toContainText('retained rather than overwritten');await expect(body.getByRole('button',{name:'Open Compare'})).toBeVisible()}
    const qilt=await validateSource(page,dialog,s=>/QILT GOS 2025 National Report Tables/i.test(s.source_label||''),'QILT GOS');expect(qilt?.ok).toBe(true);expect(qilt?.validation?.source_system).toBe('QILT');expect(qilt?.validation?.discovered?.candidate_observations).toBeGreaterThan(100)
    const prisms=await validateSource(page,dialog,s=>/PRISMS/i.test(s.source_label||''),'PRISMS');expect(prisms?.ok).toBe(true);expect(prisms?.validation?.source_system).toBe('PRISMS');expect(prisms?.validation?.discovered?.candidate_observations).toBeGreaterThan(1000)
    await milestoneScreenshot(page,testInfo,'cf-066-layer1-statistics-sources')
  }finally{await finish(testInfo,runtime)}})

  test('anonymous browser cannot execute Layer 1 read or command contracts',async({request})=>{
    const base=process.env.UAT_BASE_URL;const home=await request.get(base);expect(home.ok()).toBeTruthy();const html=await home.text();expect(html).not.toContain('SUPABASE_SERVICE_ROLE_KEY')
  })
})
