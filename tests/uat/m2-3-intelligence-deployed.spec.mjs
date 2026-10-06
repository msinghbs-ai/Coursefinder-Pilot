import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment, clickPrimaryNav } from './support/runtime-evidence.mjs'
import { openLayer3, openLayer4 } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder deployed M2.3 intelligence acceptance on canonical routes @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'deployed-m2-3-intelligence-canonical-routes',change_control:'CF-CHG-20260830-048'})})

const NO_SECRETS=/sb_secret_|service_role|SUPABASE_SERVICE_ROLE_KEY/i
async function openTab(page,menu,tab){await clickPrimaryNav(page,menu);const t=page.locator('.cf-page-tabs [role="tab"]').filter({hasText:tab}).first();await expect(t).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await t.click();await expect(t).toHaveAttribute('aria-selected','true')}

 // v2.15.107 to v2.15.200: the M2.3 screens moved into the single menu map; these checks follow the screens to where they now live.
 test('Layer 3 work queue and Control tab load without exposing credentials',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);const ws=await openLayer3(page);await expect(ws.getByRole('heading',{name:'Work by task'})).toBeVisible()
  await page.locator('.cf-page-tabs [role="tab"]').filter({hasText:'Control'}).first().click();await expect(page.locator('main').first()).not.toBeEmpty()
  expect(await page.locator('body').innerText()).not.toMatch(NO_SECRETS);await milestoneScreenshot(page,testInfo,'m2-3-layer3-canonical')
 }finally{await finish(testInfo,runtime)}})

 test('Layer 4 review and Scheduled jobs are separate workspaces',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);const l4=await openLayer4(page);await expect(l4.getByRole('heading',{name:'Layer 4 status'})).toBeVisible()
  await clickPrimaryNav(page,'Scheduled Tasks');await expect(page.getByRole('heading',{name:'Scheduled jobs',exact:true}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await expect(page.getByText('UNBOUNDED',{exact:true})).toHaveCount(0)
  await milestoneScreenshot(page,testInfo,'m2-3-layer4-refresh-separate')
 }finally{await finish(testInfo,runtime)}})

 test('Key dates and Reference sources are separate Reference data tabs',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await openTab(page,'Reference data','Reference sources');await openTab(page,'Reference data','Key dates')
  await milestoneScreenshot(page,testInfo,'m2-3-links-dates-parent-menu')
 }finally{await finish(testInfo,runtime)}})

 test('Onboarding sits as a tab under Providers',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await openTab(page,'Providers','Onboarding');await expect(page.locator('main').first()).not.toBeEmpty();await milestoneScreenshot(page,testInfo,'m2-3-onboarding-administration')
 }finally{await finish(testInfo,runtime)}})
})
