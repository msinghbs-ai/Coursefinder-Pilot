// Guards: CF-102 Provider logos across detail, list and comparison
import{test,expect}from'@playwright/test'
import fs from'node:fs'
import{attachRuntimeEvidence,assertNoServerErrors,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment}from'./support/runtime-evidence.mjs'

const RMIT='8e1adb6c-e069-43db-9584-bd054255e702'
const UQ='e55396d2-869a-46ef-9d17-841c7eab1313'
const RMIT_COURSE='415e1105-8b45-4a72-9711-93d9217777ee'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CF-102 Provider logos across detail, list and comparison @targeted',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-102-provider-logo-surfaces-v3',change_control:'CF-CHG-20260904-102 / CF-CHG-20260905-152'})})

 test('source contract preserves governed signed access, caching and all identity surfaces',async()=>{
   const main=fs.readFileSync('src/mature-main.jsx','utf8')
   const course=fs.readFileSync('src/CourseDetailPolish.jsx','utf8')
   const compare=fs.readFileSync('src/ComparisonWorkspace.jsx','utf8')
   const logo=fs.readFileSync('src/ProviderLogo.jsx','utf8')
   const edge=fs.readFileSync('supabase/functions/provider-asset-access/index.ts','utf8')
   const api=fs.readFileSync('src/lib/supabase.js','utf8')

   // Feature contract, deliberately NOT pinned to an old UI version.
   expect(main).toMatch(/import ProviderLogo,\{ProviderBrand[^}]*\}from'\.\/ProviderLogo'/) // v2.15.281 also imports logoCapability
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
   expect(edge).toContain('const SIGNED_URL_TTL_SECONDS=1800')
   expect(edge).toContain('const SIGNING_CONCURRENCY=8')
   expect(edge).toContain('mapLimit(rows,SIGNING_CONCURRENCY')
   expect(api).toContain("providerAssetAccess: providerId => invoke('provider-asset-access'")

   // Later Scholarship work must coexist with, not replace, CF-102 logo wiring.
   // v2.15.174: Course decision support (scholarship-selection-entry) retired with Scholarships › Course links;
   // the course record's scholarship cards show which scholarships apply to a course.
   expect(fs.existsSync('src/scholarship-selection-entry.jsx')).toBe(false)
 })
})
