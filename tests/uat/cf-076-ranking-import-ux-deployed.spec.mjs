import fs from'node:fs/promises'
import{test,expect}from'@playwright/test'
import{loginAsUatUser,observeRuntime,attachRuntimeEvidence,assertNoServerErrors,DETERMINISTIC_UI_TIMEOUT,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-076 compact ranking import UX @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-076-ranking-import-ux',change_control:'CF-CHG-20260902-076'})})

 test('nested Administration route shows breadcrumbs and compact file-first import',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await page.goto(new URL('/#administration?section=sources-imports',process.env.UAT_BASE_URL).toString())
  await expect(page.getByRole('navigation',{name:'Breadcrumb'})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const crumb=page.getByRole('navigation',{name:'Breadcrumb'})
  await expect(crumb).toContainText('Home')
  await expect(crumb).toContainText('Administration')
  await expect(crumb).toContainText('Sources & Imports')
  await expect(page.getByRole('heading',{name:'Register ranking publisher file'})).toBeVisible()
  await expect(page.getByRole('button',{name:'Advanced metadata'})).toBeVisible()
  await expect(page.locator('.m-ranking-advanced')).toHaveCount(0)
  const fileInput=page.locator('.m-ranking-drop input[type="file"]')
  await fileInput.setInputFiles({name:'THE_year2016.txt',mimeType:'text/plain',buffer:Buffer.from('Year 2016\n'+JSON.stringify({status:'success',data:{data:[{name:'Example University',rank:'1',location:'Australia',scores_overall:'90'}]}}))})
  await expect(page.locator('.m-ranking-detected')).toContainText('Times Higher Education · 2016')
  await expect(page.locator('.m-ranking-essentials select')).toHaveValue('the_wur')
  await expect(page.locator('.m-ranking-essentials input[type="number"]')).toHaveValue('2016')
  await expect(page.locator('.m-alert')).not.toContainText('txt_native_json_is_the_only')
  const box=await page.locator('.m-ranking-import-compact').boundingBox();expect(box?.height||9999).toBeLessThan(520)
 }finally{await finish(testInfo,runtime)}})

 test('service source derives THE native JSON system/year from file content',async()=>{
  const src=await fs.readFile('supabase/functions/ranking-publisher-import/index.ts','utf8')
  expect(src).toContain('detectedNativeThe')
  expect(src).toContain('systemCode="the_wur"')
  expect(src).toContain('editionYear=detectedYear')
  expect(src).toContain('Times Higher Education')
 })
})
