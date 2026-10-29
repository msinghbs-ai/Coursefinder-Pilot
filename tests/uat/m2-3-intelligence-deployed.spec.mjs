// Guards: M2.3: CourseFinder deployed M2.3 intelligence acceptance on canonical routes
import { test, expect } from '@playwright/test'
import { attachRuntimeEvidence, assertNoServerErrors, DETERMINISTIC_UI_TIMEOUT, loginAsUatUser, milestoneScreenshot, observeRuntime, writeRunEnvironment, clickPrimaryNav } from './support/runtime-evidence.mjs'
import { openRetiredLayer3, openLayer4 } from './support/navigation.mjs'

async function finish(testInfo,runtime){await attachRuntimeEvidence(testInfo,runtime);assertNoServerErrors(runtime)}

test.describe('CourseFinder deployed M2.3 intelligence acceptance on canonical routes @deployed',()=>{
 test.beforeAll(async()=>{await writeRunEnvironment({suite:'deployed-m2-3-intelligence-canonical-routes',change_control:'CF-CHG-20260830-048'})})

const NO_SECRETS=/sb_secret_|service_role|SUPABASE_SERVICE_ROLE_KEY/i

 // v2.15.107 to v2.15.200: the M2.3 screens moved into the single menu map; these checks follow the screens to where they now live.
 // v2.15.252 (Platform Admin, 12 Oct 2026): Layer 3 retired; its old addresses open Layer 2 › Adapters.
 test('old Layer 3 addresses open Layer 2 › Adapters without exposing credentials',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await openRetiredLayer3(page);await openRetiredLayer3(page,'/#layer-3-ai?tab=work');await expect(page.locator('main').first()).not.toBeEmpty()
  expect(await page.locator('body').innerText()).not.toMatch(NO_SECRETS);await milestoneScreenshot(page,testInfo,'m2-3-layer3-retired')
 }finally{await finish(testInfo,runtime)}})

 test('Layer 4 review and Scheduled jobs are separate workspaces',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await openLayer4(page) // v2.15.300: Layer 4 Review is one Inbox (the Layer 4 status panel is retired)
  await clickPrimaryNav(page,'Scheduled Tasks');await expect(page.getByRole('heading',{name:'Scheduled jobs',exact:true}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT});await expect(page.getByText('UNBOUNDED',{exact:true})).toHaveCount(0)
  await milestoneScreenshot(page,testInfo,'m2-3-layer4-refresh-separate')
 }finally{await finish(testInfo,runtime)}})

 // v2.15.301 (Platform Admin, 20 Oct 2026, "One list with a type filter"): Key dates and Reference sources are one Reference data list
 // with a type filter (?type=dates|links); each type shows only its own list.
 test('Key dates and Reference sources are separate Reference data types',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await clickPrimaryNav(page,'Reference data')
  const types=page.getByRole('toolbar',{name:'Type'})
  await expect(types).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  for(const [label,own,other] of [['Reference sources','Reference sources','Key dates'],['Key dates','Key dates','Reference sources']]){
   const b=types.getByRole('button',{name:label,exact:true});await b.click();await expect(b).toHaveAttribute('aria-pressed','true')
   await expect(page.getByRole('heading',{name:own,exact:true}).first()).toBeVisible({timeout:20_000})
   await expect(page.getByRole('heading',{name:other,exact:true})).toHaveCount(0)
  }
  await milestoneScreenshot(page,testInfo,'m2-3-links-dates-parent-menu')
 }finally{await finish(testInfo,runtime)}})

 // v2.15.258 (bug 12/10-01) moved Providers › Onboarding to Layer 2; v2.15.300 joined it with Adapters as Layer 2/3 › Universities.
 test('Onboarding sits under Layer 2/3 Universities and its old Providers address follows it',async({page},testInfo)=>{const runtime=observeRuntime(page);try{
  await loginAsUatUser(page);await clickPrimaryNav(page,'Providers')
  await expect(page.locator('.cf-page-tabs [role="tab"]').filter({hasText:'Providers'}).first()).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(page.locator('.cf-page-tabs [role="tab"]').filter({hasText:'Onboarding'})).toHaveCount(0)
  await page.evaluate(()=>{location.hash='#providers?tab=onboarding'})
  await expect(page).toHaveURL(/#layer-2-discovery\?tab=universities$/,{timeout:DETERMINISTIC_UI_TIMEOUT})
  await expect(page.locator('.cf-page-tabs [role="tab"][aria-selected="true"]')).toHaveText('Universities')
  await expect(page.locator('[data-adapters-workspace]')).toBeVisible({timeout:20_000})
  await milestoneScreenshot(page,testInfo,'m2-3-onboarding-administration')
 }finally{await finish(testInfo,runtime)}})
})
