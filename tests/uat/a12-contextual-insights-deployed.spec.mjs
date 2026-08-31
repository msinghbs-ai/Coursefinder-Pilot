import fs from'node:fs/promises'
import{test,expect}from'@playwright/test'
import{attachRuntimeEvidence,assertNoServerErrors,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
async function openCatalogue(page,hash,heading){await page.evaluate(h=>{location.hash=h},hash);await expect(page.getByRole('heading',{name:heading,exact:true})).toBeVisible()}

test.describe('A12 contextual insights on catalogue detail blades @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'a12-contextual-insights-v1.5',change_control:'CF-CHG-20260827-044'})})

 test('RMIT Provider blade relates QILT PRISMS context and Scholarships without flattening granularity',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await openCatalogue(page,'#providers','Providers')
  const search=page.locator('.m-searchbox input').first();await search.fill('RMIT University')
  const row=page.locator('.m-table tbody tr').filter({hasText:'RMIT University (RMIT)'}).first();await expect(row).toBeVisible()
  const response=page.waitForResponse(r=>{if(!r.url().includes('/rest/v1/rpc/admin_read'))return false;try{const b=r.request().postDataJSON();return b?.p_operation==='provider_detail'}catch{return false}})
  await row.click();const payload=await(await response).json();const ci=payload.contextual_insights
  expect(Number(ci?.student_outcomes?.total||0)).toBeGreaterThan(0)
  expect(ci?.student_outcomes?.source_label).toBe('QILT')
  expect(ci?.student_outcomes?.granularity).toBe('provider')
  expect(ci?.student_flow?.source_label).toBe('PRISMS')
  expect(ci?.student_flow?.relationship_state).toBe('regional_context')
  expect(ci?.student_flow?.granularity).toBe('regional')
  expect(Number(ci?.scholarships?.total||0)).toBeGreaterThanOrEqual(3)
  await expect(page.getByRole('heading',{name:'Related insights & funding'})).toBeVisible()
  await expect(page.getByText(/Student outcomes & benchmarks/)).toBeVisible()
  await expect(page.getByText(/International student flow/)).toBeVisible()
  await expect(page.getByText(/Scholarships & funding/)).toBeVisible()
  await expect(page.getByText(/Regional Context/i).first()).toBeVisible()
  await milestoneScreenshot(page,testInfo,'a12-provider-contextual-insights')
 }finally{await finish(testInfo,runtime)}})

 test('Course blade labels Provider outcomes and Provider-scope Scholarships as context not Course truth',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await openCatalogue(page,'#courses','Courses')
  const search=page.locator('.m-searchbox input').first();await search.fill('Advanced Diploma of Accounting')
  const row=page.locator('.m-table tbody tr').filter({hasText:'Advanced Diploma of Accounting'}).filter({hasText:'RMIT University (RMIT)'}).first();await expect(row).toBeVisible()
  const response=page.waitForResponse(r=>{if(!r.url().includes('/rest/v1/rpc/admin_read'))return false;try{const b=r.request().postDataJSON();return b?.p_operation==='course_detail'}catch{return false}})
  await row.click();const payload=await(await response).json();const ci=payload.contextual_insights
  expect(ci?.student_outcomes?.granularity).toBe('provider_context')
  expect(Number(ci?.student_outcomes?.total||0)).toBeGreaterThan(0)
  expect(['not_mapped','regional_field_context','direct_course']).toContain(ci?.student_flow?.relationship_state)
  expect(Number(ci?.scholarships?.total||0)).toBeGreaterThanOrEqual(3)
  expect((ci?.scholarships?.items||[]).every(x=>x.granularity==='contextual_eligibility'||x.granularity==='course')).toBeTruthy()
  await expect(page.getByRole('heading',{name:'Related insights & funding'})).toBeVisible()
  await expect(page.getByText(/Governed scope · exclusions override broad inclusion/i)).toBeVisible()
  await expect(page.getByText(/Provider\/regional statistics retain their actual granularity and are not Course facts/i)).toBeVisible()
  await expect(page.locator('.ci-outcome-card').first()).toBeVisible()
  await expect(page.getByText(/vs benchmark/i).first()).toBeVisible()
  const drawer=page.locator('.m-drawer-course')
  await page.setViewportSize({width:1440,height:1100})
  const desktop=await drawer.boundingBox();expect(desktop).toBeTruthy()
  const desktopViewport=page.viewportSize();expect(desktop.width).toBeLessThanOrEqual(1102);expect(desktop.width/desktopViewport.width).toBeGreaterThan(0.62);expect(desktop.width/desktopViewport.width).toBeLessThanOrEqual(0.67)
  await milestoneScreenshot(page,testInfo,'a12-course-contextual-insights')
  await page.setViewportSize({width:900,height:720});const tablet=await drawer.boundingBox();expect(tablet.width/900).toBeGreaterThanOrEqual(0.9)
  await page.setViewportSize({width:390,height:844});const mobile=await drawer.boundingBox();expect(Math.abs(mobile.width-390)).toBeLessThanOrEqual(2)
 }finally{await finish(testInfo,runtime)}})

 test('A12 source contract remains bounded and role checked',async()=>{
  const sql=await fs.readFile('supabase/migrations/20260827235930_a12_contextual_insight_projection.sql','utf8')
  expect(sql).toContain('security.current_role_rank()')
  expect(sql).toContain("limit 12")
  expect(sql).toContain("limit 10")
  expect(sql).toContain("'provider_context'::text granularity")
  expect(sql).toContain("'regional_field_context'::text granularity")
  expect(sql).toContain("'contextual_eligibility'")
  expect(sql).toContain("include_exclude='exclude'")
  expect(sql).toContain('do not authorise Search or Publication mutation')
  expect(sql).toMatch(/revoke all on function security\.admin_contextual_insights\(text,uuid\) from public,anon/i)
  const component=await fs.readFile('src/ContextualInsights.jsx','utf8')
  expect(component).toContain('Student outcomes & benchmarks')
  expect(component).toContain('International student flow')
  expect(component).toContain('Scholarships & funding')
  expect(component).toContain('not Course facts')
 })
})
