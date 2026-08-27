import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
function op(req){if(!req.url().includes('/rest/v1/rpc/admin_read'))return null;try{return req.postDataJSON()}catch{return null}}
async function route(page,slug,heading){await page.evaluate(x=>{location.hash='#'+x},slug);await expect(page.locator('.m-title-wrap h1')).toContainText(heading)}
async function pagedOpen(page,container,kind){
  const responsePromise=page.waitForResponse(r=>{const b=op(r.request());return b?.p_operation==='admin_filter_option_page'&&b?.p_args?.kind===kind},{timeout:12000})
  await container.locator('button').first().click()
  const response=await responsePromise
  expect(response.status()).toBe(200)
  const body=await response.json()
  expect(body.limit).toBe(10)
  expect(Array.isArray(body.items)).toBeTruthy()
  expect(body.items.length).toBeLessThanOrEqual(10)
  return body
}

test.describe('A10 paged filters and tablet focus @deployed',()=>{
  test.beforeAll(async()=>{if(!process.env.UAT_BASE_URL)throw new Error('UAT_BASE_URL is required');await writeRunEnvironment({suite:'a10-paged-filters-v1.0',change_control:'CF-CHG-20260827-044'})})
  test.beforeEach(async({page})=>{
    await page.addInitScript(()=>{const native=window.matchMedia.bind(window);window.matchMedia=q=>q==='(pointer:fine)'?{matches:false,media:q,onchange:null,addListener(){},removeListener(){},addEventListener(){},removeEventListener(){},dispatchEvent(){return false}}:native(q)})
    await loginAsUatUser(page)
  })

  test('QILT Provider and Metric use 10-item server paging without coarse-pointer autofocus',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await route(page,'outcomes-qilt','Outcomes')
    const provider=page.locator('.m-filter-select').filter({hasText:'Provider'}).first()
    await expect(provider).toBeVisible()
    const p=await pagedOpen(page,provider,'qilt_provider')
    expect(Number(p.total||0)).toBeGreaterThan(10)
    const pSearch=provider.locator('.m-filter-search input')
    await expect(pSearch).toBeVisible();await expect(pSearch).not.toBeFocused()
    await provider.locator('button').first().click()

    const metric=page.locator('.m-filter-select').filter({hasText:'Metric'}).first()
    await expect(metric).toBeVisible()
    const m=await pagedOpen(page,metric,'qilt_metric')
    expect(Number(m.total||0)).toBeGreaterThan(10)
    await expect(metric.locator('.m-filter-search input')).not.toBeFocused()
    await milestoneScreenshot(page,testInfo,'a10-qilt-paged-filters')
  }finally{await finish(testInfo,runtime)}})

  test('PRISMS Study area uses 10-item server paging without coarse-pointer autofocus',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await route(page,'student-flow-prisms','Student Flow')
    const study=page.locator('.m-filter-select').filter({hasText:'Study area'}).first()
    await expect(study).toBeVisible()
    const body=await pagedOpen(page,study,'prisms_study_area')
    expect(Number(body.total||0)).toBeGreaterThan(10)
    await expect(study.locator('.m-filter-search input')).not.toBeFocused()
    await milestoneScreenshot(page,testInfo,'a10-prisms-paged-filter')
  }finally{await finish(testInfo,runtime)}})

  test('Evidence Source uses country-aware 10-item server paging and local filters do not autofocus',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
    await route(page,'evidence','Evidence')
    const source=page.locator('.evidence-select').filter({hasText:'Source'}).first()
    await expect(source).toBeVisible()
    const body=await pagedOpen(page,source,'evidence_source')
    expect(Number(body.total||0)).toBeGreaterThan(10)
    const sourceSearch=source.locator('input')
    await expect(sourceSearch).toBeVisible();await expect(sourceSearch).not.toBeFocused()
    await source.locator('button').first().click()

    const evidenceType=page.locator('.evidence-select').filter({hasText:'Evidence type'}).first()
    await evidenceType.locator('button').first().click()
    await expect(evidenceType.locator('input')).not.toBeFocused()
    const optionButtons=evidenceType.locator('.evidence-select-pop > button')
    expect(await optionButtons.count()).toBeLessThanOrEqual(11)
    await milestoneScreenshot(page,testInfo,'a10-evidence-paged-filters')
  }finally{await finish(testInfo,runtime)}})

  test('A10 server contracts are mirrored and large legacy bundles stay empty',async()=>{
    const sql=await fs.readFile('supabase/migrations/20260827232500_a10_platform_paged_filter_options.sql','utf8')
    expect(sql).toContain('admin_filter_option_page')
    expect(sql).toContain("v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,10),1),10)")
    expect(sql).toContain("'sources','[]'::jsonb")
    expect(sql).toContain("'metrics','[]'::jsonb,'providers','[]'::jsonb")
    expect(sql).toContain("'study_areas','[]'::jsonb")

    const mature=await fs.readFile('src/mature-main.jsx','utf8')
    expect(mature).toContain('function AsyncPagedFilterSelect')
    expect(mature).toContain('qilt_provider')
    expect(mature).toContain('qilt_metric')
    expect(mature).toContain('prisms_study_area')

    const evidence=await fs.readFile('src/EvidenceWorkspace.jsx','utf8')
    expect(evidence).toContain('function PagedEvidenceSelect')
    expect(evidence).toContain("kind:'evidence_source'")
    expect(evidence).not.toContain('<input autoFocus')
    expect(evidence).toContain('slice(safePage*10,safePage*10+10)')
  })
})
