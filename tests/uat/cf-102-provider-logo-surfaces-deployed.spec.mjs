import{test,expect}from'@playwright/test'
import fs from'node:fs'
import{attachRuntimeEvidence,assertNoServerErrors,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment}from'./support/runtime-evidence.mjs'

const RMIT='8e1adb6c-e069-43db-9584-bd054255e702'
const UQ='e55396d2-869a-46ef-9d17-841c7eab1313'
const RMIT_COURSE='415e1105-8b45-4a72-9711-93d9217777ee'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-102 Provider logos across detail, list and comparison @targeted',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-102-provider-logo-surfaces-v2',change_control:'CF-CHG-20260904-102 / CF-CHG-20260905-152'})})

 test('source contract preserves governed signed access, caching and all identity surfaces',async()=>{
   const main=fs.readFileSync('src/mature-main.jsx','utf8')
   const course=fs.readFileSync('src/CourseDetailPolish.jsx','utf8')
   const compare=fs.readFileSync('src/ComparisonWorkspace.jsx','utf8')
   const logo=fs.readFileSync('src/ProviderLogo.jsx','utf8')
   const api=fs.readFileSync('src/lib/supabase.js','utf8')
   const scholarship=fs.readFileSync('src/scholarship-selection-entry.jsx','utf8')

   // Feature contract, deliberately NOT pinned to an old UI version.
   expect(main).toContain("import ProviderLogo,{ProviderBrand}from'./ProviderLogo'")
   expect(main).toContain("ProviderBrand providerId={data.id}")
   expect(course).toContain("ProviderBrand providerId={data.provider_id}")
   expect(compare).toContain("import ProviderLogo from'./ProviderLogo'")
   expect(compare).toContain("<ProviderLogo providerId={providerId}")
   expect(logo).toContain('const cache=new Map()')
   expect(logo).toContain('const inflight=new Map()')
   expect(logo).toContain('const listCache=new Map()')
   expect(logo).toContain("const listCacheKey='coursefinder:provider-list-logo-cache:v2'")
   expect(logo).toContain('if(inflight.has(key))return inflight.get(key)')
   expect(logo).toContain("supabase.functions.invoke('provider-asset-access',{body:{stable_keys:keys}})")
   expect(logo).toContain('persistListCache()')
   expect(logo).toContain('requestAnimationFrame')
   expect(logo).toContain('img.loading=\'lazy\'')
   expect(logo).toContain("img.decoding='async'")
   expect(logo).toContain("img.fetchPriority='low'")
   expect(api).toContain("providerAssetAccess: providerId => invoke('provider-asset-access'")

   // Later Scholarship work must coexist with, not replace, CF-102 logo wiring.
   expect(main).toContain("import{ScholarshipSelectionWorkspace}from'./scholarship-selection-entry'")
   expect(scholarship).toContain('International students only')
 })

 test('deployed Provider, Course and Compare render approved primary logos',async({page},testInfo)=>{
   if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
   const runtime=observeRuntime(page)
   try{
     await loginAsUatUser(page)

     await page.goto(new URL('/#providers?id='+RMIT,process.env.UAT_BASE_URL).toString())
     await expect(page.locator('.m-drawer-provider')).toBeVisible({timeout:45000})
     const providerLogo=page.locator('.m-drawer-provider .m-drawer-head .cf-provider-logo img')
     await expect(providerLogo).toBeVisible({timeout:45000})
     await expect(providerLogo).toHaveAttribute('src',/provider-assets/i)

     await page.goto(new URL('/#courses?id='+RMIT_COURSE,process.env.UAT_BASE_URL).toString())
     await expect(page.locator('.m-drawer-course')).toBeVisible({timeout:45000})
     const courseLogo=page.locator('.m-drawer-course .cf-course-provider-brand .cf-provider-logo img')
     await expect(courseLogo).toBeVisible({timeout:45000})
     await expect(courseLogo).toHaveAttribute('src',/provider-assets/i)

     await page.goto(new URL('/#compare?type=provider&ids='+RMIT+','+UQ,process.env.UAT_BASE_URL).toString())
     await expect(page.getByRole('heading',{name:'Compare providers',exact:true})).toBeVisible({timeout:45000})
     const compareLogos=page.locator('.cf-compare-entity .cf-provider-logo img')
     await expect(compareLogos).toHaveCount(2,{timeout:45000})
     await milestoneScreenshot(page,testInfo,'cf-102-provider-logo-surfaces')
   }finally{await finish(testInfo,runtime)}
 })

 test('Provider list hydrates logos with one bounded bulk access request and session cache',async({page},testInfo)=>{
   if(!process.env.UAT_BASE_URL||!process.env.UAT_EMAIL||!process.env.UAT_PASSWORD)test.skip(true,'deployed UAT environment not configured')
   const runtime=observeRuntime(page)
   const calls=[]
   page.on('request',req=>{if(req.url().includes('/functions/v1/provider-asset-access'))calls.push(req)})
   try{
     await loginAsUatUser(page)
     await page.goto(new URL('/#providers',process.env.UAT_BASE_URL).toString())
     await expect(page.locator('.m-catalogue-panel .m-table tbody tr').first()).toBeVisible({timeout:45000})
     await page.waitForTimeout(1500)
     const logos=page.locator('.m-catalogue-panel .cf-provider-list-logo')
     await expect(logos.first()).toBeVisible({timeout:45000})
     expect(calls.length).toBeLessThanOrEqual(2)
     const cached=await page.evaluate(()=>sessionStorage.getItem('coursefinder:provider-list-logo-cache:v2'))
     expect(cached).toBeTruthy()
   }finally{await finish(testInfo,runtime)}
 })
})
