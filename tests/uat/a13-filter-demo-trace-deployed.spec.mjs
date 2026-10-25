// Guards: A13 stable Course filters and Layer 2 acquisition Evidence trace
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

})
