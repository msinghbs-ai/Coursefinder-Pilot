import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF 2.15.74 governed course PIM detail contract @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-2-15-74-course-pim-detail-contract',change_control:'PR-46'})})

 test('course_detail supplies only currently effective display-safe PIM values through admin_read',async({page},testInfo)=>{const runtime=observeRuntime(page);let detailPayload=null;try{
  page.on('response',async response=>{
   try{
    if(!response.url().includes('/rest/v1/rpc/admin_read')||response.request().method()!=='POST')return
    const requestBody=response.request().postDataJSON()
    if(requestBody?.p_operation!=='course_detail')return
    detailPayload=await response.json()
   }catch{}
  })
  await loginAsUatUser(page)
  await page.evaluate(()=>{location.hash='#courses'})
  await expect(page.locator('.m-title-wrap h1')).toHaveText('Courses',{timeout:DETERMINISTIC_UI_TIMEOUT})
  const search=page.locator('.m-searchbox input')
  await search.fill('001952K')
  const row=page.locator('.m-table tbody tr').filter({hasText:'001952K'}).first()
  await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await row.click()
  await expect(page.getByRole('complementary',{name:'Course detail',exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect.poll(()=>detailPayload?.pim_family_id||null,{timeout:DETERMINISTIC_UI_TIMEOUT}).not.toBeNull()
  expect(detailPayload?.pim_family_name).toBeTruthy()
  expect(Array.isArray(detailPayload?.pim_attribute_values)).toBe(true)
  expect(detailPayload.pim_attribute_values.length).toBeGreaterThan(0)
  const value=detailPayload.pim_attribute_values[0]
  expect(value.attribute_id).toBeTruthy()
  expect(value.attribute_code).toBeTruthy()
  expect(value.attribute_name).toBeTruthy()
  expect(value.attribute_data_type).toBeTruthy()
  expect(value.option_labels&&typeof value.option_labels==='object').toBe(true)
  const today=new Date().toISOString().slice(0,10)
  const singleValueCounts=new Map()
  for(const item of detailPayload.pim_attribute_values){
   if(item.valid_from)expect(item.valid_from<=today).toBe(true)
   if(item.valid_to)expect(item.valid_to>=today).toBe(true)
   if(!item.attribute_is_multivalue){
    expect(item.is_preferred).toBe(true)
    const key=String(item.attribute_id)
    singleValueCounts.set(key,(singleValueCounts.get(key)||0)+1)
   }
  }
  for(const count of singleValueCounts.values())expect(count).toBe(1)
  const coreDescription=detailPayload.pim_attribute_values.find(x=>x.attribute_code==='course_description')
  expect(coreDescription).toBeTruthy()
  const dynamicLabels=page.locator('[data-pim-dynamic-fields] .cf-field-label span')
  await expect(dynamicLabels.filter({hasText:coreDescription.attribute_name})).toHaveCount(0)
 }finally{await finish(testInfo,runtime)}})
})
