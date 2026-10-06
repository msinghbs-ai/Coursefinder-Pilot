import{test,expect}from'@playwright/test'
import{attachRuntimeEvidence,assertNoServerErrors,loginAsUatUser,milestoneScreenshot,observeRuntime,writeRunEnvironment}from'./support/runtime-evidence.mjs'
import{openLayer2,openLayer2Tab}from'./support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('A13 stable Course filters and Layer 2 acquisition Evidence trace @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'a13-filter-demo-trace-v1.4',change_control:'CF-CHG-20260827-044'})})

 test('tablet Course Provider filter stays anchored and does not auto-focus',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await page.setViewportSize({width:900,height:720})
  await page.addInitScript(()=>{const native=window.matchMedia.bind(window);window.matchMedia=q=>q==='(pointer:fine)'?{matches:false,media:q,onchange:null,addListener(){},removeListener(){},addEventListener(){},removeEventListener(){},dispatchEvent(){return false}}:native(q)})
  await loginAsUatUser(page)
  await page.evaluate(()=>{location.hash='#courses'})
  await expect(page.getByRole('heading',{name:'Courses',exact:true})).toBeVisible()
  const provider=page.locator('.m-filter-select').filter({hasText:'Provider'}).first()
  const trigger=provider.locator('button.m-filter-button')
  await trigger.click()
  const pop=provider.locator('.m-filter-popover')
  await expect(pop).toBeVisible()
  const search=provider.locator('.m-filter-search input')
  await expect(search).not.toBeFocused()
  const tb=await trigger.boundingBox(),pb=await pop.boundingBox()
  expect(tb).toBeTruthy();expect(pb).toBeTruthy()
  expect(Math.abs(pb.x-tb.x)).toBeLessThanOrEqual(3)
  expect(pb.y).toBeGreaterThanOrEqual(tb.y+tb.height-2)
  expect(pb.y).toBeLessThan(tb.y+tb.height+20)
  await page.mouse.click(20,20)
  await expect(pop).toBeHidden()
  await trigger.click();await expect(pop).toBeVisible()
  const pb2=await pop.boundingBox()
  expect(Math.abs(pb2.x-pb.x)).toBeLessThanOrEqual(3)
  expect(Math.abs(pb2.y-pb.y)).toBeLessThanOrEqual(3)
  await milestoneScreenshot(page,testInfo,'a13-tablet-filter-anchored')
 }finally{await finish(testInfo,runtime)}})

 // Skipped in v2.15.203: this drives a Layer 2 screen retired in v2.15.200 (Decision 254). Its facts now live on Layer 2 > Adapters and Scheduled jobs > Jobs.
  test.skip('Layer 2 explains governed Firecrawl production route and opens accepted UQ Evidence',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page)
  // v2.15.128: the policy chain and the fixed UQ example were removed from Layer 2 (policy lives on Scrapers &
  // fetchers); History lists the latest page fetches, each opening the evidence it saved.
  const dialog=await openLayer2Tab(page,'History')
  await expect(page.getByRole('heading',{name:'Layer 2 Discovery & reading'}).first()).toBeVisible()
  // Decision 220 (v2.15.147): the retired pipeline's fetch list is gone; History shows daily progress by country and
  // the execution trace, whose rows still open their evidence.
  await expect(dialog.getByRole('heading',{name:'Daily progress',exact:true})).toBeVisible()
  await expect(dialog.getByRole('heading',{name:'Recent page fetches',exact:true})).toHaveCount(0)
  await expect(dialog.locator('[data-l2-daily] tbody tr').first()).toBeVisible({timeout:45000})
  await milestoneScreenshot(page,testInfo,'a13-layer2-daily-progress')
 }finally{await finish(testInfo,runtime)}})
})
