import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF 2.15.74 governed course PIM detail contract @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-2-15-74-course-pim-detail-contract',change_control:'PR-46'})})

 test('course_detail supplies only accepted effective family-scoped PIM values through admin_read',async({page},testInfo)=>{const runtime=observeRuntime(page);let detailPayload=null;try{
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
  const today=new Date().toISOString().slice(0,10)
  const singleValueCounts=new Map()
  for(const item of detailPayload.pim_attribute_values){
   expect(item.attribute_id).toBeTruthy()
   expect(item.attribute_code).toBeTruthy()
   expect(item.attribute_name).toBeTruthy()
   expect(item.attribute_data_type).toBeTruthy()
   expect(item.option_labels&&typeof item.option_labels==='object').toBe(true)
   expect(item.review_status).toBe('accepted')
   if(item.valid_from)expect(item.valid_from<=today).toBe(true)
   if(item.valid_to)expect(item.valid_to>=today).toBe(true)
   if(!item.attribute_is_multivalue){
    expect(item.is_preferred).toBe(true)
    const key=`${item.attribute_id}:${item.locale??''}:${item.channel_code??''}`
    singleValueCounts.set(key,(singleValueCounts.get(key)||0)+1)
   }
  }
  for(const count of singleValueCounts.values())expect(count).toBe(1)
  // 001952K has a retained accepted course_description value, but that attribute is not a member of its assigned Course family.
  // The governed dynamic payload must therefore exclude it rather than treating a missing family association as visible.
  expect(detailPayload.pim_attribute_values.some(x=>x.attribute_code==='course_description')).toBe(false)
  const dynamicLabels=(await page.locator('[data-pim-dynamic-fields] .cf-field-label span').allTextContents()).map(x=>x.trim())
  expect(dynamicLabels).not.toContain('Course Description')
 }finally{await finish(testInfo,runtime)}})
})
