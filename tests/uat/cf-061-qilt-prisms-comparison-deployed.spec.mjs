import{test,expect}from'@playwright/test'
import{attachRuntimeEvidence,assertNoServerErrors,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment,DETERMINISTIC_UI_TIMEOUT}from'./support/runtime-evidence.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
async function openCatalogue(page,hash,heading){await page.evaluate(h=>{location.hash=h},hash);await expect(page.getByRole('heading',{name:heading,exact:true})).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})}

test.describe('CF-061 QILT PRISMS comparison experience @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'cf-061-qilt-prisms-comparison-deployed',change_control:'CF-CHG-20260901-061'})})

 test('Provider comparison aligns QILT cards for two selected universities',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await expect(page.locator('.m-release-pill')).toContainText('v2.15.21')
  await openCatalogue(page,'#providers','Providers')
  const search=page.locator('.m-searchbox input').first()
  await search.fill('Charles Darwin University')
  const row=page.locator('.m-table tbody tr').filter({hasText:'Charles Darwin University'}).first()
  await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await row.click()
  const compare=page.getByTitle('Compare this provider')
  await expect(compare).toBeVisible()
  await compare.click()

  await expect(page.getByRole('heading',{name:'Compare providers',exact:true})).toBeVisible()
  await expect(page.getByText('1 / 6 selected',{exact:true})).toBeVisible()

  const compareSearch=page.locator('.cf-compare-search input')
  await compareSearch.fill('Curtin University')
  const add=page.locator('.cf-compare-results button').filter({hasText:'Curtin University'}).first()
  await expect(add).toBeVisible()
  const response=page.waitForResponse(r=>{if(!r.url().includes('/rest/v1/rpc/admin_read'))return false;try{return r.request().postDataJSON()?.p_operation==='contextual_compare'}catch{return false}})
  await add.click()
  const payload=await(await response).json()
  expect(Number(payload.total)).toBe(2)
  expect(Number(payload.max_items)).toBe(6)
  expect(payload.items.map(x=>x.name)).toEqual(['Charles Darwin University','Curtin University'])
  expect(payload.items.every(x=>x.contextual_insights?.student_outcomes?.granularity==='provider')).toBeTruthy()

  await expect(page.getByText('2 / 6 selected',{exact:true})).toBeVisible()
  await expect(page.locator('.cf-compare-entity').filter({hasText:'Charles Darwin University'})).toBeVisible()
  await expect(page.locator('.cf-compare-entity').filter({hasText:'Curtin University'})).toBeVisible()
  await expect(page.locator('.cf-compare-value').first()).toBeVisible()
  await expect(page.getByText('International student flow',{exact:true})).toBeVisible()
  await milestoneScreenshot(page,testInfo,'cf-061-provider-comparison')
 }finally{await finish(testInfo,runtime)}})

 test('Course detail keeps QILT as Provider context and opens Course comparison',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  await openCatalogue(page,'#courses','Courses')
  const search=page.locator('.m-searchbox input').first()
  await search.fill('Advanced Diploma of Accounting')
  const row=page.locator('.m-table tbody tr').filter({hasText:'Advanced Diploma of Accounting'}).filter({hasText:'RMIT'}).first()
  await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const detailResponse=page.waitForResponse(r=>{if(!r.url().includes('/rest/v1/rpc/admin_read'))return false;try{return r.request().postDataJSON()?.p_operation==='course_detail'}catch{return false}})
  await row.click()
  const detail=await(await detailResponse).json()
  expect(detail.contextual_insights?.student_outcomes?.granularity).toBe('provider_context')
  expect(Number(detail.contextual_insights?.student_outcomes?.total||0)).toBeGreaterThan(0)
  await expect(page.locator('.ci-outcome-card').first()).toBeVisible()
  await expect(page.getByText(/National benchmark/i).first()).toBeVisible()

  const compare=page.getByTitle('Compare this course')
  await expect(compare).toBeVisible()
  const compareResponse=page.waitForResponse(r=>{if(!r.url().includes('/rest/v1/rpc/admin_read'))return false;try{return r.request().postDataJSON()?.p_operation==='contextual_compare'}catch{return false}})
  await compare.click()
  const payload=await(await compareResponse).json()
  expect(Number(payload.total)).toBe(1)
  expect(payload.items[0]?.contextual_insights?.student_outcomes?.granularity).toBe('provider_context')
  await expect(page.getByRole('heading',{name:'Compare courses',exact:true})).toBeVisible()
  await expect(page.getByText(/QILT outcomes and PRISMS student-flow context/i)).toBeVisible()
  await milestoneScreenshot(page,testInfo,'cf-061-course-comparison')
 }finally{await finish(testInfo,runtime)}})
})
