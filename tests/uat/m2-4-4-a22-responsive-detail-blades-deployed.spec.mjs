import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment } from './support/runtime-evidence.mjs'
async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}
async function openFirst(page,label,query=''){
  await page.locator('.m-nav').getByRole('button',{name:label,exact:true}).click()
  if(query){const search=page.locator('.m-searchbox input');await search.fill(query)}
  const row=page.locator('.m-table tbody tr').filter({hasNot:page.locator('.m-row-skeleton')}).first()
  await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await row.click()
}
test.describe('A22 responsive detail blades @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'m2-4-4-a22-responsive-detail-blades',change_control:'CF-CHG-20260830-048'})})

 test('Provider blade is wide, scroll-owned and does not clip contextual cards',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await page.setViewportSize({width:1600,height:820});await loginAsUatUser(page);await openFirst(page,'Providers','Federation University')
  const drawer=page.getByLabel('Provider detail'),content=drawer.locator('.m-drawer-content')
  await expect(drawer).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  const metrics=await drawer.evaluate(el=>({w:el.getBoundingClientRect().width,vw:innerWidth}))
  expect(metrics.w).toBeGreaterThan(800);expect(metrics.w).toBeLessThanOrEqual(1050)
  const scroll=await content.evaluate(el=>({overflow:getComputedStyle(el).overflowY,scrollHeight:el.scrollHeight,clientHeight:el.clientHeight,scrollWidth:el.scrollWidth,clientWidth:el.clientWidth}))
  expect(scroll.overflow).toMatch(/scroll|auto/);expect(scroll.scrollHeight).toBeGreaterThanOrEqual(scroll.clientHeight);expect(scroll.scrollWidth).toBeLessThanOrEqual(scroll.clientWidth+2)
  const cards=drawer.locator('.ci-outcome-card');if(await cards.count()){const right=await content.evaluate(el=>el.getBoundingClientRect().right);for(let i=0;i<Math.min(await cards.count(),5);i++){const b=await cards.nth(i).boundingBox();expect((b?.x||0)+(b?.width||0)).toBeLessThanOrEqual(right+2)}}
  await expect(drawer.getByRole('button',{name:/Close Provider detail/i})).toBeVisible()
  await milestoneScreenshot(page,testInfo,'a22-provider-wide-drawer')
 }finally{await finish(testInfo,runtime)}})

 test('Course blade owns vertical scrolling and remains usable on tablet and mobile',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await page.setViewportSize({width:1440,height:720});await loginAsUatUser(page);await openFirst(page,'Courses')
  let drawer=page.getByLabel('Course detail'),content=drawer.locator('.m-drawer-content')
  await expect(drawer).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  let state=await content.evaluate(el=>({overflow:getComputedStyle(el).overflowY,scrollHeight:el.scrollHeight,clientHeight:el.clientHeight,scrollWidth:el.scrollWidth,clientWidth:el.clientWidth}))
  expect(state.overflow).toMatch(/scroll|auto/);expect(state.scrollHeight).toBeGreaterThan(state.clientHeight);expect(state.scrollWidth).toBeLessThanOrEqual(state.clientWidth+2)
  await content.evaluate(el=>{el.scrollTop=Math.min(500,el.scrollHeight-el.clientHeight)});await expect.poll(()=>content.evaluate(el=>el.scrollTop)).toBeGreaterThan(0)
  await page.getByRole('button',{name:/Close Course detail/i}).click()
  await page.setViewportSize({width:900,height:820});await openFirst(page,'Courses');drawer=page.getByLabel('Course detail');content=drawer.locator('.m-drawer-content')
  const tablet=await drawer.evaluate(el=>({w:el.getBoundingClientRect().width,vw:innerWidth}));expect(tablet.w/tablet.vw).toBeGreaterThan(.93);expect(tablet.w/tablet.vw).toBeLessThanOrEqual(1)
  await page.getByRole('button',{name:/Close Course detail/i}).click()
  await page.setViewportSize({width:390,height:844});await openFirst(page,'Courses');drawer=page.getByLabel('Course detail');content=drawer.locator('.m-drawer-content')
  const mobile=await drawer.evaluate(el=>({w:el.getBoundingClientRect().width,vw:innerWidth}));expect(Math.abs(mobile.w-mobile.vw)).toBeLessThanOrEqual(2)
  await expect(content).toBeVisible();await milestoneScreenshot(page,testInfo,'a22-course-mobile-drawer')
 }finally{await finish(testInfo,runtime)}})
})